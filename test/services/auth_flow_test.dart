import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/services/auth_service.dart';
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
    await SessionManager.instance.clear();
  });

  group('AuthService.login — 실패 경로', () {
    test('refresh 지원 헤더와 자격을 담아 login 엣지 함수를 호출한다', () async {
      FakeSupabase.on('login', (_) => {'ok': false});

      await AuthService.instance.login('paw', 'pw123');

      final req = FakeSupabase.requests.single;
      expect(req.url.path, '/functions/v1/login');
      expect(req.headers['x-client-refresh'], '1');
      expect(jsonDecode(req.body), {'username': 'paw', 'password': 'pw123'});
    });

    test('서버가 에러코드를 주면(401) 그대로 사용자 문구로 매핑된다', () async {
      FakeSupabase.on(
        'login',
        (_) => FakeSupabase.error(401, {'error': 'invalid_credentials'}),
      );

      final r = await AuthService.instance.login('paw', 'wrong');

      expect(r.ok, isFalse);
      expect(r.errorCode, 'invalid_credentials');
      expect(r.message, '아이디 또는 비밀번호가 올바르지 않아요');
      expect(SessionManager.instance.isLoggedIn, isFalse);
    });

    test('200 이지만 토큰이 없으면 login_failed, 세션은 만들지 않는다', () async {
      FakeSupabase.on('login', (_) => {'ok': true});

      final r = await AuthService.instance.login('paw', 'pw');

      expect(r.errorCode, 'login_failed');
      expect(SessionManager.instance.isLoggedIn, isFalse);
      expect(secureStore, isEmpty);
    });
  });

  group('AuthService.changePassword — 세션 교체 흐름', () {
    setUp(() async {
      await SessionManager.instance.setSession(
        jwtWithExp(nowSec() + 3600),
        _me,
        refresh: 'r-old',
      );
    });

    test('성공 시 새 access/refresh 로 세션이 통째로 교체된다', () async {
      final newJwt = jwtWithExp(nowSec() + 7200);
      FakeSupabase.on(
        'change-password',
        (_) => {'ok': true, 'token': newJwt, 'refresh_token': 'r-new'},
      );

      final r = await AuthService.instance.changePassword('old', 'new123');

      expect(r.ok, isTrue);
      expect(SessionManager.instance.token, newJwt);
      expect(secureStore['session_access'], newJwt);
      expect(secureStore['session_refresh'], 'r-new');
      expect(SessionManager.instance.user?.id, 'u1', reason: '사용자 정보 유지');
    });

    test('현재 비밀번호 불일치(401)면 기존 세션을 건드리지 않는다', () async {
      final oldToken = SessionManager.instance.token;
      FakeSupabase.on(
        'change-password',
        (_) => FakeSupabase.error(401, {'error': 'invalid_current'}),
      );

      final r = await AuthService.instance.changePassword('bad', 'new123');

      expect(r.errorCode, 'invalid_current');
      expect(r.message, '현재 비밀번호가 올바르지 않아요');
      expect(SessionManager.instance.token, oldToken);
      expect(SessionManager.instance.isLoggedIn, isTrue);
    });
  });
}
