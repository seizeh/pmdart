import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/services/activity_repository.dart';
import 'package:pawmate/services/app_events.dart';
import 'package:pawmate/services/report_repository.dart';
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

/// 차단·해제가 화면 갱신 이벤트를 쏘는가.
///
/// 서버는 차단 즉시 v_post_feed 등에서 상대를 걸러내지만, 앱이 목록을 다시 받지
/// 않으면 화면은 그대로다. 실제로 그랬다 — 각 화면이 차단 후 자기 자신만 pop 하고
/// 커뮤니티 탭은 상세에서 돌아와도 재조회하지 않아, "차단했어요" 토스트 직후
/// **차단한 사람의 글이 그대로 보이는 피드**로 돌아왔다.
///
/// 이벤트 발행은 눈에 보이는 부수 효과가 아니라서 빠져도 아무도 모른다. 못 박아 둔다.
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

  group('차단·해제 후 화면 갱신 이벤트', () {
    test('block 은 feed·chat·social 을 함께 쏜다', () async {
      FakeSupabase.on('rpc/block_user', (_) => null);
      final feed = AppEvents.instance.feed.value;
      final chat = AppEvents.instance.chat.value;
      final social = AppEvents.instance.social.value;

      await ReportRepository.instance.block('u2', reason: '테스트');

      // 차단은 세 곳을 동시에 바꾼다 — 글·댓글(feed), 채팅방 목록(chat),
      // 그리고 서버가 팔로우를 양방향으로 끊으므로 Pawing 수·차단 목록(social).
      expect(AppEvents.instance.feed.value, feed + 1, reason: '피드 재조회 트리거');
      expect(AppEvents.instance.chat.value, chat + 1, reason: '채팅 목록 재조회 트리거');
      expect(AppEvents.instance.social.value, social + 1, reason: '소셜 재조회 트리거');
    });

    test('block RPC 가 실패하면 이벤트를 쏘지 않는다(갱신할 것이 없다)', () async {
      FakeSupabase.on(
        'rpc/block_user',
        (_) => FakeSupabase.error(403, {'message': 'nope'}),
      );
      final feed = AppEvents.instance.feed.value;

      await expectLater(
        ReportRepository.instance.block('u2'),
        throwsA(isA<Object>()),
      );

      expect(AppEvents.instance.feed.value, feed);
    });

    test('unblock 도 대칭으로 쏜다 — social 만 쏘면 피드가 안 돌아온다', () async {
      FakeSupabase.on('user_blocks', (_) => []);
      final feed = AppEvents.instance.feed.value;
      final chat = AppEvents.instance.chat.value;
      final social = AppEvents.instance.social.value;

      await ActivityRepository.instance.unblock('u2');

      expect(AppEvents.instance.social.value, social + 1);
      expect(
        AppEvents.instance.feed.value,
        feed + 1,
        reason: '해제하면 글이 다시 보여야 한다',
      );
      expect(AppEvents.instance.chat.value, chat + 1);
    });
  });
}
