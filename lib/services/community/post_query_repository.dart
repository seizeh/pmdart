/// 게시글 **조회** — 피드·프로필·펫·지도·단건.
///
/// 읽기 경로가 공유하는 `_postsFromRows`(하트 여부·작성자 정보 보강)가 여기 있다 —
/// 이 헬퍼가 조회 계열을 하나로 묶는 실제 근거다.
library;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/community.dart';
import '../../models/post_cluster.dart';
import '../error_reporter.dart';
import '../query_limits.dart';
import '../session.dart';

class PostQueryRepository {
  PostQueryRepository._();
  static final PostQueryRepository instance = PostQueryRepository._();

  SupabaseClient get _c => Supabase.instance.client;

  String? get _uid => SessionManager.instance.user?.id;

  String _requireUid() {
    final uid = _uid;
    if (uid == null) {
      throw StateError('로그인이 필요합니다');
    }
    return uid;
  }

  /// v_post_feed 행 목록 → [Post] 목록.
  ///
  /// 뷰가 아직 미디어 컬럼(image_mime_type/image_thumbnail_url)을 노출하지
  /// 않으면 posts 에서 보강한다(영상 글 표시용 — posts_select RLS 가 visible
  /// 행을 모두 통과시키므로 비로그인도 가능). 뷰가 컬럼을 갖게 되면 행에 키가
  /// 존재하므로 추가 조회 없이 그대로 통과한다. 보강 실패는 사진 표시로 폴백.
  Future<List<Post>> _postsFromRows(List<dynamic> rows) async {
    final maps = rows.cast<Map<String, dynamic>>();
    if (maps.isNotEmpty && !maps.first.containsKey('image_mime_type')) {
      final ids = [
        for (final m in maps)
          if (m['image_url'] != null) m['id'] as String,
      ];
      if (ids.isNotEmpty) {
        try {
          final media = await _c
              .from('posts')
              .select('id, image_mime_type, image_thumbnail_url')
              .inFilter('id', ids);
          final byId = {
            for (final m in (media as List).cast<Map<String, dynamic>>())
              m['id'] as String: m,
          };
          for (final m in maps) {
            final extra = byId[m['id']];
            if (extra != null) {
              m['image_mime_type'] = extra['image_mime_type'];
              m['image_thumbnail_url'] = extra['image_thumbnail_url'];
            }
          }
        } catch (e) {
          debugPrint('게시글 미디어 컬럼 보강 실패(사진 표시로 폴백): $e');
        }
      }
    }
    return [for (final m in maps) Post.fromJson(m)];
  }

  /// 게시글 피드. [category] 가 null 이면 전체. [query] 가 있으면 제목/내용 검색.
  /// 활동 범위가 설정돼 있으면 그 반경 안의 동네 게시글만 조회(서버가 region_code 산출).
  Future<List<Post>> fetchFeed({String? category, String? query}) async {
    // 활동범위 내 동 코드들. null = 필터 없음(미인증/미설정), [] = 반경 내 게시글 없음.
    List<String>? codes;
    // 비로그인(게스트)은 인증 동네가 없어 조회할 것이 없다. 그런데도 부르면
    // feed_region_codes 가 anon EXECUTE 를 안 줘서 **매번 401 이 찍힌다**
    // (PostgREST 는 권한 거부를 42501 과 함께 401 로 돌려준다 — 인증 문제처럼 보인다).
    // 결과는 어차피 null 이라 동작은 같고, 왕복 한 번과 콘솔 오류만 사라진다.
    if (SessionManager.instance.isLoggedIn) {
      try {
        final res = await _c.rpc('feed_region_codes');
        if (res != null) {
          codes = [for (final c in (res as List)) c as String];
        }
      } catch (e, st) {
        // 조용히 codes=null(필터 없음)로 폴백하면 하이퍼로컬 전제가 깨진 채
        // **멀쩡해 보이는 전국 피드**가 나간다 — 오류가 데이터처럼 보이는
        // 최악의 실패 모드다(#234). 피드 실패로 승격해 화면의 오류 상태
        // (재시도 UI)에 태운다. silent 갱신이면 기존 목록이 유지된다.
        ErrorReporter.userFacing(
          e,
          where: 'community.feedRegionCodes',
          stackTrace: st,
        );
        rethrow;
      }
    }
    if (codes != null && codes.isEmpty) return const [];

    var q = _c.from('v_post_feed').select();
    if (category != null) {
      q = q.eq('category', category);
    }
    // or() 파서를 깨뜨릴 수 있는 문자 제거 후 제목/내용 ilike 검색.
    final term = (query ?? '').replaceAll(RegExp(r'[,()%*]'), ' ').trim();
    if (term.isNotEmpty) {
      q = q.or('title.ilike.%$term%,content.ilike.%$term%');
    }
    if (codes != null) {
      q = q.inFilter('region_code', codes);
    }
    final rows = await q.order('created_at', ascending: false).limit(100);
    return _postsFromRows(rows as List);
  }

