import 'dart:async';

import 'package:flutter/material.dart';

import '../models/profile.dart';
import '../motion/motion.dart';
import '../services/auth_service.dart';
import '../services/business_repository.dart';
import '../services/profile_repository.dart';
import '../services/session.dart';
import '../services/storage_service.dart';
import '../services/theme_controller.dart';
import '../state/profile_edit_state.dart';
import '../theme/app_palette.dart';
import 'activity_screens.dart';
import 'blocked_users_screen.dart';
import 'business_register_screen.dart';
import 'change_password_screen.dart';
import 'connections_screen.dart';
import 'guardian_invites_screen.dart';
import 'location_verify_screen.dart';
import 'my_posts_screen.dart';
import 'notification_settings_screen.dart';
import 'terms_screen.dart';
import 'welcome_screen.dart';

/// 화면 이동 공용 헬퍼.
void _push(BuildContext context, Widget screen) {
  Navigator.push(context, AppPageRoute(builder: (_) => screen));
}

/// 내정보 수정 — 닉네임 + 프로필 사진 + 활동 지역(GPS 인증)에 더해
/// 내 활동 / 활동 범위 / 관심 / 설정 섹션(내정보 탭에서 이동)까지 한 화면에서.
class ProfileEditScreen extends StatefulWidget {
  final String initialNickname;

  /// 활동 지역(동네 인증) 초기 상태. address 는 GPS 인증으로만 바뀐다.
  final String? initialAddress;
  final bool initialVerified;

  /// 내 활동/관심/설정 섹션 표시용 프로필 집계(내정보 탭이 넘겨준다).
  /// null 이면 섹션 없이 편집 폼만 표시.
  final ProfileData? profile;
  final int pendingInvites;

  const ProfileEditScreen({
    super.key,
    required this.initialNickname,
    this.initialAddress,
    this.initialVerified = false,
    this.profile,
    this.pendingInvites = 0,
  });

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  // 업로드/저장/모드/활동 지역 상태는 홀더가 갖고, 화면은 구독해 그리기 +
  // 피커/화면 이동/토스트/pop 만 담당한다 (docs/architecture-state.md).
  late final ProfileEditState _state = ProfileEditState(
    initialMode: widget.profile?.activeMode ?? 'personal',
    initialAddress: widget.initialAddress,
    initialVerified: widget.initialVerified,
  );
  late final TextEditingController _nickCtrl = TextEditingController(
    text: widget.initialNickname,
  );
  Timer? _nickDebounce; // 입력 중 닉네임 중복확인 디바운스

  @override
  void dispose() {
    _nickDebounce?.cancel();
    _nickCtrl.dispose();
    _state.dispose();
    super.dispose();
  }

  bool get _canSave =>
      !_state.saving &&
      !_state.uploading &&
      _nickCtrl.text.trim().isNotEmpty &&
      _state.nickAvailable != false; // 중복 확정 상태만 막는다(미확인은 통과)

  void _onNickChanged(String v) {
    setState(() {});
    _nickDebounce?.cancel();
    _nickDebounce = Timer(const Duration(milliseconds: 400), () {
      _state.checkNickname(v, original: widget.initialNickname);
    });
  }

  Future<void> _pickImage() async {
    final file = await StorageService.instance.pickImage();
    if (file == null || !mounted) return;
    if (!await _state.uploadImage(file)) _toast('사진 업로드에 실패했어요');
  }

