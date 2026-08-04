/// 관리자 — 고객센터 문의. 모든 호출은 DB 에서 `app.is_admin()` 으로 검증된다 —
/// 이 클래스에는 권한 판단이 없고, 있어서도 안 된다(클라이언트 판단은 우회된다).
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/admin.dart';

class AdminInquiryRepository {
  AdminInquiryRepository._();
  static final AdminInquiryRepository instance = AdminInquiryRepository._();

  SupabaseClient get _c => Supabase.instance.client;

  /// 문의(admin_inquiry 채팅방) 목록.
  Future<List<AdminInquiry>> listInquiries() async {
    final res = await _c.rpc('admin_list_inquiries');
    return (res as List).map((r) => AdminInquiry.fromJson(r as Map)).toList();
  }

  /// 문의방에 참여(답장 위해). 멱등.
  Future<void> joinInquiry(String roomId) async {
    await _c.rpc('admin_join_inquiry', params: {'p_room': roomId});
  }
}
