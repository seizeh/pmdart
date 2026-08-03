import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/services/community_repository.dart';
import 'package:pawmate/services/session.dart';

import '../helpers/fake_session.dart';
import '../helpers/fake_supabase.dart';

Map<String, dynamic> postRow(String id) => {
  'id': id,
  'title': '제목 $id',
  'user_id': 'u1',
  'created_at': '2026-07-01T00:00:00Z',
};

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    installFakeSecureStorage();
    await FakeSupabase.init();
  });

  setUp(() async {
    FakeSupabase.reset();
    // 활동범위 게이트는 로그인 사용자에게만 도는 경로다(게스트는 아래 그룹 참고).
    await SessionManager.instance.setSession(
      'fake-access',
      const AuthUser(
        id: 'u1',
        username: 'u1',
        nickname: 'U1',
        userType: 'pet_owner',
      ),
    );
  });

  tearDown(() async => SessionManager.instance.clear());

  group('CommunityRepository.fetchFeed — 게스트', () {
    test('비로그인이면 feed_region_codes 를 아예 호출하지 않는다', () async {
      // 회귀: anon 에는 이 함수의 EXECUTE 가 없어 부르면 매번 401 이 찍혔다.
      // (PostgREST 가 권한 거부를 42501 과 함께 401 로 돌려줘 인증 문제처럼 보인다.)
      await SessionManager.instance.clear();
      FakeSupabase.on('v_post_feed', (_) => [postRow('p1')]);

      final posts = await CommunityRepository.instance.fetchFeed();

      expect(posts.single.id, 'p1');
      expect(
        FakeSupabase.requests.any(
          (r) => r.url.path.endsWith('feed_region_codes'),
        ),
        isFalse,
        reason: '게스트는 인증 동네가 없어 조회할 것이 없다',
      );
    });

    test('비로그인이어도 지역 필터 없이 피드는 그대로 온다', () async {
      await SessionManager.instance.clear();
      FakeSupabase.on('v_post_feed', (_) => [postRow('p1'), postRow('p2')]);

      final posts = await CommunityRepository.instance.fetchFeed();

      expect(posts, hasLength(2));
      final feedReq = FakeSupabase.requests.last;
      expect(feedReq.url.queryParameters.containsKey('region_code'), isFalse);
    });
  });

  group('CommunityRepository.fetchFeed — 활동범위 게이트', () {
    test('활동범위 미설정(null)이면 지역 필터 없이 최신 100건을 요청한다', () async {
      FakeSupabase.on('feed_region_codes', (_) => null);
      FakeSupabase.on('v_post_feed', (_) => [postRow('p1')]);

      final posts = await CommunityRepository.instance.fetchFeed();

      expect(posts.single.id, 'p1');
      final feedReq = FakeSupabase.requests.last;
      expect(feedReq.url.path, '/rest/v1/v_post_feed');
      expect(feedReq.url.queryParameters['order'], 'created_at.desc.nullslast');
      expect(feedReq.url.queryParameters['limit'], '100');
      expect(feedReq.url.queryParameters.containsKey('region_code'), isFalse);
    });

    test('활동범위 안에 동이 하나도 없으면 피드 요청 없이 빈 목록', () async {
      FakeSupabase.on('feed_region_codes', (_) => <String>[]);

      final posts = await CommunityRepository.instance.fetchFeed();

      expect(posts, isEmpty);
      expect(FakeSupabase.requests, hasLength(1), reason: 'RPC 한 번뿐이어야 한다');
    });

    test('feed_region_codes 실패는 전국 피드 폴백이 아니라 피드 실패로 승격한다(#234)', () async {
      // 조용히 필터 없이 진행하면 멀쩡해 보이는 전국 피드가 나간다 —
      // 오류가 데이터처럼 보이는 실패 모드. 던져서 화면의 재시도 UI 에 태운다.
      FakeSupabase.on(
        'feed_region_codes',
        (_) => FakeSupabase.error(500, {'message': 'boom'}),
      );
      FakeSupabase.on('v_post_feed', (_) => [postRow('p1')]);

      await expectLater(
        CommunityRepository.instance.fetchFeed(),
        throwsA(anything),
      );
      expect(
        FakeSupabase.requests.any((r) => r.url.path.contains('v_post_feed')),
        isFalse,
        reason: '필터 미확정 상태로 피드를 요청하면 안 된다',
      );
    });

    test('활동범위 동 코드들이 오면 region_code in 필터로 좁힌다', () async {
      FakeSupabase.on('feed_region_codes', (_) => ['1111010100', '1111010200']);
      FakeSupabase.on('v_post_feed', (_) => []);

      await CommunityRepository.instance.fetchFeed();

      final regionParam =
          FakeSupabase.requests.last.url.queryParameters['region_code']!;
      expect(regionParam, startsWith('in.('));
      expect(regionParam, contains('1111010100'));
      expect(regionParam, contains('1111010200'));
    });

    test('카테고리 지정 시 eq 필터가 붙는다', () async {
      FakeSupabase.on('feed_region_codes', (_) => null);
      FakeSupabase.on('v_post_feed', (_) => []);

      await CommunityRepository.instance.fetchFeed(category: 'walk_together');

      expect(
        FakeSupabase.requests.last.url.queryParameters['category'],
        'eq.walk_together',
      );
    });

    test('검색어의 or() 파서 위험 문자(쉼표·괄호·%·*)는 공백으로 정제된다', () async {
      FakeSupabase.on('feed_region_codes', (_) => null);
      FakeSupabase.on('v_post_feed', (_) => []);

      await CommunityRepository.instance.fetchFeed(query: '멍멍(1),2');

      final or = FakeSupabase.requests.last.url.queryParameters['or']!;
      expect(or, contains('title.ilike.%멍멍 1  2%'));
      expect(or, contains('content.ilike.%멍멍 1  2%'));
      expect(or, isNot(contains('(1)')));
    });
  });

  group('CommunityRepository.toggleHeart — 경합 관용(#239)', () {
    test('중복 INSERT(23505)는 하트 성공으로 수렴한다(연타·낡은 스냅샷)', () async {
      FakeSupabase.on(
        'post_hearts',
        (_) => FakeSupabase.error(409, {
          'code': '23505',
          'message': 'duplicate key value',
        }),
      );

      expect(
        await CommunityRepository.instance.toggleHeart('p1', false),
        isTrue,
      );
    });

    test('중복이 아닌 오류는 그대로 던진다', () async {
      FakeSupabase.on(
        'post_hearts',
        (_) => FakeSupabase.error(500, {'code': 'XX000', 'message': 'boom'}),
      );

      await expectLater(
        CommunityRepository.instance.toggleHeart('p1', false),
        throwsA(anything),
      );
    });
  });

  group('CommunityRepository.deletePosts — 부분 실패 가시화(#239)', () {
    test('중간 실패도 끝까지 진행하고 실패 개수를 담아 던진다', () async {
      var calls = 0;
      FakeSupabase.on('delete_my_post', (_) {
        calls++;
        return calls == 2 ? FakeSupabase.error(500, {'message': 'boom'}) : null;
      });

      await expectLater(
        CommunityRepository.instance.deletePosts(['p1', 'p2', 'p3']),
        throwsA(isA<StateError>()),
      );
      expect(calls, 3, reason: '한 건 실패가 나머지 삭제를 막지 않는다');
    });
  });

  group('CommunityRepository.fetchUserPosts — 얼굴(authoredAs) 필터', () {
    test('authoredAs 지정 시 posts 의 모드 맵과 병합해 해당 얼굴 글만 남긴다', () async {
      FakeSupabase.on('v_post_feed', (_) => [postRow('p1'), postRow('p2')]);
      FakeSupabase.on(
        '/rest/v1/posts',
        (_) => [
          {'id': 'p1', 'authored_as': 'business'},
          // p2 는 모드 행 없음 → personal 로 간주
        ],
      );

      final business = await CommunityRepository.instance.fetchUserPosts(
        'u1',
        authoredAs: 'business',
      );
      expect(business.map((p) => p.id), ['p1']);

      final personal = await CommunityRepository.instance.fetchUserPosts(
        'u1',
        authoredAs: 'personal',
      );
      expect(personal.map((p) => p.id), ['p2']);
    });

    test('모드 조회가 깨져도 글을 숨기지 않고 전체를 유지한다(안전 폴백)', () async {
      FakeSupabase.on('v_post_feed', (_) => [postRow('p1'), postRow('p2')]);
      FakeSupabase.on('/rest/v1/posts', (_) => '이상한 응답');

      final posts = await CommunityRepository.instance.fetchUserPosts(
        'u1',
        authoredAs: 'business',
      );

      expect(posts, hasLength(2), reason: '표시 누락보다 전체 유지가 안전');
    });

    test('authoredAs 미지정이면 모드 조회 자체를 하지 않는다', () async {
      FakeSupabase.on('v_post_feed', (_) => [postRow('p1')]);

      await CommunityRepository.instance.fetchUserPosts('u1');

      expect(FakeSupabase.requests, hasLength(1));
      expect(
        FakeSupabase.requests.single.url.queryParameters['user_id'],
        'eq.u1',
      );
    });
  });
}
