import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/services/session.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
