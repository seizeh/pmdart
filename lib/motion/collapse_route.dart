import 'dart:ui' show lerpDouble;
import 'package:flutter/gestures.dart' show VelocityTracker;
import 'package:flutter/material.dart';

import '../utils/layout.dart' show shellOrigin, toRouteRect;

/// 아래에서 위로 떠오르는 모달형 원점 — [CollapsibleView.originRect] 에 넘기면
/// 화면이 하단(오프스크린)에서 슬라이드 업으로 등장하고, 당기거나 뒤로가기 시
/// 아래로 내려가며 닫힌다. 카드 크로스페이드는 생략(card: null).
Rect riseOriginRect(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  // originRect 규약은 '화면 좌표'다(utils/layout.dart toRouteRect 참고). 여기서는
  // MediaQuery(=라우트 크기) 기준으로 만들므로 셸 오프셋을 더해 화면 좌표로 맞춘다.
  return Rect.fromLTWH(
    0,
    size.height,
    size.width,
    size.height,
  ).shift(shellOrigin(context));
}

/// 투명 통과 라우트 — 아래 화면(피드)이 그대로 비쳐 보인다.
///
/// 카드에서 펼쳐지고/카드로 축소되는 **모든 시각 효과와 제스처는 화면 내부의
/// 로컬 컨트롤러**([PostDetailScreen])가 담당한다. 라우트는 컨테이너 역할만 하며
/// 컨트롤러를 손가락으로 직접 조작하지 않으므로, 축소가 끝까지 진행돼도(=로컬 0)
/// 내비게이터 상태와 충돌하지 않는다(먹통 방지).
class CollapseRoute<T> extends PageRoute<T> {
  CollapseRoute({required this.builder, super.settings});

  final WidgetBuilder builder;

  // 배경(피드)이 제자리에 있어야 originRect 안착이 정확하다 — 이전 라우트의
  // secondary 전환(Fluid 의 좌측 시차 이동·딤)을 구동하지 않는다.
  @override
  bool canTransitionFrom(TransitionRoute<dynamic> previousRoute) => false;

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

