import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../services/admin_repository.dart';
import '../../services/auth_service.dart';
import '../coming_soon_screen.dart';
import '../welcome_screen.dart';
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
              child: const Text('취소')),
          TextButton(
              onPressed: () => Navigator.pop(dCtx, true),
              child: const Text('로그아웃')),
        ],
      ),
    );
    if (ok != true) return;
    await AuthService.instance.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }

  void _open(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('관리자'),
        actions: [
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
              _dashboard(),
              const SizedBox(height: 24),
              const Text(
                '관리',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
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
                onTap: () =>
                    _open(const ComingSoonScreen(title: '게시글/댓글 관리')),
              ),
              _MenuTile(
                icon: Icons.flag_outlined,
                label: '신고 처리',
                badge: _stats?.reportsOpen ?? 0,
                onTap: () => _open(const ComingSoonScreen(title: '신고 처리')),
              ),
              _MenuTile(
                icon: Icons.support_agent_outlined,
                label: '문의 처리',
                onTap: () => _open(const ComingSoonScreen(title: '문의 처리')),
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
              Text(_error ?? '통계를 불러오지 못했어요',
                  style: const TextStyle(color: AppColors.textSecondary)),
              TextButton(onPressed: _load, child: const Text('다시 시도')),
            ],
          ),
        ),
      );
    }
    final s = _stats!;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.7,
      children: [
        _StatCard(label: '전체 회원', value: s.users, icon: Icons.people_outline),
        _StatCard(
            label: '정지 회원',
            value: s.usersSuspended,
            icon: Icons.block,
            highlight: s.usersSuspended > 0),
        _StatCard(label: '게시글', value: s.posts, icon: Icons.article_outlined),
        _StatCard(
            label: '진행 중 약속',
            value: s.appointmentsScheduled,
            icon: Icons.event_available_outlined),
        _StatCard(
            label: '미처리 신고',
            value: s.reportsOpen,
            icon: Icons.flag_outlined,
            highlight: s.reportsOpen > 0),
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
        color: highlight ? AppColors.danger.withValues(alpha: 0.08) : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlight ? AppColors.danger.withValues(alpha: 0.4) : AppColors.border,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon,
              size: 20,
              color: highlight ? AppColors.danger : AppColors.primaryDark),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: highlight ? AppColors.danger : AppColors.textPrimary,
            ),
          ),
          Text(label,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primaryDark),
        title: Text(label,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (badge > 0)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.danger,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text('$badge',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, color: AppColors.textTertiary),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
