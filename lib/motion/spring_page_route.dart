import 'package:flutter/material.dart';
import 'app_motion.dart';

/// 들어오는/나가는 두 애니메이션을 받아 유체 전환 위젯을 만든다.
///
/// 단일 동작으로 통일: 들어오는 화면은 오른쪽에서 슬라이드+페이드로 들어오고,
/// 아래 화면은 같은 비율만큼 왼쪽으로 시차 이동하며 살짝 디밍된다.
/// 앞/뒤(push/pop)가 **대칭**이고 모두 스냅 스프링으로 빠르게 안착하므로,
/// 뒤로가기도 답답하지 않고 한 가지 일관된 느낌으로 흐른다(continuity + direction).
Widget buildFluidTransition(
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  // 한 가지 곡선만 사용 — push/pop 모두 동일하게 빠르게 반응(통일).
  final enter = CurvedAnimation(parent: animation, curve: SpringCurve.snappy);
  final exit =
      CurvedAnimation(parent: secondaryAnimation, curve: SpringCurve.snappy);

  return AnimatedBuilder(
    animation: Listenable.merge([enter, exit]),
    child: child,
    builder: (context, child) {
      final e = enter.value; // 0 → 1 : 들어옴
      final s = exit.value; // 0 → 1 : 다음 화면에 가려짐

      final incomingDx = (1 - e) * 0.18; // 오른쪽에서 진입(화면폭 비율)
      final outgoingDx = -s * 0.18; // 같은 비율로 왼쪽 시차 이동(대칭)

      return FractionalTranslation(
        translation: Offset(outgoingDx, 0),
        child: Opacity(
          opacity: 1 - s * 0.25,
          child: FractionalTranslation(
            translation: Offset(incomingDx, 0),
            child: Opacity(opacity: e.clamp(0.0, 1.0), child: child),
          ),
        ),
      );
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
  ) =>
      buildFluidTransition(animation, secondaryAnimation, child);
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
