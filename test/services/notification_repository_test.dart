import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pawmate/services/app_events.dart';
import 'package:pawmate/services/notification_repository.dart';
import 'package:pawmate/services/session.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_session.dart';
import '../helpers/fake_supabase.dart';

const _me = AuthUser(
  id: 'u1',
  username: 'me',
  nickname: '나',
  userType: 'no_pet',
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    installFakeSecureStorage();
    SharedPreferences.setMockInitialValues({});
    await FakeSupabase.init();
  });

  setUp(() async {
    FakeSupabase.reset();
    SharedPreferences.setMockInitialValues({});
    await SessionManager.instance.setSession(
      jwtWithExp(nowSec() + 3600),
      _me,
      refresh: 'r1',
    );
  });

  group('NotificationRepository.fetch', () {
    test('내 것 + 비무음만 최신순 100건 요청하고 타입 폴백 파싱', () async {
      FakeSupabase.on(
        'notifications',
        (_) => [
          {
            'id': 'n1',
            'notification_type': null, // 미지정 → system_notice 폴백
            'is_read': false,
            'created_at': '2026-07-01T00:00:00Z',
          },
        ],
      );

      final list = await NotificationRepository.instance.fetch();

      expect(list.single.type, 'system_notice');
      final q = FakeSupabase.requests.single.url.queryParameters;
      expect(q['user_id'], 'eq.u1');
      expect(q['is_silent'], 'eq.false');
      expect(q['order'], 'created_at.desc.nullslast');
      expect(q['limit'], '100');
    });

    test('로그아웃 상태면 요청 없이 빈 목록', () async {
      await SessionManager.instance.clear();

      expect(await NotificationRepository.instance.fetch(), isEmpty);
      expect(FakeSupabase.requests, isEmpty);
    });
  });

  group('NotificationRepository.unreadCount', () {
    test('exact 카운트를 요청하고 content-range 의 총계를 읽는다', () async {
      FakeSupabase.on(
        'notifications',
        (_) => http.Response(
          '[]',
          200,
          headers: {
            'content-type': 'application/json',
            'content-range': '0-0/42',
          },
        ),
      );

      final n = await NotificationRepository.instance.unreadCount();

      expect(n, 42);
      final req = FakeSupabase.requests.single;
      expect(req.headers['Prefer'], contains('count=exact'));
      expect(req.url.queryParameters['is_read'], 'eq.false');
      expect(req.url.queryParameters['is_silent'], 'eq.false');
    });
  });

  group('읽음/삭제 처리', () {
    test('markRead 는 단건 update + 알림 이벤트 발행', () async {
      FakeSupabase.on('notifications', (_) => []);
      final before = AppEvents.instance.notification.value;

      await NotificationRepository.instance.markRead('n1');

      final req = FakeSupabase.requests.single;
      expect(req.method, 'PATCH');
      expect(jsonDecode(req.body), {'is_read': true});
      expect(req.url.queryParameters['id'], 'eq.n1');
      expect(AppEvents.instance.notification.value, before + 1);
    });

    test('markAllRead 는 안읽은 것만 일괄 update', () async {
      FakeSupabase.on('notifications', (_) => []);

      await NotificationRepository.instance.markAllRead();

      final q = FakeSupabase.requests.single.url.queryParameters;
      expect(q['user_id'], 'eq.u1');
      expect(q['is_read'], 'eq.false');
    });

    test(
      'delete 는 읽음 처리(UPDATE) 후 삭제한다 — 카운터 트리거 DELETE 분기 부재(#232)',
      () async {
        FakeSupabase.on('notifications', (_) => []);

        await NotificationRepository.instance.delete('n1');

        expect(FakeSupabase.requests, hasLength(2));
        final read = FakeSupabase.requests[0];
        expect(read.method, 'PATCH', reason: '안읽음 행을 바로 지우면 배지 카운터가 영구 드리프트');
        expect(jsonDecode(read.body), {'is_read': true});
        expect(read.url.queryParameters['id'], 'eq.n1');
        expect(read.url.queryParameters['is_read'], 'eq.false');
        final del = FakeSupabase.requests[1];
        expect(del.method, 'DELETE');
        expect(del.url.queryParameters['id'], 'eq.n1');
      },
    );

    test('deleteAll 도 읽음 처리 선행 후 내 알림 전체를 지운다(#232)', () async {
      FakeSupabase.on('notifications', (_) => []);

      await NotificationRepository.instance.deleteAll();

      expect(FakeSupabase.requests, hasLength(2));
      final read = FakeSupabase.requests[0];
      expect(read.method, 'PATCH');
      expect(read.url.queryParameters['user_id'], 'eq.u1');
      expect(read.url.queryParameters['is_read'], 'eq.false');
      final del = FakeSupabase.requests[1];
      expect(del.method, 'DELETE');
      expect(del.url.queryParameters['user_id'], 'eq.u1');
    });
  });
}
