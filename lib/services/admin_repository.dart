import 'package:supabase_flutter/supabase_flutter.dart';

/// 관리자 대시보드 통계.
class AdminStats {
  final int users;
  final int usersSuspended;
  final int posts;
  final int appointmentsScheduled;
  final int reportsOpen;

  const AdminStats({
    required this.users,
    required this.usersSuspended,
    required this.posts,
    required this.appointmentsScheduled,
    required this.reportsOpen,
  });

  factory AdminStats.fromJson(Map j) => AdminStats(
        users: (j['users'] as num?)?.toInt() ?? 0,
        usersSuspended: (j['users_suspended'] as num?)?.toInt() ?? 0,
        posts: (j['posts'] as num?)?.toInt() ?? 0,
        appointmentsScheduled:
            (j['appointments_scheduled'] as num?)?.toInt() ?? 0,
        reportsOpen: (j['reports_open'] as num?)?.toInt() ?? 0,
      );
}

/// 관리자가 보는 회원 1명.
class AdminUser {
  final String id;
  final String username;
  final String nickname;
  final String userType;
  final String status; // active / inactive / suspended
  final String? phone;
  final DateTime createdAt;

  const AdminUser({
    required this.id,
    required this.username,
    required this.nickname,
    required this.userType,
    required this.status,
    required this.phone,
    required this.createdAt,
  });

  bool get isAdmin => userType == 'admin';

  factory AdminUser.fromJson(Map j) => AdminUser(
        id: j['id'] as String,
        username: (j['username'] ?? '') as String,
        nickname: (j['nickname'] ?? '') as String,
        userType: (j['user_type'] ?? '') as String,
        status: (j['status'] ?? 'active') as String,
        phone: j['phone'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
      );
}

/// 관리자가 보는 신고 1건.
class AdminReport {
  final String id;
  final String targetType; // post / comment / chat_message / user
  final String? targetId;
  final List<String> categories;
  final String? extraDescription;
  final String status; // submitted / reviewing / resolved / dismissed
  final DateTime createdAt;
  final DateTime? reviewedAt;
  final String reporterNickname;

  const AdminReport({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.categories,
    required this.extraDescription,
    required this.status,
    required this.createdAt,
    required this.reviewedAt,
    required this.reporterNickname,
  });

