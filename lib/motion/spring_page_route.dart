import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'app_motion.dart';

/// 들어오는/나가는 두 애니메이션을 받아 유체 전환 위젯을 만든다.
///
/// Luma 스타일 "부드러운 열림/닫힘" 전환:
/// - 새 화면은 살짝 축소(0.92)·둥근 모서리·아래에서 올라오며 스프링으로 펼쳐진다.
/// - **뒤로가기(pop)** 는 그 역재생 — 현재 화면이 스프링으로 축소되고 모서리가
///   둥글어지며 아래로 내려가고, 뒤 화면은 축소·딤 상태에서 제자리로 스프링백하며 밝아진다.
/// push/pop 이 **대칭**이고 모두 같은 스프링 물리를 공유해 한 가지 재질감으로 흐른다.
Widget buildFluidTransition(
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  // 모션이 전 구간에 고르게 퍼지는 강조 이징(중앙 가중) — 스프링의 플랫 테일 때문에
  // 짧게 느껴지던 문제 해결. 시작~끝 내내 움직여 전환이 또렷이 체감된다.
  final enter = CurvedAnimation(
    parent: animation,
    curve: Curves.easeInOutCubicEmphasized,
    reverseCurve: Curves.easeInOutCubicEmphasized,
  );
  final cover = CurvedAnimation(
    parent: secondaryAnimation,
    curve: Curves.easeInOutCubicEmphasized,
    reverseCurve: Curves.easeInOutCubicEmphasized,
  );

  return AnimatedBuilder(
    animation: Listenable.merge([enter, cover]),
    child: child,
    builder: (context, child) {
      final e = enter.value.clamp(0.0, 1.0); // 0→1: 이 화면이 들어옴 / 1→0: 뒤로 닫힘
      final s = cover.value.clamp(0.0, 1.0); // 0→1: 다음 화면에 가려짐 / 1→0: 다시 드러남

      // (1) 이 화면의 등장/닫힘 — 오른쪽에서/으로 슬라이드 + 축소 + 모서리 곡률.
      //     엣지 스와이프가 손가락(오른쪽)을 그대로 따라오도록 가로 이동을 주축으로.
      final selfShiftX = (1 - e) * 0.30; // 화면폭 비율: +0.30(오른쪽) → 0
      final selfScale = 0.92 + 0.08 * e; // 0.92 → 1.0
      final selfRadius = (1 - e) * 24.0; // 둥근 카드 → 평평한 풀스크린
      final selfOpacity = (e * 2).clamp(0.0, 1.0); // 후반부만 페이드(닫힐 때 모서리 보이게)

      // (2) 다음 화면에 가려질 때 — 왼쪽으로 살짝 시차 이동 + 축소 + 딤(깊이감).
      final coverShiftX = -0.10 * s; // 화면폭 비율: 0 → -0.10(왼쪽)
      final coverScale = 1 - 0.05 * s; // 1.0 → 0.95
      final coverDim = 0.45 * s; // 위로 덮이는 만큼 어두워짐

      Widget content = child!;

      // 등장/닫힘 변환(안쪽): 카드가 오른쪽에서 들어오고 오른쪽으로 나간다.
      content = FractionalTranslation(
        translation: Offset(selfShiftX, 0),
        child: Transform.scale(
          scale: selfScale,
          filterQuality: FilterQuality.low,
          child: Opacity(
            opacity: selfOpacity,
            child: selfRadius < 0.5
                ? content
                : ClipRRect(
                    borderRadius: BorderRadius.circular(selfRadius),
                    child: content,
                  ),
          ),
        ),
      );

      // 가려짐 변환(바깥): 왼쪽으로 물러나며 축소·딤 오버레이가 덮인다.
      content = FractionalTranslation(
        translation: Offset(coverShiftX, 0),
        child: Transform.scale(
          scale: coverScale,
          filterQuality: FilterQuality.low,
          child: coverDim <= 0
              ? content
              : Stack(
                  fit: StackFit.passthrough,
                  children: [
                    content,
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ColoredBox(
                          color: const Color(
                            0xFF000000,
                          ).withValues(alpha: coverDim),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      );

      return content;
    },
  );
}

/// 테마에 등록해 모든 [MaterialPageRoute] 전환을 유체 전환으로 통일한다.
class FluidPageTransitionsBuilder extends PageTransitionsBuilder {
  const FluidPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => buildFluidTransition(animation, secondaryAnimation, child);
}

/// 개별 push 에 직접 쓰고 싶을 때(테마를 안 타는 모달성 화면 등).
class FluidPageRoute<T> extends PageRouteBuilder<T> {
  FluidPageRoute({required WidgetBuilder builder, super.settings})
    : super(
        transitionDuration: MotionDurations.page,
        reverseTransitionDuration: MotionDurations.base,
        pageBuilder: (context, _, _) => builder(context),
        transitionsBuilder: (context, animation, secondary, child) =>
            buildFluidTransition(animation, secondary, child),
      );
}

/// 앱 표준 화면 라우트 — [MaterialPageRoute] 대체.
///
/// 두 가지를 더한다.
/// 1) 전환 시간을 넉넉히 잡아 Luma 축소/모서리/딤 모션이 또렷이 체감된다.
/// 2) **왼쪽 가장자리 → 오른쪽 스와이프**로 같은 dismiss 애니메이션을 손가락으로
///    스크럽한다(놓으면 스프링백 또는 닫힘). 세로 스크롤과 충돌하지 않도록 좌측
///    엣지 스트립에서만 인식한다.
class AppPageRoute<T> extends MaterialPageRoute<T> {
  AppPageRoute({
    required super.builder,
    super.settings,
    super.maintainState,
    super.fullscreenDialog,
  });

  // 넉넉한 전환 시간(짧아서 안 보이던 문제 해결). 강조 이징이 이 구간을 채운다.
  @override
  Duration get transitionDuration => const Duration(milliseconds: 620);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 560);

  bool get _canSwipeBack =>
      isCurrent &&
      !isFirst &&
      !fullscreenDialog &&
      !willHandlePopInternally &&
      popDisposition == RoutePopDisposition.pop &&
      animation?.status == AnimationStatus.completed &&
      navigator != null &&
      !navigator!.userGestureInProgress;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // 테마 빌더 대신 직접 유체 전환 + 엣지 스와이프 래핑.
    final visual = buildFluidTransition(animation, secondaryAnimation, child);
    return _EdgeSwipeBack(
      enabledCallback: () => _canSwipeBack,
      onStart: () =>
          _EdgeBackController(controller: controller!, navigator: navigator!),
      child: visual,
    );
  }
}

// 좌측 감지 스트립 폭 / 튕김으로 판정할 최소 속도(화면폭 정규화, 초당).
const double _kEdgeWidth = 28.0;
const double _kMinFlingVelocity = 1.0;

/// 왼쪽 엣지 가로 드래그를 감지해 route 컨트롤러를 스크럽하는 래퍼.
class _EdgeSwipeBack extends StatefulWidget {
  final ValueGetter<bool> enabledCallback;
  final _EdgeBackController Function() onStart;
  final Widget child;
  const _EdgeSwipeBack({
    required this.enabledCallback,
    required this.onStart,
    required this.child,
  });

  @override
  State<_EdgeSwipeBack> createState() => _EdgeSwipeBackState();
}

class _EdgeSwipeBackState extends State<_EdgeSwipeBack> {
  _EdgeBackController? _drag;

  double get _width => (context.size?.width ?? 1).clamp(1.0, double.infinity);

  void _onStart(DragStartDetails _) {
    if (widget.enabledCallback()) _drag = widget.onStart();
  }

  void _onUpdate(DragUpdateDetails d) =>
      _drag?.dragUpdate((d.primaryDelta ?? 0) / _width);

  void _onEnd(DragEndDetails d) {
    _drag?.dragEnd(d.velocity.pixelsPerSecond.dx / _width);
    _drag = null;
  }

  void _onCancel() {
    _drag?.dragEnd(0);
    _drag = null;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        // 좌측 얇은 스트립에서만 가로 드래그 인식(탭·세로 스크롤은 그대로 통과).
        PositionedDirectional(
          start: 0,
          top: 0,
          bottom: 0,
          width: _kEdgeWidth,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            excludeFromSemantics: true,
            onHorizontalDragStart: _onStart,
            onHorizontalDragUpdate: _onUpdate,
            onHorizontalDragEnd: _onEnd,
            onHorizontalDragCancel: _onCancel,
          ),
        ),
      ],
    );
  }
}

