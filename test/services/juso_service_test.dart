import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/services/error_reporter.dart';
import 'package:pawmate/services/juso_service.dart';

import '../helpers/fake_supabase.dart';

/// 주소 검색(서버 함수 juso-search)의 응답 해석 회귀 가드.
///
/// 종전에는 앱이 juso 를 직접 불렀고, 키 누락·키 오류·네트워크 실패·검색어 문제가
/// 전부 빈 목록으로 뭉개져 "검색 결과가 없어요" 하나로 보였다. 지금은 키를 서버에만
/// 두고(pmdb juso-search), 앱은 서버가 나눠 준 응답을 화면 문구와 기록으로 옮긴다.
class _Sink implements ErrorSink {
  final records = <ErrorRecord>[];
  @override
  void add(ErrorRecord record) => records.add(record);
  @override
  void breadcrumb(String m, {String? category, Map<String, Object?>? data}) {}
}

void main() {
  late _Sink sink;
  final juso = JusoService.instance;

  setUpAll(() async {
    await FakeSupabase.init();
  });

  setUp(() {
    FakeSupabase.reset();
    ErrorReporter.resetForTest();
    sink = _Sink();
    ErrorReporter.sink = sink;
  });

  tearDown(ErrorReporter.resetForTest);

  test('정상 응답은 주소 목록 — 검색어·페이지를 서버에 넘기고 기록은 없다', () async {
    late Map<String, dynamic> sent;
    FakeSupabase.on('juso-search', (req) {
      sent = jsonDecode(req.body) as Map<String, dynamic>;
      return {
        'results': [
          {
            'road_addr': '경기도 화성시 동탄구 동탄대로 537 (여울동)',
            'jibun_addr': '경기도 화성시 동탄구 오산동 1023',
            'adm_cd': '4159012000',
            'zip_no': '18471',
          },
          {'road_addr': '', 'jibun_addr': '버려지는 행'},
        ],
        'total': 1,
      };
    });

    final r = await juso.search('  동탄대로 537 ', page: 2);

    expect(sent, {'keyword': '동탄대로 537', 'page': 2});
    expect(r.message, isNull);
    expect(r.addresses.single.jibunAddr, '경기도 화성시 동탄구 오산동 1023');
    expect(r.addresses.single.admCd, '4159012000');
    expect(sink.records, isEmpty);
  });

  test('결과가 없어도 정상이다 — 안내 문구 없이 빈 목록', () async {
    FakeSupabase.on('juso-search', (_) => {'results': [], 'total': 0});
    final r = await juso.search('없는주소없는주소');
    expect(r.addresses, isEmpty);
    expect(r.message, isNull);
    expect(sink.records, isEmpty);
  });

  test('검색어 거절(422)은 서버가 넘긴 juso 문구를 그대로 보여 주고 기록하지 않는다', () async {
    const msg = 'SQL 예약어 또는 특수문자( %,=,>,<,[,] )는 검색이 불가능 합니다.';
    FakeSupabase.on(
      'juso-search',
      (_) => FakeSupabase.error(422, {
        'error': 'keyword_rejected',
        'message': msg,
      }),
    );
    final r = await juso.search('select');
    expect(r.message, msg);
    expect(sink.records, isEmpty);
  });

  test('호출 제한(429)은 따로 안내하고 사용자 등급으로 남긴다', () async {
    FakeSupabase.on(
      'juso-search',
      (_) => FakeSupabase.error(429, {'error': 'rate_limited'}),
    );
    final r = await juso.search('동탄대로');
    expect(r.message, JusoService.rateLimitedMessage);
    expect(sink.records.single.tier, ErrorTier.userFacing);
  });

  test('juso·키 문제(502)는 실패 안내 + 보고', () async {
    FakeSupabase.on(
      'juso-search',
      (_) => FakeSupabase.error(502, {'error': 'juso_unavailable'}),
    );
    final r = await juso.search('동탄대로');
    expect(r.message, JusoService.failMessage);
    final rec = sink.records.single;
    expect(rec.tier, ErrorTier.reported);
    expect(rec.where, 'juso.search');
    expect(rec.extra?['status'], 502);
    expect(rec.extra?['error'], 'juso_unavailable');
  });

  test('네트워크 실패는 실패 안내 + 사용자 등급(서버·코드 문제가 아니다)', () async {
    FakeSupabase.on('juso-search', (_) => throw Exception('connection reset'));
    final r = await juso.search('동탄대로');
    expect(r.message, JusoService.failMessage);
    expect(sink.records.single.tier, ErrorTier.userFacing);
  });

  test('한 글자 검색은 서버에 묻지 않는다', () async {
    final r = await juso.search('동');
    expect(FakeSupabase.requests, isEmpty);
    expect(r.addresses, isEmpty);
    expect(r.message, isNull);
  });
}
