import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/community.dart';
import 'session.dart';

/// 커뮤니티(게시글/하트/댓글/지원) 데이터 접근.
/// 모든 쓰기는 RLS(app.uid() = JWT sub) 를 통과해야 하므로 로그인 필요.
class CommunityRepository {
  CommunityRepository._();
  static final CommunityRepository instance = CommunityRepository._();

  SupabaseClient get _c => Supabase.instance.client;
  String? get _uid => SessionManager.instance.user?.id;

  /// 게시글 피드. [category] 가 null 이면 전체.
  Future<List<Post>> fetchFeed({String? category}) async {
    var query = _c.from('v_post_feed').select();
    if (category != null) {
      query = query.eq('category', category);
    }
    final rows = await query.order('created_at', ascending: false).limit(100);
    return (rows as List)
        .map((r) => Post.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// 특정 사용자의 게시글 (내 게시글 등).
  Future<List<Post>> fetchUserPosts(String userId) async {
    final rows = await _c
        .from('v_post_feed')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => Post.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// 단일 게시글 조회 (알림 등에서 이동용). 없으면 null.
  Future<Post?> fetchPost(String postId) async {
    final row =
        await _c.from('v_post_feed').select().eq('id', postId).maybeSingle();
    return row == null ? null : Post.fromJson(row);
  }

  /// 내가 하트한 게시글.
  Future<List<Post>> fetchHeartedPosts() async {
    final uid = _requireUid();
    final hearts =
        await _c.from('post_hearts').select('post_id').eq('user_id', uid);
    final ids = [for (final h in hearts as List) h['post_id'] as String];
    if (ids.isEmpty) return const [];
    final rows = await _c
        .from('v_post_feed')
        .select()
        .inFilter('id', ids)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((r) => Post.fromJson(r as Map<String, dynamic>))
        .toList();
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
    String? photoToken,
  }) async {
    _requireUid();
    final postId = await _c.rpc('create_post_verified', params: {
      'p_category': category,
      'p_title': title,
      'p_content': content,
      'p_scheduled_at': scheduledAt?.toUtc().toIso8601String(),
      'p_pet_ids': petIds.isEmpty ? null : petIds,
      'p_image_url': imageUrl,
      'p_image_mime': imageMime,
      'p_image_size': imageSize,
      'p_photo_token': photoToken,
    });
    return postId as String;
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
      final res =
          await _c.rpc('can_manage_post_applicants', params: {'p_post': postId});
      return res == true;
    } catch (_) {
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
    final bucket =
        DateTime.utc(now.year, now.month, now.day, now.hour).toIso8601String();
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
    } catch (_) {
      return false;
    }
  }

  /// 내 반려동물 목록 (작성 시 연결용).
  Future<List<MyPet>> fetchMyPets() async {
    final uid = _requireUid();
    final rows = await _c
        .from('pet_guardians')
        .select(
            'role, pets(id, name, species, pet_status, ai_ref_image_url, pet_match_count)')
        .eq('user_id', uid);
    final result = <MyPet>[];
    for (final r in rows as List) {
      final pet = r['pets'] as Map<String, dynamic>?;
      if (pet == null) continue;
      if (pet['pet_status'] != 'active') continue;
      result.add(MyPet(
        id: pet['id'] as String,
        name: (pet['name'] ?? '') as String,
        species: (pet['species'] ?? '') as String,
        role: (r['role'] ?? 'co_guardian') as String,
        hasAiReference: pet['ai_ref_image_url'] != null,
        matchCount: (pet['pet_match_count'] ?? 0) as int,
      ));
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
