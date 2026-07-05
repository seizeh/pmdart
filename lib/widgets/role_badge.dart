import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../data/mock_data.dart';

/// 보호자 역할 배지 — owner / co_guardian 구분.
class RoleBadge extends StatelessWidget {
  final String role;
  final bool compact;

  const RoleBadge({super.key, required this.role, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final isOwner = role == 'owner';
    final label = isOwner ? '소유자' : '공동보호자';
    final color = isOwner ? AppColors.primaryDark : AppColors.info;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isOwner ? Icons.shield_outlined : Icons.group_outlined,
            size: compact ? 11 : 13,
            color: color,
          ),
          SizedBox(width: compact ? 3 : 4),
          Text(
            label,
            style: TextStyle(
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// 게시글 카테고리 선택 칩.
class CategoryChip extends StatelessWidget {
  final String category;
  final bool selected;
  final VoidCallback onTap;

  const CategoryChip({
    super.key,
    required this.category,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          // 선택칩 색은 '전체' 칩과 동일하게 primaryDark 로 통일(카테고리별 색 안 씀).
          // 채우기만 투명(테두리·글씨는 불투명 유지 → 가독성).
          color: selected
              ? AppColors.primaryDark.withValues(alpha: 0.7)
              : Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: selected ? AppColors.primaryDark : AppColors.border,
          ),
        ),
        child: Text(
          categoryLabel(category),
          style: TextStyle(
            color: selected ? AppColors.textOnPrimary : AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// 카테고리별 강조 색상.
Color categoryColor(String category) => switch (category) {
      'walk_together' => AppColors.catWalk,
      'walk_proxy' => AppColors.catWalkProxy,
      'care' => AppColors.catCare,
      'give_away' => AppColors.catGiveAway,
      'adoption' => AppColors.catAdoption,
      'free' => AppColors.catFree,
      _ => AppColors.primary,
    };
