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

/// 카드에서 펼쳐지고(등장)·아래로 당기면 카드로 축소되어 닫히는 상세 화면 래퍼.
///
/// [PostDetailScreen]·[ChatRoomScreen] 등이 공유. 스크롤이 최상단일 때 아래로 당기면
/// 화면 전체가 균일 축소되며 원본 카드([originRect])로 인계된다. 라우트 컨트롤러가
/// 아니라 **로컬 컨트롤러**로 구동하므로 축소 완주(=0) 시에도 먹통이 없다.
///
/// [builder] 는 스크롤 리스트에 물릴 [ScrollPhysics] 를 받아 화면(Scaffold)을 만든다.
/// (드래그 중 스크롤을 잠그기 위해 반드시 이 physics 를 리스트에 전달해야 한다.)
/// [originRect] 가 null 이면 축소 없이 [builder] 결과만 그대로 보여준다.
/// CollapsibleView 의 확장/축소 진행도(0=카드, 1=풀스크린)를 하위 위젯에 노출.
/// 상세 화면 내부 요소가 전환 상태에 반응(예: 히어로 본문 정렬 전환)할 때 쓴다.
/// 값 구독은 [of] 로 받은 애니메이션에 직접 listener 를 달아 관리한다
/// (Inherited 의존 리빌드가 아니라 임계값 교차 시에만 setState 하도록).
class CollapseProgress extends InheritedWidget {
  final Animation<double> progress;
  const CollapseProgress({
    super.key,
    required this.progress,
    required super.child,
  });

  static Animation<double>? of(BuildContext context) => context
      .getInheritedWidgetOfExactType<CollapseProgress>()
      ?.progress;

  @override
  bool updateShouldNotify(CollapseProgress oldWidget) =>
      progress != oldWidget.progress;
}

class CollapsibleView extends StatefulWidget {
  const CollapsibleView({
    super.key,
    required this.originRect,
    required this.card,
    required this.scrollController,
    required this.builder,
    this.expandDuration = const Duration(milliseconds: 420),
    this.expandCurve = Curves.easeOutCubic,
    this.onSettled,
  });

  final Rect? originRect;
  final WidgetBuilder? card; // 축소 도착 시 크로스페이드할 실제 카드
  final ScrollController scrollController;
  final Widget Function(BuildContext context, ScrollPhysics physics) builder;

  /// 원본(카드/타일)에서 펼쳐지는 확장 전환의 시간·커브. 화면별로 강조 정도를
  /// 다르게 줄 수 있다(기본은 게시글 상세와 동일).
  final Duration expandDuration;
  final Curve expandCurve;

  /// 축소가 원본 위치에 안착한 뒤(=카드) pop 하기 전에 실행할 2단계 모션.
  /// 예) 채팅방 프로필 카드가 목록 타일 모습으로 변형되는 후속 애니메이션.
  /// 반환 Future 가 끝나면 라우트를 닫는다. null 이면 즉시 pop(기존 동작).
  final Future<void> Function()? onSettled;

  @override
  State<CollapsibleView> createState() => _CollapsibleViewState();
}

