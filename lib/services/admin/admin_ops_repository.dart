/// 관리자 — 운영 지표·로그·공지. 모든 호출은 DB 에서 `app.is_admin()` 으로 검증된다 —
/// 이 클래스에는 권한 판단이 없고, 있어서도 안 된다(클라이언트 판단은 우회된다).
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/admin.dart';

class AdminOpsRepository {
  AdminOpsRepository._();
  static final AdminOpsRepository instance = AdminOpsRepository._();

  SupabaseClient get _c => Supabase.instance.client;

  /// 대시보드 통계.
  Future<AdminStats> dashboardStats() async {
    final res = await _c.rpc('admin_dashboard_stats');
    return AdminStats.fromJson((res as Map));
  }

  /// 감사 로그 조회.
  Future<List<AdminLog>> listLogs() async {
    final res = await _c.rpc(
      'admin_list_logs',
      params: {'p_limit': 100, 'p_offset': 0},
    );
    return (res as List).map((r) => AdminLog.fromJson(r as Map)).toList();
  }

  /// 클라이언트 오류 목록 (reported 등급만, 30일 보존).
  Future<List<AdminClientError>> listClientErrors({
    String? where,
    int limit = 100,
  }) async {
    final res = await _c.rpc(
      'admin_client_errors',
      params: {'p_where': where, 'p_limit': limit, 'p_offset': 0},
    );
    return (res as List)
        .map((r) => AdminClientError.fromJson(r as Map))
        .toList();
  }

  /// 최근 [hours] 시간의 발생 지점별 집계.
  Future<List<AdminClientErrorStat>> clientErrorSummary({
    int hours = 24,
  }) async {
    final res = await _c.rpc(
      'admin_client_error_summary',
      params: {'p_hours': hours},
    );
    return (res as List)
        .map((r) => AdminClientErrorStat.fromJson(r as Map))
        .toList();
  }

  /// 운영 지표·비용 (AI 사진인증 / Solapi 문자 / DAU).
  Future<AdminOpsMetrics> opsMetrics() async {
    final res = await _c.rpc('admin_ops_metrics');
    return AdminOpsMetrics.fromJson(res as Map);
  }

  /// AI 사진 인증 실패 로그(최신순).
  Future<List<PhotoVerifyFailure>> photoVerificationFailures({
    int limit = 50,
  }) async {
    final res = await _c.rpc(
      'admin_photo_verification_failures',
      params: {'p_limit': limit, 'p_offset': 0},
    );
    return (res as List)
        .map((r) => PhotoVerifyFailure.fromJson(r as Map))
        .toList();
  }

  /// 전체 공지 발송(system_notice) — 약관 개정 고지 등. 발송 대상 수를 반환.
  Future<int> broadcastSystemNotice(String title, String body) async {
    final res = await _c.rpc(
      'admin_broadcast_system_notice',
      params: {'p_title': title, 'p_body': body},
    );
    return (res as num).toInt();
  }
}
