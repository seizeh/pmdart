/// 관리자 — 신고·게시글·댓글·채팅 조치. 모든 호출은 DB 에서 `app.is_admin()` 으로 검증된다 —
/// 이 클래스에는 권한 판단이 없고, 있어서도 안 된다(클라이언트 판단은 우회된다).
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/admin.dart';

class AdminModerationRepository {
  AdminModerationRepository._();
  static final AdminModerationRepository instance =
      AdminModerationRepository._();

  SupabaseClient get _c => Supabase.instance.client;

  /// 신고 목록. [status] = 'open'(미처리), null(전체), 또는 정확한 상태값.
  Future<List<AdminReport>> listReports({String? status = 'open'}) async {
    final res = await _c.rpc(
      'admin_list_reports',
      params: {'p_status': status, 'p_limit': 50, 'p_offset': 0},
    );
    return (res as List).map((r) => AdminReport.fromJson(r as Map)).toList();
  }

  /// 신고 상태 변경 (submitted/reviewing/resolved/dismissed).
  Future<void> setReportStatus(String reportId, String status) async {
    await _c.rpc(
      'admin_set_report_status',
      params: {'p_report': reportId, 'p_status': status},
    );
  }

  /// 신고 대상의 실제 내용 조회.
  Future<ReportTarget> getReportTarget(String reportId) async {
    final res = await _c.rpc(
      'admin_get_report_target',
      params: {'p_report': reportId},
    );
    return ReportTarget.fromJson(res as Map);
  }

  /// 게시글 목록/검색 (숨김·삭제 포함).
  Future<List<AdminPost>> listPosts({String? search}) async {
    final res = await _c.rpc(
      'admin_list_posts',
      params: {
        'p_search': (search == null || search.trim().isEmpty)
            ? null
            : search.trim(),
        'p_limit': 50,
        'p_offset': 0,
      },
    );
    return (res as List).map((r) => AdminPost.fromJson(r as Map)).toList();
  }

  /// 게시글 가시성 변경 (visible/hidden_by_admin/deleted_by_admin).
  Future<void> setPostVisibility(String postId, String visibility) async {
    await _c.rpc(
      'admin_set_post_visibility',
      params: {'p_post': postId, 'p_visibility': visibility},
    );
  }

  /// 특정 게시글의 댓글 목록 (삭제 포함).
  Future<List<AdminComment>> listComments(String postId) async {
    final res = await _c.rpc('admin_list_comments', params: {'p_post': postId});
    return (res as List).map((r) => AdminComment.fromJson(r as Map)).toList();
  }

  /// 댓글 숨김/복원.
  Future<void> setCommentDeleted(String commentId, bool deleted) async {
    await _c.rpc(
      'admin_set_comment_deleted',
      params: {'p_comment': commentId, 'p_deleted': deleted},
    );
  }

  /// 신고된 채팅 메시지 숨김/복원.
  Future<void> setChatMessageDeleted(String messageId, bool deleted) async {
    await _c.rpc(
      'admin_set_chat_message_deleted',
      params: {'p_message': messageId, 'p_deleted': deleted},
    );
  }

  /// 채팅방 대화 내역(삭제분 포함, 오래된 순) — 신고 맥락 확인용.
  Future<List<AdminChatMessage>> fetchRoomMessages(
    String roomId, {
    int limit = 300,
  }) async {
    final res = await _c.rpc(
      'admin_room_messages',
      params: {'p_room': roomId, 'p_limit': limit},
    );
    return (res as List)
        .map((r) => AdminChatMessage.fromJson(r as Map<String, dynamic>))
        .toList();
  }
}
