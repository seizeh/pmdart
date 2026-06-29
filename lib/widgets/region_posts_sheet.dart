import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../data/mock_data.dart' show categoryLabel, timeAgo;
import '../models/community.dart';
import '../services/community_repository.dart';
import '../widgets/role_badge.dart' show categoryColor;
import '../screen/post_detail_screen.dart';

/// 동네(행정동) 게시글 목록 콘텐츠 — 지도 위 바텀시트([MapBottomSheet]) 안에 올라간다.
///
/// `MapTab.showSheetOverMap` 이 지도를 스냅샷으로 얼린 뒤 이 콘텐츠를 시트에 올린다.
/// 스냅샷-스왑이라 시트 밑엔 라이브 PlatformView 가 없어 평범한 위젯 트리 → 일반
/// 위젯(Expanded/Spacer 등) 안전(pmdart #28). 폭은 시트가 `Align>SizedBox` 로 고정.
///
/// 시설 상세와 달리 목록은 한 화면에 여러 개라, 카드 대신 **컴팩트 행**으로 그린다:
/// 사진은 작은 썸네일(56)로 축소하고, 통계는 하트/댓글만 간소 표시.
class RegionPostsContent extends StatefulWidget {
  final PostCluster cluster;
  const RegionPostsContent({super.key, required this.cluster});

  @override
  State<RegionPostsContent> createState() => _RegionPostsContentState();
}

class _RegionPostsContentState extends State<RegionPostsContent> {
  List<Post>? _posts;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await CommunityRepository.instance
          .fetchPostsByIds(widget.cluster.postIds);
      if (mounted) setState(() => _posts = p);
    } catch (_) {
      if (mounted) setState(() => _posts = const []);
    }
  }

  void _openPost(Post p) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PostDetailScreen(post: p)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final posts = _posts;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text('이 동네 게시글 ${widget.cluster.count}개',
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary)),
        const SizedBox(height: 12),
        if (posts == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
          )
        else if (posts.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text('게시글을 불러오지 못했어요',
                  style: TextStyle(color: AppColors.textTertiary)),
            ),
          )
        else
          for (final p in posts) _PostRow(post: p, onTap: () => _openPost(p)),
      ],
    );
  }
}

/// 컴팩트 게시글 행(목록용) — 좌측 텍스트, 우측 작은 썸네일(있을 때만).
class _PostRow extends StatelessWidget {
  final Post post;
  final VoidCallback onTap;
  const _PostRow({required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = categoryColor(post.category);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(categoryLabel(post.category),
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: color)),
                      ),
                      const SizedBox(width: 6),
                      Text(timeAgo(post.createdAt),
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textTertiary)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(post.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 3),
                  Text(post.content,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          height: 1.4)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.favorite_border,
                          size: 14, color: AppColors.textTertiary),
                      const SizedBox(width: 3),
                      Text('${post.heartCount}',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                      const SizedBox(width: 12),
                      const Icon(Icons.chat_bubble_outline,
                          size: 14, color: AppColors.textTertiary),
                      const SizedBox(width: 3),
                      Text('${post.commentCount}',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                ],
              ),
            ),
            if (post.imageUrl != null) ...[
              const SizedBox(width: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  post.imageUrl!,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox(
                    width: 56,
                    height: 56,
                    child: ColoredBox(color: AppColors.surfaceMuted),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
