import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/services/app_events.dart';
import 'package:pawmate/services/session.dart';
import 'package:pawmate/state/my_info_state.dart';
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

  void mockProfile({String mode = 'personal'}) {
    FakeSupabase.on('public_profiles', (_) => {'nickname': '집사'});
    FakeSupabase.on('users', (_) => {'active_mode': mode});
    // 통계 카운트·펫·초대·게시글은 기본 응답([], count 0)으로 충분.
  }

  group('MyInfoState.load', () {
    test('개인 모드: 프로필을 채우고 업체 후기 요약은 조회하지 않는다', () async {
      mockProfile();
      final s = MyInfoState(isGuest: false);

      await s.load();

      expect(s.loading, isFalse);
      expect(s.error, isNull);
      expect(s.profile?.nickname, '집사');
      expect(s.profile?.activeMode, 'personal');
      expect(s.bizReviewCount, isNull, reason: '개인 모드엔 업체 후기 요약 없음');
      expect(
        FakeSupabase.requests.map((r) => r.url.path),
        everyElement(isNot(contains('business_profiles'))),
      );
    });

    test('업체 모드: 후기 요약까지 조회한다(시설 미매칭이면 0건)', () async {
      mockProfile(mode: 'business');
      FakeSupabase.on('business_profiles', (_) => []);
      final s = MyInfoState(isGuest: false);

      await s.load();

      expect(s.profile?.activeMode, 'business');
      expect(s.bizReviewCount, 0);
      expect(s.bizReviewAvg, isNull);
    });

    test('첫 로드 실패면 에러 표시, 이후 silent 실패는 기존 데이터 유지', () async {
      FakeSupabase.on('public_profiles', (_) => throw Exception('네트워크'));
      final s = MyInfoState(isGuest: false);

      await s.load();
      expect(s.error, '프로필을 불러오지 못했어요');
      expect(s.profile, isNull);

      // 복구 후 성공
      mockProfile();
      await s.load();
      expect(s.error, isNull);
      expect(s.profile, isNotNull);

      // 다시 실패해도(silent) 기존 프로필 유지 + 에러 미표시
      FakeSupabase.on('public_profiles', (_) => throw Exception('네트워크'));
      FakeSupabase.on('users', (_) => throw Exception('네트워크'));
      await s.load(silent: true);
      expect(s.profile, isNotNull, reason: '조용한 새로고침 실패 시 기존 데이터 유지');
      expect(s.error, isNull);
    });

    test('게시글 조회만 실패하면 프로필은 갱신하고 기존 글 목록을 유지한다', () async {
      mockProfile();
      FakeSupabase.on('v_post_feed', (_) => throw Exception('네트워크'));
      final s = MyInfoState(isGuest: false);

      await s.load();

      expect(s.profile, isNotNull);
      expect(s.error, isNull);
      expect(s.myPosts, isEmpty);
    });
  });

  group('MyInfoState — AppEvents 자동 새로고침', () {
    test('소셜/프로필 변경 이벤트에 silent 재로드하고, dispose 후엔 반응하지 않는다', () async {
      mockProfile();
      final s = MyInfoState(isGuest: false);
      s.init();
      await pumpEventQueue();
      final baseline = FakeSupabase.requests.length;

      AppEvents.instance.notifySocial();
      await pumpEventQueue();
      expect(
        FakeSupabase.requests.length,
        greaterThan(baseline),
        reason: '팔로우 변경 → 재로드',
      );

      final afterSocial = FakeSupabase.requests.length;
      AppEvents.instance.notifyProfile();
      await pumpEventQueue();
      expect(
        FakeSupabase.requests.length,
        greaterThan(afterSocial),
        reason: '프로필 변경 → 재로드',
      );

      s.dispose();
      final afterDispose = FakeSupabase.requests.length;
      AppEvents.instance.notifySocial();
      await pumpEventQueue();
      expect(
        FakeSupabase.requests.length,
        afterDispose,
        reason: 'dispose 후 리스너 해제',
      );
    });

    test('게스트는 초기 로드도 이벤트 구독도 하지 않는다', () async {
      final s = MyInfoState(isGuest: true);
      s.init();
      await pumpEventQueue();

      expect(FakeSupabase.requests, isEmpty);
      AppEvents.instance.notifySocial();
      await pumpEventQueue();
      expect(FakeSupabase.requests, isEmpty);
      s.dispose();
    });
  });
}
