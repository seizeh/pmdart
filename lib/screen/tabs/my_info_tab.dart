import 'package:flutter/material.dart';
import '../../motion/motion.dart';
import '../../theme/app_colors.dart';
import '../../data/mock_data.dart' show MockPet;
import '../../models/profile.dart';
import '../../services/profile_repository.dart';
import '../../services/pet_repository.dart';
import '../../services/app_events.dart';
import '../../widgets/pet_card.dart';
import '../../widgets/role_badge.dart';
import '../../widgets/gradient_header.dart';
import '../../services/auth_service.dart';
import '../pet_detail_screen.dart';
import '../pet_edit_screen.dart';
import '../connections_screen.dart';
import '../profile_edit_screen.dart';
import '../my_posts_screen.dart';
import '../activity_screens.dart';
import '../change_password_screen.dart';
import '../guardian_invites_screen.dart';
import '../notification_settings_screen.dart';
import '../blocked_users_screen.dart';
import '../auth/login_screen.dart';
import '../auth/signup_phone_screen.dart';
import '../welcome_screen.dart';
import '../terms_screen.dart';

/// 화면 이동 공용 헬퍼.
void _push(BuildContext context, Widget screen) {
  Navigator.push(context, AppPageRoute(builder: (_) => screen));
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
  int _pendingInvites = 0;
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
      int invites = 0;
      try {
        invites = await PetRepository.instance.pendingInviteCount();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _profile = p;
        _pendingInvites = invites;
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

    final topInset = MediaQuery.of(context).padding.top;
    // 다른 탭(채팅·검색·커뮤니티)과 동일하게: 콘텐츠가 떠 있는 프로스트 헤더
    // 아래로 스크롤되며 비치는 구조.
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Positioned.fill(child: _buildBody(topInset + 56)),
          GradientHeader(
            topInset: topInset,
            child: const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 10),
              child: Text(
                '내 정보',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryDark,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(double topPad) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null || _profile == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error ?? '프로필을 불러오지 못했어요',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: _load, child: const Text('다시 시도')),
          ],
        ),
      );
    }

    final profile = _profile!;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return RefreshIndicator(
      onRefresh: _load,
      edgeOffset: topPad,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        // 헤더 아래에서 시작, 하단은 플로팅 메뉴바(62+여백) 뒤로 확장되는 만큼 여백.
        padding: EdgeInsets.only(
          top: topPad + 14,
          bottom: 62 + bottomInset + 32,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 반려동물이 주인공 — 큰 히어로 카드/캐러셀을 최상단에.
            _PetHero(pets: profile.pets),
            const SizedBox(height: 20),
            // 유저 정보는 작은 카드로 축소(보조).
            _UserStrip(profile: profile),
            const SizedBox(height: 20),
            _ActivitySection(
              profile: profile,
              pendingInvites: _pendingInvites,
            ),
            const SizedBox(height: 12),
            _ActivityRangeSection(profile: profile),
            const SizedBox(height: 12),
            _InterestSection(profile: profile),
            const SizedBox(height: 12),
            _SettingsSection(profile: profile),
            const SizedBox(height: 20),
            // 약관·처리방침 상시 열람(게시 의무).
            const _GuestFooter(),
          ],
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
      backgroundColor: Colors.white,
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
                child: const Icon(
                  Icons.person_outline,
                  size: 48,
                  color: AppColors.primaryDark,
                ),
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
                  AppPageRoute(builder: (_) => const SignupPhoneScreen()),
                ),
                child: const Text('전화번호로 시작하기'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.push(
                  context,
                  AppPageRoute(builder: (_) => const LoginScreen()),
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
        _link(context, '이용약관', TermsScreen.service()),
        _link(context, '위치기반서비스 약관', TermsScreen.location()),
        _link(context, '개인정보 처리방침', TermsScreen.privacy()),
      ],
    );
  }

  Widget _link(BuildContext context, String s, Widget screen) =>
      GestureDetector(
        onTap: () => _push(context, screen),
        child: Text(
          s,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textTertiary,
            decoration: TextDecoration.underline,
          ),
        ),
      );
}

