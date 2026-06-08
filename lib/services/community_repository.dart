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
  Future<String> createPost({
    required String category,
    required String title,
    required String content,
    DateTime? scheduledAt,
    List<String> petIds = const [],
  }) async {
    final uid = _requireUid();
    final inserted = await _c
        .from('posts')
        .insert({
          'user_id': uid,
          'category': category,
          'title': title,
          'content': content,
          'scheduled_at': scheduledAt?.toUtc().toIso8601String(),
        })
        .select('id')
        .single();
    final postId = inserted['id'] as String;

    if (petIds.isNotEmpty) {
      await _c.from('post_pets').insert(
            petIds.map((pid) => {'post_id': postId, 'pet_id': pid}).toList(),
          );
    }
    return postId;
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

  /// 내 반려동물 목록 (작성 시 연결용).
  Future<List<MyPet>> fetchMyPets() async {
    final uid = _requireUid();
    final rows = await _c
        .from('pet_guardians')
        .select('role, pets(id, name, species, pet_status)')
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
