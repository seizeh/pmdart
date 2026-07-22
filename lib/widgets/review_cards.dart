import 'package:flutter/material.dart';

import '../models/facility_review.dart';
import '../motion/motion.dart';
import '../screen/review_detail_screen.dart';
import '../theme/app_palette.dart';
import 'blob_background.dart';

/// 후기 카드 그리드 — 사진+평점 타일(2열), 탭하면 상세 화면(게시글 상세 문법).
/// 지도 시설 상세·업체 프로필(내정보/타사용자)의 후기 표시 공용 언어.
class ReviewCardData {
  final String author;
  final int rating; // 1~5
  final String? content;
  final DateTime? createdAt;
  final List<String> photoUrls;
  final bool isMine;

  /// 같은 사용자의 몇 번째 방문 후기인지(1부터) — 복수 후기 순번 표시.
  final int? visitNo;

  /// 업체 혜택(할인·사은품)을 받고 작성 — 표시광고법 표시 의무(0028 §6).
  final bool hasIncentive;

  /// 사진 없는 카드의 블롭 배경 시드 — 후기마다 다른 패턴, 같은 후기는 항상 동일.
  final Object? seed;

  /// 내 후기 삭제(상세 화면 우상단 버튼) — 삭제 API 호출과 목록 갱신은 제공자가
  /// 담당하고, 성공 여부를 돌려준다. null 이면 삭제 버튼이 없다(타인 후기 등).
  final Future<bool> Function()? onDelete;

  /// 후기 id(facility_reviews) — 있으면 상세 화면에 댓글 섹션이 붙는다.
  final String? reviewId;

  /// 작성자 user id — 있으면 상세에서 닉네임 탭 → 프로필(개인 얼굴)로 이동.
  final String? authorUserId;

  const ReviewCardData({
    required this.author,
    required this.rating,
    this.content,
    this.createdAt,
    this.photoUrls = const [],
    this.isMine = false,
    this.visitNo,
    this.hasIncentive = false,
    this.seed,
    this.onDelete,
    this.reviewId,
    this.authorUserId,
  });

  /// FacilityReview → 카드 데이터 (알림 딥링크 등 목록 밖 진입용).
  factory ReviewCardData.fromFacilityReview(
    FacilityReview r, {
    Future<bool> Function()? onDelete,
  }) => ReviewCardData(
    author: r.authorNickname,
    rating: r.rating,
    content: r.content,
    createdAt: r.createdAt,
    photoUrls: r.photoUrls,
    isMine: r.isMine,
    visitNo: r.visitNo,
    hasIncentive: r.hasIncentive,
    seed: r.id,
    reviewId: r.id,
    authorUserId: r.userId,
    onDelete: onDelete,
  );
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

/// 카드 모서리 소형 배지(방문 차수·업체 혜택 공용) — 사진 위에선 스크림 톤.
Widget _cornerBadge(
  BuildContext context,
  String label, {
  required bool onPhoto,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: onPhoto ? const Color(0x66000000) : context.colors.surfaceMuted,
      borderRadius: BorderRadius.circular(100),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        color: onPhoto ? Colors.white : context.colors.textSecondary,
      ),
    ),
  );
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
            else ...[
              // 사진 없는 후기 — 게시글과 동일하게 랜덤 블롭 배경(후기별 고정 패턴)
              // 위에 본문을 히어로로 올린다.
              Positioned.fill(
                child: BlobBackground(
                  seed:
                      review.seed ??
                      '${review.author}/${review.createdAt?.millisecondsSinceEpoch}',
                  color: context.colors.primary,
                ),
              ),
              // 사진 없는 게시글 카드와 동일 문법 — 하단 평점 구간을 제외한
              // 영역의 정중앙에 본문을 크게(카드 폭에 맞춰 축소한 스케일).
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 16, 14, 40),
                  child: Center(
                    child: Text(
                      (review.content ?? '').isEmpty
                          ? '내용 없는 후기'
                          : review.content!,
                      textAlign: TextAlign.center,
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.colors.textPrimary,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            ],
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
            // 상단 좌측: 방문 차수 배지 — 재방문 후기임이 한눈에 보이게.
            // 대가성 후기(표시광고법)는 '업체 혜택' 배지가 항상 같이 붙는다.
            if (review.visitNo != null || review.hasIncentive)
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    if (review.visitNo != null)
                      _cornerBadge(
                        context,
                        '${review.visitNo}번째 방문',
                        onPhoto: photo != null,
                      ),
                    if (review.hasIncentive)
                      _cornerBadge(context, '업체 혜택', onPhoto: photo != null),
                  ],
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

  /// 카드 자리에서 펼쳐지는 상세(게시글 상세와 동일 문법) — 카드 사각형을
  /// 캡처해 CollapseRoute 로 열고, 아래로 당기면 이 카드로 축소되며 닫힌다.
  void _openDetail(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    final rect = (box != null && box.hasSize)
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    final page = ReviewDetailScreen(
      review: review,
      originRect: rect,
      cardBuilder: rect == null ? null : (_) => _ReviewCard(review: review),
    );
    Navigator.push<void>(
      context,
      rect == null
          ? AppPageRoute<void>(builder: (_) => page)
          : CollapseRoute<void>(builder: (_) => page),
    );
  }
}
