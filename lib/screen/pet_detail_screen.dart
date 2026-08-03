import 'dart:async';
import 'package:flutter/material.dart';

import '../models/pet.dart';
import '../motion/motion.dart';
import '../services/pet_repository.dart';
import '../theme/app_palette.dart';
import '../widgets/pet_trust_badge.dart';
import '../widgets/role_badge.dart';
import 'pet_edit_screen.dart';
import 'vaccination_schedule_screen.dart';

/// 펫 상세 — 펫 정보 + 보호자 목록(실데이터). owner 는 수정/삭제/초대 가능.
/// [originRect] 가 있으면 카드에서 펼쳐지고/당기면 그 자리로 축소된다
/// (게시글 상세와 동일한 전환 언어).
class PetDetailScreen extends StatefulWidget {
  final Pet pet;

  /// 카드에서 펼쳐지는 전환용. null 이면 일반 화면.
  final Rect? originRect;

  /// 축소 시 크로스페이드로 나타날 원본 카드(내정보 펫 히어로와 동일 위젯).
  final WidgetBuilder? cardBuilder;

  /// 원본 카드의 모서리 곡률 — 축소 안착 시 곡률이 튀지 않도록 카드와 맞춘다.
  final double cardRadius;

  const PetDetailScreen({
    super.key,
    required this.pet,
    this.originRect,
    this.cardBuilder,
    this.cardRadius = 24,
  });

  @override
  State<PetDetailScreen> createState() => _PetDetailScreenState();
}

class _PetDetailScreenState extends State<PetDetailScreen> {
  final _repo = PetRepository.instance;
  late Pet _pet;
  List<Guardian> _guardians = [];
  bool _loading = true;

  // CollapsibleView(당겨서 축소) 용 스크롤 컨트롤러.
  final _scroll = ScrollController();

  bool get _isOwner => _pet.role == 'owner';

  @override
  void initState() {
    super.initState();
    _pet = widget.pet;
    _loadGuardians();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
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
    unawaited(_loadGuardians());
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 카드에서 펼쳐지고/아래로 당기면 카드로 축소되는 공통 래퍼(게시글 상세와 동일).
    return CollapsibleView(
      originRect: widget.originRect,
      card: widget.cardBuilder,
      cardRadius: widget.cardRadius,
      scrollController: _scroll,
      builder: (context, physics) => Scaffold(
        backgroundColor: context.colors.background,
        body: CustomScrollView(
          controller: _scroll,
          physics: physics, // 드래그 중 잠금은 CollapsibleView 가 제공
          slivers: [
            SliverAppBar(
              backgroundColor: context.colors.background,
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
            SliverToBoxAdapter(child: _vaccinationEntry()),
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
      ),
    );
  }

  /// 접종 일정 진입(0028 P3 분양 스타터) — 보호자 섹션과 같은 카드 언어.
  Widget _vaccinationEntry() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      child: Pressable(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          Navigator.push(
            context,
            AppPageRoute(
              builder: (_) => VaccinationScheduleScreen(
                petId: _pet.id,
                petName: _pet.name,
                birthDate: _pet.birthDate,
                speciesKind: _pet.speciesKind,
                source: 'manage',
              ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: context.colors.border, width: 0.5),
          ),
          child: Row(
            children: [
              Icon(
                Icons.vaccines_outlined,
                color: context.colors.primaryDark,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '접종 일정',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: context.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '표준 접종 일정을 등록하면 전날·당일 아침에 알려드려요',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: context.colors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showOwnerMenu() {
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
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.colors.border,
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: Icon(
                Icons.edit_outlined,
                color: context.colors.primaryDark,
              ),
              title: const Text('펫 정보 수정'),
              onTap: () async {
                Navigator.pop(sheetCtx);
                final changed = await Navigator.push<bool>(
                  context,
                  AppPageRoute(builder: (_) => PetEditScreen(pet: _pet)),
                );
                if (changed == true) unawaited(_reloadPet());
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: context.colors.danger),
              title: Text(
                '펫 삭제',
                style: TextStyle(color: context.colors.danger),
              ),
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
            child: const Text('취소'),
          ),
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
            child: Text('삭제', style: TextStyle(color: context.colors.danger)),
          ),
        ],
      ),
    );
  }

  Future<void> _removeGuardian(Guardian g) async {
    try {
      await _repo.removeGuardian(_pet.id, g.userId);
      unawaited(_loadGuardians());
    } catch (_) {
      _toast('보호자 제거에 실패했어요');
    }
  }

  void _showInviteSheet() {
    final phoneCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 20,
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.colors.border,
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '공동보호자 초대',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '전화번호로 초대장을 보내드려요.\n상대가 수락하면 보호자로 등록됩니다.',
              style: TextStyle(
                fontSize: 13,
                color: context.colors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                hintText: '01012345678',
                prefixIcon: Icon(
                  Icons.phone_outlined,
                  color: context.colors.textSecondary,
                ),
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
                  final registered = await _repo.invite(_pet.id, phone);
                  _toast(
                    registered ? '초대를 보냈어요' : '가입 전 번호예요 — 문자로 초대 안내를 보냈어요',
                  );
                } on StateError catch (e) {
                  _toast(
                    e.message == 'self_invite'
                        ? '본인 번호로는 초대할 수 없어요'
                        : '이미 초대 중인 번호예요',
                  );
                } catch (_) {
                  _toast('초대에 실패했어요');
                }
              },
              child: const Text('초대 보내기'),
            ),
          ],
        ),
      ),
      // 시트가 닫히면(전환 마무리 뒤) 컨트롤러 해제(#239 — 반복 열기 누수).
    ).whenComplete(
      () => Future.delayed(const Duration(seconds: 1), phoneCtrl.dispose),
    );
  }
}

