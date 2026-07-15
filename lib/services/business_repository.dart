import 'package:supabase_flutter/supabase_flutter.dart';
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

  /// 내 업소(매칭 시설)에 달린 후기 — 업체 프로필의 후기 관리 UI 용.
  /// 매칭 시설이 없으면(신규개업 트랙 등) 빈 목록.
  Future<List<BizFacilityReview>> fetchMyFacilityReviews() async {
    final mine = await fetchMine();
    final fid = mine?.matchedFacilityId;
    if (fid == null) return const [];
    try {
      final rows = await _c
          .from('v_facility_reviews')
          .select('author_nickname, rating, content, created_at')
          .eq('facility_id', fid)
          .order('created_at', ascending: false)
          .limit(50);
      return [
        for (final r in (rows as List).cast<Map<String, dynamic>>())
          BizFacilityReview(
            authorNickname: (r['author_nickname'] as String?) ?? '알 수 없음',
            rating: (r['rating'] as num?)?.toInt() ?? 0,
            content: r['content'] as String?,
            createdAt:
                DateTime.tryParse(r['created_at'] as String? ?? '')?.toLocal(),
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// 승인 업체 정보 수정 — 사업장명·업장 전화·연락 이메일만(심사 근거인 사업자번호·
  /// 주소·업종은 재신청 경로). 간판명·전화는 매칭 시설(지도)에도 서버가 동기화한다.
  Future<bool> updateMyInfo({
    String? storefrontName,
    String? phone,
    String? email,
  }) async {
    try {
      await _c.rpc(
        'update_my_business_info',
        params: {
          'p_storefront_name': storefrontName,
          'p_phone': phone,
          'p_email': email,
        },
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 계정 전환 — business 는 승인(approved) 상태에서만 서버가 허용.
  Future<String?> switchMode(String mode) async {
    try {
      final res = await _c.rpc(
        'switch_account_mode',
        params: {'p_mode': mode},
      );
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
    photoAlignY: (m['photo_align_y'] as num?)?.toDouble() ?? 0,
  );

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
}

/// 내 업소에 달린 시설 후기 1건 (업체 프로필 후기 관리 UI).
class BizFacilityReview {
  final String authorNickname;
  final int rating; // 1~5
  final String? content;
  final DateTime? createdAt;
  const BizFacilityReview({
    required this.authorNickname,
    required this.rating,
    this.content,
    this.createdAt,
  });
}

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
