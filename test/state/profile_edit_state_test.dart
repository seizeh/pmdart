import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pawmate/services/session.dart';
import 'package:pawmate/state/profile_edit_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_session.dart';
import '../helpers/fake_supabase.dart';

const _me = AuthUser(
  id: 'u1',
  username: 'me',
  nickname: '나',
  userType: 'no_pet',
);

ProfileEditState newState({String mode = 'personal'}) => ProfileEditState(
  initialMode: mode,
  initialAddress: '서울 종로구 청운동',
  initialVerified: true,
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

  group('ProfileEditState — 모드/지역 파생 상태', () {
    test('초기값과 regionName(주소 마지막 토큰) 파생', () {
      final s = newState();
      expect(s.isBizMode, isFalse);
      expect(s.regionName, '청운동');
    });

    test('setMode 로 업체 관리 화면 전환', () {
      final s = newState();
      s.setMode('business');
      expect(s.isBizMode, isTrue);
    });
  });

  group('ProfileEditState.uploadImage', () {
    test('성공: 업로드 후 공개 URL 보관, uploading 수명 정상', () async {
      FakeSupabase.on('storage', (_) => {'Key': 'media/u1/profile/a.jpg'});
      final s = newState();
      final file = XFile.fromData(
        Uint8List.fromList([1, 2, 3]),
        name: 'a.jpg',
        mimeType: 'image/jpeg',
      );

      final future = s.uploadImage(file);
      expect(s.uploading, isTrue);
      expect(await future, isTrue);

      expect(s.uploading, isFalse);
      expect(s.imageUrl, contains('/storage/v1/object/public/media/'));
      final req = FakeSupabase.requests.single;
      expect(req.url.path, contains('/object/media/u1/profile/'));
    });

    test('실패: false 반환, imageUrl 은 그대로', () async {
      FakeSupabase.on(
        'storage',
        (_) => FakeSupabase.error(500, {'error': 'x'}),
      );
      final s = newState();
      final file = XFile.fromData(Uint8List.fromList([1]), name: 'a.jpg');

      expect(await s.uploadImage(file), isFalse);
      expect(s.imageUrl, isNull);
      expect(s.uploading, isFalse);
    });
  });

  group('ProfileEditState.save', () {
    test('닉네임(+업로드된 사진)을 내 행에 저장한다', () async {
      FakeSupabase.on('storage', (_) => {'Key': 'media/u1/profile/a.jpg'});
      FakeSupabase.on('users', (_) => []);
      final s = newState();
      await s.uploadImage(
        XFile.fromData(Uint8List.fromList([1]), name: 'a.jpg'),
      );
      FakeSupabase.requests.clear();

      expect(await s.save('새닉네임'), isTrue);

      final req = FakeSupabase.requests.single;
      expect(req.method, 'PATCH');
      expect(req.url.queryParameters['id'], 'eq.u1');
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      expect(body['nickname'], '새닉네임');
      expect(body['profile_image_url'], s.imageUrl);
      expect(
        SessionManager.instance.user?.nickname,
        '새닉네임',
        reason: '세션 닉네임도 갱신(토큰 유지)',
      );
    });

    test('실패: false 반환, saving 해제', () async {
      FakeSupabase.on('users', (_) => FakeSupabase.error(500, {'error': 'x'}));
      final s = newState();

      expect(await s.save('새닉네임'), isFalse);
      expect(s.saving, isFalse);
    });
  });

  group('ProfileEditState.refreshRegion', () {
    test('GPS 인증 후 서버 값으로 주소·인증 상태를 갱신한다', () async {
      FakeSupabase.on(
        'public_profiles',
        (_) => {'address': '서울 종로구 효자동', 'is_location_verified': true},
      );
      final s = newState();

      await s.refreshRegion();

      expect(s.regionName, '효자동');
      expect(s.verified, isTrue);
    });

    test('조회 실패 시 기존 값 유지(인증 자체는 서버에 반영됨)', () async {
      FakeSupabase.on('public_profiles', (_) => throw Exception('네트워크'));
      final s = newState();

      await s.refreshRegion();

      expect(s.regionName, '청운동', reason: '기존 값 유지');
    });
  });
}
