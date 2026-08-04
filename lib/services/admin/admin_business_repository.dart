/// 관리자 — 업체 심사·허가·공유링크. 모든 호출은 DB 에서 `app.is_admin()` 으로 검증된다 —
/// 이 클래스에는 권한 판단이 없고, 있어서도 안 된다(클라이언트 판단은 우회된다).
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/admin.dart';

class AdminBusinessRepository {
  AdminBusinessRepository._();
  static final AdminBusinessRepository instance = AdminBusinessRepository._();

  SupabaseClient get _c => Supabase.instance.client;

  /// 업체 인증 신청 목록 (0025 §6). [status]=null 이면 전체.
  Future<List<AdminBusinessApplication>> listBusinessApplications({
    String? status = 'pending',
    String? track,
    bool autoOnly = false,
  }) async {
    final res = await _c.rpc(
      'admin_list_business_applications',
      params: {
        'p_status': status,
        'p_track': track,
        'p_auto_only': autoOnly,
        'p_limit': 100,
        'p_offset': 0,
      },
    );
    return (res as List)
        .map((r) => AdminBusinessApplication.fromJson(r as Map))
        .toList();
  }

  /// 업체 인증 승인/반려. 반려는 사유 필수, 자동승인 조건 미달(review/new_business
  /// 트랙) 승인은 override 사유 필수 — 서버가 검증한다.
  Future<void> setBusinessStatus(
    String userId,
    String status, {
    String? reason,
  }) async {
    await _c.rpc(
      'admin_set_business_status',
      params: {'p_user': userId, 'p_status': status, 'p_reason': reason},
    );
  }

  /// 업종 인증(business_licenses) 심사 목록 (0028 §1). [status] null 이면 전체.
  Future<List<AdminBizLicense>> listBusinessLicenses({
    String? status = 'pending',
  }) async {
    final res = await _c.rpc(
      'admin_list_business_licenses',
      params: {'p_status': status, 'p_limit': 100, 'p_offset': 0},
    );
    return (res as List)
        .map((r) => AdminBizLicense.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// 업종 인증 승인/반려 — 반려는 사유 필수(서버 검증).
  Future<void> reviewBusinessLicense(
    String licenseId,
    String status, {
    String? reason,
  }) async {
    await _c.rpc(
      'admin_review_business_license',
      params: {'p_license': licenseId, 'p_status': status, 'p_reason': reason},
    );
  }

  /// 매장 미리보기 공유 링크(QR) 발급 (0028 §3). 같은 시설의 유효 링크가 있으면
  /// 서버가 그 토큰을 재사용한다 — 재호출해도 이미 인쇄한 QR 이 안 죽는다.
  Future<({String token, DateTime? expiresAt})> createFacilityShareLink(
    String facilityId, {
    int days = 365,
  }) async {
    final res = await _c.rpc(
      'admin_create_facility_share_link',
      params: {'p_facility': facilityId, 'p_days': days},
    );
    final row = (res as List).first as Map<String, dynamic>;
    return (
      token: row['token'] as String,
      expiresAt: DateTime.tryParse(
        (row['expires_at'] ?? '') as String,
      )?.toLocal(),
    );
  }

  /// 공유 링크 회수(오배포·유출 대응) — 회수분은 share-view 가 404 로 응답.
  Future<bool> revokeShareLink(String token) async {
    final res = await _c.rpc(
      'admin_revoke_share_link',
      params: {'p_token': token},
    );
    return res == true;
  }
}