/// 반려동물 히어로 — 내정보 최상단의 주인공. 큰 사진 카드(여러 마리면 캐러셀).
class _PetHero extends StatefulWidget {
  final List<MockPet> pets;
  const _PetHero({required this.pets});

  @override
  State<_PetHero> createState() => _PetHeroState();
}

class _PetHeroState extends State<_PetHero> {
  final _pc = PageController(viewportFraction: 0.9);
  int _page = 0;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _openEditor() => _push(context, const PetEditScreen());

  @override
  Widget build(BuildContext context) {
    final pets = widget.pets;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
          child: Row(
            children: [
              const Text(
                '내 반려동물',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              if (pets.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  '${pets.length}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
              const Spacer(),
              TextButton.icon(
                onPressed: _openEditor,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('등록'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        if (pets.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: EmptyPetCard(onTap: _openEditor),
          )
        else ...[
          SizedBox(
            height: 320,
            child: PageView.builder(
              controller: _pc,
              padEnds: pets.length > 1,
              itemCount: pets.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: _PetHeroCard(
                  pet: pets[i],
                  onTap: () => _push(context, PetDetailScreen(pet: pets[i])),
                ),
              ),
            ),
          ),
          if (pets.length > 1) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < pets.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? AppColors.primaryDark
                          : AppColors.border,
                      borderRadius: BorderRadius.circular(100),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ],
    );
  }
}

/// 반려동물 히어로 카드 — 큰 사진 위에 이름/종·나이/인증 배지를 오버레이(포스터형).
class _PetHeroCard extends StatelessWidget {
  final MockPet pet;
  final VoidCallback onTap;
  const _PetHeroCard({required this.pet, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final age = pet.birthDate == null
        ? null
        : '${DateTime.now().year - pet.birthDate!.year}살';
    final genderKo = switch (pet.gender) {
      'male' => '남아',
      'female' => '여아',
      _ => null,
    };
    final subtitle = [
      pet.species,
      if (age != null) age,
      if (genderKo != null) genderKo,
    ].join('  ·  ');

    // Pressable — 피드 카드·검색 타일과 동일한 스프링 눌림 피드백으로 통일.
    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.primarySoft,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 사진(없으면 발바닥 플레이스홀더)
            if (pet.imageUrl != null)
              Image.network(
                pet.imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const _PetHeroPlaceholder(),
              )
            else
              const _PetHeroPlaceholder(),
            // 하단 어둡게 — 흰 글씨 가독성.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 150,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xB3000000)],
                  ),
                ),
              ),
            ),
            // 상단 우측: 역할 + 인증 배지
            Positioned(
              top: 14,
              right: 14,
              child: Row(
                children: [
                  if (pet.isIdentityVerified) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.verified,
                            size: 13,
                            color: AppColors.primaryDark,
                          ),
                          SizedBox(width: 3),
                          Text(
                            '인증',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  RoleBadge(role: pet.role, compact: true),
                ],
              ),
            ),
            // 하단 좌측: 이름 + 종·나이·성별
            Positioned(
              left: 18,
              right: 18,
              bottom: 18,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pet.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xF2FFFFFF),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PetHeroPlaceholder extends StatelessWidget {
  const _PetHeroPlaceholder();
  @override
  Widget build(BuildContext context) => const ColoredBox(
    color: AppColors.primarySoft,
    child: Center(
      child: Icon(Icons.pets, size: 72, color: AppColors.primaryDark),
    ),
  );
}

/// 유저 정보(축소) — 반려동물이 주인공이므로 작은 카드로 보조 표시.
class _UserStrip extends StatelessWidget {
  final ProfileData profile;
  const _UserStrip({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.primarySoft,
                child: Text(
                  profile.nickname.isEmpty
                      ? '?'
                      : profile.nickname.characters.first,
                  style: const TextStyle(
                    fontSize: 18,
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
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '@${profile.username}  ·  ${_userTypeLabel(profile.userType)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.edit_outlined,
                  color: AppColors.textSecondary,
                ),
                onPressed: () => Navigator.push(
                  context,
                  AppPageRoute(
                    builder: (_) => ProfileEditScreen(
                      initialNickname: profile.nickname,
                      initialAddress: profile.address,
                      initialVerified: profile.isLocationVerified,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _statCol('받은 평가', profile.reviewCount.toString()),
              ),
              Container(width: 1, height: 26, color: AppColors.border),
              Expanded(
                child: _statCol('Pawing', profile.pawingCount.toString()),
              ),
              Container(width: 1, height: 26, color: AppColors.border),
              Expanded(
                child: _statCol('Pawmate', profile.pawmateCount.toString()),
              ),
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
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        label,
        style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
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
                  height: 1,
                  indent: 56,
                  color: AppColors.border,
                );
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
  const _Item({
    required this.icon,
    required this.label,
    this.trailing,
    this.onTap,
  });
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
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

/// 활동 범위 설정 — 인증 동 기준 반경(최대 7km).
class _ActivityRangeSection extends StatefulWidget {
  final ProfileData profile;
  const _ActivityRangeSection({required this.profile});

  @override
  State<_ActivityRangeSection> createState() => _ActivityRangeSectionState();
}

class _ActivityRangeSectionState extends State<_ActivityRangeSection> {
  static const _options = [5000, 7000, 10000, 15000]; // m, 5~15km
  late int? _radius = widget.profile.activityRadiusM;
  bool _saving = false;

  Future<void> _select(int m) async {
    if (_saving || m == _radius) return;
    final prev = _radius;
    setState(() {
      _radius = m;
      _saving = true;
    });
    try {
      await ProfileRepository.instance.setActivityRadius(m);
    } catch (_) {
      if (mounted) setState(() => _radius = prev);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('활동 범위를 저장하지 못했어요')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final verified = widget.profile.isLocationVerified;
    final dong = widget.profile.regionName;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '활동 범위',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              verified
                  ? '${dong ?? '내 동네'} 기준 반경 (5~15km) · 이 범위의 게시글만 보여요'
                  : '동네 인증을 먼저 완료하면 설정할 수 있어요',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary,
              ),
            ),
            if (verified) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in _options)
                    _RadiusChip(
                      label: '${m ~/ 1000}km',
                      selected: _radius == m,
                      onTap: () => _select(m),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RadiusChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _RadiusChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryDark : AppColors.surface,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: selected ? AppColors.primaryDark : AppColors.border,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.textOnPrimary : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _ActivitySection extends StatelessWidget {
  final ProfileData profile;
  final int pendingInvites;
  const _ActivitySection({required this.profile, required this.pendingInvites});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '내 활동',
      items: [
        _Item(
          icon: Icons.mail_outline,
          label: '받은 보호자 초대',
          trailing: pendingInvites > 0 ? '$pendingInvites' : null,
          onTap: () => _push(context, const GuardianInvitesScreen()),
        ),
        _Item(
          icon: Icons.article_outlined,
          label: '내 게시글',
          trailing: '${profile.postCount}',
          onTap: () =>
              _push(context, const MyPostsScreen(mode: PostListMode.mine)),
        ),
        _Item(
          icon: Icons.send_outlined,
          label: '내 지원 내역',
          trailing: '${profile.applicationCount}',
          onTap: () => _push(context, const MyApplicationsScreen()),
        ),
        _Item(
          icon: Icons.event_available_outlined,
          label: '약속',
          trailing: '${profile.appointmentCount} 진행 중',
          onTap: () => _push(context, const MyAppointmentsScreen()),
        ),
        _Item(
          icon: Icons.star_border,
          label: '받은 평가',
          trailing: '${profile.reviewCount}',
          onTap: () => _push(context, const MyReviewsScreen()),
        ),
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
          onTap: () =>
              _push(context, const MyPostsScreen(mode: PostListMode.hearted)),
        ),
        _Item(
          icon: Icons.handshake_outlined,
          label: 'Pawing (내가 팔로우)',
          trailing: '${profile.pawingCount}',
          onTap: () => Navigator.push(
            context,
            AppPageRoute(
              builder: (_) => const ConnectionsScreen(initialIndex: 0),
            ),
          ),
        ),
        _Item(
          icon: Icons.groups_outlined,
          label: 'Pawmate (나를 팔로우)',
          trailing: '${profile.pawmateCount}',
          onTap: () => Navigator.push(
            context,
            AppPageRoute(
              builder: (_) => const ConnectionsScreen(initialIndex: 1),
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final ProfileData profile;
  const _SettingsSection({required this.profile});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: '설정',
      items: [
        _Item(
          icon: Icons.notifications_outlined,
          label: '알림 설정',
          onTap: () => _push(context, const NotificationSettingsScreen()),
        ),
        _Item(
          icon: Icons.lock_outline,
          label: '비밀번호 변경',
          onTap: () => _push(context, const ChangePasswordScreen()),
        ),
        _Item(
          icon: Icons.block_outlined,
          label: '차단 사용자 관리',
          onTap: () => _push(context, const BlockedUsersScreen()),
        ),
        _Item(
          icon: Icons.description_outlined,
          label: '약관 및 정책',
          onTap: () => _showTerms(context),
        ),
        _Item(
          icon: Icons.logout,
          label: '로그아웃',
          onTap: () => _confirmLogout(context),
        ),
        _Item(
          icon: Icons.person_off_outlined,
          label: '회원 탈퇴',
          onTap: () => _confirmWithdraw(context),
        ),
      ],
    );
  }

  /// 약관·정책 전문 조회 — 가입 때 동의한 문서를 언제든 다시 볼 수 있게.
  void _showTerms(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '약관 및 정책',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
            for (final (label, builder) in <(String, Widget Function())>[
              ('서비스 이용약관', TermsScreen.service),
              ('위치기반서비스 이용약관', TermsScreen.location),
              ('개인정보 처리방침', TermsScreen.privacy),
            ])
              ListTile(
                leading: const Icon(Icons.article_outlined,
                    color: AppColors.textSecondary),
                title: Text(label,
                    style: const TextStyle(
                        fontSize: 15, color: AppColors.textPrimary)),
                trailing: const Icon(Icons.chevron_right,
                    size: 20, color: AppColors.textTertiary),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _push(context, builder());
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
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
                AppPageRoute(builder: (_) => const WelcomeScreen()),
                (route) => false,
              );
            },
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );
  }

  /// 회원 탈퇴 — 파기·잔존 안내 후 서버 RPC 로 즉시 처리(복구 불가).
  void _confirmWithdraw(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('회원 탈퇴'),
        content: const Text(
          '탈퇴하면 되돌릴 수 없어요.\n\n'
          '· 계정·프로필·전화번호 등 개인정보는 즉시 파기됩니다\n'
          '  (부정이용 방지를 위해 아이디·전화번호만 30일 분리 보관 후 파기)\n'
          '· 등록한 반려동물 정보가 삭제됩니다\n'
          '· 작성한 게시글·채팅은 남지만 익명으로 표시됩니다\n'
          '  (남기고 싶지 않다면 탈퇴 전에 직접 삭제해주세요)',
          style: TextStyle(fontSize: 13.5, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => _withdraw(context, dialogCtx),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('탈퇴하기'),
          ),
        ],
      ),
    );
  }

  Future<void> _withdraw(BuildContext context, BuildContext dialogCtx) async {
    Navigator.pop(dialogCtx);
    try {
      await ProfileRepository.instance.withdrawAccount();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('탈퇴 처리에 실패했어요. 잠시 후 다시 시도해주세요'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    // 서버에서 이미 세션이 무효화됨 — 로컬 세션 정리 후 시작 화면으로.
    await AuthService.instance.logout();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('탈퇴가 완료되었어요. 그동안 이용해주셔서 감사합니다'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.of(context).pushAndRemoveUntil(
      AppPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
  }
}
