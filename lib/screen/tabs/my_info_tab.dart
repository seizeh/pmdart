import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../data/mock_data.dart' show MockPet;
import '../../models/profile.dart';
import '../../services/profile_repository.dart';
import '../../services/app_events.dart';
import '../../widgets/pet_card.dart';
import '../../services/auth_service.dart';
import '../pet_detail_screen.dart';
import '../pet_edit_screen.dart';
import '../connections_screen.dart';
import '../profile_edit_screen.dart';
import '../my_posts_screen.dart';
import '../activity_screens.dart';
import '../notification_settings_screen.dart';
import '../blocked_users_screen.dart';
import '../coming_soon_screen.dart';
import '../auth/login_screen.dart';
import '../auth/signup_phone_screen.dart';
import '../welcome_screen.dart';

/// 화면 이동 공용 헬퍼.
void _push(BuildContext context, Widget screen) {
  Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
}

/// 내정보 탭 — 프로필 헤더 / 내 반려동물(N:M) / 내 활동 / 관심 / 설정.
class MyInfoTab extends StatefulWidget {
  final bool isGuest;
  const MyInfoTab({super.key, this.isGuest = false});

  @override
  State<MyInfoTab> createState() => _MyInfoTabState();
}

class _MyInfoTabState extends State<MyInfoTab> {
  ProfileData? _profile;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (!widget.isGuest) {
      _load();
      AppEvents.instance.social.addListener(_onSocialChanged);
      AppEvents.instance.profile.addListener(_onSocialChanged);
    }
  }

  @override
  void dispose() {
    AppEvents.instance.social.removeListener(_onSocialChanged);
    AppEvents.instance.profile.removeListener(_onSocialChanged);
    super.dispose();
  }

  void _onSocialChanged() {
    if (mounted) _load(silent: true);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final p = await ProfileRepository.instance.fetchProfile();
      if (!mounted) return;
      setState(() {
        _profile = p;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        // 조용한 새로고침 실패 시 기존 데이터 유지
        if (_profile == null) _error = '프로필을 불러오지 못했어요';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isGuest) return const _GuestMyInfo();

    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _profile == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error ?? '프로필을 불러오지 못했어요',
                  style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 12),
              TextButton(onPressed: _load, child: const Text('다시 시도')),
            ],
          ),
        ),
      );
    }

    final profile = _profile!;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ProfileHeader(profile: profile),
                const SizedBox(height: 24),
                _PetSection(pets: profile.pets),
                const SizedBox(height: 24),
                _ActivitySection(profile: profile),
                const SizedBox(height: 12),
                _InterestSection(profile: profile),
                const SizedBox(height: 12),
                const _SettingsSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GuestMyInfo extends StatelessWidget {
  const _GuestMyInfo();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(32),
                ),
                child: const Icon(Icons.person_outline,
                    size: 48, color: AppColors.primaryDark),
              ),
              const SizedBox(height: 20),
              const Text(
                '게스트로 둘러보는 중',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '회원이 되면 반려동물 등록·산책 메이트 매칭·\n채팅까지 모두 이용할 수 있어요',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const SignupPhoneScreen()),
                ),
                child: const Text('전화번호로 시작하기'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                ),
                child: const Text('로그인'),
              ),
              const Spacer(),
              const _GuestFooter(),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuestFooter extends StatelessWidget {
  const _GuestFooter();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 20,
      children: [
        _link('이용약관'),
        _link('개인정보 처리방침'),
        _link('고객센터'),
      ],
    );
  }

  Widget _link(String s) => Text(
    s,
    style: const TextStyle(
        fontSize: 12, color: AppColors.textTertiary),
  );
}

class _ProfileHeader extends StatelessWidget {
  final ProfileData profile;
  const _ProfileHeader({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primaryDark,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.primarySoft,
                child: Text(
                  profile.nickname.isEmpty
                      ? '?'
                      : profile.nickname.characters.first,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.nickname,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textOnPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '@${profile.username}  ·  ${_userTypeLabel(profile.userType)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFD9CBA8),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined,
                    color: AppColors.textOnPrimary),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ProfileEditScreen(initialNickname: profile.nickname),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                  child: _statCol('받은 평가', profile.reviewCount.toString())),
              Container(
                width: 1,
                height: 32,
                color: const Color(0x33D9CBA8),
              ),
              Expanded(
                  child: _statCol('Pawing', profile.pawingCount.toString())),
              Container(
                width: 1,
                height: 32,
                color: const Color(0x33D9CBA8),
              ),
              Expanded(
                  child: _statCol('Pawmate', profile.pawmateCount.toString())),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statCol(String label, String value) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.textOnPrimary,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        label,
        style: const TextStyle(fontSize: 11, color: Color(0xFFD9CBA8)),
      ),
    ],
  );

  String _userTypeLabel(String t) => switch (t) {
    'pet_owner' => '반려동물 보호자',
    'no_pet' => '반려동물 미보유',
    'business' => '업체',
    'admin' => '관리자',
    _ => t,
  };
}

