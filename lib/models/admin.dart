/// 관리자 화면이 쓰는 값 객체들 — 종전에는 admin_repository.dart 안에 있었다.
///
/// 913줄 중 631줄이 모델이었다. 리포지토리를 역할별로 쪼개면서 모델은 공통으로
/// 남으므로 여기로 옮긴다(어느 역할에도 속하지 않고, 여러 역할이 함께 쓴다).
library;

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

  factory AdminStats.fromJson(Map<dynamic, dynamic> j) => AdminStats(
    users: (j['users'] as num?)?.toInt() ?? 0,
    usersSuspended: (j['users_suspended'] as num?)?.toInt() ?? 0,
    posts: (j['posts'] as num?)?.toInt() ?? 0,
    appointmentsScheduled: (j['appointments_scheduled'] as num?)?.toInt() ?? 0,
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

  factory AdminUser.fromJson(Map<dynamic, dynamic> j) => AdminUser(
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

  factory AdminReport.fromJson(Map<dynamic, dynamic> j) => AdminReport(
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

  factory AdminPost.fromJson(Map<dynamic, dynamic> j) => AdminPost(
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

  factory AdminComment.fromJson(Map<dynamic, dynamic> j) => AdminComment(
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

  factory AdminInquiry.fromJson(Map<dynamic, dynamic> j) => AdminInquiry(
    roomId: j['room_id'] as String,
    userId: j['user_id'] as String?,
    userNickname: (j['user_nickname'] ?? '알 수 없음') as String,
    lastMessage: j['last_message'] as String?,
    lastMessageAt: j['last_message_at'] == null
        ? null
        : DateTime.parse(j['last_message_at'] as String).toLocal(),
  );
}

/// 관리자가 보는 채팅 메시지 1건(삭제분 포함) — admin_room_messages RPC.
class AdminChatMessage {
  final String id;
  final String senderId;
  final String senderNickname;
  final String? content;
  final String? imageUrl;
  final bool isDeleted;
  final DateTime? deletedAt;
  final DateTime createdAt;

  bool get isImage => imageUrl != null && imageUrl!.isNotEmpty;

  const AdminChatMessage({
    required this.id,
    required this.senderId,
    required this.senderNickname,
    required this.content,
    required this.imageUrl,
    required this.isDeleted,
    required this.deletedAt,
    required this.createdAt,
  });

  factory AdminChatMessage.fromJson(Map<String, dynamic> j) => AdminChatMessage(
    id: j['id'] as String,
    senderId: (j['sender_id'] ?? '') as String,
    senderNickname: (j['sender_nickname'] ?? '알 수 없음') as String,
    content: j['content'] as String?,
    imageUrl: j['image_url'] as String?,
    isDeleted: j['is_deleted'] == true,
    deletedAt: j['deleted_at'] == null
        ? null
        : DateTime.parse(j['deleted_at'] as String).toLocal(),
    createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
  );
}

/// 신고 대상의 실제 내용 (게시글/댓글/회원/채팅메시지). [data] 는 kind 별 필드.
class ReportTarget {
  final String kind; // post / comment / user / chat_message
  final bool exists;
  final Map<String, dynamic> data;
  const ReportTarget({
    required this.kind,
    required this.exists,
    required this.data,
  });

  factory ReportTarget.fromJson(Map<dynamic, dynamic> j) => ReportTarget(
    kind: (j['kind'] ?? '') as String,
    exists: j['exists'] == true,
    data: j.cast<String, dynamic>(),
  );
}

/// 감사 로그 1건.
/// 클라이언트 오류 한 건 (`app.client_errors`, reported 등급만).
class AdminClientError {
  final int id;
  final String? userId;
  final String nickname; // 비로그인이면 '(비로그인)'
  final String where;
  final String message;
  final String? stack;
  final String? platform;
  final String? release;
  final Map<String, dynamic>? extra;
  final DateTime createdAt;

  const AdminClientError({
    required this.id,
    required this.userId,
    required this.nickname,
    required this.where,
    required this.message,
    required this.stack,
    required this.platform,
    required this.release,
    required this.extra,
    required this.createdAt,
  });

  factory AdminClientError.fromJson(Map<dynamic, dynamic> j) =>
      AdminClientError(
        id: (j['id'] as num).toInt(),
        userId: j['user_id'] as String?,
        nickname: (j['nickname'] ?? '') as String,
        where: (j['where_key'] ?? '') as String,
        message: (j['message'] ?? '') as String,
        stack: j['stack'] as String?,
        platform: j['platform'] as String?,
        release: j['app_release'] as String?,
        extra: (j['extra'] as Map?)?.cast<String, dynamic>(),
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
      );
}

/// 발생 지점별 집계 — 그룹핑이 없는 대신 '어디가 자주 터지나' 를 본다.
class AdminClientErrorStat {
  final String where;
  final int hits;
  final int users;
  final DateTime lastAt;

  const AdminClientErrorStat({
    required this.where,
    required this.hits,
    required this.users,
    required this.lastAt,
  });

  factory AdminClientErrorStat.fromJson(Map<dynamic, dynamic> j) =>
      AdminClientErrorStat(
        where: (j['where_key'] ?? '') as String,
        hits: (j['hits'] as num).toInt(),
        users: (j['users'] as num).toInt(),
        lastAt: DateTime.parse(j['last_at'] as String).toLocal(),
      );
}

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

  factory AdminLog.fromJson(Map<dynamic, dynamic> j) => AdminLog(
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

  static int _gi(Map<dynamic, dynamic> m, String k) =>
      (m[k] as num?)?.toInt() ?? 0;

  factory AdminOpsMetrics.fromJson(Map<dynamic, dynamic> j) {
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
          .map(
            (e) => DauPoint(
              (e['d'] ?? '') as String,
              (e['c'] as num?)?.toInt() ?? 0,
            ),
          )
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

  factory PhotoVerifyFailure.fromJson(Map<dynamic, dynamic> j) =>
      PhotoVerifyFailure(
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

/// 관리자가 보는 업체 인증 신청 1건 (0025 §6).
/// 업종 인증 심사 1건 (admin_list_business_licenses RPC 기준, 0028 §1).
class AdminBizLicense {
  final String id;
  final String userId;
  final String nickname;
  final String? businessName;
  final String type; // grooming | boarding | sales | production | ...
  final String licenseNo;
  final String documentPath;
  final String status; // pending / approved / rejected
  final String? rejectReason;
  final DateTime? createdAt;
  final DateTime? reviewedAt;

  const AdminBizLicense({
    required this.id,
    required this.userId,
    required this.nickname,
    required this.businessName,
    required this.type,
    required this.licenseNo,
    required this.documentPath,
    required this.status,
    this.rejectReason,
    this.createdAt,
    this.reviewedAt,
  });

  factory AdminBizLicense.fromJson(Map<String, dynamic> j) => AdminBizLicense(
    id: (j['id'] ?? '') as String,
    userId: (j['user_id'] ?? '') as String,
    nickname: (j['nickname'] ?? '') as String,
    businessName: j['business_name'] as String?,
    type: (j['license_type'] ?? '') as String,
    licenseNo: (j['license_no'] ?? '') as String,
    documentPath: (j['document_path'] ?? '') as String,
    status: (j['status'] ?? 'pending') as String,
    rejectReason: j['reject_reason'] as String?,
    createdAt: DateTime.tryParse((j['created_at'] ?? '') as String)?.toLocal(),
    reviewedAt: DateTime.tryParse(
      (j['reviewed_at'] ?? '') as String,
    )?.toLocal(),
  );
}

class AdminBusinessApplication {
  final String userId;
  final String nickname;
  final String businessRegNo;
  final String declaredCategory;
  final String businessName;
  final String? storefrontName;
  final String? prevBusinessName;
  final String businessAddress;
  final String? businessAddressJibun;
  final String? businessPhone;
  final String? representativeName;
  final String contactEmail;
  final String licenseImagePath;
  final String? extraDocPath;
  final String? matchedFacilityName;
  final int? matchScore;
  final Map<String, dynamic> matchDetail;
  final String reviewTrack; // auto / review / new_business
  final bool autoApproved;
  final String status; // pending / approved / rejected
  final String? rejectedReason;
  final String? reviewNote;
  final DateTime createdAt;
  final DateTime updatedAt;

  const AdminBusinessApplication({
    required this.userId,
    required this.nickname,
    required this.businessRegNo,
    required this.declaredCategory,
    required this.businessName,
    required this.storefrontName,
    required this.prevBusinessName,
    required this.businessAddress,
    required this.businessAddressJibun,
    required this.businessPhone,
    required this.representativeName,
    required this.contactEmail,
    required this.licenseImagePath,
    required this.extraDocPath,
    required this.matchedFacilityName,
    required this.matchScore,
    required this.matchDetail,
    required this.reviewTrack,
    required this.autoApproved,
    required this.status,
    required this.rejectedReason,
    required this.reviewNote,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 자동승인 트랙이 아니면 승인이 override(사유 필수)로 처리된다 (0025 §6-2).
  bool get approveNeedsReason => reviewTrack != 'auto';

  factory AdminBusinessApplication.fromJson(Map<dynamic, dynamic> j) =>
      AdminBusinessApplication(
        userId: j['user_id'] as String,
        nickname: (j['nickname'] ?? '') as String,
        businessRegNo: (j['business_reg_no'] ?? '') as String,
        declaredCategory: (j['declared_category'] ?? '') as String,
        businessName: (j['business_name'] ?? '') as String,
        storefrontName: j['storefront_name'] as String?,
        prevBusinessName: j['prev_business_name'] as String?,
        businessAddress: (j['business_address'] ?? '') as String,
        businessAddressJibun: j['business_address_jibun'] as String?,
        businessPhone: j['business_phone'] as String?,
        representativeName: j['representative_name'] as String?,
        contactEmail: (j['contact_email'] ?? '') as String,
        licenseImagePath: (j['license_image_path'] ?? '') as String,
        extraDocPath: j['extra_doc_path'] as String?,
        matchedFacilityName: j['matched_facility_name'] as String?,
        matchScore: (j['match_score'] as num?)?.toInt(),
        matchDetail:
            (j['match_detail'] as Map?)?.cast<String, dynamic>() ?? const {},
        reviewTrack: (j['review_track'] ?? 'review') as String,
        autoApproved: j['auto_approved'] == true,
        status: (j['status'] ?? 'pending') as String,
        rejectedReason: j['rejected_reason'] as String?,
        reviewNote: j['review_note'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
        updatedAt: DateTime.parse(j['updated_at'] as String).toLocal(),
      );
}
