import 'dart:ui' show lerpDouble;
import 'package:flutter/material.dart';

/// 투명 통과 라우트 — 아래 화면(피드)이 그대로 비쳐 보인다.
///
/// 카드에서 펼쳐지고/카드로 축소되는 **모든 시각 효과와 제스처는 화면 내부의
/// 로컬 컨트롤러**([PostDetailScreen])가 담당한다. 라우트는 컨테이너 역할만 하며
/// 컨트롤러를 손가락으로 직접 조작하지 않으므로, 축소가 끝까지 진행돼도(=로컬 0)
/// 내비게이터 상태와 충돌하지 않는다(먹통 방지).
class CollapseRoute<T> extends PageRoute<T> {
  CollapseRoute({required this.builder, super.settings});

  final WidgetBuilder builder;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get opaque => false; // 뒤 피드가 비쳐 카드로 자연스럽게 인계.

  @override
  bool get maintainState => true;

  @override
  bool get barrierDismissible => false;

  // 시각 전환은 화면이 로컬로 처리하므로 라우트 전환은 즉시.
  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Duration get reverseTransitionDuration => Duration.zero;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

/// 특정 원본 사각형([originRect], 예: 글쓰기 버튼)에서 **펼쳐지고 그 자리로 축소**되는
/// 라우트(App Store / Luma 맥락). [PostDetailScreen] 의 카드 확장과 같은 시각 언어이되,
/// 인터랙티브 드래그 없이 **프레임워크가 구동하는 안전한 전환**이라 폼 화면에 적합하다.
///
/// - push: originRect → 풀스크린으로 확장(원본 위젯 [origin] 이 화면으로 크로스페이드).
/// - pop : 풀스크린 → originRect 로 축소(다시 원본으로 인계).
class ExpandRoute<T> extends PageRoute<T> {
  ExpandRoute({
    required this.builder,
    required this.originRect,
    this.origin,
    this.originRadius,
    super.settings,
  });

  final WidgetBuilder builder;
  final Rect originRect;

  /// 축소 끝에서 원본으로 크로스페이드할 위젯(예: 버튼 모양). null 이면 크로스페이드 없음.
  final WidgetBuilder? origin;

  /// 원본(버튼)의 모서리 곡률. null 이면 알약(높이/2)으로 간주.
  final double? originRadius;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get opaque => false;

  @override
  bool get maintainState => true;

  @override
  bool get barrierDismissible => false;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 440);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 380);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return _OriginExpand(
      animation: curved,
      originRect: originRect,
      collapsedRadius: originRadius ?? originRect.height / 2,
      origin: origin,
      child: child,
    );
  }
}

/// 풀스크린 콘텐츠를 [animation](1=풀스크린, 0=원본)에 따라 원본 사각형으로 균일
/// 축소·클립하고, 원본 위젯으로 크로스페이드한다. [CollapseRoute] 내부 처리와 동일 언어.
class _OriginExpand extends StatelessWidget {
  const _OriginExpand({
    required this.animation,
    required this.originRect,
    required this.collapsedRadius,
    required this.origin,
    required this.child,
  });

  final Animation<double> animation;
  final Rect originRect;
  final double collapsedRadius;
  final WidgetBuilder? origin;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final w = size.width;
    final h = size.height;
    // Material 로 감싸 텍스트가 조상 없이 노란 밑줄로 렌더되는 것 방지.
    final originWidget = origin == null
        ? null
        : Material(
            type: MaterialType.transparency,
            child: SizedBox(
              width: originRect.width,
              height: originRect.height,
              child: origin!(context),
            ),
          );
    return AnimatedBuilder(
      animation: animation,
      // RepaintBoundary 로 작성 화면 페인트를 캐시 → 확장/축소 스케일 매 프레임에
      // 전체 재페인트 대신 캐시 레이어 재사용.
      child: RepaintBoundary(child: child),
      builder: (context, child) {
        final p = animation.value.clamp(0.0, 1.0);
        final t = 1 - p;
        final win = Rect.lerp(Offset.zero & size, originRect, t)!;
        final scale = win.width / w;
        final radius = lerpDouble(0, collapsedRadius, (t * 2).clamp(0.0, 1.0))!;
        final scrim = 0.32 * p;
        final originFade = ((t - 0.5) / 0.5).clamp(0.0, 1.0);

        return Stack(
          fit: StackFit.expand,
          children: [
            if (scrim > 0.001)
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: scrim),
                  ),
                ),
              ),
            Positioned.fromRect(
              rect: win,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (originFade < 1)
                      Opacity(
                        opacity: 1 - originFade,
                        child: OverflowBox(
                          alignment: Alignment.topLeft,
                          minWidth: w,
                          maxWidth: w,
                          minHeight: h,
                          maxHeight: h,
                          child: Transform.scale(
                            scale: scale,
                            alignment: Alignment.topLeft,
                            filterQuality: FilterQuality.low,
                            child: child,
                          ),
                        ),
                      ),
                    if (originWidget != null && originFade > 0)
                      Opacity(
                        opacity: originFade,
                        child: Transform.scale(
                          scale: win.width / originRect.width,
                          alignment: Alignment.topLeft,
                          filterQuality: FilterQuality.low,
                          child: originWidget,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