  /// 특정 사용자의 게시글 (내 게시글 등).
  /// [authoredAs] 지정 시 해당 모드('personal'|'business')로 작성한 글만 —
  /// 업체/일반 프로필 분리(0025 후속). 피드 뷰에는 없는 컬럼이라 posts 에서
  /// 모드 맵을 따로 읽어 필터한다(실패 시 전체 유지 — 표시 누락보다 안전).
  Future<List<Post>> fetchUserPosts(String userId, {String? authoredAs}) async {
    final rows = await _c
        .from('v_post_feed')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    var posts = guardTruncation(
      await _postsFromRows(rows as List),
      where: 'community.fetchUserPosts',
    );
    if (authoredAs != null && posts.isNotEmpty) {
      try {
        final modes = await _c
            .from('posts')
            .select('id, authored_as')
            .eq('user_id', userId);
        final byId = {
          for (final m in (modes as List).cast<Map<String, dynamic>>())
            m['id'] as String: (m['authored_as'] as String?) ?? 'personal',
        };
        posts = posts
            .where((p) => (byId[p.id] ?? 'personal') == authoredAs)
            .toList();
      } catch (e) {
        debugPrint('얼굴 필터용 모드 조회 실패 — 전체 유지(표시 누락 방지): $e');
      }
    }
    return posts;
  }

  /// 특정 펫이 연결된(태그된) 공개 게시글 — 펫 공개 프로필용.
  /// post_pets RLS 가 visible 글만 통과시키므로 그대로 조회하면 된다.
  Future<List<Post>> fetchPetPosts(String petId) async {
    final links = await _c
        .from('post_pets')
        .select('post_id')
        .eq('pet_id', petId);
    final ids = guardTruncation([
      for (final l in (links as List).cast<Map<String, dynamic>>())
        l['post_id'] as String,
    ], where: 'community.fetchPetPosts.ids');
    return fetchPostsByIds(ids);
  }

  /// 지도 bbox 내 행정동별 게시글 클러스터 (0021 §6).
  Future<List<PostCluster>> postsByRegion({
    required double minLng,
    required double minLat,
    required double maxLng,
    required double maxLat,
  }) async {
    final rows = await _c.rpc(
      'posts_by_region',
      params: {
        'p_min_lng': minLng,
        'p_min_lat': minLat,
        'p_max_lng': maxLng,
        'p_max_lat': maxLat,
      },
    );
    return (rows as List)
        .map((r) => PostCluster.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// 행정동 중심좌표 보충(동 이름 지오코딩) — 멱등. 실패는 무시(폴백 동작).
  Future<void> syncDongCentroids() async {
    try {
      await _c.functions.invoke('sync-dong-centroids', body: {});
    } catch (e) {
      ErrorReporter.ignored(
        e,
        where: 'community.syncDongCentroids',
        why: '비어있으면 posts_by_region 이 사용자 평균으로 폴백한다',
      );
    }
  }

  /// 게시글 ID 목록으로 피드 행 조회 (클러스터 탭 → 그 지역 글 목록).
  Future<List<Post>> fetchPostsByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final rows = await _c
        .from('v_post_feed')
        .select()
        .inFilter('id', ids)
        .order('created_at', ascending: false);
    return _postsFromRows(rows as List);
  }

  /// 단일 게시글 조회 (알림 등에서 이동용). 없으면 null.
  Future<Post?> fetchPost(String postId) async {
    final row = await _c
        .from('v_post_feed')
        .select()
        .eq('id', postId)
        .maybeSingle();
    if (row == null) return null;
    return (await _postsFromRows([row])).first;
  }

  /// 내가 하트한 게시글.
  Future<List<Post>> fetchHeartedPosts() async {
    final uid = _requireUid();
    final hearts = await _c
        .from('post_hearts')
        .select('post_id')
        .eq('user_id', uid);
    // 오래 쓴 계정의 하트 이력이 서버 상한에 닿을 수 있다 — 닿으면 그 위 글들이
    // '하트 안 함' 으로 보인다(0031 §5.2).
    final ids = guardTruncation([
      for (final h in hearts as List) h['post_id'] as String,
    ], where: 'community.fetchHeartedPosts.ids');
    if (ids.isEmpty) return const [];
    final rows = await _c
        .from('v_post_feed')
        .select()
        .inFilter('id', ids)
        .order('created_at', ascending: false);
    return _postsFromRows(rows as List);
  }
}
