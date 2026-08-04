/// 승인된 업체의 프로필 — 조회 · 정보 수정 · 대표 사진.
///
/// 쓰기는 전부 서버(apply-business 엣지 → definer RPC)가 담당하고,
/// 여기서는 본인 행 조회(RLS select-own)와 호출만 한다.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/business.dart';
import '../error_reporter.dart';
import '../session.dart';

class BusinessProfileRepository {
  BusinessProfileRepository._();
  static final BusinessProfileRepository instance =
      BusinessProfileRepository._();

  SupabaseClient get _c => Supabase.instance.client;

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
    } catch (e, st) {
      // null 은 '업체 아님' 으로 읽힌다 — 승인된 업체가 개인 계정처럼 보인다.
      ErrorReporter.report(e, where: 'business.fetchMine', stackTrace: st);
      return null;
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
    } catch (e, st) {
      ErrorReporter.userFacing(
        e,
        where: 'business.updateMyInfo',
        stackTrace: st,
      );
      return false;
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
    } catch (e, st) {
      ErrorReporter.userFacing(e, where: 'business.setPhoto', stackTrace: st);
      return false;
    }
  }
}
