import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../data/mock_data.dart';
import 'role_badge.dart';

/// 반려동물 카드 — 내정보 탭의 펫 목록에 사용.
class PetCard extends StatelessWidget {
  final MockPet pet;
  final VoidCallback onTap;

  const PetCard({super.key, required this.pet, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final age = pet.birthDate == null
        ? null
        : '${DateTime.now().year - pet.birthDate!.year}살';
    final subtitle =
        age == null ? pet.species : '${pet.species}  ·  $age';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.pets,
                  color: AppColors.primaryDark, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pet.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            RoleBadge(role: pet.role, compact: true),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right,
                size: 20, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// 등록된 펫이 없을 때 보여주는 빈 카드.
class EmptyPetCard extends StatelessWidget {
  final VoidCallback onTap;

  const EmptyPetCard({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 28),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.border,
            width: 1,
          ),
        ),
        child: Column(
          children: const [
            Icon(Icons.add_circle_outline,
                color: AppColors.primaryDark, size: 28),
            SizedBox(height: 8),
            Text(
              '반려동물을 등록해보세요',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
