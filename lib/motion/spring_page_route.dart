import 'package:flutter/material.dart';
import 'app_motion.dart';

/// 들어오는/나가는 두 애니메이션을 받아 유체 전환 위젯을 만든다.
///
/// 들어오는 화면은 오른쪽에서 스프링 감속으로 미끄러져 들어오며 페이드 인하고,
/// 떠나는(아래에 깔리는) 화면은 살짝 왼쪽으로 밀리며 축소·디밍되어 깊이로 물러난다.
/// → 두 화면이 한 동작으로 이어지고(continuity), "앞으로 들어간다" 는 방향(direction)이 분명해진다.
Widget buildFluidTransition(
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  final enter = CurvedAnimation(
    parent: animation,
    curve: SpringCurve.standard,
    reverseCurve: Curves.easeInCubic,
  );
  final exit = CurvedAnimation(
    parent: secondaryAnimation,
    curve: Curves.easeOutCubic,
    reverseCurve: SpringCurve.standard,
  );

  return AnimatedBuilder(
    animation: Listenable.merge([enter, exit]),
    child: child,
    builder: (context, child) {
      final e = enter.value; // 0 → 1 : 들어옴
      final s = exit.value; // 0 → 1 : 다음 화면에 가려짐

      final incomingDx = (1 - e) * 0.16; // 오른쪽에서 진입(화면폭 비율)
      final outgoingDx = -s * 0.18; // 왼쪽으로 물러남(시차/깊이)
      final outgoingScale = 1 - s * 0.06;

      return FractionalTranslation(
        translation: Offset(outgoingDx, 0),
        child: Transform.scale(
          scale: outgoingScale,
          child: Opacity(
            opacity: 1 - s * 0.35,
            child: FractionalTranslation(
              translation: Offset(incomingDx, 0),
              child: Opacity(opacity: e.clamp(0.0, 1.0), child: child),
            ),
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
