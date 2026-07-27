import 'dart:async';

import 'package:flutter/material.dart';

import 'app_motion.dart';

/// 카드가 목록의 제 자리를 떠나 다른 자리로 **날아가는** 오버레이 애니메이션.
///
/// 왜 오버레이인가 — 출발지(피드)와 도착지(상세 패널)가 서로 다른 박스라 어느 한쪽
/// 안에서 그리면 경계에서 잘린다. 도착지의 Navigator 를 피드까지 넓히면 잘리지는
/// 않지만, 이번엔 라우트의 **모달 배리어가 피드 전체를 덮어** 카드를 누를 수 없게
/// 된다. 그래서 이동 구간만 창 전체를 덮는 루트 오버레이에서 그리고, 포인터는
/// 통과시킨다.
///
/// [from]·[to] 는 **오버레이(=루트 Navigator) 좌표**다. 화면 좌표로 잡은
/// 사각형이라면 `toRouteRect` 로 변환해 넘긴다 — 셸이 본문을 옮겨 놓았기 때문이다.
///
/// 반환되는 Future 는 카드가 도착해 오버레이에서 사라진 뒤 완료된다.
Future<void> flyCard({
  required BuildContext context,
  required Rect from,
  required Rect to,
  required WidgetBuilder card,
  Duration duration = MotionDurations.base,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return Future<void>.value();

  final done = Completer<void>();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _FlyingCard(
      from: from,
      to: to,
      card: card,
      duration: duration,
      onArrived: () {
        entry.remove();
        if (!done.isCompleted) done.complete();
      },
    ),
  );
  overlay.insert(entry);
  return done.future;
}

class _FlyingCard extends StatefulWidget {
  const _FlyingCard({
    required this.from,
    required this.to,
    required this.card,
    required this.duration,
    required this.onArrived,
  });

  final Rect from;
  final Rect to;
  final WidgetBuilder card;
  final Duration duration;
  final VoidCallback onArrived;

  @override
  State<_FlyingCard> createState() => _FlyingCardState();
}

class _FlyingCardState extends State<_FlyingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((s) {
      // 도착 통보는 프레임 밖에서 — 리스너는 애니메이션 틱 중에 불리므로 그 자리에서
      // OverlayEntry 를 제거하면 빌드 중 트리를 건드리게 된다.
      if (s == AnimationStatus.completed) {
        WidgetsBinding.instance.addPostFrameCallback((_) => widget.onArrived());
      }
    });
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 카드는 출발 크기로 한 번만 배치하고 스케일로 키운다 — 매 프레임 재레이아웃
    // 대신 페인트만 하도록(게시글 상세 모프와 같은 방식).
    final child = Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: widget.from.width,
        height: widget.from.height,
        child: widget.card(context),
      ),
    );
    return AnimatedBuilder(
      animation: _c,
      child: RepaintBoundary(child: child),
      builder: (context, child) {
        final t = SpringCurve.standard.transform(_c.value.clamp(0.0, 1.0));
        final r = Rect.lerp(widget.from, widget.to, t)!;
        return Positioned.fromRect(
          rect: r,
          // 나는 카드는 순수한 시각 요소다 — 그 밑의 피드가 계속 눌려야 한다.
          child: IgnorePointer(
            child: OverflowBox(
              alignment: Alignment.center,
              minWidth: widget.from.width,
              maxWidth: widget.from.width,
              minHeight: widget.from.height,
              maxHeight: widget.from.height,
              child: Transform.scale(
                scale: r.width / widget.from.width,
                alignment: Alignment.center,
                filterQuality: FilterQuality.low,
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
