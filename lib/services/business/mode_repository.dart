/// 개인/업체 **활성 모드** — 앱 전반이 묻는 값이라 따로 뗐다.
///
/// 이 셋만 따로 뗀 이유: 화면 5곳이 "지금 개인인가 업체인가" 하나를 묻자고 업체
/// 등록·심사 코드까지 딸려 오는 리포지토리를 통째로 잡고 있었다. 활성 모드는
/// 업체 기능이 아니라 **앱 전반의 상태**다.
/// 쓰기는 전부 서버(apply-business 엣지 → definer RPC)가 담당하고,
/// 여기서는 본인 행 조회(RLS select-own)와 호출만 한다.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../error_reporter.dart';
import '../session.dart';

class AccountModeRepository {
  AccountModeRepository._();
  static final AccountModeRepository instance = AccountModeRepository._();

  SupabaseClient get _c => Supabase.instance.client;

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
    } catch (e, st) {
      // 업체 모드로 쓰던 사람이 개인 얼굴로 돌아간다(두 얼굴 전제가 깨짐).
      ErrorReporter.report(
        e,
        where: 'business.fetchActiveMode',
        stackTrace: st,
      );
      return 'personal';
    }
  }

  /// 계정 전환 — business 는 승인(approved) 상태에서만 서버가 허용.
  Future<String?> switchMode(String mode) async {
    try {
      final res = await _c.rpc('switch_account_mode', params: {'p_mode': mode});
      return res as String?;
    } catch (e, st) {
      ErrorReporter.userFacing(e, where: 'business.switchMode', stackTrace: st);
      return null;
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
    } catch (e) {
      ErrorReporter.ignored(
        e,
        where: 'business.shouldSuggestBusinessSwitch',
        why: '전환 제안 힌트일 뿐 — 안 뜨면 사용자가 직접 전환하면 된다',
      );
      return false;
    }
  }
}
