/// 업체 등록 — 국세청 확인 · 신청 · 영업 허가증 제출 (0025).
///
/// 쓰기는 전부 서버(apply-business 엣지 → definer RPC)가 담당하고,
/// 여기서는 본인 행 조회(RLS select-own)와 호출만 한다.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/business.dart';
import '../error_reporter.dart';

class BusinessRegistrationRepository {
  BusinessRegistrationRepository._();
  static final BusinessRegistrationRepository instance =
      BusinessRegistrationRepository._();

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
    } catch (e, st) {
      ErrorReporter.userFacing(
        e,
        where: 'business.checkBusinessNo',
        stackTrace: st,
      );
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
    } catch (e, st) {
      ErrorReporter.userFacing(e, where: 'business.apply', stackTrace: st);
      return const BizApplyResult(ok: false, errorCode: 'network');
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
    } catch (e, st) {
      ErrorReporter.userFacing(
        e,
        where: 'business.applyLicense',
        stackTrace: st,
      );
      return 'network';
    }
  }

  /// 내 업종 인증(business_licenses) 목록 — 업체 관리 패널 표시용 (0028 §1).
  Future<List<BizLicense>> fetchMyLicenses() async {
    try {
      final rows = await _c.rpc('my_business_licenses');
      return (rows as List)
          .map((r) => BizLicense.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      // 빈 목록은 '등록한 증빙 없음' 으로 보인다 — 심사 대기 중인 서류가 사라진다.
      ErrorReporter.report(
        e,
        where: 'business.fetchMyLicenses',
        stackTrace: st,
      );
      return const [];
    }
  }
}
