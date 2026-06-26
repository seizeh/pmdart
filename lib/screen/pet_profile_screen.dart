import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../models/pet_search.dart';
import '../services/pet_repository.dart';
import '../services/chat_launcher.dart';
import '../widgets/pet_trust_badge.dart';

/// 공개 반려동물 프로필 (read-only) — 검색에서 펫을 눌렀을 때 진입.
/// 사용자 프로필이 아니라 반려동물 정보를 보여준다. 보호자 관리 기능은 없다.
class PetProfileScreen extends StatefulWidget {
  final String petId;

  /// 검색 결과에서 받은 최소 정보 (로딩 동안 즉시 헤더 표시용, 선택).
  final PetHit? preview;

  const PetProfileScreen({super.key, required this.petId, this.preview});

  @override
  State<PetProfileScreen> createState() => _PetProfileScreenState();
}

class _PetProfileScreenState extends State<PetProfileScreen> {
  PetProfile? _pet;
  bool _loading = true;
  bool _notFound = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final pet = await PetRepository.instance.fetchPublicPet(widget.petId);
      if (!mounted) return;
      setState(() {
        _pet = pet;
        _notFound = pet == null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _notFound = true;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(_pet?.name ?? preview?.name ?? '반려동물'),
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_notFound || _pet == null) {
      return const Center(
        child: Text('찾을 수 없는 반려동물이에요',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
      );
    }
    final pet = _pet!;
    final age = pet.birthDate == null
        ? ''
        : '${DateTime.now().year - pet.birthDate!.year}살';
    final meta = [
      if (pet.species.isNotEmpty) pet.species,
      if (age.isNotEmpty) age,
      if (pet.gender == 'male') '수컷' else if (pet.gender == 'female') '암컷',
      if (pet.isNeutered) '중성화 완료',
    ].join('  ·  ');

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
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
                ? const Icon(Icons.pets, color: AppColors.primaryDark, size: 64)
                : null,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          pet.name,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        if (pet.matchCount > 0) ...[
          const SizedBox(height: 8),
          PetTrustBadge(matchCount: pet.matchCount),
        ],
        if (meta.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(meta,
              style:
                  const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
        ],
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
                    fontSize: 14, color: AppColors.textPrimary, height: 1.5)),
          ),
        ],
        const SizedBox(height: 24),
        _OwnerRow(pet: pet),
      ],
    );
  }
}

/// 보호자(소유자) 한 줄 + 채팅 버튼.
class _OwnerRow extends StatelessWidget {
  final PetProfile pet;
  const _OwnerRow({required this.pet});

  @override
  Widget build(BuildContext context) {
    final name = pet.ownerNickname.isEmpty ? '알 수 없음' : pet.ownerNickname;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.primarySoft,
            child: Text(
              name.characters.first,
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryDark),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('보호자',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textTertiary)),
                const SizedBox(height: 2),
                Text(name,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ],
            ),
          ),
          if (pet.ownerId.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.chat_bubble_outline,
                  color: AppColors.primaryDark),
              tooltip: '보호자에게 채팅',
              onPressed: () => openDirectChat(context, pet.ownerId),
            ),
        ],
      ),
    );
  }
}
