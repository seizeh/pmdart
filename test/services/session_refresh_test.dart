import 'package:flutter_test/flutter_test.dart';
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
  late Map<String, String> secureStore;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    secureStore = installFakeSecureStorage();
    SharedPreferences.setMockInitialValues({});
    await FakeSupabase.init();
  });

  setUp(() async {
    FakeSupabase.reset();
    secureStore.clear();
    SharedPreferences.setMockInitialValues({});
    SessionManager.instance.onInvalidated = null;
    await SessionManager.instance.setSession(
      jwtWithExp(nowSec() + 30),
      _me,
      refresh: 'r1',
    );
    FakeSupabase.requests.clear();
  });

  tearDown(() {
    SessionManager.instance.onInvalidated = null;
  });

  int refreshCalls() =>
      FakeSupabase.requests.where((r) => r.url.path.contains('refresh')).length;

  group('SessionManager.refreshOnce — 단일비행 토큰 회전', () {
    test('동시에 여러 번 불러도 refresh 요청은 1회, 토큰·refresh 가 회전된다', () async {
      final newJwt = jwtWithExp(nowSec() + 7200);
      FakeSupabase.on(
        'refresh',
        (_) => {'ok': true, 'token': newJwt, 'refresh_token': 'r2'},
      );

      await Future.wait([
        SessionManager.instance.refreshOnce(),
        SessionManager.instance.refreshOnce(),
        SessionManager.instance.refreshOnce(),
      ]);

      expect(refreshCalls(), 1, reason: '단일비행 — 동시 호출 병합');
      expect(SessionManager.instance.token, newJwt);
      expect(secureStore['session_access'], newJwt);
      expect(secureStore['session_refresh'], 'r2', reason: 'refresh 회전 영속화');
      expect(SessionManager.instance.isLoggedIn, isTrue);
    });

    test('완료 후 다시 부르면 새 요청이 나간다(비행 종료 후 재사용 아님)', () async {
      FakeSupabase.on(
        'refresh',
        (_) => {
          'ok': true,
          'token': jwtWithExp(nowSec() + 7200),
          'refresh_token': 'r2',
        },
      );

      await SessionManager.instance.refreshOnce();
      await SessionManager.instance.refreshOnce();

      expect(refreshCalls(), 2);
    });

    test('401(invalid_refresh)이면 세션 clear + 강제 로그아웃 콜백', () async {
      FakeSupabase.on(
        'refresh',
        (_) => FakeSupabase.error(401, {'error': 'invalid_refresh'}),
      );
      var invalidated = false;
      SessionManager.instance.onInvalidated = () => invalidated = true;

      await SessionManager.instance.refreshOnce();

      expect(invalidated, isTrue);
      expect(SessionManager.instance.isLoggedIn, isFalse);
      expect(secureStore, isEmpty);
    });

    test('200 이지만 예상 밖 응답이어도 세션 만료로 처리한다', () async {
      FakeSupabase.on('refresh', (_) => {'ok': false});
      var invalidated = false;
      SessionManager.instance.onInvalidated = () => invalidated = true;

      await SessionManager.instance.refreshOnce();

      expect(invalidated, isTrue);
      expect(SessionManager.instance.isLoggedIn, isFalse);
    });

    test('일시 오류는 1초 후 1회 재시도해 성공하면 회전을 이어간다', () async {
      final newJwt = jwtWithExp(nowSec() + 7200);
      var calls = 0;
      FakeSupabase.on('refresh', (_) {
        calls++;
        if (calls == 1) throw Exception('타임아웃 흉내');
        return {'ok': true, 'token': newJwt, 'refresh_token': 'r2'};
      });

      await SessionManager.instance.refreshOnce();

      expect(calls, 2);
      expect(SessionManager.instance.token, newJwt);
      expect(SessionManager.instance.isLoggedIn, isTrue);
    });

    test('재시도까지 실패한 네트워크 오류는 세션을 유지한다(다음 요청에서 재시도)', () async {
      final oldToken = SessionManager.instance.token;
      FakeSupabase.on('refresh', (_) => throw Exception('네트워크 다운'));
      var invalidated = false;
      SessionManager.instance.onInvalidated = () => invalidated = true;

      await SessionManager.instance.refreshOnce();

      expect(invalidated, isFalse, reason: '오탐 로그아웃 금지');
      expect(SessionManager.instance.token, oldToken);
      expect(SessionManager.instance.isLoggedIn, isTrue);
    });

    test('refresh 미보유(레거시)면 아무 요청도 하지 않는다', () async {
      await SessionManager.instance.setSession(jwtWithExp(nowSec() + 30), _me);
      FakeSupabase.requests.clear();

      await SessionManager.instance.refreshOnce();

      expect(refreshCalls(), 0);
    });
  });

  group('SessionManager.checkAliveAndClearIfDead — 세션 생존 확인', () {
    test('서버가 무효(false)라면 강제 로그아웃하고 true 반환', () async {
      FakeSupabase.on('session_alive', (_) => false);
      var invalidated = false;
      SessionManager.instance.onInvalidated = () => invalidated = true;

      final dead = await SessionManager.instance.checkAliveAndClearIfDead();

      expect(dead, isTrue);
      expect(invalidated, isTrue);
      expect(SessionManager.instance.isLoggedIn, isFalse);
    });

    test('유효(true)면 세션 유지', () async {
      FakeSupabase.on('session_alive', (_) => true);

      expect(await SessionManager.instance.checkAliveAndClearIfDead(), isFalse);
      expect(SessionManager.instance.isLoggedIn, isTrue);
    });

    test('네트워크 오류는 무효로 단정하지 않는다(오탐 로그아웃 방지)', () async {
      FakeSupabase.on('session_alive', (_) => throw Exception('네트워크'));

      expect(await SessionManager.instance.checkAliveAndClearIfDead(), isFalse);
      expect(SessionManager.instance.isLoggedIn, isTrue);
    });

    test('토큰 거절(PGRST301)·refresh 미보유(레거시/웹)면 강제 로그아웃한다(#231)', () async {
      await SessionManager.instance.setSession(jwtWithExp(nowSec() - 10), _me);
      FakeSupabase.on(
        'session_alive',
        (_) => FakeSupabase.error(401, {
          'code': 'PGRST301',
          'message': 'JWT expired',
        }),
      );
      var invalidated = false;
      SessionManager.instance.onInvalidated = () => invalidated = true;

      expect(await SessionManager.instance.checkAliveAndClearIfDead(), isTrue);
      expect(invalidated, isTrue, reason: '만료 토큰을 일시 오류로 삼키면 좀비 세션');
      expect(SessionManager.instance.isLoggedIn, isFalse);
    });

    test('토큰 거절이라도 refresh 로 살아나면 세션을 유지한다(오탐 로그아웃 방지)', () async {
      var aliveCalls = 0;
      FakeSupabase.on('session_alive', (_) {
        aliveCalls++;
        return aliveCalls == 1
            ? FakeSupabase.error(401, {
                'code': 'PGRST301',
                'message': 'JWT expired',
              })
            : true;
      });
      FakeSupabase.on(
        'refresh',
        (_) => {
          'ok': true,
          'token': jwtWithExp(nowSec() + 7200),
          'refresh_token': 'r2',
        },
      );

      expect(await SessionManager.instance.checkAliveAndClearIfDead(), isFalse);
      expect(SessionManager.instance.isLoggedIn, isTrue);
      expect(aliveCalls, 2, reason: '갱신 후 재확인');
    });

    test('refresh 후에도 토큰이 거절되면 강제 로그아웃한다', () async {
      FakeSupabase.on(
        'session_alive',
        (_) => FakeSupabase.error(401, {
          'code': 'PGRST301',
          'message': 'JWT expired',
        }),
      );
      FakeSupabase.on(
        'refresh',
        (_) => {
          'ok': true,
          'token': jwtWithExp(nowSec() + 7200),
          'refresh_token': 'r2',
        },
      );
      var invalidated = false;
      SessionManager.instance.onInvalidated = () => invalidated = true;

      expect(await SessionManager.instance.checkAliveAndClearIfDead(), isTrue);
      expect(invalidated, isTrue);
      expect(SessionManager.instance.isLoggedIn, isFalse);
    });
  });

  group('SessionManager.invalidateIfExpired — 갱신 불가 세션 만료(#231)', () {
    test('refresh 없는 세션의 만료 access 는 즉시 무효화한다', () async {
      await SessionManager.instance.setSession(
        jwtWithExp(nowSec() - 3600),
        _me,
      );
      var invalidated = false;
      SessionManager.instance.onInvalidated = () => invalidated = true;

      SessionManager.instance.invalidateIfExpired();
      await pumpEventQueue();

      expect(invalidated, isTrue);
      expect(SessionManager.instance.isLoggedIn, isFalse);
    });

    test('refresh 보유 세션은 만료돼도 건드리지 않는다(갱신 경로가 담당)', () async {
      await SessionManager.instance.setSession(
        jwtWithExp(nowSec() - 3600),
        _me,
        refresh: 'r1',
      );

      SessionManager.instance.invalidateIfExpired();
      await pumpEventQueue();

      expect(SessionManager.instance.isLoggedIn, isTrue);
    });

    test('만료 후 5분(클럭 스큐 여유) 이내면 유지한다', () async {
      await SessionManager.instance.setSession(jwtWithExp(nowSec() - 60), _me);

      SessionManager.instance.invalidateIfExpired();
      await pumpEventQueue();

      expect(SessionManager.instance.isLoggedIn, isTrue);
    });
  });
}
