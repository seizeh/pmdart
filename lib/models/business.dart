/// 업체(사업자) 값 객체와 업종 상수 — 종전에는 business_repository.dart 안에 있었다.
library;

import 'facility_review.dart' show ReviewVideo;

class BizNoCheck {
  final bool ok; // 계속사업자(01)
  final String? statusCode; // 01/02/03, 미등록 null
  final String? statusLabel; // 계속사업자/휴업자/폐업자
  final String? error;
  const BizNoCheck({
    required this.ok,
    this.statusCode,
    this.statusLabel,
    this.error,
  });
}

class BizApplyResult {
  final bool ok;
  final String? track; // auto | review | new_business
  final String? status; // approved | pending
  final String? errorCode;
  final String? statusLabel;
  const BizApplyResult({
    required this.ok,
    this.track,
    this.status,
    this.errorCode,
    this.statusLabel,
  });
}

class BusinessProfile {
  final String businessRegNo;
  final String declaredCategory;
  final String businessName;
  final String? storefrontName;
  final String? prevBusinessName;
  final String businessAddress;
  final String? businessPhone;
  final String contactEmail;
  final String status; // pending | approved | rejected
  final String reviewTrack; // auto | review | new_business
  final bool autoApproved;
  final String? rejectedReason;
  final DateTime? reviewedAt;
  final DateTime createdAt;
  final String? matchedFacilityId; // 공공데이터 매칭 시설 — 업체 후기 조회에 사용
  final String? photoUrl; // 대표 사진(지도 상세 히어로)
  final String? businessHours; // 영업시간(자유 서식 한 줄)
  final double photoAlignY; // 사진 세로 초점 -1~1

  const BusinessProfile({
    required this.businessRegNo,
    required this.declaredCategory,
    required this.businessName,
    this.storefrontName,
    this.prevBusinessName,
    required this.businessAddress,
    this.businessPhone,
    required this.contactEmail,
    required this.status,
    required this.reviewTrack,
    required this.autoApproved,
    this.rejectedReason,
    this.reviewedAt,
    required this.createdAt,
    this.matchedFacilityId,
    this.photoUrl,
    this.photoAlignY = 0,
    this.businessHours,
  });

  factory BusinessProfile.fromMap(Map<String, dynamic> m) => BusinessProfile(
    businessRegNo: m['business_reg_no'] as String,
    declaredCategory: m['declared_category'] as String,
    businessName: m['business_name'] as String,
    storefrontName: m['storefront_name'] as String?,
    prevBusinessName: m['prev_business_name'] as String?,
    businessAddress: m['business_address'] as String,
    businessPhone: m['business_phone'] as String?,
    contactEmail: m['contact_email'] as String,
    status: m['status'] as String,
    reviewTrack: m['review_track'] as String,
    autoApproved: m['auto_approved'] == true,
    rejectedReason: m['rejected_reason'] as String?,
    // .toLocal() — 다른 모델들과 표기 일관(#239 메모, 현재 표시 UI 는 없음).
    reviewedAt: m['reviewed_at'] == null
        ? null
        : DateTime.tryParse(m['reviewed_at'] as String)?.toLocal(),
    createdAt:
        (DateTime.tryParse(m['created_at'] as String? ?? '') ?? DateTime.now())
            .toLocal(),
    matchedFacilityId: m['matched_facility_id'] as String?,
    photoUrl: m['photo_url'] as String?,
    businessHours: m['business_hours'] as String?,
    photoAlignY: (m['photo_align_y'] as num?)?.toDouble() ?? 0,
  );

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
}

/// 내 업소에 달린 시설 후기 1건 (업체 프로필 후기 관리 UI).
class BizFacilityReview {
  final String id; // 블롭 배경 시드 등 후기 식별용
  final String authorUserId; // 작성자 — 후기 상세 닉네임 탭 → 프로필용
  final String authorNickname;
  final int rating; // 1~5
  final String? content;
  final DateTime? createdAt;
  final List<String> photoUrls;
  final List<ReviewVideo> videos; // 첨부 영상(최대 2개)
  final int? visitNo; // 같은 사용자의 몇 번째 방문 후기인지
  final bool hasIncentive; // 업체 혜택 받고 작성(표시광고법 표시, 0028 §6)

  /// 내가 쓴 후기인가 — 상세 화면 우상단 삭제 버튼 노출 조건.
  /// 서버(`facility_reviews_of.is_mine`)가 정본이다. 이 필드를 안 채우면 작성자가
  /// 자기 후기를 지울 수 없다(지도 상세에서는 되는데 업체 프로필에서만 안 되던 버그).
  final bool isMine;

  const BizFacilityReview({
    this.id = '',
    this.authorUserId = '',
    required this.authorNickname,
    required this.rating,
    this.content,
    this.createdAt,
    this.photoUrls = const [],
    this.videos = const [],
    this.visitNo,
    this.hasIncentive = false,
    this.isMine = false,
  });
}

/// 업종 인증(등록·허가증) 1건 — my_business_licenses RPC 기준 (0028 §1).
class BizLicense {
  final String id;
  final String type; // grooming | boarding | sales | production | ...
  final String licenseNo;
  final String status; // pending | approved | rejected
  final String? rejectReason;
  final DateTime? createdAt;
  final DateTime? reviewedAt;

  const BizLicense({
    required this.id,
    required this.type,
    required this.licenseNo,
    required this.status,
    this.rejectReason,
    this.createdAt,
    this.reviewedAt,
  });

  factory BizLicense.fromJson(Map<String, dynamic> j) => BizLicense(
    id: (j['id'] ?? '') as String,
    type: (j['license_type'] ?? '') as String,
    licenseNo: (j['license_no'] ?? '') as String,
    status: (j['status'] ?? 'pending') as String,
    rejectReason: j['reject_reason'] as String?,
    createdAt: DateTime.tryParse((j['created_at'] ?? '') as String)?.toLocal(),
    reviewedAt: DateTime.tryParse(
      (j['reviewed_at'] ?? '') as String,
    )?.toLocal(),
  );
}

/// 업종 인증 종류 라벨 (동물보호법 업종명 — app.biz_license_type 과 1:1).
/// 신청 UI 에는 모듈이 있는 앞 4종만 노출(전시·운송은 enum 선점만, 0028 §1).
const bizLicenseTypes = <(String, String)>[
  ('grooming', '동물미용업'),
  ('boarding', '동물위탁관리업'),
  ('sales', '동물판매업'),
  ('production', '동물생산업'),
];

String bizLicenseLabel(String key) => switch (key) {
  'grooming' => '동물미용업',
  'boarding' => '동물위탁관리업',
  'sales' => '동물판매업',
  'production' => '동물생산업',
  'exhibition' => '동물전시업',
  'transport' => '동물운송업',
  _ => key,
};

/// 업종 라벨 (0025 §4.2 — 사업자등록증 업태·종목 확인 고지와 함께 사용)
const businessCategories = <(String, String)>[
  ('pet_sales', '분양'),
  ('pet_hotel', '위탁 · 호텔'),
  ('animal_hospital', '동물병원'),
  ('grooming', '미용'),
  ('other', '기타 (카페 등)'),
];

String businessCategoryLabel(String key) => businessCategories
    .firstWhere((e) => e.$1 == key, orElse: () => (key, key))
    .$2;
