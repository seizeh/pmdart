import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/models/community.dart';
import 'package:pawmate/services/session.dart';
import 'package:pawmate/state/post_detail_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_session.dart';
import '../helpers/fake_supabase.dart';

const _me = AuthUser(
  id: 'u1',
  username: 'me',
  nickname: '나',
  userType: 'no_pet',
);

Post post({
  String id = 'p1',
  String userId = 'u2',
  String category = 'walk_together',
  bool hearted = false,
  int heartCount = 0,
}) => Post.fromJson({
  'id': id,
  'user_id': userId,
  'category': category,
  'hearted': hearted,
  'heart_count': heartCount,
  'view_count': 10,
});

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

  group('PostDetailState.init — 초기 로드 오케스트레이션', () {
    test('타인 매칭 글: 댓글·조회수·팔로우·권한·모드를 모두 조회한다', () async {
      FakeSupabase.on(
        'v_comment_feed',
        (_) => [
          {'id': 'c1', 'post_id': 'p1', 'created_at': '2026-07-01T00:00:00Z'},
        ],
      );
      FakeSupabase.on('can_manage_post_applicants', (_) => true);
      final s = PostDetailState(post: post(), isGuest: false);

      s.init();
      await pumpEventQueue();

      expect(s.comments, hasLength(1));
      expect(s.loadingComments, isFalse);
      expect(s.canManage, isTrue, reason: '공동보호자 권한 RPC 결과 반영');
      expect(s.managerChecked, isTrue);
      expect(s.post.viewCount, 11, reason: '조회수 집계 성공 시 +1');
      final paths = FakeSupabase.requests.map((r) => r.url.path).toList();
      expect(paths.where((p) => p.contains('post_views')), hasLength(1));
      expect(paths.where((p) => p.contains('pawings')), hasLength(1));
    });

    test('내 글: 조회수·팔로우·권한 요청 없이 즉시 관리자', () async {
      FakeSupabase.on('v_comment_feed', (_) => []);
      final s = PostDetailState(post: post(userId: 'u1'), isGuest: false);

      s.init();
      await pumpEventQueue();

      expect(s.isMyPost, isTrue);
      expect(s.canManage, isTrue);
      expect(s.managerChecked, isTrue);
      expect(
        FakeSupabase.requests.map((r) => r.url.path),
        everyElement(contains('v_comment_feed')),
      );
    });

    test('자유글은 지원 관련 조회(권한·모드)를 하지 않는다', () async {
      FakeSupabase.on('v_comment_feed', (_) => []);
      final s = PostDetailState(post: post(category: 'free'), isGuest: false);

      s.init();
      await pumpEventQueue();

      expect(s.isFreePost, isTrue);
      expect(s.managerChecked, isTrue);
      final paths = FakeSupabase.requests.map((r) => r.url.path);
      expect(paths.any((p) => p.contains('can_manage')), isFalse);
    });
  });

  group('PostDetailState.toggleHeart — 낙관적 하트', () {
    test('즉시 반영 후 서버 성공이면 유지', () async {
      FakeSupabase.on('post_hearts', (_) => []);
      final s = PostDetailState(post: post(), isGuest: false);

      final ok = await s.toggleHeart();

      expect(ok, isTrue);
      expect(s.post.hearted, isTrue);
      expect(s.post.heartCount, 1);
    });

    test('서버 실패면 롤백하고 false', () async {
      FakeSupabase.on('post_hearts', (_) => throw Exception('네트워크'));
      final s = PostDetailState(
        post: post(hearted: true, heartCount: 3),
        isGuest: false,
      );

      final ok = await s.toggleHeart();

      expect(ok, isFalse);
      expect(s.post.hearted, isTrue, reason: '원상 복구');
      expect(s.post.heartCount, 3);
    });
  });

  group('PostDetailState.toggleFollow — 쿨다운 낙관적 토글', () {
    test('700ms 안의 재탭은 무시된다(요청 1회)', () async {
      FakeSupabase.on('pawings', (_) => []);
      final s = PostDetailState(post: post(), isGuest: false);

      await s.toggleFollow();
      await s.toggleFollow(); // 즉시 재탭

      expect(s.following, isTrue, reason: '두 번째 탭은 무시');
      expect(FakeSupabase.requests, hasLength(1));
    });

    test('실패하면 롤백한다', () async {
      FakeSupabase.on('pawings', (_) => throw Exception('네트워크'));
      final s = PostDetailState(post: post(), isGuest: false);

      await s.toggleFollow();

      expect(s.following, isFalse);
    });
  });

  group('제출 플래그와 결과', () {
    test('submitComment: 성공 true, sending 은 진행 중에만 켜진다', () async {
      FakeSupabase.on('comments', (_) => []);
      final s = PostDetailState(post: post(), isGuest: false);

      final future = s.submitComment('안녕하세요');
      expect(s.sending, isTrue);
      expect(await future, isTrue);
      expect(s.sending, isFalse);
    });

    test('submitApply: 중복 지원 등 실패면 false', () async {
      FakeSupabase.on(
        'applications',
        (_) => FakeSupabase.error(409, {'code': '23505'}),
      );
      final s = PostDetailState(post: post(), isGuest: false);

      expect(await s.submitApply(), isFalse);
      expect(s.applying, isFalse);
    });
  });

  group('PostDetailState.reloadPost — 수정 후 재조회', () {
    test('최신 행으로 교체하고 true', () async {
      FakeSupabase.on(
        'v_post_feed',
        (_) => {
          'id': 'p1',
          'user_id': 'u2',
          'category': 'walk_together',
          'title': '수정된 제목',
        },
      );
      final s = PostDetailState(post: post(), isGuest: false);

      expect(await s.reloadPost(), isTrue);
      expect(s.post.title, '수정된 제목');
    });

    test('삭제됐으면 false(화면이 닫는다)', () async {
      FakeSupabase.on('v_post_feed', (_) => []);
      final s = PostDetailState(post: post(), isGuest: false);

      expect(await s.reloadPost(), isFalse);
    });
  });
}
