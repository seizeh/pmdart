import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../models/profile.dart';
import '../services/profile_repository.dart';
import '../services/social_repository.dart';
import '../services/chat_launcher.dart';
import '../services/session.dart';
import '../widgets/pet_card.dart';
import 'pet_detail_screen.dart';

/// 타 사용자 공개 프로필 — 사용자 검색/연결 목록에서 진입.
/// 프로필 헤더 + 활동 통계 + 반려동물 + 팔로우/채팅.
class UserProfileScreen extends StatefulWidget {
  final String userId;

  /// 로딩 전 즉시 보여줄 닉네임(선택).
  final String? previewNickname;
  const UserProfileScreen({super.key, required this.userId, this.previewNickname});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  PublicProfileData? _profile;
  bool _loading = true;
  bool _error = false;

  bool _following = false;
  bool _followBusy = false;

  bool get _isMe => widget.userId == SessionManager.instance.user?.id;

  @override
  void initState() {
    super.initState();
    _load();
    if (!_isMe) _loadFollowing();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final p = await ProfileRepository.instance.fetchPublicProfile(widget.userId);
      if (!mounted) return;
      setState(() {
        _profile = p;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  Future<void> _loadFollowing() async {
    try {
      final f = await SocialRepository.instance.isFollowing(widget.userId);
      if (mounted) setState(() => _following = f);
    } catch (_) {}
  }

  Future<void> _toggleFollow() async {
    if (_followBusy) return;
    final was = _following;
    setState(() {
      _followBusy = true;
      _following = !was;
    });
    try {
      if (was) {
        await SocialRepository.instance.unfollow(widget.userId);
      } else {
        await SocialRepository.instance.follow(widget.userId);
      }
    } catch (_) {
      if (mounted) setState(() => _following = was);
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  String _userTypeLabel(String t) => switch (t) {
        'pet_owner' => '반려동물 보호자',
        'no_pet' => '반려동물 미보유',
        'business' => '업체',
        'admin' => '관리자',
        _ => t,
      };

  @override
  Widget build(BuildContext context) {
    final title = _profile?.nickname ?? widget.previewNickname ?? '프로필';
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: Text(title)),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error || _profile == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('프로필을 불러오지 못했어요',
                style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            TextButton(onPressed: _load, child: const Text('다시 시도')),
          ],
        ),
      );
    }

    final p = _profile!;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(p),
          if (!_isMe) ...[
            const SizedBox(height: 16),
            _actions(p),
          ],
          const SizedBox(height: 24),
          _petSection(p),
        ],
      ),
    );
  }

  /// 보유 반려동물들의 개체 일치 누적 합(사용자 단위 신뢰 표시).
  int _petMatchTotal(PublicProfileData p) =>
      p.pets.fold(0, (s, e) => s + e.matchCount);

  Widget _header(PublicProfileData p) {
    final region = p.regionName;
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
                backgroundImage: p.profileImageUrl != null
                    ? NetworkImage(p.profileImageUrl!)
                    : null,
                child: p.profileImageUrl == null
                    ? Text(
                        p.nickname.isEmpty ? '?' : p.nickname.characters.first,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryDark,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.nickname,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textOnPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          _userTypeLabel(p.userType),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFD9CBA8),
                          ),
                        ),
                        if (region != null) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.location_on,
                              size: 12, color: Color(0xFFD9CBA8)),
                          const SizedBox(width: 2),
                          Text(
                            region,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFFD9CBA8),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (_petMatchTotal(p) > 0) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.verified,
                              size: 13, color: Color(0xFFD9CBA8)),
                          const SizedBox(width: 4),
                          Text(
                            '반려동물 개체 인증 ${_petMatchTotal(p)}회',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFD9CBA8),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: _statCol('받은 평가', p.reviewCount)),
              _divider(),
              Expanded(child: _statCol('Pawing', p.pawingCount)),
              _divider(),
              Expanded(child: _statCol('Pawmate', p.pawmateCount)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _divider() =>
      Container(width: 1, height: 32, color: const Color(0x33D9CBA8));

  Widget _statCol(String label, int value) => Column(
        children: [
          Text(
            '$value',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textOnPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(fontSize: 11, color: Color(0xFFD9CBA8))),
        ],
      );

  Widget _actions(PublicProfileData p) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: _toggleFollow,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _following ? AppColors.surface : AppColors.primaryDark,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: _following ? AppColors.border : AppColors.primaryDark,
                  ),
                ),
                child: Text(
                  _following ? 'Pawing 중' : 'Pawing',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _following
                        ? AppColors.textSecondary
                        : AppColors.textOnPrimary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => openDirectChat(context, p.userId),
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              label: const Text('채팅'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _petSection(PublicProfileData p) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '반려동물',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          if (p.pets.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(
                child: Text('등록된 반려동물이 없어요',
                    style:
                        TextStyle(fontSize: 13, color: AppColors.textTertiary)),
              ),
            )
          else
            ...p.pets.map(
              (pet) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: PetCard(
                  pet: pet,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => PetDetailScreen(pet: pet)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