class _Header extends StatelessWidget {
  final Pet pet;
  const _Header({required this.pet});

  @override
  Widget build(BuildContext context) {
    final age = pet.birthDate == null
        ? ''
        : '${DateTime.now().year - pet.birthDate!.year}살';
    final meta = [
      pet.species,
      if (age.isNotEmpty) age,
      if (pet.gender == 'male') '남아' else if (pet.gender == 'female') '여아',
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
                color: context.colors.primarySoft,
                borderRadius: BorderRadius.circular(48),
                image: pet.imageUrl != null
                    ? DecorationImage(
                        image: NetworkImage(pet.imageUrl!),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: pet.imageUrl == null
                  ? Icon(
                      Icons.pets,
                      color: context.colors.primaryDark,
                      size: 64,
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  pet.name,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
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
          Text(
            meta,
            style: TextStyle(fontSize: 14, color: context.colors.textSecondary),
          ),
          if (pet.bio != null && pet.bio!.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              width: double.infinity,
              decoration: BoxDecoration(
                color: context.colors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.colors.border, width: 0.5),
              ),
              child: Text(
                pet.bio!,
                style: TextStyle(
                  fontSize: 14,
                  color: context.colors.textPrimary,
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
  final Pet pet;
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
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: context.colors.border, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.group_outlined,
                  color: context.colors.primaryDark,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  '보호자 ${loading ? '' : '${guardians.length}명'}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
                  ),
                ),
                const Spacer(),
                if (isOwner)
                  TextButton.icon(
                    onPressed: onInvite,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('초대'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
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
            backgroundColor: context.colors.primarySoft,
            child: Text(
              g.nickname.isEmpty ? '?' : g.nickname.characters.first,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: context.colors.primaryDark,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              children: [
                Text(
                  g.nickname,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textPrimary,
                  ),
                ),
                if (g.isMe) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: context.colors.primarySoft,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      '나',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: context.colors.primaryDark,
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
              icon: Icon(
                Icons.close,
                size: 18,
                color: context.colors.textTertiary,
              ),
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
