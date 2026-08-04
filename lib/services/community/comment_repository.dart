/// 게시글 **댓글**.
///
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/community.dart';
import '../query_limits.dart';
import '../session.dart';

class CommentRepository {
  CommentRepository._();
  static final CommentRepository instance = CommentRepository._();

  SupabaseClient get _c => Supabase.instance.client;

  String? get _uid => SessionManager.instance.user?.id;

  String _requireUid() {
    final uid = _uid;
    if (uid == null) {
      throw StateError('로그인이 필요합니다');
    }
    return uid;
  }

  /// 댓글 목록.
  Future<List<Comment>> fetchComments(String postId) async {
    final rows = await _c
        .from('v_comment_feed')
        .select()
        .eq('post_id', postId)
        .order('created_at', ascending: true);
    // 인기 글의 댓글이 서버 상한에 **가장 먼저 닿는다**(0031 §5.2).
    return guardTruncation(
      (rows as List)
          .map((r) => Comment.fromJson(r as Map<String, dynamic>))
          .toList(),
      where: 'community.fetchComments',
    );
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
}
