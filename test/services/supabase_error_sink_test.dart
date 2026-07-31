import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/services/error_reporter.dart';
import 'package:pawmate/services/observability.dart';

import '../helpers/fake_supabase.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await FakeSupabase.init();
  });

  setUp(() {
    FakeSupabase.reset();
    ErrorReporter.resetForTest();
    ErrorReporter.sink = const SupabaseErrorSink();
  });

  tearDown(ErrorReporter.resetForTest);

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('reported 만 서버로 보낸다 — 무시·사용자알림은 링 버퍼에만', () async {
    FakeSupabase.on('record_client_error', (_) => null);

    ErrorReporter.ignored('e1', where: 'a.b', why: '무해');
    ErrorReporter.userFacing('e2', where: 'c.d');
    await settle();

    expect(
      FakeSupabase.requests.any(
        (r) => r.url.path.endsWith('record_client_error'),
      ),
      isFalse,
      reason: '이 둘까지 보내면 게스트 한 명이 테이블을 채운다',
    );
    expect(ErrorReporter.recent, hasLength(2), reason: '링 버퍼에는 남는다');
  });

  test('reported 는 where·message 를 담아 RPC 로 나간다', () async {
    FakeSupabase.on('record_client_error', (_) => null);

    ErrorReporter.report(
      Exception('무너짐'),
      where: 'session.restoreUser',
      stackTrace: StackTrace.current,
    );
    await settle();

    final req = FakeSupabase.requests.singleWhere(
      (r) => r.url.path.endsWith('record_client_error'),
    );
    final body = jsonDecode(req.body) as Map<String, dynamic>;
    expect(body['p_where'], 'session.restoreUser');
    expect(body['p_message'], contains('무너짐'));
    expect(body['p_stack'], isNotNull);
  });

  test('전송이 실패해도 예외가 새어나오지 않는다', () async {
    // 오류를 알리려다 또 오류를 내면 안 된다(무한 재귀 방지).
    FakeSupabase.on('record_client_error', (_) => throw Exception('서버 down'));

    ErrorReporter.report('boom', where: 'x.y');
    await settle();

    expect(ErrorReporter.recent.single.where, 'x.y');
  });

  test('sink 가 붙기 전 쌓인 reported 는 flushPending 이 흘려보낸다', () async {
    // 회귀: main() 은 Supabase.initialize 보다 먼저 세션을 복원한다.
    // 그때 난 report(session.restoreUser 등)가 조용히 사라지던 문제.
    ErrorReporter.resetForTest(); // sink = Silent (부팅 초기 상태)
    ErrorReporter.report('부팅 중 오류', where: 'session.restoreUser');
    await settle();
    expect(
      FakeSupabase.requests.any(
        (r) => r.url.path.endsWith('record_client_error'),
      ),
      isFalse,
      reason: 'sink 가 붙기 전이므로 아직 안 나간다',
    );

    FakeSupabase.on('record_client_error', (_) => null);
    ErrorReporter.sink = const SupabaseErrorSink();
    ErrorReporter.flushPending();
    await settle();

    final req = FakeSupabase.requests.singleWhere(
      (r) => r.url.path.endsWith('record_client_error'),
    );
    expect(jsonDecode(req.body)['p_where'], 'session.restoreUser');
  });
}
