import 'package:flutter/material.dart';

import '../../motion/motion.dart';
import '../../services/admin_repository.dart';
import '../../services/auth_service.dart';
import '../../services/session.dart';
import '../../theme/app_palette.dart';
import '../change_password_screen.dart';
import '../welcome_screen.dart';
import 'admin_broadcast_screen.dart';
import 'admin_business_screen.dart';
import 'admin_client_errors_screen.dart';
import 'admin_inquiries_screen.dart';
import 'admin_licenses_screen.dart';
import 'admin_logs_screen.dart';
import 'admin_metrics_screen.dart';
import 'admin_posts_screen.dart';
import 'admin_reports_screen.dart';
import 'admin_share_qr_screen.dart';
import 'admin_theme.dart';
import 'admin_users_screen.dart';

/// 관리자 홈 — 대시보드 + 관리 메뉴.
/// 관리자(user_type='admin') 로 로그인하면 일반 화면 대신 이 화면으로 진입한다.
class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  AdminStats? _stats;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await AdminRepository.instance.dashboardStats();
      if (!mounted) return;
      setState(() {
        _stats = s;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '통계를 불러오지 못했어요';
        _loading = false;
      });
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('로그아웃'),
        content: const Text('관리자 계정에서 로그아웃할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await AuthService.instance.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      AppPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  void _open(Widget screen) {
    Navigator.push(context, AppPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: adminAppBar(
        context,
        '관리자 콘솔',
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: '비밀번호 변경',
            onPressed: () => _open(const ChangePasswordScreen()),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '로그아웃',
            onPressed: _logout,
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const _AdminIdentityHeader(),
              const SizedBox(height: 16),
              _dashboard(),
              const SizedBox(height: 24),
              Text(
                '관리',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              _MenuTile(
                icon: Icons.group_outlined,
                label: '회원 관리',
                onTap: () => _open(const AdminUsersScreen()),
              ),
              _MenuTile(
                icon: Icons.article_outlined,
                label: '게시글/댓글 관리',
                onTap: () => _open(const AdminPostsScreen()),
              ),
              _MenuTile(
                icon: Icons.flag_outlined,
                label: '신고 처리',
                badge: _stats?.reportsOpen ?? 0,
                onTap: () => _open(const AdminReportsScreen()),
              ),
              _MenuTile(
                icon: Icons.storefront_outlined,
                label: '업체 인증 심사',
                onTap: () => _open(const AdminBusinessScreen()),
              ),
              _MenuTile(
                icon: Icons.badge_outlined,
                label: '업종 인증 심사',
                onTap: () => _open(const AdminLicensesScreen()),
              ),
              _MenuTile(
                icon: Icons.qr_code_2,
                label: '매장 QR 발급',
                onTap: () => _open(const AdminShareQrScreen()),
              ),
              _MenuTile(
                icon: Icons.support_agent_outlined,
                label: '문의 처리',
                onTap: () => _open(const AdminInquiriesScreen()),
              ),
              _MenuTile(
                icon: Icons.campaign_outlined,
                label: '전체 공지 발송',
                onTap: () => _open(const AdminBroadcastScreen()),
              ),
              _MenuTile(
                icon: Icons.query_stats_outlined,
                label: '운영 지표 · 비용',
                onTap: () => _open(const AdminMetricsScreen()),
              ),
              _MenuTile(
                icon: Icons.receipt_long_outlined,
                label: '감사 로그',
                onTap: () => _open(const AdminLogsScreen()),
              ),
              _MenuTile(
                icon: Icons.bug_report_outlined,
                label: '클라이언트 오류',
                onTap: () => _open(const AdminClientErrorsScreen()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dashboard() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _stats == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Column(
            children: [
              Text(
                _error ?? '통계를 불러오지 못했어요',
                style: TextStyle(color: context.colors.textSecondary),
              ),
              TextButton(onPressed: _load, child: const Text('다시 시도')),
            ],
          ),
        ),
      );
    }
    final s = _stats!;
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      // 비율(childAspectRatio) 대신 고정 높이로 — 좁은 화면에서도 카드 높이가
      // 콘텐츠(아이콘+숫자+라벨)보다 작아져 하단이 넘치는 문제를 막는다.
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: 120,
      ),
      children: [
        _StatCard(label: '전체 회원', value: s.users, icon: Icons.people_outline),
        _StatCard(
          label: '정지 회원',
          value: s.usersSuspended,
          icon: Icons.block,
          highlight: s.usersSuspended > 0,
        ),
        _StatCard(label: '게시글', value: s.posts, icon: Icons.article_outlined),
        _StatCard(
          label: '진행 중 약속',
          value: s.appointmentsScheduled,
          icon: Icons.event_available_outlined,
        ),
        _StatCard(
          label: '미처리 신고',
          value: s.reportsOpen,
          icon: Icons.flag_outlined,
          highlight: s.reportsOpen > 0,
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final bool highlight;
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highlight
            ? context.colors.danger.withValues(alpha: 0.08)
            : context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlight
              ? context.colors.danger.withValues(alpha: 0.4)
              : context.colors.border,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(
            icon,
            size: 20,
            color: highlight
                ? context.colors.danger
                : context.colors.primaryDark,
          ),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: highlight
                  ? context.colors.danger
                  : context.colors.textPrimary,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 12, color: context.colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final int badge;
  final VoidCallback onTap;
  const _MenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.border, width: 0.5),
      ),
      child: ListTile(
        leading: Icon(icon, color: context.colors.primaryDark),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: context.colors.textPrimary,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (badge > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: context.colors.danger,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  '$badge',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, color: context.colors.textTertiary),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

/// 관리자 신원 헤더 — 닉네임 + '관리자' 배지로 일반 사용자와 구분.
class _AdminIdentityHeader extends StatelessWidget {
  const _AdminIdentityHeader();

  @override
  Widget build(BuildContext context) {
    final nickname = SessionManager.instance.user?.nickname ?? '관리자';
    final username = SessionManager.instance.user?.username ?? '';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.colors.adminAccent,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.shield_outlined,
              color: context.colors.adminOnAccent,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        nickname,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: context.colors.adminOnAccent,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const AdminBadge(light: true),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  username.isEmpty ? '관리자 모드' : '@$username · 관리자 모드',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
