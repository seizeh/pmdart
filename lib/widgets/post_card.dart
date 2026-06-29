import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../data/mock_data.dart' show categoryLabel, timeAgo;
import '../models/community.dart';
import '../motion/pressable.dart';
import '../motion/heart_burst.dart';
import 'role_badge.dart';

/// 커뮤니티 게시글 카드.
class PostCard extends StatelessWidget {
  final Post post;
  final VoidCallback? onTap;
  final VoidCallback? onHeart;

  const PostCard({super.key, required this.post, this.onTap, this.onHeart});

  @override
  Widget build(BuildContext context) {
    final color = categoryColor(post.category);

    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
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
                _CategoryTag(category: post.category, color: color),
                // 작성자 활동지역(동 단위) — 카테고리 옆에 표시
                if (post.location != null && post.location!.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Flexible(
                      child: _DongTag(
                          label: post.location!, moved: post.authorMoved)),
                ],
                const Spacer(),
                Text(
                  timeAgo(post.createdAt),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              post.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              post.content,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            if (post.imageUrl != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AspectRatio(
                  aspectRatio: kPostImageAspectRatio, // 4284 : 5712
                  child: Image.network(
                    post.imageUrl!,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const ColoredBox(color: AppColors.surfaceMuted),
                  ),
                ),
              ),
            ],
            if (post.scheduledAt != null) ...[
              const SizedBox(height: 10),
              _MetaPill(
                icon: Icons.event_outlined,
                label:
                    '${post.scheduledAt!.month}/${post.scheduledAt!.day} ${post.scheduledAt!.hour}시',
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: AppColors.primarySoft,
                  child: Text(
                    post.authorNickname.characters.first,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryDark,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  post.authorNickname,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const Spacer(),
                HeartButton(
                  active: post.hearted,
                  count: post.heartCount,
                  onTap: onHeart,
                ),
                const SizedBox(width: 14),
                _Stat(
                  icon: Icons.chat_bubble_outline,
                  value: post.commentCount,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(width: 14),
                _Stat(
                  icon: Icons.visibility_outlined,
                  value: post.viewCount,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryTag extends StatelessWidget {
  final String category;
  final Color color;
  const _CategoryTag({required this.category, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        categoryLabel(category),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// 작성자 활동지역(동 단위) 태그 — 카테고리 옆.
/// [moved] = 작성자가 현재 다른 지역에 있음(작성 당시 동과 다름) → 경고색 + 아이콘.
class _DongTag extends StatelessWidget {
  final String label;
  final bool moved;
  const _DongTag({required this.label, this.moved = false});

  @override
  Widget build(BuildContext context) {
    final color = moved ? AppColors.warning : AppColors.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(moved ? Icons.info_outline : Icons.place_outlined,
            size: 13, color: moved ? AppColors.warning : AppColors.textTertiary),
        const SizedBox(width: 2),
        Flexible(
          child: Text(
            moved ? '$label·이동' : label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _MetaPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetaPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final int value;
  final Color color;
  const _Stat({
    required this.icon,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          '$value',
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
