import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/community.dart';
import 'error_reporter.dart';
import 'session.dart';
import 'storage_service.dart' show UploadedImage;

/// 행정동별 게시글 클러스터(지도용). posts_by_region RPC 결과 (0021 §6).
class PostCluster {
  final String regionCode;
  final int count;
  final double lat;
  final double lng;
  final List<String> postIds;

  const PostCluster({
    required this.regionCode,
    required this.count,
    required this.lat,
    required this.lng,
    required this.postIds,
  });

  factory PostCluster.fromJson(Map<String, dynamic> j) => PostCluster(
    regionCode: (j['region_code'] ?? '') as String,
    count: (j['post_count'] as num?)?.toInt() ?? 0,
    lat: (j['lat'] as num).toDouble(),
    lng: (j['lng'] as num).toDouble(),
    postIds: [
      for (final id in (j['post_ids'] as List? ?? const [])) id as String,
    ],
  );
}

/// 커뮤니티(게시글/하트/댓글/지원) 데이터 접근.
/// 모든 쓰기는 RLS(app.uid() = JWT sub) 를 통과해야 하므로 로그인 필요.
class CommunityRepository {
  CommunityRepository._();
  static final CommunityRepository instance = CommunityRepository._();

  SupabaseClient get _c => Supabase.instance.client;
  String? get _uid => SessionManager.instance.user?.id;

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
        // codes=null 은 '지역 필터 없음' 이라 전 지역 글이 섞여 나온다 —
        // 하이퍼로컬 전제가 조용히 깨지는 자리다.
        ErrorReporter.report(
          e,
          where: 'community.feedRegionCodes',
          stackTrace: st,
        );
        codes = null;
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
    var posts = await _postsFromRows(rows as List);
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
    final ids = [
      for (final l in (links as List).cast<Map<String, dynamic>>())
        l['post_id'] as String,
    ];
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
    final ids = [for (final h in hearts as List) h['post_id'] as String];
    if (ids.isEmpty) return const [];
    final rows = await _c
        .from('v_post_feed')
        .select()
        .inFilter('id', ids)
        .order('created_at', ascending: false);
    return _postsFromRows(rows as List);
  }

  /// 하트 토글. 반환값은 토글 후 hearted 상태.
  Future<bool> toggleHeart(String postId, bool currentlyHearted) async {
    final uid = _requireUid();
    if (currentlyHearted) {
      await _c
          .from('post_hearts')
          .delete()
          .eq('post_id', postId)
          .eq('user_id', uid);
      return false;
    } else {
      await _c.from('post_hearts').insert({'post_id': postId, 'user_id': uid});
      return true;
    }
  }

  /// 게시글 작성. 반환값은 새 게시글 id.
  ///
  /// create_post_verified RPC 로 일원화(0018): 토큰 전달·INSERT·post_pets 연결·토큰
  /// 소진이 한 트랜잭션에서 일어난다. 사진 필수 카테고리는 [photoToken] 필수
  /// (서버 트리거가 검증), free/adoption 은 토큰 없이 호출.
  Future<String> createPost({
    required String category,
    required String title,
    required String content,
    DateTime? scheduledAt,
    List<String> petIds = const [],
    String? imageUrl,
    String? imageMime,
    int? imageSize,
    String? imageThumbUrl,
    String? photoToken,
  }) async {
    _requireUid();
    final postId = await _c.rpc(
      'create_post_verified',
      params: {
        'p_category': category,
        'p_title': title,
        'p_content': content,
        'p_scheduled_at': scheduledAt?.toUtc().toIso8601String(),
        'p_pet_ids': petIds.isEmpty ? null : petIds,
        'p_image_url': imageUrl,
        'p_image_mime': imageMime,
        'p_image_size': imageSize,
        // 영상 첨부(free/news) 시 포스터 jpeg — 사진 글은 null.
        'p_image_thumb_url': imageThumbUrl,
        'p_photo_token': photoToken,
      },
    );
    return postId as String;
  }

  /// 내 게시글 제목·내용·약속일정·(자유/입양 한정)사진 수정 — update_my_post RPC.
  /// 일정이 실제로 바뀌면 진행 중 지원자에게 알림/푸시가 서버에서 발송된다.
  /// 카메라 인증 게시글의 검증 사진·카테고리·펫은 편집 대상이 아니다(서버가 무시).
  /// [scheduledAt] 은 일정 게시글이면 현재/변경 값, 아니면 null.
  /// [editImage] 가 true 면 자유/입양/소식 게시글의 미디어를 [image] 값으로
  /// 교체(null=제거). 영상으로 교체 시 [imageThumbUrl] 에 포스터를 전달한다.
  Future<void> updatePost(
    String postId, {
    required String title,
    required String content,
    DateTime? scheduledAt,
    bool editImage = false,
    UploadedImage? image,
    String? imageThumbUrl,
  }) async {
    _requireUid();
    await _c.rpc(
      'update_my_post',
      params: {
        'p_post': postId,
        'p_title': title,
        'p_content': content,
        'p_scheduled_at': scheduledAt?.toUtc().toIso8601String(),
        'p_edit_image': editImage,
        'p_image_url': image?.url,
        'p_image_mime': image?.mime,
        'p_image_size': image?.size,
        'p_image_thumb_url': imageThumbUrl,
      },
    );
  }

  /// 게시글 공유 링크 발급 — 공유 뷰어(go.pawmate.kr) 토큰 반환.
  /// 서버가 게시글당 유효 링크를 재사용한다(30일, visible 게시글만).
  Future<String> createPostShareLink(String postId) async {
    _requireUid();
    final rows =
        await _c.rpc('create_post_share_link', params: {'p_post': postId})
            as List;
    return (rows.first as Map<String, dynamic>)['token'] as String;
  }

  /// 내 게시글 삭제(소프트) — delete_my_post RPC.
  /// 직접 UPDATE 는 결과 행이 posts_select 비가시라 RLS(42501)에 막히므로,
  /// 본인 확인 후 RLS 를 우회하는 SECURITY DEFINER RPC 로 처리한다.
  Future<void> deletePost(String postId) async {
    _requireUid();
    await _c.rpc('delete_my_post', params: {'p_post': postId});
  }

  /// 여러 게시글 일괄 삭제(소프트).
  Future<void> deletePosts(Iterable<String> postIds) async {
    _requireUid();
    for (final id in postIds) {
      await deletePost(id);
    }
  }

  /// 댓글 목록.
  Future<List<Comment>> fetchComments(String postId) async {
    final rows = await _c
        .from('v_comment_feed')
        .select()
        .eq('post_id', postId)
        .order('created_at', ascending: true);
    return (rows as List)
        .map((r) => Comment.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// 댓글 작성.
  Future<void> addComment(String postId, String content) async {
    final uid = _requireUid();
    await _c.from('comments').insert({
      'post_id': postId,
      'user_id': uid,
      'content': content,
    });
  }

  /// 게시글 지원.
  Future<void> apply(String postId, {String? message}) async {
    final uid = _requireUid();
    await _c.from('applications').insert({
      'post_id': postId,
      'applicant_id': uid,
      if (message != null && message.isNotEmpty) 'message': message,
    });
  }

  /// 지원자 목록을 관리(조회·수락)할 수 있는지 — 작성자 또는 게시글 펫의 공동보호자.
  /// 비로그인/실패 시 false.
  Future<bool> canManageApplicants(String postId) async {
    if (_uid == null) return false;
    try {
      final res = await _c.rpc(
        'can_manage_post_applicants',
        params: {'p_post': postId},
      );
      return res == true;
    } catch (e, st) {
      // false 는 '권한 없음' 으로 읽혀 작성자에게 지원자 관리 버튼이 사라진다.
      ErrorReporter.report(
        e,
        where: 'community.canManageApplicants',
        stackTrace: st,
      );
      return false;
    }
  }

  /// 게시글 조회 기록 — post_views INSERT 시 트리거가 view_count +1.
  /// (post_id, user_id, view_bucket) 부분 유니크로 같은 시간대 재조회는 중복 집계되지 않는다.
  /// 조회 리타이어는 1시간(시간 단위 버킷). 실제로 1 증가했으면 true(낙관적 표시용),
  /// 중복/비로그인/실패면 false.
  Future<bool> recordView(String postId) async {
    final uid = _uid;
    if (uid == null) return false; // 비로그인은 RLS상 기록 불가
    final now = DateTime.now().toUtc();
    final bucket = DateTime.utc(
      now.year,
      now.month,
      now.day,
      now.hour,
    ).toIso8601String();
    try {
      await _c.from('post_views').insert({
        'post_id': postId,
        'user_id': uid,
        'view_bucket': bucket,
      });
      return true;
    } on PostgrestException catch (e) {
      // 23505 = 같은 버킷 내 중복 조회 → 정상(집계 안 됨)
      if (e.code == '23505') return false;
      return false;
    } catch (e) {
      ErrorReporter.ignored(
        e,
        where: 'community.recordView',
        why: '조회수 집계 실패 — 화면 표시와 무관하다',
      );
      return false;
    }
  }

  /// 내 반려동물 목록 (작성 시 연결용).
  Future<List<MyPet>> fetchMyPets() async {
    final uid = _requireUid();
    final rows = await _c
        .from('pet_guardians')
        .select(
          'role, pets(id, name, species, pet_status, identity_verified, '
          'pet_match_count, trust_score, verify_post_count)',
        )
        .eq('user_id', uid);
    final result = <MyPet>[];
    for (final r in rows as List) {
      final pet = r['pets'] as Map<String, dynamic>?;
      if (pet == null) continue;
      if (pet['pet_status'] != 'active') continue;
      result.add(
        MyPet(
          id: pet['id'] as String,
          name: (pet['name'] ?? '') as String,
          species: (pet['species'] ?? '') as String,
          role: (r['role'] ?? 'co_guardian') as String,
          isIdentityVerified: pet['identity_verified'] == true,
          matchCount: (pet['pet_match_count'] ?? 0) as int,
          trustScore: (pet['trust_score'] ?? 0) as int,
          verifyPostCount: (pet['verify_post_count'] ?? 0) as int,
        ),
      );
    }
    return result;
  }

  String _requireUid() {
    final uid = _uid;
    if (uid == null) {
      throw StateError('로그인이 필요합니다');
    }
    return uid;
  }
}
