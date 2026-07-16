import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/community.dart' show kPostImageAspectRatio;
import '../motion/motion.dart';
import '../theme/app_palette.dart';
import '../widgets/blob_background.dart';
import '../widgets/review_cards.dart';

/// 시설 방문 후기 상세 — 게시글 상세와 동일한 문법.
///
/// 후기 카드 자리에서 펼쳐지고(originRect), 최상단에서 아래로 당기면 카드로
/// 축소되며 닫힌다(CollapsibleView). 히어로는 사진 후기면 대표 사진,
/// 사진 없는 후기면 카드와 같은 블롭 배경 + 본문(축소 시 카드와 겹쳐 안착).
class ReviewDetailScreen extends StatefulWidget {
  final ReviewCardData review;

  /// 탭한 카드의 화면상 사각형 — 있으면 그 자리에서 펼쳐지고/그 자리로 축소.
  final Rect? originRect;

  /// 축소 안착 시 크로스페이드할 실제 카드(피드의 PostCard 역할).
  final WidgetBuilder? cardBuilder;

  const ReviewDetailScreen({
    super.key,
    required this.review,
    this.originRect,
    this.cardBuilder,
  });

  @override
  State<ReviewDetailScreen> createState() => _ReviewDetailScreenState();
}

class _ReviewDetailScreenState extends State<ReviewDetailScreen> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// 히어로(블롭)에 본문이 다 담겼는지 — 게시글 상세와 같은 기준(9줄·짧은 글).
  bool get _heroHoldsFullContent {
    final c = widget.review.content ?? '';
    return c.length <= 180 && '\n'.allMatches(c).length < 9;
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.review;
    final hasPhoto = r.photoUrls.isNotEmpty;

    // 게시글 상세와 동일 — 테마 밝기 기준 상태바 아이콘 유지, 어두운 사진 위
    // 가독성은 히어로 상단의 밝은 스크림이 담당.
    final overlay = Theme.of(context).brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: CollapsibleView(
        originRect: widget.originRect,
        card: widget.cardBuilder,
        cardRadius: 14, // _ReviewCard 와 동일 곡률
        scrollController: _scroll,
        builder: (context, physics) => Scaffold(
          backgroundColor: context.colors.background,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            // 뒤로가기 버튼 없음 — 아래로 당겨 카드로 축소(게시글 상세와 동일).
            automaticallyImplyLeading: false,
          ),
          body: ListView(
            controller: _scroll,
            physics: physics,
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              AspectRatio(
                aspectRatio: kPostImageAspectRatio,
                child: hasPhoto ? _photoHero(r) : _blobHero(r),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: _infoChildren(r, contentInHero: !hasPhoto),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photoHero(ReviewCardData r) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(
          r.photoUrls.first,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) =>
              ColoredBox(color: context.colors.surfaceMuted),
        ),
        // 상태바 스크림 — 어두운 사진에서도 시간·배터리가 읽히게(게시글과 동일).
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: MediaQuery.paddingOf(context).top + 24,
          child: const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.white70, Colors.transparent],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 사진 없는 후기 — 카드와 같은 블롭 배경 + 본문. 축소 시 카드와 겹쳐진다.
  Widget _blobHero(ReviewCardData r) {
    return Stack(
      fit: StackFit.expand,
      children: [
        BlobBackground(
          seed: r.seed ?? '${r.author}/${r.createdAt?.millisecondsSinceEpoch}',
          color: context.colors.primary,
        ),
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
            child: Center(
              child: Text(
                (r.content ?? '').isEmpty ? '내용 없는 후기' : r.content!,
                textAlign: TextAlign.center,
                maxLines: 9,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: context.colors.textPrimary,
                  height: 1.6,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 본문 정보 위젯들 — 게시글 상세의 칩→제목→작성자→본문 순서를 후기 문법으로:
  /// 방문 차수 칩 → 별점(제목 자리) → 작성자·날짜 → 본문 → 나머지 사진.
  List<Widget> _infoChildren(ReviewCardData r, {required bool contentInHero}) {
    final showContent = (r.content ?? '').isNotEmpty &&
        (!contentInHero || !_heroHoldsFullContent);
    return [
      if (r.visitNo != null || r.isMine)
        Align(
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (r.visitNo != null)
                _chip(
                  '${r.visitNo}번째 방문',
                  fg: context.colors.primaryDark,
                  bg: context.colors.primary.withValues(alpha: 0.12),
                ),
              if (r.visitNo != null && r.isMine) const SizedBox(width: 6),
              if (r.isMine)
                _chip(
                  '내 후기',
                  fg: context.colors.textSecondary,
                  bg: context.colors.surfaceMuted,
                ),
            ],
          ),
        ),
      if (r.visitNo != null || r.isMine) const SizedBox(height: 14),
      // 별점 — 게시글의 제목 자리.
      Row(
        children: [
          for (var i = 0; i < 5; i++)
            Icon(
              i < r.rating ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 26,
              color: i < r.rating
                  ? const Color(0xFFFFB300)
                  : context.colors.border,
            ),
          const SizedBox(width: 8),
          Text(
            '${r.rating}.0',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      // 작성자 행 — 닉네임 + 작성일(팔로우 등은 후기에 없음).
      Row(
        children: [
          Expanded(
            child: Text(
              r.author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
              ),
            ),
          ),
          if (r.createdAt != null)
            Text(
              '${r.createdAt!.year}.${r.createdAt!.month}.${r.createdAt!.day}',
              style: TextStyle(
                fontSize: 12.5,
                color: context.colors.textTertiary,
              ),
            ),
        ],
      ),
      if (showContent) ...[
        const SizedBox(height: 20),
        Divider(height: 1, color: context.colors.border),
        const SizedBox(height: 20),
        Text(
          r.content!,
          style: TextStyle(
            fontSize: 15,
            color: context.colors.textPrimary,
            height: 1.7,
          ),
        ),
      ],
      // 나머지 사진(히어로에 쓴 첫 장 제외) — 본문 아래에 이어서.
      for (final url in r.photoUrls.skip(1)) ...[
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
    ];
  }

  Widget _chip(String label, {required Color fg, required Color bg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}