/// 드래그 진행도로 route 컨트롤러(1=열림, 0=닫힘)를 직접 움직이고,
/// 손을 떼면 스프링백(복귀) 또는 pop(닫힘)을 결정한다. Cupertino 뒤로가기 제스처와
/// 같은 메커니즘이되, 복귀는 앱 스프링 물리를 쓴다(continuity).
class _EdgeBackController {
  final AnimationController controller;
  final NavigatorState navigator;

  _EdgeBackController({required this.controller, required this.navigator}) {
    navigator.didStartUserGesture();
  }

  // 오른쪽으로 끈 비율만큼 1→0 으로 스크럽(= dismiss 애니메이션 되감기).
  void dragUpdate(double fraction) {
    controller.value = (controller.value - fraction).clamp(0.0, 1.0);
  }

  void dragEnd(double velocity) {
    final bool settleOpen; // true=제자리 복귀, false=닫힘
    if (velocity.abs() >= _kMinFlingVelocity) {
      settleOpen = velocity < 0; // 왼쪽으로 튕김 → 복귀
    } else {
      settleOpen = controller.value > 0.5;
    }

    if (settleOpen) {
      // 제자리로 스프링백(미세 탄성 — 앱 공통 물리).
      controller.animateWith(
        SpringSimulation(
          MotionSprings.standard,
          controller.value,
          1.0,
          velocity,
        ),
      );
    } else {
      navigator.pop(); // route 가 reverse 시작
      if (controller.isAnimating) {
        controller.animateBack(
          0.0,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        );
      }
    }

    if (controller.isAnimating) {
      late AnimationStatusListener cb;
      cb = (_) {
        navigator.didStopUserGesture();
        controller.removeStatusListener(cb);
      };
      controller.addStatusListener(cb);
    } else {
      navigator.didStopUserGesture();
    }
  }
}
