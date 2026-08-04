/// 관리자 — 사용자. 모든 호출은 DB 에서 `app.is_admin()` 으로 검증된다 —
/// 이 클래스에는 권한 판단이 없고, 있어서도 안 된다(클라이언트 판단은 우회된다).
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/admin.dart';

class AdminUsersRepository {
  AdminUsersRepository._();
  static final AdminUsersRepository instance = AdminUsersRepository._();

  SupabaseClient get _c => Supabase.instance.client;

  /// 회원 목록/검색 (닉네임·아이디·전화).
  Future<List<AdminUser>> listUsers({String? search, int limit = 50}) async {
    final res = await _c.rpc(
      'admin_list_users',
      params: {
        'p_search': (search == null || search.trim().isEmpty)
            ? null
            : search.trim(),
        'p_limit': limit,
        'p_offset': 0,
      },
    );
    return (res as List).map((r) => AdminUser.fromJson(r as Map)).toList();
  }

  /// 회원 상태 변경 (active/inactive/suspended).
  Future<void> setUserStatus(String userId, String status) async {
    await _c.rpc(
      'admin_set_user_status',
      params: {'p_user': userId, 'p_status': status},
    );
  }
}