class _CollapsibleViewState extends State<CollapsibleView>
    with SingleTickerProviderStateMixin {
  bool get _collapsible => widget.originRect != null;

  bool _dragging = false; // 축소 드래그 중(이 동안 스크롤 잠금)
  bool _settling = false; // 손 뗌→축소 완주 중(추가 입력 무시, 곧 pop)
  Offset _dragStart = Offset.zero;
  Offset _drag = Offset.zero; // 축소 UI 이동량(손가락 따라)

  // 로컬 축소 컨트롤러(1=풀스크린, 0=카드).
  late final AnimationController _cc = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 440),
    value: _collapsible ? 0 : 1,
  );

  // 드래그 중엔 스크롤 오프셋만 0으로 무력화(클래스는 유지 → 취소/재진입 루프 없음).
  late final ScrollPhysics _physics = _LockableScrollPhysics(
    locked: () => _dragging,
    parent: const AlwaysScrollableScrollPhysics(
      parent: ClampingScrollPhysics(),
    ),
  );

  @override
  void initState() {
    super.initState();
    if (_collapsible) {
      _cc.animateTo(
        1,
        duration: widget.expandDuration,
        curve: widget.expandCurve,
      );
    }
  }

  @override
  void dispose() {
    _cc.dispose();
    super.dispose();
  }

  bool get _atTop =>
      !widget.scrollController.hasClients ||
      widget.scrollController.position.pixels <= 0;

  void _onPointerDown(PointerDownEvent e) {
    if (_settling) return;
    _dragStart = e.position;
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!mounted || _settling || !_collapsible) return;
    if (!_dragging) {
      final d = e.position - _dragStart;
      // 최상단에서 아래로(세로 우세) 끌기 시작할 때만 축소 진입.
      if (_atTop && d.dy > 8 && d.dy > d.dx.abs()) {
        _dragStart = e.position;
        _dragging = true; // 물리가 live 로 읽음(rebuild 불필요)
      }
      return;
    }
    final d = e.position - _dragStart;
    final vh = MediaQuery.of(context).size.height;
    final pull = d.dy.clamp(0.0, vh);
    _drag = d;
    _cc.value = 1 - (pull / (vh * 0.4)).clamp(0.0, 1.0); // 40% 당기면 카드
  }

  void _onPointerUp([_]) {
    if (!mounted || _settling || !_dragging) return;
    _dragging = false;
    if (_cc.value < 0.97) {
      _startDismiss();
    } else {
      _drag = Offset.zero;
      _cc.animateTo(
        1,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  void _startDismiss() {
    if (_settling) return;
    setState(() => _settling = true);
    final dur = Duration(milliseconds: (260 + 300 * _cc.value).round());
    _cc.animateTo(0, duration: dur, curve: Curves.easeOutCubic).whenComplete(
      () async {
        // 축소가 카드(원본 위치)에 안착. 2단계 모션이 있으면 먼저 재생 후 pop.
        if (widget.onSettled != null) await widget.onSettled!();
        if (mounted) Navigator.of(context).pop();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = CollapseProgress(
      progress: _cc,
      child: widget.builder(context, _physics),
    );
    if (!_collapsible) return content;

    final origin = widget.originRect!;
    final cardWidget = Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: origin.width,
        height: origin.height,
        child: widget.card!(context),
      ),
    );
    return PopScope(
      canPop: _settling,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _startDismiss();
      },
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerUp,
        child: AnimatedBuilder(
          animation: _cc,
          builder: (context, child) =>
              _wrapCollapse(context, child!, cardWidget),
          child: RepaintBoundary(child: content),
        ),
      ),
    );
  }

  /// 풀스크린 콘텐츠를 _cc 에 따라 카드로 균일 축소·클립하고, 카드 크기에서 실제 카드로
  /// 크로스페이드(피드 카드와 동일). 게시글 상세와 완전히 동일한 시각 언어.
  Widget _wrapCollapse(BuildContext context, Widget child, Widget cardWidget) {
    final origin = widget.originRect!;
    final size = MediaQuery.of(context).size;
    final w = size.width;
    final h = size.height;
    final p = _cc.value.clamp(0.0, 1.0);
    final t = 1 - p;

    final win = Rect.lerp(Offset.zero & size, origin, t)!.shift(_drag * p);
    final scale = win.width / w;
    final radius = 20.0 * (t * 2).clamp(0.0, 1.0);
    final scrim = 0.32 * p;
    final cardFade = ((t - 0.5) / 0.5).clamp(0.0, 1.0);

    return Stack(
      fit: StackFit.expand,
      children: [
        if (scrim > 0.001)
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(color: Colors.black.withValues(alpha: scrim)),
            ),
          ),
        Positioned.fromRect(
          rect: win,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (cardFade < 1)
                  Opacity(
                    opacity: 1 - cardFade,
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
                if (cardFade > 0)
                  Opacity(
                    opacity: cardFade,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Transform.scale(
                        scale: win.width / origin.width,
                        alignment: Alignment.topLeft,
                        filterQuality: FilterQuality.low,
                        child: cardWidget,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 잠겼을 때 사용자 스크롤 오프셋을 0으로 무력화(클래스는 유지 → 드래그 취소 없음).
class _LockableScrollPhysics extends ScrollPhysics {
  final ValueGetter<bool> locked;
  const _LockableScrollPhysics({required this.locked, super.parent});

  @override
  _LockableScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _LockableScrollPhysics(locked: locked, parent: buildParent(ancestor));

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) =>
      locked() ? 0.0 : super.applyPhysicsToUserOffset(position, offset);

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) => locked() ? null : super.createBallisticSimulation(position, velocity);
}
