import 'package:flutter/material.dart';
import '../motion/motion.dart';
import '../theme/app_colors.dart';
import '../data/mock_data.dart' show MockPet;
import '../services/pet_repository.dart';
import '../widgets/role_badge.dart';
import '../widgets/pet_trust_badge.dart';
import 'pet_edit_screen.dart';

/// 펫 상세 — 펫 정보 + 보호자 목록(실데이터). owner 는 수정/삭제/초대 가능.
class PetDetailScreen extends StatefulWidget {
  final MockPet pet;
  const PetDetailScreen({super.key, required this.pet});

  @override
  State<PetDetailScreen> createState() => _PetDetailScreenState();
}

class _PetDetailScreenState extends State<PetDetailScreen> {
  final _repo = PetRepository.instance;
  late MockPet _pet;
  List<Guardian> _guardians = [];
  bool _loading = true;

  bool get _isOwner => _pet.role == 'owner';

  @override
  void initState() {
    super.initState();
    _pet = widget.pet;
    _loadGuardians();
  }

  Future<void> _loadGuardians() async {
    try {
      final list = await _repo.fetchGuardians(_pet.id);
      if (mounted) {
        setState(() {
          _guardians = list;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reloadPet() async {
    final fresh = await _repo.fetchPet(_pet.id);
    if (!mounted) return;
    if (fresh == null) {
      Navigator.pop(context); // 삭제됨
      return;
    }
    setState(() => _pet = fresh);
    _loadGuardians();
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            pinned: true,
            actions: [
              if (_isOwner)
                IconButton(
                  icon: const Icon(Icons.more_horiz),
                  onPressed: _showOwnerMenu,
                ),
            ],
          ),
          SliverToBoxAdapter(child: _Header(pet: _pet)),
          SliverToBoxAdapter(
            child: _GuardiansSection(
              pet: _pet,
              guardians: _guardians,
              loading: _loading,
              isOwner: _isOwner,
              onInvite: _showInviteSheet,
              onRemove: _removeGuardian,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  void _showOwnerMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
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
            ListTile(
              leading: const Icon(Icons.edit_outlined,
                  color: AppColors.primaryDark),
              title: const Text('펫 정보 수정'),
              onTap: () async {
                Navigator.pop(sheetCtx);
                final changed = await Navigator.push<bool>(
                  context,
                  AppPageRoute(
                      builder: (_) => PetEditScreen(pet: _pet)),
                );
                if (changed == true) _reloadPet();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline,
                  color: AppColors.danger),
              title: const Text('펫 삭제',
                  style: TextStyle(color: AppColors.danger)),
              onTap: () {
                Navigator.pop(sheetCtx);
                _confirmDelete();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('펫 삭제'),
        content: Text('${_pet.name}을(를) 삭제할까요? 되돌릴 수 없어요.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: const Text('취소')),
          TextButton(
            onPressed: () async {
              Navigator.pop(dCtx);
              try {
                await _repo.deletePet(_pet.id);
                if (!mounted) return;
                Navigator.pop(context);
                _toast('삭제했어요');
              } catch (_) {
                _toast('삭제에 실패했어요');
              }
            },
            child: const Text('삭제', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  Future<void> _removeGuardian(Guardian g) async {
    try {
      await _repo.removeGuardian(_pet.id, g.userId);
      _loadGuardians();
    } catch (_) {
      _toast('보호자 제거에 실패했어요');
    }
  }

  void _showInviteSheet() {
    final phoneCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 20,
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 24),
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
            const Text('공동보호자 초대',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            const Text(
              '전화번호로 초대장을 보내드려요.\n상대가 수락하면 보호자로 등록됩니다.',
              style: TextStyle(
                  fontSize: 13, color: AppColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                hintText: '01012345678',
                prefixIcon:
                    Icon(Icons.phone_outlined, color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                final phone = phoneCtrl.text.replaceAll(RegExp(r'[^\d]'), '');
                if (phone.length < 10) {
                  _toast('전화번호를 확인해주세요');
                  return;
                }
                Navigator.pop(sheetCtx);
                try {
                  await _repo.invite(_pet.id, phone);
                  _toast('초대를 보냈어요');
                } catch (_) {
                  _toast('초대에 실패했어요');
                }
              },
              child: const Text('초대 보내기'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final MockPet pet;
  const _Header({required this.pet});

  @override
  Widget build(BuildContext context) {
    final age = pet.birthDate == null
        ? ''
        : '${DateTime.now().year - pet.birthDate!.year}살';
    final meta = [
      pet.species,
      if (age.isNotEmpty) age,
      if (pet.gender == 'male') '수컷' else if (pet.gender == 'female') '암컷',
    ].join('  ·  ');

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
                image: pet.imageUrl != null
                    ? DecorationImage(
                        image: NetworkImage(pet.imageUrl!), fit: BoxFit.cover)
                    : null,
              ),
              child: pet.imageUrl == null
                  ? const Icon(Icons.pets,
                      color: AppColors.primaryDark, size: 64)
                  : null,
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
          if (pet.matchCount > 0) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: PetTrustBadge(matchCount: pet.matchCount),
            ),
          ],
          const SizedBox(height: 6),
          Text(meta,
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textSecondary)),
          if (pet.bio != null && pet.bio!.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border, width: 0.5),
              ),
              child: Text(pet.bio!,
                  style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                      height: 1.5)),
            ),
          ],
        ],
      ),
    );
  }
}

class _GuardiansSection extends StatelessWidget {
  final MockPet pet;
  final List<Guardian> guardians;
  final bool loading;
  final bool isOwner;
  final VoidCallback onInvite;
  final Future<void> Function(Guardian) onRemove;

  const _GuardiansSection({
    required this.pet,
    required this.guardians,
    required this.loading,
    required this.isOwner,
    required this.onInvite,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
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
                  '보호자 ${loading ? '' : '${guardians.length}명'}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                if (isOwner)
                  TextButton.icon(
                    onPressed: onInvite,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('초대'),
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              ...guardians.map((g) => _guardianRow(context, g)),
          ],
        ),
      ),
    );
  }

  Widget _guardianRow(BuildContext context, Guardian g) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primarySoft,
            child: Text(
              g.nickname.isEmpty ? '?' : g.nickname.characters.first,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryDark),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: [
                Text(g.nickname,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                if (g.isMe) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primarySoft,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: const Text('나',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryDark)),
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
              onPressed: () => onRemove(g),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ],
      ),
    );
  }
}
