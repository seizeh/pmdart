import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/services/session.dart';
import 'package:pawmate/state/user_profile_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_session.dart';
import '../helpers/fake_supabase.dart';

const _me = AuthUser(
  id: 'u1',
  username: 'me',
  nickname: '나',
  userType: 'no_pet',
);

void mockProfileRow({bool business = false}) {
  FakeSupabase.on(
    'public_profiles',
    (_) => {
      'nickname': '냥집사',
      'user_type': 'no_pet',
      'is_business': business,
      'business_name': business ? '멍멍상회' : null,
      'business_facility_id': business ? 'f1' : null,
    },
  );
}

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

  group('UserProfileState — 두 얼굴 규칙(0025)', () {
    test('개인 프로필: 개인 글만 조회, 방문 후기 미조회', () async {
      mockProfileRow();
      final s = UserProfileState(userId: 'u2', forcePersonalFace: false);

      await s.load();
      await pumpEventQueue();

      expect(s.bizFace, isFalse);
      expect(s.displayName(s.profile!), '냥집사');
      final feedReq = FakeSupabase.requests.firstWhere(
        (r) => r.url.path.contains('v_post_feed'),
      );
      expect(feedReq.url.queryParameters['user_id'], 'eq.u2');
      expect(
        FakeSupabase.requests.map((r) => r.url.path),
        everyElement(isNot(contains('facility_reviews'))),
      );
    });

    test('업체 맥락 + 업체 모드 상대: 업체 얼굴 — 상호 표시·업체 글·방문 후기', () async {
      mockProfileRow(business: true);
      FakeSupabase.on('facility_reviews', (_) => []);
      final s = UserProfileState(userId: 'u2', forcePersonalFace: false);

      await s.load();
      await pumpEventQueue();

      expect(s.bizFace, isTrue);
      expect(s.displayName(s.profile!), '멍멍상회');
      expect(
        FakeSupabase.requests.any(
          (r) => r.url.path.contains('facility_reviews'),
        ),
        isTrue,
        reason: '매칭 시설 방문 후기 조회',
      );
    });

    test('개인 맥락 진입은 상대가 업체 모드여도 개인 얼굴 고정(연결 차단)', () async {
      mockProfileRow(business: true);
      final s = UserProfileState(userId: 'u2', forcePersonalFace: true);

      await s.load();
      await pumpEventQueue();

      expect(s.bizFace, isFalse, reason: '업체 모드 상대라도 개인 얼굴');
      expect(s.displayName(s.profile!), '냥집사', reason: '상호 미노출');
      expect(
        FakeSupabase.requests.map((r) => r.url.path),
        everyElement(isNot(contains('facility_reviews'))),
        reason: '업체 후기 미조회 — 운영 업체 연결 차단',
      );
    });
  });

  group('UserProfileState.load — 상태 전이', () {
    test('실패: 첫 로드는 에러 표시, silent 는 기존 데이터 유지', () async {
      FakeSupabase.on('public_profiles', (_) => throw Exception('네트워크'));
      final s = UserProfileState(userId: 'u2', forcePersonalFace: false);

      await s.load();
      expect(s.error, isTrue);

      mockProfileRow();
      await s.load();
      expect(s.error, isFalse);
      expect(s.profile, isNotNull);

      FakeSupabase.on('public_profiles', (_) => throw Exception('네트워크'));
      await s.load(silent: true);
      expect(s.error, isFalse, reason: 'silent 실패는 에러 미표시');
      expect(s.profile, isNotNull);
    });

    test('내 프로필이면 팔로우 상태를 조회하지 않는다', () async {
      mockProfileRow();
      final s = UserProfileState(userId: 'u1', forcePersonalFace: false);

      await s.load();
      await pumpEventQueue();

      expect(s.isMe, isTrue);
      // 통계 카운트(팔로잉/팔로워 수)도 pawings 를 조회하므로, isFollowing
      // 특유의 시그니처(follower_id + following_id 동시 필터)로 구분한다.
      expect(
        FakeSupabase.requests.any(
          (r) =>
              r.url.queryParameters.containsKey('follower_id') &&
              r.url.queryParameters.containsKey('following_id'),
        ),
        isFalse,
        reason: '내 프로필엔 팔로우 상태 조회 없음',
      );
    });
  });

  group('UserProfileState.toggleFollow', () {
    test('낙관적 토글 + 700ms 쿨다운(연속 탭 1회만) — 얼굴 단위 컨텍스트', () async {
      mockProfileRow();
      final s = UserProfileState(userId: 'u2', forcePersonalFace: false);
      await s.load();
      await pumpEventQueue();
      FakeSupabase.requests.clear();

      await s.toggleFollow();
      await s.toggleFollow(); // 즉시 재탭 — 무시

      expect(s.following, isTrue);
      expect(FakeSupabase.requests, hasLength(1));
      expect(FakeSupabase.requests.single.method, 'POST');
    });

    test('실패하면 롤백한다', () async {
      mockProfileRow();
      final s = UserProfileState(userId: 'u2', forcePersonalFace: false);
      await s.load();
      await pumpEventQueue();
      FakeSupabase.on('pawings', (_) => throw Exception('네트워크'));

      await s.toggleFollow();

      expect(s.following, isFalse);
    });
  });
}
