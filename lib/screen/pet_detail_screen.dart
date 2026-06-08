import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../data/mock_data.dart';
import '../widgets/role_badge.dart';

/// 펫 상세 — 보호자 목록을 핵심 섹션으로 노출.
/// owner 인 경우 펫 정보 수정·삭제·분양·보호자 초대/제거 액션이 보이고,
/// co_guardian 인 경우는 조회만.
class PetDetailScreen extends StatelessWidget {
  final MockPet pet;
  const PetDetailScreen({super.key, required this.pet});

  @override
  Widget build(BuildContext context) {
    final isOwner = pet.role == 'owner';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: AppColors.background,
            elevation: 0,
            pinned: true,
            actions: [
              if (isOwner)
                IconButton(
                  icon: const Icon(Icons.more_horiz),
                  onPressed: () => _showOwnerMenu(context),
                ),
            ],
          ),
          SliverToBoxAdapter(
            child: _Header(pet: pet),
          ),
          SliverToBoxAdapter(
            child: _GuardiansSection(pet: pet, isOwner: isOwner),
          ),
          SliverToBoxAdapter(
            child: _ActionSection(pet: pet, isOwner: isOwner),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  void _showOwnerMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            const SizedBox(height: 12),
            _menu(Icons.edit_outlined, '펫 정보 수정'),
            _menu(Icons.send_outlined, '분양 게시글 작성'),
            _menu(Icons.swap_horiz, '소유권 이전'),
            _menu(Icons.delete_outline, '펫 삭제', color: AppColors.danger),
          ],
        ),
      ),
    );
  }

  Widget _menu(IconData icon, String label, {Color? color}) => ListTile(
    leading: Icon(icon, color: color ?? AppColors.primaryDark),
    title: Text(
      label,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: color ?? AppColors.textPrimary,
      ),
    ),
    onTap: () {},
  );
}

class _Header extends StatelessWidget {
  final MockPet pet;
  const _Header({required this.pet});

  @override
  Widget build(BuildContext context) {
    final age = pet.birthDate == null
        ? ''
        : '${DateTime.now().year - pet.birthDate!.year}살';
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(48),
              ),
              child: const Icon(Icons.pets,
                  color: AppColors.primaryDark, size: 64),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  pet.name,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              RoleBadge(role: pet.role),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            [pet.species, if (age.isNotEmpty) age, if (pet.gender == 'male') '수컷' else if (pet.gender == 'female') '암컷']
                .join('  ·  '),
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
          if (pet.bio != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border, width: 0.5),
              ),
              child: Text(
                pet.bio!,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GuardiansSection extends StatelessWidget {
  final MockPet pet;
  final bool isOwner;
  const _GuardiansSection({required this.pet, required this.isOwner});

  @override
  Widget build(BuildContext context) {
    // Mock 보호자 목록 — 실제로는 pet_guardians 조회.
    final guardians = [
      _Guardian('주인장', 'owner', isMe: pet.role == 'owner'),
      _Guardian('우진', 'co_guardian', isMe: pet.role == 'co_guardian'),
      if (pet.guardianCount > 2) _Guardian('승주', 'co_guardian'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.group_outlined,
                    color: AppColors.primaryDark, size: 20),
                const SizedBox(width: 8),
                Text(
                  '보호자 ${pet.guardianCount}명',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                if (isOwner)
                  TextButton.icon(
                    onPressed: () => _showInviteSheet(context),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('초대'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ...guardians.map(
                  (g) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: AppColors.primarySoft,
                      child: Text(
                        g.nickname.characters.first,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Row(
                        children: [
                          Text(
                            g.nickname,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          if (g.isMe) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primarySoft,
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: const Text(
                                '나',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primaryDark,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    RoleBadge(role: g.role, compact: true),
                    if (isOwner && !g.isMe && g.role != 'owner') ...[
                      const SizedBox(width: 6),
                      IconButton(
                        icon: const Icon(Icons.close,
                            size: 18, color: AppColors.textTertiary),
                        onPressed: () {},
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showInviteSheet(BuildContext context) {
    final phoneCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '공동보호자 초대',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '전화번호로 초대장을 보내드려요.\n상대가 수락하면 보호자로 자동 등록됩니다.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                hintText: '01012345678',
                prefixIcon: Icon(Icons.phone_outlined,
                    color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('초대를 보냈습니다'),
                      behavior: SnackBarBehavior.floating),
                );
              },
              child: const Text('초대 보내기'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Guardian {
  final String nickname;
  final String role;
  final bool isMe;
  const _Guardian(this.nickname, this.role, {this.isMe = false});
}

class _ActionSection extends StatelessWidget {
  final MockPet pet;
  final bool isOwner;
  const _ActionSection({required this.pet, required this.isOwner});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!isOwner)
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      color: AppColors.warning, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '소유자 ${pet.ownerName}님이 이 펫의 정보 수정·분양·삭제 권한을 가집니다',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textPrimary,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.directions_walk),
            label: Text('${pet.name}와(과) 산책 글 쓰기'),
          ),
        ],
      ),
    );
  }
}