  factory AdminReport.fromJson(Map j) => AdminReport(
        id: j['id'] as String,
        targetType: (j['target_type'] ?? '') as String,
        targetId: j['target_id'] as String?,
        categories: ((j['categories'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        extraDescription: j['extra_description'] as String?,
        status: (j['status'] ?? 'submitted') as String,
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
        reviewedAt: j['reviewed_at'] == null
            ? null
            : DateTime.parse(j['reviewed_at'] as String).toLocal(),
        reporterNickname: (j['reporter_nickname'] ?? '알 수 없음') as String,
      );
}

/// 관리자가 보는 게시글 1건.
class AdminPost {
  final String id;
  final String title;
  final String content;
  final String category;
  final String authorNickname;
  final String visibilityStatus;
  final int heartCount;
  final int commentCount;
  final int viewCount;
  final DateTime createdAt;

  const AdminPost({
    required this.id,
    required this.title,
    required this.content,
    required this.category,
    required this.authorNickname,
    required this.visibilityStatus,
    required this.heartCount,
    required this.commentCount,
    required this.viewCount,
    required this.createdAt,
  });

  factory AdminPost.fromJson(Map j) => AdminPost(
        id: j['id'] as String,
        title: (j['title'] ?? '') as String,
        content: (j['content'] ?? '') as String,
        category: (j['category'] ?? '') as String,
        authorNickname: (j['author_nickname'] ?? '알 수 없음') as String,
        visibilityStatus: (j['visibility_status'] ?? 'visible') as String,
        heartCount: (j['heart_count'] as num?)?.toInt() ?? 0,
        commentCount: (j['comment_count'] as num?)?.toInt() ?? 0,
        viewCount: (j['view_count'] as num?)?.toInt() ?? 0,
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
      );
}

/// 관리자가 보는 댓글 1건.
class AdminComment {
  final String id;
  final String content;
  final String authorNickname;
  final bool isDeleted;
  final DateTime createdAt;

  const AdminComment({
    required this.id,
    required this.content,
    required this.authorNickname,
    required this.isDeleted,
    required this.createdAt,
  });

  factory AdminComment.fromJson(Map j) => AdminComment(
        id: j['id'] as String,
        content: (j['content'] ?? '') as String,
        authorNickname: (j['author_nickname'] ?? '알 수 없음') as String,
        isDeleted: j['is_deleted'] == true,
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
      );
}

/// 관리자가 보는 문의(admin_inquiry 채팅방) 1건.
class AdminInquiry {
  final String roomId;
  final String? userId;
  final String userNickname;
  final String? lastMessage;
  final DateTime? lastMessageAt;

  const AdminInquiry({
    required this.roomId,
    required this.userId,
    required this.userNickname,
    required this.lastMessage,
    required this.lastMessageAt,
  });

  factory AdminInquiry.fromJson(Map j) => AdminInquiry(
        roomId: j['room_id'] as String,
        userId: j['user_id'] as String?,
        userNickname: (j['user_nickname'] ?? '알 수 없음') as String,
        lastMessage: j['last_message'] as String?,
        lastMessageAt: j['last_message_at'] == null
            ? null
            : DateTime.parse(j['last_message_at'] as String).toLocal(),
      );
}

/// 신고 대상의 실제 내용 (게시글/댓글/회원/채팅메시지). [data] 는 kind 별 필드.
class ReportTarget {
  final String kind; // post / comment / user / chat_message
  final bool exists;
  final Map<String, dynamic> data;
  const ReportTarget(
      {required this.kind, required this.exists, required this.data});

  factory ReportTarget.fromJson(Map j) => ReportTarget(
        kind: (j['kind'] ?? '') as String,
        exists: j['exists'] == true,
        data: j.cast<String, dynamic>(),
      );
}

/// 감사 로그 1건.
class AdminLog {
  final String id;
  final String adminNickname;
  final String actionType;
  final String? targetType;
  final String? targetId;
  final Map<String, dynamic>? detail;
  final DateTime createdAt;

  const AdminLog({
    required this.id,
    required this.adminNickname,
    required this.actionType,
    required this.targetType,
    required this.targetId,
    required this.detail,
    required this.createdAt,
  });

  factory AdminLog.fromJson(Map j) => AdminLog(
        id: j['id'] as String,
        adminNickname: (j['admin_nickname'] ?? '알 수 없음') as String,
        actionType: (j['action_type'] ?? '') as String,
        targetType: j['target_type'] as String?,
        targetId: j['target_id'] as String?,
        detail: (j['detail'] as Map?)?.cast<String, dynamic>(),
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
      );
}

/// DAU(일일 활성 사용자) 1일치.
class DauPoint {
  final String day; // 'MM-DD'
  final int count;
  const DauPoint(this.day, this.count);
}

/// 운영 지표·비용 (AI 사진인증 / Solapi 문자 / DAU).
/// 비용은 로그가 없어 "단가 × 건수" 추정치다(단가는 서버 상수).
class AdminOpsMetrics {
  final int smsUnitKrw;
  final int aiUnitKrw;

  // AI 사진 인증
  final int aiTotal, aiPass, aiFail, aiToday, aiD7, aiD30;
  final int aiCostAll, aiCostToday, aiCostD7, aiCostD30;

  // Solapi 문자 인증(발송 건)
  final int smsTotal, smsToday, smsD7, smsD30;
  final int smsCostAll, smsCostToday, smsCostD7, smsCostD30;

  // 일일 활성 사용자
  final int dauToday;
  final List<DauPoint> dauSeries;

  const AdminOpsMetrics({
    required this.smsUnitKrw,
    required this.aiUnitKrw,
    required this.aiTotal,
    required this.aiPass,
    required this.aiFail,
    required this.aiToday,
    required this.aiD7,
    required this.aiD30,
    required this.aiCostAll,
    required this.aiCostToday,
    required this.aiCostD7,
    required this.aiCostD30,
    required this.smsTotal,
    required this.smsToday,
    required this.smsD7,
    required this.smsD30,
    required this.smsCostAll,
    required this.smsCostToday,
    required this.smsCostD7,
    required this.smsCostD30,
    required this.dauToday,
    required this.dauSeries,
  });

  /// AI 인증 성공률 0~1.
  double get aiSuccessRate => aiTotal == 0 ? 0 : aiPass / aiTotal;

  static int _gi(Map m, String k) => (m[k] as num?)?.toInt() ?? 0;

  factory AdminOpsMetrics.fromJson(Map j) {
    final uc = (j['unit_cost'] as Map?) ?? const {};
    final ai = (j['ai'] as Map?) ?? const {};
    final sms = (j['sms'] as Map?) ?? const {};
    final dau = (j['dau'] as Map?) ?? const {};
    return AdminOpsMetrics(
      smsUnitKrw: _gi(uc, 'sms_krw'),
      aiUnitKrw: _gi(uc, 'ai_krw'),
      aiTotal: _gi(ai, 'total'),
      aiPass: _gi(ai, 'pass'),
      aiFail: _gi(ai, 'fail'),
      aiToday: _gi(ai, 'today'),
      aiD7: _gi(ai, 'd7'),
      aiD30: _gi(ai, 'd30'),
      aiCostAll: _gi(ai, 'cost_all'),
      aiCostToday: _gi(ai, 'cost_today'),
      aiCostD7: _gi(ai, 'cost_d7'),
      aiCostD30: _gi(ai, 'cost_d30'),
      smsTotal: _gi(sms, 'total'),
      smsToday: _gi(sms, 'today'),
      smsD7: _gi(sms, 'd7'),
      smsD30: _gi(sms, 'd30'),
      smsCostAll: _gi(sms, 'cost_all'),
      smsCostToday: _gi(sms, 'cost_today'),
      smsCostD7: _gi(sms, 'cost_d7'),
      smsCostD30: _gi(sms, 'cost_d30'),
      dauToday: _gi(dau, 'today'),
      dauSeries: ((dau['series'] as List?) ?? const [])
          .map((e) => DauPoint(
                (e['d'] ?? '') as String,
                (e['c'] as num?)?.toInt() ?? 0,
              ))
          .toList(),
    );
  }
}

/// AI 사진 인증 실패 로그 1건.
class PhotoVerifyFailure {
  final String id;
  final DateTime createdAt;
  final String? failReason;
  final String? aiReason;
  final bool regionMatched;
  final double? aiMatchScore;
  final String purpose;
  final String nickname;

  const PhotoVerifyFailure({
    required this.id,
    required this.createdAt,
    required this.failReason,
    required this.aiReason,
    required this.regionMatched,
    required this.aiMatchScore,
    required this.purpose,
    required this.nickname,
  });

  /// 실패 사유 한글 라벨(verify-post-photo reason 코드 기준).
  String get failLabel {
    switch (failReason) {
      case 'mock_location':
        return '모의 위치 감지';
      case 'geocode_failed':
        return '촬영지 동네 확인 실패';
      case 'region_mismatch':
        return '촬영지가 인증 동네와 불일치';
      case 'not_real_pet':
        return '실제 반려동물 아님(라이브니스)';
      case 'identity_mismatch':
        return '등록 개체와 불일치';
      case 'pet_not_enrolled':
        return '신원 미등록 반려동물';
      case 'not_verified':
        return '활동지역 미인증';
      case null:
        return '알 수 없음';
      default:
        return failReason!;
    }
  }

  factory PhotoVerifyFailure.fromJson(Map j) => PhotoVerifyFailure(
        id: j['id'] as String,
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
        failReason: j['fail_reason'] as String?,
        aiReason: j['ai_reason'] as String?,
        regionMatched: j['region_matched'] == true,
        aiMatchScore: (j['ai_match_score'] as num?)?.toDouble(),
        purpose: (j['purpose'] ?? '') as String,
        nickname: (j['nickname'] ?? '알 수 없음') as String,
      );
}

/// 관리자 전용 데이터 접근. 모든 호출은 DB 에서 app.is_admin() 으로 검증된다.
class AdminRepository {
  AdminRepository._();
  static final AdminRepository instance = AdminRepository._();

  SupabaseClient get _c => Supabase.instance.client;

  /// 대시보드 통계.
  Future<AdminStats> dashboardStats() async {
    final res = await _c.rpc('admin_dashboard_stats');
    return AdminStats.fromJson((res as Map));
  }

  /// 회원 목록/검색 (닉네임·아이디·전화).
  Future<List<AdminUser>> listUsers({String? search, int limit = 50}) async {
    final res = await _c.rpc('admin_list_users', params: {
      'p_search': (search == null || search.trim().isEmpty) ? null : search.trim(),
      'p_limit': limit,
      'p_offset': 0,
    });
    return (res as List)
        .map((r) => AdminUser.fromJson(r as Map))
        .toList();
  }

  /// 회원 상태 변경 (active/inactive/suspended).
  Future<void> setUserStatus(String userId, String status) async {
    await _c.rpc('admin_set_user_status',
        params: {'p_user': userId, 'p_status': status});
  }

  /// 신고 목록. [status] = 'open'(미처리), null(전체), 또는 정확한 상태값.
  Future<List<AdminReport>> listReports({String? status = 'open'}) async {
    final res = await _c.rpc('admin_list_reports', params: {
      'p_status': status,
      'p_limit': 50,
      'p_offset': 0,
    });
    return (res as List).map((r) => AdminReport.fromJson(r as Map)).toList();
  }

  /// 신고 상태 변경 (submitted/reviewing/resolved/dismissed).
  Future<void> setReportStatus(String reportId, String status) async {
    await _c.rpc('admin_set_report_status',
        params: {'p_report': reportId, 'p_status': status});
  }

  /// 게시글 목록/검색 (숨김·삭제 포함).
  Future<List<AdminPost>> listPosts({String? search}) async {
    final res = await _c.rpc('admin_list_posts', params: {
      'p_search': (search == null || search.trim().isEmpty) ? null : search.trim(),
      'p_limit': 50,
      'p_offset': 0,
    });
    return (res as List).map((r) => AdminPost.fromJson(r as Map)).toList();
  }

  /// 게시글 가시성 변경 (visible/hidden_by_admin/deleted_by_admin).
  Future<void> setPostVisibility(String postId, String visibility) async {
    await _c.rpc('admin_set_post_visibility',
        params: {'p_post': postId, 'p_visibility': visibility});
  }

  /// 특정 게시글의 댓글 목록 (삭제 포함).
  Future<List<AdminComment>> listComments(String postId) async {
    final res =
        await _c.rpc('admin_list_comments', params: {'p_post': postId});
    return (res as List).map((r) => AdminComment.fromJson(r as Map)).toList();
  }

  /// 댓글 숨김/복원.
  Future<void> setCommentDeleted(String commentId, bool deleted) async {
    await _c.rpc('admin_set_comment_deleted',
        params: {'p_comment': commentId, 'p_deleted': deleted});
  }

  /// 문의(admin_inquiry 채팅방) 목록.
  Future<List<AdminInquiry>> listInquiries() async {
    final res = await _c.rpc('admin_list_inquiries');
    return (res as List).map((r) => AdminInquiry.fromJson(r as Map)).toList();
  }

  /// 문의방에 참여(답장 위해). 멱등.
  Future<void> joinInquiry(String roomId) async {
    await _c.rpc('admin_join_inquiry', params: {'p_room': roomId});
  }

  /// 신고 대상의 실제 내용 조회.
  Future<ReportTarget> getReportTarget(String reportId) async {
    final res =
        await _c.rpc('admin_get_report_target', params: {'p_report': reportId});
    return ReportTarget.fromJson(res as Map);
  }

  /// 신고된 채팅 메시지 숨김/복원.
  Future<void> setChatMessageDeleted(String messageId, bool deleted) async {
    await _c.rpc('admin_set_chat_message_deleted',
        params: {'p_message': messageId, 'p_deleted': deleted});
  }

  /// 감사 로그 조회.
  Future<List<AdminLog>> listLogs() async {
    final res =
        await _c.rpc('admin_list_logs', params: {'p_limit': 100, 'p_offset': 0});
    return (res as List).map((r) => AdminLog.fromJson(r as Map)).toList();
  }

  /// 운영 지표·비용 (AI 사진인증 / Solapi 문자 / DAU).
  Future<AdminOpsMetrics> opsMetrics() async {
    final res = await _c.rpc('admin_ops_metrics');
    return AdminOpsMetrics.fromJson(res as Map);
  }

  /// AI 사진 인증 실패 로그(최신순).
  Future<List<PhotoVerifyFailure>> photoVerificationFailures(
      {int limit = 50}) async {
    final res = await _c.rpc('admin_photo_verification_failures',
        params: {'p_limit': limit, 'p_offset': 0});
    return (res as List)
        .map((r) => PhotoVerifyFailure.fromJson(r as Map))
        .toList();
  }
}
