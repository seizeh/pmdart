import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/services/app_events.dart';
import 'package:pawmate/services/session.dart';
import 'package:pawmate/services/social_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_session.dart';
import '../helpers/fake_supabase.dart';

const _me = AuthUser(
  id: 'u1',
  username: 'me',
  nickname: '나',
  userType: 'no_pet',
);

Map<String, dynamic> profileRow(String id, {String? businessName}) => {
  'id': id,
  'nickname': '닉$id',
  'user_type': 'no_pet',
  'profile_image_url': null,
  'business_name': businessName,
  'business_photo_url': null,
  'review_count': 1,
  'pawing_count': 2,
  'pawmate_count': 3,
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

  group('SocialRepository.follow/unfollow — 얼굴 단위 팔로우', () {
    test('follow 는 얼굴(context) 포함 upsert + 중복 무시 + 소셜 이벤트 발행', () async {
      FakeSupabase.on('pawings', (_) => []);
      final before = AppEvents.instance.social.value;

      await SocialRepository.instance.follow('u2', business: true);

      final req = FakeSupabase.requests.single;
      expect(req.method, 'POST');
      expect(jsonDecode(req.body), {
        'follower_id': 'u1',
        'following_id': 'u2',
        'context': 'business',
      });
      expect(
        req.url.queryParameters['on_conflict'],
        'follower_id,following_id,context',
      );
      expect(req.headers['Prefer'], contains('ignore-duplicates'));
      expect(AppEvents.instance.social.value, before + 1);
    });

    test('unfollow 는 해당 얼굴의 행만 지운다(다른 얼굴 팔로우 유지)', () async {
      FakeSupabase.on('pawings', (_) => []);

      await SocialRepository.instance.unfollow('u2');

      final q = FakeSupabase.requests.single.url.queryParameters;
      expect(FakeSupabase.requests.single.method, 'DELETE');
      expect(q['follower_id'], 'eq.u1');
      expect(q['following_id'], 'eq.u2');
      expect(q['context'], 'eq.personal');
    });

    test('isFollowing 은 행 존재 여부로 판정', () async {
      FakeSupabase.on(
        'pawings',
        (_) => [
          {'following_id': 'u2'},
        ],
      );
      expect(await SocialRepository.instance.isFollowing('u2'), isTrue);

      FakeSupabase.on('pawings', (_) => []);
      expect(await SocialRepository.instance.isFollowing('u2'), isFalse);
    });
  });

  group('SocialRepository.fetchPawing', () {
    test('내 팔로우 목록은 전부 following=true 로 표시된다', () async {
      FakeSupabase.on('v_pawing', (_) => [profileRow('u2'), profileRow('u3')]);

      final list = await SocialRepository.instance.fetchPawing();

      expect(list, hasLength(2));
      expect(list.every((c) => c.following == true), isTrue);
    });
  });

  group('SocialRepository.searchUsers — 두 얼굴 검색 + 팔로우 병합', () {
    test('상호 매칭(업체 얼굴)이 먼저 오고, 팔로우 여부는 얼굴 단위로 매칭된다', () async {
      // public_profiles 는 닉네임/상호 두 쿼리로 나가므로 파라미터로 구분해 응답.
      FakeSupabase.on('public_profiles', (req) {
        final q = req.url.queryParameters;
        if (q.containsKey('business_name')) {
          return [profileRow('u3', businessName: '멍멍상회')];
        }
        return [profileRow('u2')];
      });
      // 나는 u3 의 '업체 얼굴'만 팔로우 중.
      FakeSupabase.on(
        'pawings',
        (_) => [
          {'following_id': 'u3', 'context': 'business'},
        ],
      );

      final list = await SocialRepository.instance.searchUsers('멍');

      expect(list, hasLength(2));
      final biz = list[0];
      expect(biz.isBusiness, isTrue, reason: '업체 얼굴 결과가 먼저');
      expect(biz.businessName, '멍멍상회');
      expect(biz.following, isTrue, reason: 'business 컨텍스트 팔로우와 매칭');

      final personal = list[1];
      expect(personal.isBusiness, isFalse);
      expect(personal.businessName, isNull, reason: '개인 얼굴엔 상호 미노출');
      expect(personal.following, isFalse);
    });

    test('개인 얼굴 팔로우는 업체 얼굴 결과와 매칭되지 않는다', () async {
      FakeSupabase.on('public_profiles', (req) {
        final q = req.url.queryParameters;
        if (q.containsKey('business_name')) {
          return [profileRow('u3', businessName: '멍멍상회')];
        }
        return [];
      });
      FakeSupabase.on(
        'pawings',
        (_) => [
          {'following_id': 'u3', 'context': 'personal'},
        ],
      );

      final list = await SocialRepository.instance.searchUsers('멍');

      expect(list.single.following, isFalse);
    });

    test('빈 검색어는 요청 없이 빈 결과', () async {
      expect(await SocialRepository.instance.searchUsers('  '), isEmpty);
      expect(FakeSupabase.requests, isEmpty);
    });
  });
}
