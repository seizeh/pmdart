import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/facility_review.dart' show ReviewVideo, reviewVideosFromJson;
import 'session.dart';

/// 업체(사업자) 인증 — 국세청 확인·신청·상태 조회·계정 전환 (0025).
/// 쓰기는 전부 서버(apply-business 엣지 → definer RPC)가 담당하고,
/// 여기서는 본인 행 조회(RLS select-own)와 호출만 한다.
class BusinessRepository {
  BusinessRepository._();
  static final BusinessRepository instance = BusinessRepository._();

  SupabaseClient get _c => Supabase.instance.client;

  /// 사업자등록번호 국세청 상태 사전 확인 (업체등록 화면 1단계 즉시 피드백).
  Future<BizNoCheck> checkBusinessNo(String bNo) async {
    try {
      final res = await _c.functions.invoke(
        'check-business-no',
        body: {'b_no': bNo},
      );
      final data = (res.data as Map?) ?? const {};
      return BizNoCheck(
        ok: data['ok'] == true,
        statusCode: data['status_code'] as String?,
        statusLabel: data['status_label'] as String?,
        error: data['error'] as String?,
      );
    } on FunctionException catch (e) {
      final data = (e.details is Map) ? e.details as Map : const {};
      return BizNoCheck(
        ok: false,
        statusCode: data['status_code'] as String?,
        statusLabel: data['status_label'] as String?,
        error: (data['error'] as String?) ?? 'nts_unavailable',
      );
    } catch (_) {
      return const BizNoCheck(ok: false, error: 'network');
    }
  }

  /// 신청/재신청 제출. 서버가 국세청 재조회 + facilities 대조·트랙 판정.
  Future<BizApplyResult> apply({
    required String bNo,
    required String category,
    required String businessName,
    String? storefrontName,
    String? prevBusinessName,
    required String addressRoad,
    String? addressJibun,
    String? regionCode,
    String? phone,
    String? repName,
    required String email,
    required String licensePath,
    String? extraDocPath,
  }) async {
    try {
      final res = await _c.functions.invoke(
        'apply-business',
        body: {
          'b_no': bNo,
          'category': category,
          'business_name': businessName,
          if (storefrontName != null && storefrontName.isNotEmpty)
            'storefront_name': storefrontName,
          if (prevBusinessName != null && prevBusinessName.isNotEmpty)
            'prev_business_name': prevBusinessName,
          'address_road': addressRoad,
          if (addressJibun != null && addressJibun.isNotEmpty)
            'address_jibun': addressJibun,
          if (regionCode != null && regionCode.isNotEmpty)
            'region_code': regionCode,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
          if (repName != null && repName.isNotEmpty) 'rep_name': repName,
          'email': email,
          'license_path': licensePath,
          if (extraDocPath != null && extraDocPath.isNotEmpty)
            'extra_doc_path': extraDocPath,
        },
      );
      final data = (res.data as Map?) ?? const {};
      return BizApplyResult(
        ok: data['ok'] == true,
        track: data['track'] as String?,
        status: data['status'] as String?,
      );
    } on FunctionException catch (e) {
      final data = (e.details is Map) ? e.details as Map : const {};
      return BizApplyResult(
        ok: false,
        errorCode: (data['error'] as String?) ?? 'internal_error',
        statusLabel: data['status_label'] as String?,
      );
    } catch (_) {
      return const BizApplyResult(ok: false, errorCode: 'network');
    }
  }

  /// 내 업체 프로필 (없으면 null). RLS 가 본인 행만 보여준다.
  Future<BusinessProfile?> fetchMine() async {
    final uid = SessionManager.instance.user?.id;
    if (uid == null) return null;
    try {
      final row = await _c
          .from('business_profiles')
          .select()
          .eq('user_id', uid)
          .maybeSingle();
      return row == null ? null : BusinessProfile.fromMap(row);
    } catch (_) {
      return null;
    }
  }

  /// 내 계정 전환 모드 ('personal' | 'business'). 실패 시 personal 로 간주.
  Future<String> fetchActiveMode() async {
    final uid = SessionManager.instance.user?.id;
    if (uid == null) return 'personal';
    try {
      final row = await _c
          .from('users')
          .select('active_mode')
          .eq('id', uid)
          .maybeSingle();
      return (row?['active_mode'] as String?) ?? 'personal';
    } catch (_) {
      return 'personal';
    }
  }

