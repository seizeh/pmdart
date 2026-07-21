import 'package:flutter/material.dart';

import '../models/pet.dart';
import '../theme/app_palette.dart';
import 'role_badge.dart';

/// 반려동물 카드 — 내정보 탭의 펫 목록에 사용.
class PetCard extends StatelessWidget {
  final Pet pet;
  final VoidCallback onTap;

  const PetCard({super.key, required this.pet, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final age = pet.birthDate == null
        ? null
        : '${DateTime.now().year - pet.birthDate!.year}살';
    final subtitle = age == null ? pet.species : '${pet.species}  ·  $age';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.colors.border, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: context.colors.primarySoft,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                Icons.pets,
                color: context.colors.primaryDark,
                size: 26,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pet.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            RoleBadge(role: pet.role, compact: true),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: context.colors.textTertiary,
            ),
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
          color: context.colors.surfaceMuted,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.colors.border, width: 1),
        ),
        child: Column(
          children: [
            Icon(
              Icons.add_circle_outline,
              color: context.colors.primaryDark,
              size: 28,
            ),
            SizedBox(height: 8),
            Text(
              '반려동물을 등록해보세요',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
