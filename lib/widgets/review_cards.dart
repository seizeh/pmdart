import 'package:flutter/material.dart';

import '../theme/app_palette.dart';

/// 후기 카드 그리드 — 사진+평점 타일(2열), 탭하면 상세 시트.
/// 지도 시설 상세·업체 프로필(내정보/타사용자)의 후기 표시 공용 언어.
class ReviewCardData {
  final String author;
  final int rating; // 1~5
  final String? content;
  final DateTime? createdAt;
  final List<String> photoUrls;
  final bool isMine;
  const ReviewCardData({
    required this.author,
    required this.rating,
    this.content,
    this.createdAt,
    this.photoUrls = const [],
    this.isMine = false,
  });
}

class ReviewCardGrid extends StatelessWidget {
  final List<ReviewCardData> reviews;
  const ReviewCardGrid({super.key, required this.reviews});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: reviews.length,
      itemBuilder: (context, i) => _ReviewCard(review: reviews[i]),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final ReviewCardData review;
  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    final photo = review.photoUrls.isNotEmpty ? review.photoUrls.first : null;
    return InkWell(
      onTap: () => _openDetail(context),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.colors.border, width: 0.5),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (photo != null)
              Image.network(
                photo,
                fit: BoxFit.cover,
                cacheWidth: 600,
                errorBuilder: (_, _, _) =>
                    ColoredBox(color: context.colors.surfaceMuted),
              )
            else
              // 사진 없는 후기 — 내용 미리보기로 채운다.
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 34),
                child: Text(
                  (review.content ?? '').isEmpty ? '내용 없는 후기' : review.content!,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.5,
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
            // 사진 위 가독용 스크림(하단).
            if (photo != null)
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 56,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0x66000000)],
                    ),
                  ),
                ),
              ),
            // 하단: 평점(+내 후기 표시).
            Positioned(
              left: 10,
              right: 10,
              bottom: 8,
              child: Row(
                children: [
                  const Icon(
                    Icons.star_rounded,
                    size: 15,
                    color: Color(0xFFFFB300),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '${review.rating}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: photo != null
                          ? Colors.white
                          : context.colors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  if (review.isMine)
                    Text(
                      '내 후기',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: photo != null
                            ? const Color(0xE6FFFFFF)
                            : context.colors.primaryDark,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openDetail(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    review.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: context.colors.textPrimary,
                    ),
                  ),
                ),
                if (review.createdAt != null)
                  Text(
                    '${review.createdAt!.year}.${review.createdAt!.month}.${review.createdAt!.day}',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.colors.textTertiary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (var i = 0; i < 5; i++)
                  Icon(
                    i < review.rating
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 18,
                    color: i < review.rating
                        ? const Color(0xFFFFB300)
                        : context.colors.border,
                  ),
              ],
            ),
            if ((review.content ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                review.content!,
                style: TextStyle(
                  fontSize: 14.5,
                  height: 1.6,
                  color: context.colors.textPrimary,
                ),
              ),
            ],
            for (final url in review.photoUrls) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
