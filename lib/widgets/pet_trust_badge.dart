import 'package:flutter/material.dart';
import '../theme/app_palette.dart';

/// 개체 인증 신뢰도 배지 (0019).
/// 검증 카테고리 게시글에서 등록 펫과 개체가 일치한 누적 횟수([matchCount])로 단계를 보여준다.
/// matchCount 가 0이면 아무것도 그리지 않는다(인증 이력 없음).
class PetTrustBadge extends StatelessWidget {
  final int matchCount;
  final bool compact;

  const PetTrustBadge({
    super.key,
    required this.matchCount,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (matchCount <= 0) return const SizedBox.shrink();

    // 단계: 1‑2 입문 / 3‑9 신뢰 / 10+ 우수
    final (label, color) = matchCount >= 10
        ? ('개체 인증 우수', context.colors.primary)
        : matchCount >= 3
        ? ('개체 인증', context.colors.primaryDark)
        : ('개체 인증', context.colors.info);

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
          Icon(Icons.verified, size: compact ? 11 : 13, color: color),
          SizedBox(width: compact ? 3 : 4),
          Text(
            '$label · $matchCount',
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