class _PetSection extends StatelessWidget {
  final List<MockPet> pets;
  const _PetSection({required this.pets});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text(
                '내 반려동물',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: const Text(
                  'N:M 공유',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _openPetEditor(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('등록'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...pets.map(
                (p) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: PetCard(
                pet: p,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => PetDetailScreen(pet: p)),
                ),
              ),
            ),
          ),
          if (pets.isEmpty)
            EmptyPetCard(onTap: () => _openPetEditor(context)),
        ],
      ),
    );
  }

  void _openPetEditor(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PetEditScreen()),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<_Item> items;
  const _SectionCard({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            ...items.expand((it) sync* {
              yield _ItemRow(item: it);
              if (it != items.last) {
                yield const Divider(
                    height: 1, indent: 56, color: AppColors.border);
              }
            }),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

class _Item {
  final IconData icon;
  final String label;
  final String? trailing;
  final VoidCallback? onTap;
  const _Item({required this.icon, required this.label, this.trailing, this.onTap});
}

class _ItemRow extends StatelessWidget {
  final _Item item;
  const _ItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: item.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(item.icon, size: 20, color: AppColors.primaryDark),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                item.label,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (item.trailing != null)
              Text(
                item.trailing!,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right,
                size: 18, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _ActivitySection extends StatelessWidget {
  final ProfileData profile;
  const _ActivitySection({required this.profile});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '내 활동',
      items: [
        _Item(
            icon: Icons.article_outlined,
            label: '내 게시글',
            trailing: '${profile.postCount}',
            onTap: () => _push(context,
                const MyPostsScreen(mode: PostListMode.mine))),
        _Item(
            icon: Icons.send_outlined,
            label: '내 지원 내역',
            trailing: '${profile.applicationCount}',
            onTap: () => _push(context, const MyApplicationsScreen())),
        _Item(
            icon: Icons.event_available_outlined,
            label: '약속',
            trailing: '${profile.appointmentCount} 진행 중',
            onTap: () => _push(context, const MyAppointmentsScreen())),
        _Item(
            icon: Icons.star_border,
            label: '받은 평가',
            trailing: '${profile.reviewCount}',
            onTap: () => _push(context, const MyReviewsScreen())),
      ],
    );
  }
}

class _InterestSection extends StatelessWidget {
  final ProfileData profile;
  const _InterestSection({required this.profile});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '관심',
      items: [
        _Item(
            icon: Icons.favorite_border,
            label: '하트한 게시글',
            trailing: '${profile.heartCount}',
            onTap: () => _push(context,
                const MyPostsScreen(mode: PostListMode.hearted))),
        _Item(
          icon: Icons.handshake_outlined,
          label: 'Pawing (내가 팔로우)',
          trailing: '${profile.pawingCount}',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const ConnectionsScreen(initialIndex: 0)),
          ),
        ),
        _Item(
          icon: Icons.groups_outlined,
          label: 'Pawmate (나를 팔로우)',
          trailing: '${profile.pawmateCount}',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const ConnectionsScreen(initialIndex: 1)),
          ),
        ),
      ],
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection();

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '설정',
      items: [
        _Item(
            icon: Icons.notifications_outlined,
            label: '알림 설정',
            onTap: () => _push(context, const NotificationSettingsScreen())),
        _Item(
            icon: Icons.location_on_outlined,
            label: '지역 인증',
            onTap: () => _push(context, const ComingSoonScreen(title: '지역 인증'))),
        _Item(
            icon: Icons.lock_outline,
            label: '계정 / 비밀번호',
            onTap: () =>
                _push(context, const ComingSoonScreen(title: '계정 / 비밀번호'))),
        _Item(
            icon: Icons.block_outlined,
            label: '차단 사용자 관리',
            onTap: () => _push(context, const BlockedUsersScreen())),
        _Item(
          icon: Icons.logout,
          label: '로그아웃',
          onTap: () => _confirmLogout(context),
        ),
      ],
    );
  }

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('로그아웃'),
        content: const Text('로그아웃 하시겠어요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await AuthService.instance.logout();
              if (!context.mounted) return;
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                (route) => false,
              );
            },
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );
  }
}