  /// 대표 사진 설정/해제 — 매칭 시설(지도 상세 히어로)에도 서버가 동기화.
  /// [url] null 이면 사진 제거. [alignY] 는 세로 초점 -1(상단)~1(하단).
  Future<bool> setPhoto({required String? url, double alignY = 0}) async {
    try {
      await _c.rpc(
        'set_my_business_photo',
        params: {'p_url': url, 'p_align_y': alignY},
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 내 업종 인증(business_licenses) 목록 — 업체 관리 패널 표시용 (0028 §1).
  Future<List<BizLicense>> fetchMyLicenses() async {
    try {
      final rows = await _c.rpc('my_business_licenses');
      return (rows as List)
          .map((r) => BizLicense.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// 업종 인증 신청/재신청. 성공 시 null, 실패 시 에러 코드
  /// (biz_profile_required / invalid_type / invalid_license_no /
  ///  invalid_document_path / already_approved / network).
  Future<String?> applyLicense({
    required String type,
    required String licenseNo,
    required String documentPath,
  }) async {
    try {
      await _c.rpc(
        'apply_business_license',
        params: {
          'p_type': type,
          'p_license_no': licenseNo,
          'p_document_path': documentPath,
        },
      );
      return null;
    } on PostgrestException catch (e) {
      const codes = [
        'biz_profile_required',
        'invalid_type',
        'invalid_license_no',
        'invalid_document_path',
        'already_approved',
      ];
      for (final c in codes) {
        if (e.message.contains(c)) return c;
      }
      return 'network';
    } catch (_) {
      return 'network';
    }
  }

  /// 내 업소(매칭 시설)에 달린 후기 — 업체 프로필의 후기 관리 UI 용.
  /// 매칭 시설이 없으면(신규개업 트랙 등) 빈 목록.
  Future<List<BizFacilityReview>> fetchMyFacilityReviews() async {
    final mine = await fetchMine();
    final fid = mine?.matchedFacilityId;
    if (fid == null) return const [];
    return fetchFacilityReviews(fid);
  }

  /// 특정 시설의 방문 후기 — 타사용자가 보는 업체 프로필에서도 사용.
  /// 지도 상세와 동일한 RPC(facility_reviews_of) 사용 — 뷰가 아니라 RPC 가 정본
  /// (존재하지 않는 v_facility_reviews 를 조회하던 버그 수정: 조용한 catch 로
  /// 빈 목록이 되어 '후기 동기화 안 됨'으로 보였다).
  Future<List<BizFacilityReview>> fetchFacilityReviews(String fid) async {
    try {
      final rows = await _c.rpc(
        'facility_reviews_of',
        params: {'p_facility': fid, 'p_limit': 50},
      );
      return [
        for (final r in (rows as List).cast<Map<String, dynamic>>())
          BizFacilityReview(
            id: (r['id'] as String?) ?? '',
            authorUserId: (r['user_id'] as String?) ?? '',
            authorNickname: (r['author_nickname'] as String?) ?? '알 수 없음',
            rating: (r['rating'] as num?)?.toInt() ?? 0,
            content: r['content'] as String?,
            createdAt: DateTime.tryParse(
              r['created_at'] as String? ?? '',
            )?.toLocal(),
            photoUrls: [
              for (final u in (r['photo_urls'] as List? ?? const []))
                u as String,
            ],
            videos: reviewVideosFromJson(r['videos']),
            visitNo: (r['visit_no'] as num?)?.toInt(),
            hasIncentive: r['has_incentive'] == true,
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// 승인 업체 정보 수정 — 사업장명·업장 전화·연락 이메일·영업시간만(심사 근거인
  /// 사업자번호·주소·업종은 재신청 경로). 간판명·전화·영업시간은 매칭 시설(지도)에도
  /// 서버가 동기화한다. [hours] 는 null=유지, 빈 문자열=삭제.
  Future<bool> updateMyInfo({
    String? storefrontName,
    String? phone,
    String? email,
    String? hours,
  }) async {
    try {
      await _c.rpc(
        'update_my_business_info',
        params: {
          'p_storefront_name': storefrontName,
          'p_phone': phone,
          'p_email': email,
          'p_hours': hours,
        },
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 후기 딥링크 진입 시 '업체 모드로 전환' 제안 여부 — 내가 이 후기 시설의
  /// 인증 업주(형제 행 포함)이고 현재 개인 모드일 때만 true(서버 판정).
  Future<bool> shouldSuggestBusinessSwitch(String reviewId) async {
    try {
      final res = await _c.rpc(
        'review_owner_switch_hint',
        params: {'p_review': reviewId},
      );
      return res == true;
    } catch (_) {
      return false;
    }
  }

  /// 계정 전환 — business 는 승인(approved) 상태에서만 서버가 허용.
  Future<String?> switchMode(String mode) async {
    try {
      final res = await _c.rpc('switch_account_mode', params: {'p_mode': mode});
      return res as String?;
    } catch (_) {
      return null;
    }
  }
}

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
    reviewedAt: m['reviewed_at'] == null
        ? null
        : DateTime.tryParse(m['reviewed_at'] as String),
    createdAt:
        DateTime.tryParse(m['created_at'] as String? ?? '') ?? DateTime.now(),
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
