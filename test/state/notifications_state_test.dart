import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/services/session.dart';
import 'package:pawmate/state/notifications_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_session.dart';
import '../helpers/fake_supabase.dart';

const _me = AuthUser(
  id: 'u1',
  username: 'me',
  nickname: '나',
  userType: 'no_pet',
);

Map<String, dynamic> row(String id, {bool read = false}) => {
  'id': id,
  'notification_type': 'post_comment',
  'is_read': read,
  'created_at': '2026-07-01T00:00:00Z',
};

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

  group('NotificationsState.load', () {
    test('성공: 목록 채우고 loading 해제, 변경 통지', () async {
      FakeSupabase.on(
        'notifications',
        (_) => [row('n1'), row('n2', read: true)],
      );
      final s = NotificationsState();
      var notified = 0;
      s.addListener(() => notified++);

      await s.load();

      expect(s.loading, isFalse);
      expect(s.error, isNull);
      expect(s.items.map((n) => n.id), ['n1', 'n2']);
      expect(s.hasUnread, isTrue);
      expect(notified, greaterThanOrEqualTo(2), reason: '시작·완료 최소 2회 통지');
    });

    test('실패: 사용자 문구 에러로 전환하고 loading 해제', () async {
      FakeSupabase.on('notifications', (_) => throw Exception('네트워크'));
      final s = NotificationsState();

      await s.load();

      expect(s.loading, isFalse);
      expect(s.error, '알림을 불러오지 못했어요');
      expect(s.items, isEmpty);
    });
  });

  group('NotificationsState.markRead — 낙관적 읽음', () {
    test('목록을 즉시 갱신하고 서버에 단건 update 를 보낸다', () async {
      FakeSupabase.on('notifications', (_) => [row('n1')]);
      final s = NotificationsState();
      await s.load();
      FakeSupabase.requests.clear();

      s.markRead(s.items.single);

      expect(s.items.single.isRead, isTrue, reason: '서버 응답 전 즉시 반영');
      expect(s.hasUnread, isFalse);
      await pumpEventQueue();
      final req = FakeSupabase.requests.single;
      expect(req.method, 'PATCH');
      expect(req.url.queryParameters['id'], 'eq.n1');
    });

    test('이미 읽은 알림은 아무 것도 하지 않는다', () async {
      FakeSupabase.on('notifications', (_) => [row('n1', read: true)]);
      final s = NotificationsState();
      await s.load();
      FakeSupabase.requests.clear();

      s.markRead(s.items.single);
      await pumpEventQueue();

      expect(FakeSupabase.requests, isEmpty);
    });
  });

  group('NotificationsState.markAllRead', () {
    test('일괄 읽음 후 서버 상태로 재조회한다', () async {
      var fetches = 0;
      FakeSupabase.on('notifications', (req) {
        if (req.method == 'PATCH') return [];
        fetches++;
        return [row('n1', read: fetches > 1)];
      });
      final s = NotificationsState();
      await s.load();

      await s.markAllRead();

      expect(s.items.single.isRead, isTrue);
      expect(s.hasUnread, isFalse);
      expect(fetches, 2, reason: '초기 load + markAllRead 후 재조회');
    });
  });
}