  // 배경이 제자리에 있어야 originRect 에서의 확장/축소가 정확히 겹친다.
  @override
  bool canTransitionFrom(TransitionRoute<dynamic> previousRoute) => false;

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
    // 화면 좌표 → 라우트 좌표(셸이 본문을 옮겨 놓은 만큼 보정).
    final rect = toRouteRect(context, originRect)!;
    return _OriginExpand(
      animation: curved,
      originRect: rect,
      collapsedRadius: originRadius ?? rect.height / 2,
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
                    // 콘텐츠는 윈도 중심 기준 — 원본(버튼) 중심에서 네 변이
                    // 동시에 벌어지는 사방 확장으로 읽힌다.
                    if (originFade < 1)
                      Opacity(
                        opacity: 1 - originFade,
                        child: OverflowBox(
                          alignment: Alignment.center,
                          minWidth: w,
                          maxWidth: w,
                          minHeight: h,
                          maxHeight: h,
                          child: Transform.scale(
                            scale: scale,
                            alignment: Alignment.center,
                            filterQuality: FilterQuality.low,
                            child: child,
                          ),
                        ),
                      ),
                    if (originWidget != null && originFade > 0)
                      Opacity(
                        opacity: originFade,
                        child: Align(
                          alignment: Alignment.center,
                          child: Transform.scale(
                            scale: win.width / originRect.width,
                            alignment: Alignment.center,
                            filterQuality: FilterQuality.low,
                            child: originWidget,
                          ),
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

  static Animation<double>? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<CollapseProgress>()?.progress;

  @override
  bool updateShouldNotify(CollapseProgress oldWidget) =>
      progress != oldWidget.progress;
}

/// 축소 시작 거부(veto) 판정 — 포인터 다운의 전역 좌표를 받아 true 면 축소 금지.
typedef CollapseVeto = bool Function(Offset globalPosition);

/// 하위 스크롤러의 축소 거부 등록부 — [CollapsibleView] 가 제공한다.
///
/// CollapsibleView 는 제스처 아레나 밖의 raw [Listener] 로 당김을 보므로, 화면
/// 안에 자체 스크롤러(펼친 본문 패널 등)가 있으면 내부 스크롤과 축소가 **동시에**
/// 반응한다(본문이 움직이면서 화면도 닫힘). 그런 스크롤러는 [CollapseScrollGuard]
/// 로 감싸 "이 지점에서 시작한 당김은 최상단 전까지 내가 스크롤로 소비한다"를
/// 알린다. 등록부 자체는 동일 인스턴스를 유지하므로 의존 리빌드가 없다.
class CollapseVetoes extends InheritedWidget {
  final Set<CollapseVeto> vetoes;
  const CollapseVetoes({super.key, required this.vetoes, required super.child});

  static Set<CollapseVeto>? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<CollapseVetoes>()?.vetoes;

  @override
  bool updateShouldNotify(CollapseVetoes oldWidget) => false;
}

/// 자체 스크롤러(펼친 본문 등)에 **스크롤 우선** 규칙을 적용하는 래퍼.
///
/// [builder] 가 받은 컨트롤러를 스크롤러에 물리면, 스크롤에 쓰인 제스처는
/// 끝까지 스크롤 전용이 된다 — 본문이 최상단에 닿아도 그 손가락으론 축소가
/// 시작되지 않고, **떼었다 다시 당겨야** 축소된다(도착과 동시에 닫히는 과민함
/// 방지). 진입 문턱은 CollapsibleView 의 기존 판정을 그대로 탄다.
/// CollapsibleView 밖이면 무동작.
class CollapseScrollGuard extends StatefulWidget {
  final Widget Function(BuildContext context, ScrollController controller)
      builder;
  const CollapseScrollGuard({super.key, required this.builder});

  @override
  State<CollapseScrollGuard> createState() => _CollapseScrollGuardState();
}

class _CollapseScrollGuardState extends State<CollapseScrollGuard> {
  final _controller = ScrollController();
  Set<CollapseVeto>? _registry;

  bool _veto(Offset globalPosition) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached) return false;
    final local = box.globalToLocal(globalPosition);
    if (!(Offset.zero & box.size).contains(local)) return false;
    return _controller.hasClients && _controller.position.pixels > 0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final r = CollapseVetoes.of(context);
    if (!identical(r, _registry)) {
      _registry?.remove(_veto);
      _registry = r?..add(_veto);
    }
  }

  @override
  void dispose() {
    _registry?.remove(_veto);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}

/// 확장 전환이 안착(진행도 1)했을 때만 나타나는 래퍼 — 카드에 없는 요소(앱바
/// 오버레이 아이콘 등)가 카드 크로스페이드 중간에 불쑥 나타나 모프가 2단계로
/// 끊겨 보이는 것을 막는다. 전환 중·축소 중에는 페이드아웃(카드 미러 우선).
/// [visible] 로 추가 숨김(오버레이 몰입 토글 등)을 함께 제어할 수 있다.
class CollapseSettledFade extends StatefulWidget {
  final Widget child;

  /// 추가 표시 조건 — 안착했더라도 false 면 숨긴다(기본 true).
  final bool visible;
  final Duration duration;

  const CollapseSettledFade({
    super.key,
    required this.child,
    this.visible = true,
    this.duration = const Duration(milliseconds: 180),
  });

  @override
  State<CollapseSettledFade> createState() => _CollapseSettledFadeState();
}

class _CollapseSettledFadeState extends State<CollapseSettledFade> {
  Animation<double>? _progress;
  bool _settled = true;
  bool _initialized = false;

  void _onTick() {
    final want = (_progress?.value ?? 1) >= 1.0;
    if (want != _settled && mounted) setState(() => _settled = want);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final p = CollapseProgress.of(context);
    if (!identical(p, _progress)) {
      _progress?.removeListener(_onTick);
      _progress = p;
      _progress?.addListener(_onTick);
    }
    if (!_initialized) {
      _initialized = true;
      // 전환 없이 열린 화면(비확장 진입)은 처음부터 표시.
      _settled = (p?.value ?? 1) >= 1.0;
    }
  }

  @override
  void dispose() {
    _progress?.removeListener(_onTick);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final show = _settled && widget.visible;
    return IgnorePointer(
      ignoring: !show,
      child: AnimatedOpacity(
        opacity: show ? 1 : 0,
        duration: widget.duration,
        child: widget.child,
      ),
    );
  }
}

class CollapsibleView extends StatefulWidget {
  const CollapsibleView({
    super.key,
    required this.originRect,
    required this.card,
    required this.scrollController,
    required this.builder,
    this.cardRadius = 20,
    this.expandDuration = const Duration(milliseconds: 420),
    this.expandCurve = Curves.easeOutCubic,
    this.contentAlignment = Alignment.topCenter,
    this.onSettled,
    this.dragHandleTest,
  });

  final Rect? originRect;
  final WidgetBuilder? card; // 축소 도착 시 크로스페이드할 실제 카드
  final ScrollController scrollController;
  final Widget Function(BuildContext context, ScrollPhysics physics) builder;

  /// 원본 카드의 모서리 곡률. 축소가 안착해 실제 카드로 교체될 때 곡률이
  /// 어긋나 뚝 튀지 않도록 반드시 [card] 와 같은 값을 넘긴다(기본 20 = PostCard).
  final double cardRadius;

  /// 원본(카드/타일)에서 펼쳐지는 확장 전환의 시간·커브. 화면별로 강조 정도를
  /// 다르게 줄 수 있다(기본은 게시글 상세와 동일).
  final Duration expandDuration;
  final Curve expandCurve;

  /// 확장/축소 중 콘텐츠(와 카드 크로스페이드)의 세로 정렬 기준.
  /// (콘텐츠 폭은 항상 윈도 폭과 일치해 가로 정렬은 무의미.)
  /// - [Alignment.topCenter](기본): 콘텐츠 상단이 윈도 상단에 붙는다 —
  ///   화면 상단 헤더가 카드와 미러되는 화면(프로필·펫 상세·채팅방).
  /// - [Alignment.center]: 윈도 중심 기준으로 네 변이 동시에 벌어지는
  ///   **사방 확장** — 카드 미러 콘텐츠를 화면 세로 중앙에 두는 쇼츠형
  ///   상세(게시글·후기, 히어로의 _mirror 배치와 짝).
  final Alignment contentAlignment;

  /// 축소가 원본 위치에 안착한 뒤(=카드) pop 하기 전에 실행할 2단계 모션.
  /// 예) 채팅방 프로필 카드가 목록 타일 모습으로 변형되는 후속 애니메이션.
  /// 반환 Future 가 끝나면 라우트를 닫는다. null 이면 즉시 pop(기존 동작).
  final Future<void> Function()? onSettled;

  /// 축소 드래그를 시작할 수 있는 위치 판정(포인터 다운의 전역 좌표).
  /// null 이면 기존 동작(스크롤 최상단이면 화면 어디서나). 채팅방처럼 리스트
  /// 스크롤과 당김이 겹쳐 애매한 화면은 헤더 등 특정 핸들 영역으로 제한한다
  /// (이 경우 스크롤 위치와 무관하게 핸들에서만 시작).
  final bool Function(Offset globalPosition)? dragHandleTest;

  @override
  State<CollapsibleView> createState() => _CollapsibleViewState();
}

class _CollapsibleViewState extends State<CollapsibleView>
    with SingleTickerProviderStateMixin {
  bool get _collapsible => widget.originRect != null;

  bool _dragging = false; // 축소 드래그 중(이 동안 스크롤 잠금)
  bool _settling = false; // 손 뗌→축소 완주 중(추가 입력 무시, 곧 pop)
  final Set<CollapseVeto> _vetoes = {}; // 하위 스크롤러의 축소 거부(CollapseVetoes)
  bool _vetoLatched = false; // 이번 제스처가 하위 스크롤에 쓰였음(끝까지 축소 금지)
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

  // 플릭(빠른 하강) 판정용 속도 추적 — 문턱 미달이어도 빠르게 내리면 닫는다.
  VelocityTracker? _velocity;

  /// 이 속도(px/s) 이상으로 아래로 튕기면 거리와 무관하게 닫는다.
  static const double _kFlingVelocity = 800;

  void _onPointerDown(PointerDownEvent e) {
    if (_settling) return;
    _dragStart = e.position;
    _vetoLatched = false; // 거부는 제스처 단위 — 새 포인터에서 재판정
    _velocity = VelocityTracker.withKind(e.kind)
      ..addPosition(e.timeStamp, e.position);
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!mounted || _settling || !_collapsible) return;
    _velocity?.addPosition(e.timeStamp, e.position);
    if (!_dragging) {
      final d = e.position - _dragStart;
      // 축소 진입 조건: 핸들 영역이 지정됐으면 그 안에서 시작한 드래그만,
      // 아니면 기존처럼 스크롤 최상단에서. 이후 아래로(세로 우세) 끌기 시작.
      // 하위 스크롤러가 거부(veto)하면 시작하지 않는다 — 본문 스크롤 우선.
      // 거부는 **래치**다: 이번 제스처에서 한 번이라도 하위 스크롤이 움직였으면
      // 본문이 최상단에 닿아도 그 손가락으론 축소하지 않는다(한 제스처 한 동작 —
      // 도착과 동시에 화면이 닫히는 과민함 방지). 떼었다 다시 당기면 축소.
      _vetoLatched = _vetoLatched || _vetoes.any((v) => v(_dragStart));
      final canStart = !_vetoLatched &&
          (widget.dragHandleTest != null
              ? widget.dragHandleTest!(_dragStart)
              : _atTop);
      // 진입 문턱 36px — 최상단에서의 미세한 손떨림/관성으로 축소가 걸리지 않게.
      if (canStart && d.dy > 36 && d.dy > d.dx.abs()) {
        _dragStart = e.position;
        _dragging = true; // 물리가 live 로 읽음(rebuild 불필요)
      }
      return;
    }
    final d = e.position - _dragStart;
    final vh = MediaQuery.of(context).size.height;
    final pull = d.dy.clamp(0.0, vh);
    _drag = d;
    // 손가락 이동 거리에 1:1 비례 — 화면 높이만큼 당겨야 완전 축소.
    // (기존 40% 배율은 손가락보다 화면이 훨씬 빨리 줄어 과민하게 느껴졌음.)
    _cc.value = 1 - (pull / vh).clamp(0.0, 1.0);
  }

  void _onPointerUp([_]) {
    if (!mounted || _settling || !_dragging) return;
    _dragging = false;
    // 닫힘 판정 — ① 거리: 화면 높이의 12%(≈100px) 이상 당김, 또는
    // ② 플릭: 아래로 800px/s 이상 빠르게 튕김(거리 미달이어도 닫힘).
    // 둘 다 미달이면 스프링 복귀.
    final vy = _velocity?.getVelocity().pixelsPerSecond.dy ?? 0.0;
    if (_cc.value < 0.88 || vy > _kFlingVelocity) {
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
    final content = CollapseVetoes(
      vetoes: _vetoes,
      child: CollapseProgress(
        progress: _cc,
        child: widget.builder(context, _physics),
      ),
    );
    if (!_collapsible) return content;

    final origin = toRouteRect(context, widget.originRect)!; // 화면 좌표 → 라우트 좌표
    // card 가 없으면(오프스크린 원점 모달 등) 크로스페이드 없이 콘텐츠만 이동.
    final cardWidget = widget.card == null
        ? null
        : Material(
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
  /// [cardWidget] 이 null 이면 크로스페이드 없이 콘텐츠가 불투명하게 이동만 한다.
  Widget _wrapCollapse(BuildContext context, Widget child, Widget? cardWidget) {
    final origin = toRouteRect(context, widget.originRect)!; // 화면 좌표 → 라우트 좌표
    final size = MediaQuery.of(context).size;
    final w = size.width;
    final h = size.height;
    final p = _cc.value.clamp(0.0, 1.0);
    final t = 1 - p;

    final win = Rect.lerp(Offset.zero & size, origin, t)!.shift(_drag * p);
    final scale = win.width / w;
    final radius = widget.cardRadius * (t * 2).clamp(0.0, 1.0);
    final scrim = 0.32 * p;
    final cardFade = cardWidget == null
        ? 0.0
        : ((t - 0.5) / 0.5).clamp(0.0, 1.0);
    // 콘텐츠·카드가 윈도의 어느 지점에 붙어 움직일지 — center 면 윈도 중심
    // 기준 사방 확장(쇼츠형), topCenter 면 상단 고정(헤더 미러형).
    final align = widget.contentAlignment;

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
                      alignment: align,
                      minWidth: w,
                      maxWidth: w,
                      minHeight: h,
                      maxHeight: h,
                      child: Transform.scale(
                        scale: scale,
                        alignment: align,
                        filterQuality: FilterQuality.low,
                        child: child,
                      ),
                    ),
                  ),
                if (cardWidget != null && cardFade > 0)
                  Opacity(
                    opacity: cardFade,
                    child: Align(
                      alignment: align,
                      child: Transform.scale(
                        scale: win.width / origin.width,
                        alignment: align,
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