  Future<void> _save() async {
    final ok = await _state.save(_nickCtrl.text.trim());
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
      _toast('프로필을 수정했어요');
    } else {
      _toast(_state.saveError ?? '저장에 실패했어요');
    }
  }

  /// 활동 지역은 자유 입력이 아니라 GPS 인증으로만 바뀐다(보안: 게시글 지역 게이팅).
  /// 인증 화면에서 성공(pop true)하면 서버 값이 갱신되므로 다시 조회해 표시한다.
  Future<void> _verifyRegion() async {
    final changed = await Navigator.push<bool>(
      context,
      AppPageRoute(
        builder: (_) => LocationVerifyScreen(currentRegion: _state.regionName),
      ),
    );
    if (changed != true || !mounted) return;
    await _state.refreshRegion();
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), behavior: SnackBarBehavior.floating),
    );
  }

  /// 업체 모드 본문 — 개인 프로필 폼 없이 업체 관리(정보·대표 사진)와 전환·설정만.
  /// "같은 수정 화면을 두 얼굴이 공유"하던 혼란(개인 사진을 바꾸면 업체도 바뀌어
  /// 보이는 문제)의 구조적 해소: 업체 것은 여기서만, 개인 것은 일반 모드에서만.
  Widget _businessBody() {
    return Column(
      children: [
        // 업체 수정이 최상단 — 프로필 한 번 탭으로 정보·대표 사진 수정에 바로 도달
        // (기존: 항목을 한 번 더 탭해야 했음).
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: BusinessManagePanel(),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            '개인 프로필(닉네임·사진·활동 지역)은 일반 모드에서 수정할 수 있어요.',
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: context.colors.textTertiary,
            ),
          ),
        ),
        const SizedBox(height: 20),
        _BusinessSection(isBizMode: true, onModeChanged: _state.setMode),
        const SizedBox(height: 12),
        if (widget.profile != null) _SettingsSection(profile: widget.profile!),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final initial = _nickCtrl.text.isEmpty
        ? (SessionManager.instance.user?.nickname ?? '?')
        : _nickCtrl.text;
    return ListenableBuilder(
      listenable: _state,
      builder: (context, _) => Scaffold(
        backgroundColor: context.colors.background,
        appBar: AppBar(
          // 업체 모드는 화면 전체가 '업체 관리' — 개인 프로필 폼(저장 버튼 포함) 없음.
          title: Text(_state.isBizMode ? '업체 관리' : '내정보 수정'),
          actions: [
            if (!_state.isBizMode)
              TextButton(
                onPressed: _canSave ? _save : null,
                child: _state.saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        '저장',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
          ],
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            // 섹션 카드(내 활동 등)는 자체 좌우 20 패딩을 가지므로 스크롤뷰는
            // 상하 패딩만 주고, 편집 폼 부분만 좌우 24 를 따로 감싼다.
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: _state.isBizMode
                ? _businessBody()
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          children: [
                            GestureDetector(
                              onTap: _state.uploading ? null : _pickImage,
                              child: Container(
                                width: 110,
                                height: 110,
                                decoration: BoxDecoration(
                                  color: context.colors.primarySoft,
                                  shape: BoxShape.circle,
                                  image: _state.imageUrl != null
                                      ? DecorationImage(
                                          image: NetworkImage(_state.imageUrl!),
                                          fit: BoxFit.cover,
                                        )
                                      : null,
                                ),
                                child: _state.uploading
                                    ? const Center(
                                        child: CircularProgressIndicator(),
                                      )
                                    : (_state.imageUrl == null
                                          ? Center(
                                              child: Text(
                                                initial.characters.first,
                                                style: TextStyle(
                                                  fontSize: 40,
                                                  fontWeight: FontWeight.w700,
                                                  color: context
                                                      .colors
                                                      .primaryDark,
                                                ),
                                              ),
                                            )
                                          : null),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: _state.uploading ? null : _pickImage,
                              icon: const Icon(
                                Icons.camera_alt_outlined,
                                size: 16,
                              ),
                              label: const Text('사진 변경'),
                            ),
                            const SizedBox(height: 16),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '닉네임',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: context.colors.textPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _nickCtrl,
                              onChanged: _onNickChanged,
                              decoration: InputDecoration(
                                hintText: '닉네임',
                                errorText: _state.nickAvailable == false
                                    ? '이미 사용 중인 닉네임이에요'
                                    : null,
                                helperText: _state.nickAvailable == true
                                    ? '사용 가능한 닉네임이에요'
                                    : null,
                                suffixIcon: switch (_state.nickAvailable) {
                                  true => Icon(
                                    Icons.check_circle_rounded,
                                    color: context.colors.success,
                                  ),
                                  false => Icon(
                                    Icons.cancel_rounded,
                                    color: context.colors.danger,
                                  ),
                                  null => null,
                                },
                              ),
                            ),
                            const SizedBox(height: 24),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '활동 지역',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: context.colors.textPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: _verifyRegion,
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: context.colors.border,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.location_on_outlined,
                                      size: 20,
                                      color: context.colors.primaryDark,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _state.verified &&
                                                _state.regionName != null
                                            ? _state.regionName!
                                            : '지역 미인증',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                          color: _state.verified
                                              ? context.colors.textPrimary
                                              : context.colors.textTertiary,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      _state.verified ? '재인증' : 'GPS로 인증',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: context.colors.primaryDark,
                                      ),
                                    ),
                                    Icon(
                                      Icons.chevron_right,
                                      size: 18,
                                      color: context.colors.textTertiary,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                '활동 지역은 현재 위치(GPS)로만 인증돼요.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.colors.textTertiary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 내 활동/활동 범위/관심/설정 — 내정보 탭에서 이동해온 섹션들.
                      if (widget.profile != null) ...[
                        const SizedBox(height: 28),
                        _ActivitySection(
                          profile: widget.profile!,
                          pendingInvites: widget.pendingInvites,
                        ),
                        const SizedBox(height: 12),
                        _ActivityRangeSection(profile: widget.profile!),
                        const SizedBox(height: 12),
                        _InterestSection(profile: widget.profile!),
                        const SizedBox(height: 12),
                        // 개인 화면의 업체 섹션은 등록/전환만 — 업체 정보·사진 관리는
                        // 업체 모드(업체 관리 화면) 전용(0026, 사진 결합 혼란 제거).
                        _BusinessSection(
                          isBizMode: false,
                          onModeChanged: _state.setMode,
                        ),
                        const SizedBox(height: 12),
                        _SettingsSection(profile: widget.profile!),
                      ],
                    ],
                  ),
          ),
        ),
      ),
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
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.colors.border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textSecondary,
                ),
              ),
            ),
            ...items.expand((it) sync* {
              yield _ItemRow(item: it);
              if (it != items.last) {
                yield Divider(
                  height: 1,
                  indent: 56,
                  color: context.colors.border,
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
            Icon(item.icon, size: 20, color: context.colors.primaryDark),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                item.label,
                style: TextStyle(
                  fontSize: 14,
                  color: context.colors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (item.trailing != null)
              Text(
                item.trailing!,
                style: TextStyle(
                  fontSize: 13,
                  color: context.colors.textSecondary,
                ),
              ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: context.colors.textTertiary,
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
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.colors.border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '활동 범위',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              verified
                  ? '${dong ?? '내 동네'} 기준 반경 (5~15km) · 이 범위의 게시글만 보여요'
                  : '동네 인증을 먼저 완료하면 설정할 수 있어요',
              style: TextStyle(
                fontSize: 12,
                color: context.colors.textTertiary,
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
          color: selected ? context.colors.primaryDark : context.colors.surface,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: selected
                ? context.colors.primaryDark
                : context.colors.border,
            width: 0.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected
                ? context.colors.textOnPrimary
                : context.colors.textPrimary,
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
        // '내 게시글' 항목은 제거 — 내정보 탭의 2열 그리드에서 직접 본다.
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
          label: '받은 후기',
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

/// 업체 — 등록 신청·상태 확인·계정 전환 (0025 §7 · 0026 개편).
/// 개인 화면(isBizMode=false): 등록/심사 상태 + 계정 전환만 — 업체 정보·사진은 없음.
/// 업체 관리(isBizMode=true): 업체 정보·대표 사진(→ 업체 화면) + 일반 모드 전환.
class _BusinessSection extends StatefulWidget {
  final bool isBizMode;

  /// 계정 전환 성공 시 새 모드를 부모에 알린다 — 수정 화면이 즉시 얼굴을 바꾼다.
  final ValueChanged<String>? onModeChanged;

  const _BusinessSection({required this.isBizMode, this.onModeChanged});

  @override
  State<_BusinessSection> createState() => _BusinessSectionState();
}

class _BusinessSectionState extends State<_BusinessSection> {
  BusinessProfile? _biz;
  String _mode = 'personal';
  bool _loaded = false;
  bool _switching = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final biz = await BusinessRepository.instance.fetchMine();
    final mode = await BusinessRepository.instance.fetchActiveMode();
    if (!mounted) return;
    setState(() {
      _biz = biz;
      _mode = mode;
      _loaded = true;
    });
  }

  Future<void> _openRegister(BuildContext context) async {
    await Navigator.push(
      context,
      AppPageRoute(builder: (_) => const BusinessRegisterScreen()),
    );
    unawaited(_load()); // 신청/재신청 결과 반영
  }

  /// 일반 ↔ 업체 모드 토글 — 서버(switch_account_mode)가 approved 게이트.
  Future<void> _toggleMode() async {
    if (_switching) return;
    setState(() => _switching = true);
    final target = _mode == 'business' ? 'personal' : 'business';
    final result = await BusinessRepository.instance.switchMode(target);
    if (!mounted) return;
    setState(() {
      _switching = false;
      if (result != null) _mode = result;
    });
    if (result != null) widget.onModeChanged?.call(result);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result == null
              ? '전환에 실패했어요. 잠시 후 다시 시도해주세요'
              : result == 'business'
              ? '업체 모드로 전환했어요 — 프로필에 상호가 표시돼요'
              : '일반 모드로 전환했어요',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final biz = _biz;
    return _SectionCard(
      title: widget.isBizMode ? '업체 관리' : '업체',
      items: [
        if (biz == null)
          _Item(
            icon: Icons.storefront_outlined,
            label: '업체 등록',
            trailing: '사업자 인증',
            onTap: () => _openRegister(context),
          )
        else if (biz.isPending)
          _Item(
            icon: Icons.storefront_outlined,
            label: '업체 등록',
            trailing: '심사중',
            onTap: () => _openRegister(context),
          )
        else if (biz.isRejected)
          _Item(
            icon: Icons.storefront_outlined,
            label: '업체 등록',
            trailing: '반려됨 · 재신청',
            onTap: () => _openRegister(context),
          )
        else
          // 승인 후: 업체 정보·사진 수정은 업체 관리 패널(업체 모드 최상단)이
          // 담당 — 섹션에는 전환만 남긴다(0026, 수정 경로 단일화).
          _Item(
            icon: Icons.swap_horiz,
            label: '계정 전환',
            trailing: _mode == 'business' ? '일반 모드로' : '업체 모드로',
            onTap: _toggleMode,
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
          icon: Icons.dark_mode_outlined,
          label: '화면 테마',
          trailing: ThemeController.label(ThemeController.mode.value),
          onTap: () => _showThemePicker(context),
        ),
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

  /// 화면 테마 선택 — 시스템/라이트/다크. 선택 즉시 반영·저장.
  void _showThemePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '화면 테마',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
            ),
            for (final m in ThemeMode.values)
              ListTile(
                leading: Icon(switch (m) {
                  ThemeMode.system => Icons.brightness_auto_outlined,
                  ThemeMode.light => Icons.light_mode_outlined,
                  ThemeMode.dark => Icons.dark_mode_outlined,
                }, color: context.colors.textSecondary),
                title: Text(
                  ThemeController.label(m),
                  style: TextStyle(
                    fontSize: 15,
                    color: context.colors.textPrimary,
                  ),
                ),
                trailing: ThemeController.mode.value == m
                    ? Icon(Icons.check, color: context.colors.primary)
                    : null,
                onTap: () {
                  ThemeController.set(m);
                  Navigator.pop(sheetCtx);
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  /// 약관·정책 전문 조회 — 가입 때 동의한 문서를 언제든 다시 볼 수 있게.
  void _showTerms(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '약관 및 정책',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
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
                leading: Icon(
                  Icons.article_outlined,
                  color: context.colors.textSecondary,
                ),
                title: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    color: context.colors.textPrimary,
                  ),
                ),
                trailing: Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: context.colors.textTertiary,
                ),
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
            style: TextButton.styleFrom(foregroundColor: context.colors.danger),
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
