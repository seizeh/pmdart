import 'dart:async';
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

    // 앱 첫 실행에서 커뮤니티·채팅·내정보가 **동시에** 로드를 건다. 종전에는
    // bootstrap 의 accessToken 콜백이 `!isRefreshing` 으로 갱신을 건너뛰어,
    // 갱신이 도는 동안 들어온 요청이 **만료된 토큰**을 달고 나갔다(401 →
    // 새로고침 버튼). 갱신 중 진입한 호출자는 기다렸다가 **새 토큰**을 봐야 한다.
    test('갱신이 도는 중에 들어온 호출자도 기다렸다가 새 토큰을 본다', () async {
      final newJwt = jwtWithExp(nowSec() + 7200);
      final gate = Completer<void>();
      FakeSupabase.on('refresh', (_) async {
        await gate.future; // 갱신을 붙잡아 '진행 중' 창을 만든다
        return {'ok': true, 'token': newJwt, 'refresh_token': 'r2'};
      });

      final stale = SessionManager.instance.token;
      final first = SessionManager.instance.refreshOnce();
      await Future<void>.delayed(Duration.zero); // 비행 시작 보장
      expect(SessionManager.instance.isRefreshing, isTrue);

      // 이 시점의 다른 요청 — bootstrap 콜백과 같은 판정을 흉내낸다.
      final late_ = SessionManager.instance.refreshOnce();

      gate.complete();
      await Future.wait([first, late_]);

      expect(refreshCalls(), 1, reason: '기다려도 갱신은 한 번');
      expect(SessionManager.instance.token, newJwt);
      expect(
        SessionManager.instance.token,
        isNot(stale),
        reason: '만료 토큰으로 나가면 안 된다',
      );
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

    // 실제로 앱을 통째로 멈춘 경로다(다른 기기에서 비밀번호 변경 → refresh 4xx).
    //
    // _doRefresh 는 _refreshing 을 든 채 _invalidate() 를 await 하고, 그 안의
    // 뒷정리(푸시 토큰 해제 RPC)가 accessToken 콜백을 지나며 refreshOnce() 를
    // 다시 부른다. "갱신 중이면 기다린다" 규칙이 여기서 **자기 자신을 기다리게**
    // 만들었다. onBeforeInvalidate 가 그 RPC 를 대신한다.
    test('거절 → 정리 중에 갱신을 다시 불러도 교착되지 않는다', () async {
      FakeSupabase.on(
        'refresh',
        (_) => FakeSupabase.error(401, {'error': 'invalid_refresh'}),
      );
      var reentered = false;
      SessionManager.instance.onBeforeInvalidate = () async {
        reentered = true;
        // 정리 경로가 부르는 RPC 가 콜백을 타고 되돌아오는 상황.
        await SessionManager.instance.refreshOnce();
      };
      addTearDown(() => SessionManager.instance.onBeforeInvalidate = null);

      await SessionManager.instance.refreshOnce().timeout(
        const Duration(seconds: 5),
        onTimeout: () => fail('교착 — refreshOnce 가 자기 자신을 기다렸다'),
      );

      expect(reentered, isTrue, reason: '정리 경로를 실제로 지났는지');
      expect(SessionManager.instance.isLoggedIn, isFalse, reason: '강제 로그아웃');
      // 교착이면 여기까지 오지 못한다. 다음 갱신도 정상 진입해야 한다.
      expect(SessionManager.instance.isRefreshing, isFalse);
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
  });
}
