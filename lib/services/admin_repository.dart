import 'package:supabase_flutter/supabase_flutter.dart';

/// 관리자 대시보드 통계.
class AdminStats {
  final int users;
  final int usersSuspended;
  final int posts;
  final int appointmentsScheduled;
  final int reportsOpen;

  const AdminStats({
    required this.users,
    required this.usersSuspended,
    required this.posts,
    required this.appointmentsScheduled,
    required this.reportsOpen,
  });

  factory AdminStats.fromJson(Map j) => AdminStats(
        users: (j['users'] as num?)?.toInt() ?? 0,
        usersSuspended: (j['users_suspended'] as num?)?.toInt() ?? 0,
        posts: (j['posts'] as num?)?.toInt() ?? 0,
        appointmentsScheduled:
            (j['appointments_scheduled'] as num?)?.toInt() ?? 0,
        reportsOpen: (j['reports_open'] as num?)?.toInt() ?? 0,
      );
}

/// 관리자가 보는 회원 1명.
class AdminUser {
  final String id;
  final String username;
  final String nickname;
  final String userType;
  final String status; // active / inactive / suspended
  final String? phone;
  final DateTime createdAt;

  const AdminUser({
    required this.id,
    required this.username,
    required this.nickname,
    required this.userType,
    required this.status,
    required this.phone,
    required this.createdAt,
  });

  bool get isAdmin => userType == 'admin';

  factory AdminUser.fromJson(Map j) => AdminUser(
        id: j['id'] as String,
        username: (j['username'] ?? '') as String,
        nickname: (j['nickname'] ?? '') as String,
        userType: (j['user_type'] ?? '') as String,
        status: (j['status'] ?? 'active') as String,
        phone: j['phone'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
      );
}

/// 관리자 전용 데이터 접근. 모든 호출은 DB 에서 app.is_admin() 으로 검증된다.
class AdminRepository {
  AdminRepository._();
  static final AdminRepository instance = AdminRepository._();

  SupabaseClient get _c => Supabase.instance.client;

  /// 대시보드 통계.
  Future<AdminStats> dashboardStats() async {
    final res = await _c.rpc('admin_dashboard_stats');
    return AdminStats.fromJson((res as Map));
  }

  /// 회원 목록/검색 (닉네임·아이디·전화).
  Future<List<AdminUser>> listUsers({String? search, int limit = 50}) async {
    final res = await _c.rpc('admin_list_users', params: {
      'p_search': (search == null || search.trim().isEmpty) ? null : search.trim(),
      'p_limit': limit,
      'p_offset': 0,
    });
    return (res as List)
        .map((r) => AdminUser.fromJson(r as Map))
        .toList();
  }

  /// 회원 상태 변경 (active/inactive/suspended).
  Future<void> setUserStatus(String userId, String status) async {
    await _c.rpc('admin_set_user_status',
        params: {'p_user': userId, 'p_status': status});
  }
}
