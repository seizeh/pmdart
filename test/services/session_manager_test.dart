import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/services/session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// exp 를 지정한 가짜 HS256 JWT (서명은 검증 대상 아님 — 클라는 exp 만 읽는다).
String jwtWithExp(int expEpochSec) {
  String enc(Map<String, Object> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
  return '${enc({'alg': 'HS256'})}.${enc({'sub': 'u1', 'exp': expEpochSec})}.sig';
}

int nowSec() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

const _user = AuthUser(
  id: 'u1',
  username: 'paw',
  nickname: '집사',
  userType: 'pet_owner',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // flutter_secure_storage 플랫폼 채널을 인메모리 맵으로 대체.
  final secureStore = <String, String>{};
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          final args = (call.arguments as Map?) ?? const {};
          final key = args['key'] as String?;
          switch (call.method) {
            case 'read':
              return secureStore[key];
            case 'write':
              secureStore[key!] = args['value'] as String;
              return null;
            case 'delete':
              secureStore.remove(key);
              return null;
            case 'readAll':
              return Map<String, String>.from(secureStore);
            case 'deleteAll':
              secureStore.clear();
              return null;
            case 'containsKey':
              return secureStore.containsKey(key);
          }
          return null;
        });
    secureStore.clear();
    SharedPreferences.setMockInitialValues({});
    await SessionManager.instance.clear();
  });

  group('isAccessExpiringSoon — 무중단 갱신 트리거 판정', () {
    test('만료 60초 이내면 임박', () async {
      await SessionManager.instance.setSession(
        jwtWithExp(nowSec() + 30),
        _user,
        refresh: 'r1',
      );
      expect(SessionManager.instance.isAccessExpiringSoon(), isTrue);
    });

    test('만료가 충분히 남았으면 임박 아님', () async {
      await SessionManager.instance.setSession(
        jwtWithExp(nowSec() + 3600),
        _user,
        refresh: 'r1',
      );
      expect(SessionManager.instance.isAccessExpiringSoon(), isFalse);
    });

    test('skew 를 넓히면 같은 토큰도 임박으로 판정', () async {
      await SessionManager.instance.setSession(
        jwtWithExp(nowSec() + 3600),
        _user,
        refresh: 'r1',
      );
      expect(SessionManager.instance.isAccessExpiringSoon(skew: 7200), isTrue);
    });

    test('refresh 미보유(레거시 30일 토큰)는 만료 임박이어도 갱신 안 함', () async {
      await SessionManager.instance.setSession(jwtWithExp(nowSec() + 5), _user);
      expect(SessionManager.instance.isAccessExpiringSoon(), isFalse);
    });

    test('exp 를 읽을 수 없는 토큰(형식 불량)은 임박으로 보지 않는다', () async {
      await SessionManager.instance.setSession(
        'not-a-jwt',
        _user,
        refresh: 'r1',
      );
      expect(SessionManager.instance.isAccessExpiringSoon(), isFalse);
    });
  });

  group('만료 세션 판정 — 좀비 세션 방지(#231)', () {
    // 이 결함은 "테스터는 항상 신선한 토큰이라 재현되지 않는" 유형이었다.
    // 만료 상태를 직접 만들어 성질로 고정한다.

    test('만료 + 갱신 불가 = 죽은 세션', () async {
      // 레거시 세션(refresh 없음)이 정확히 이 경우다. 웹도 persistsRefresh=false
      // 라 8시간 뒤 확정적으로 여기 온다.
      await SessionManager.instance.setSession(
        jwtWithExp(nowSec() - 10),
        _user,
      );
      expect(SessionManager.instance.isAccessExpired, isTrue);
      expect(SessionManager.instance.canRefresh, isFalse);
      expect(SessionManager.instance.isDeadSession, isTrue);
    });

    test('만료됐어도 갱신 가능하면 죽은 세션이 아니다', () async {
      // 여기서 죽었다고 판정하면 갱신으로 살아날 세션을 끊는 오탐 로그아웃이 된다.
      await SessionManager.instance.setSession(
        jwtWithExp(nowSec() - 10),
        _user,
        refresh: 'r1',
      );
      expect(SessionManager.instance.isAccessExpired, isTrue);
      expect(SessionManager.instance.isDeadSession, isFalse);
    });

    test('아직 안 만료됐으면 죽은 세션이 아니다', () async {
      await SessionManager.instance.setSession(
        jwtWithExp(nowSec() + 3600),
        _user,
      );
      expect(SessionManager.instance.isAccessExpired, isFalse);
      expect(SessionManager.instance.isDeadSession, isFalse);
    });

    test('exp 를 못 읽는 토큰은 만료로 단정하지 않는다', () async {
      // 파싱 실패를 만료로 보면 형식이 조금만 바뀌어도 전원 로그아웃이 난다.
      await SessionManager.instance.setSession('not-a-jwt', _user);
      expect(SessionManager.instance.isAccessExpired, isFalse);
      expect(SessionManager.instance.isDeadSession, isFalse);
    });

    test('비로그인 상태는 죽은 세션이 아니다', () async {
      expect(SessionManager.instance.isDeadSession, isFalse);
    });

    test('invalidateIfDead 는 죽은 세션만 정리하고 onInvalidated 를 부른다', () async {
      var routed = 0;
      SessionManager.instance.onInvalidated = () => routed++;
      addTearDown(() => SessionManager.instance.onInvalidated = null);

      await SessionManager.instance.setSession(
        jwtWithExp(nowSec() - 10),
        _user,
      );
      await SessionManager.instance.invalidateIfDead();
      expect(SessionManager.instance.isLoggedIn, isFalse);
      expect(routed, 1);
    });

    test('invalidateIfDead 는 살아 있는 세션을 건드리지 않는다', () async {
      var routed = 0;
      SessionManager.instance.onInvalidated = () => routed++;
      addTearDown(() => SessionManager.instance.onInvalidated = null);

      await SessionManager.instance.setSession(
        jwtWithExp(nowSec() + 3600),
        _user,
      );
      await SessionManager.instance.invalidateIfDead();
      expect(SessionManager.instance.isLoggedIn, isTrue);
      expect(routed, 0);
    });

    test('여러 번 불러도 onInvalidated 는 한 번만 — 요청마다 지나가는 경로다', () async {
      var routed = 0;
      SessionManager.instance.onInvalidated = () => routed++;
      addTearDown(() => SessionManager.instance.onInvalidated = null);

      await SessionManager.instance.setSession(
        jwtWithExp(nowSec() - 10),
        _user,
      );
      await Future.wait([
        SessionManager.instance.invalidateIfDead(),
        SessionManager.instance.invalidateIfDead(),
        SessionManager.instance.invalidateIfDead(),
      ]);
      expect(routed, 1);
    });
  });

  group('isAuthExpiredError — 만료만 좁게 잡는다(#231)', () {
    test('PGRST301 은 만료로 본다', () {
      expect(
        isAuthExpiredError(
          const PostgrestException(message: 'JWT expired', code: 'PGRST301'),
        ),
        isTrue,
      );
    });

    test('메시지에 jwt expired 가 있으면 만료로 본다', () {
      expect(
        isAuthExpiredError(
          const PostgrestException(message: 'JWT expired', code: '401'),
        ),
        isTrue,
      );
    });

    test('42501 은 만료가 아니다 — 정지·차단 계정의 RLS 거부다', () {
      // PostgREST 는 권한 거부도 401 로 준다. 이걸 만료로 뭉뚱그리면
      // 정지 사유를 안내할 기회를 잃고, 정지 사용자가 로그인 화면만 반복해서 본다.
      expect(
        isAuthExpiredError(
          const PostgrestException(
            message: 'permission denied for table posts',
            code: '42501',
          ),
        ),
        isFalse,
      );
    });

    test('평범한 네트워크 오류는 만료가 아니다', () {
      expect(isAuthExpiredError(Exception('SocketException')), isFalse);
    });
  });

  group('세션 저장/복원', () {
    test('setSession 은 토큰을 secure storage 에, 사용자를 prefs 에 나눠 저장한다', () async {
      final t = jwtWithExp(nowSec() + 100);
      await SessionManager.instance.setSession(t, _user, refresh: 'r1');

      expect(SessionManager.instance.isLoggedIn, isTrue);
      expect(secureStore['session_access'], t);
      expect(secureStore['session_refresh'], 'r1');
      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString('session_user')!)['id'], 'u1');
    });

    test('load 는 구버전 prefs 토큰을 secure storage 로 마이그레이션한다', () async {
      final legacy = jwtWithExp(nowSec() + 100);
      SharedPreferences.setMockInitialValues({
        'session_token': legacy,
        'session_user': jsonEncode(_user.toJson()),
      });

      await SessionManager.instance.load();

      expect(SessionManager.instance.token, legacy);
      expect(SessionManager.instance.user?.id, 'u1');
      expect(secureStore['session_access'], legacy, reason: 'secure 로 이전');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('session_token'), isNull, reason: '구 키 제거');
    });

    test('토큰만 있고 사용자가 없으면(반쪽 세션) 통째로 무효 처리한다', () async {
      secureStore['session_access'] = jwtWithExp(nowSec() + 100);

      await SessionManager.instance.load();

      expect(SessionManager.instance.isLoggedIn, isFalse);
      expect(SessionManager.instance.token, isNull);
    });

    test('clear 는 메모리·secure·prefs 를 모두 비운다', () async {
      await SessionManager.instance.setSession(
        jwtWithExp(nowSec() + 100),
        _user,
        refresh: 'r1',
      );
      await SessionManager.instance.clear();

      expect(SessionManager.instance.isLoggedIn, isFalse);
      expect(secureStore, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('session_user'), isNull);
    });
  });

  group('권한 파생 상태', () {
    test('isAdmin 은 user_type 으로 판정', () async {
      await SessionManager.instance.setSession(
        jwtWithExp(nowSec() + 100),
        AuthUser.fromJson(const {'id': 'a1', 'user_type': 'admin'}),
      );
      expect(SessionManager.instance.isAdmin, isTrue);
    });
  });
}
