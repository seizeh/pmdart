import 'package:flutter/material.dart';

import '../motion/springy_nav_bar.dart';
import '../theme/app_palette.dart';
import '../utils/layout.dart';

/// 좌측 레일에 그릴 탭 상태. [MainScreen] 이 공개하고 [AppShell] 이 그린다.
///
/// 레일을 MainScreen 안에서 그리지 않는 이유: 본문은 폰 폭 컬럼으로 묶이는데
/// 레일은 그 **바깥**(남는 폭)에 있어야 하고, 게시글 상세 같은 라우트가 위에
/// 얹혀도 레일은 남아 있어야 한다. 둘 다 Navigator 바깥에서만 가능하다.
class NavRailConfig {
  const NavRailConfig({
    required this.currentIndex,
    required this.items,
    required this.onTap,
  });

  final int currentIndex;
  final List<SpringyNavItem> items;
  final ValueChanged<int> onTap;
}

/// 현재 레일 상태 — 없으면(웰컴·로그인 등) 레일을 그리지 않는다.
/// 화면 간 조율에 정적 `ValueNotifier` 를 쓰는 것은 이 코드베이스의 기존 관용구다
/// (`MainScreen.tabRequest`, `AppEvents`).
final ValueNotifier<NavRailConfig?> navRail = ValueNotifier<NavRailConfig?>(
  null,
);

/// 넓은 화면(데스크톱 웹)에서 본문을 폰 폭 컬럼으로 묶고 남는 폭에 좌측 레일을 둔다.
///
/// **본문 디자인은 건드리지 않는다** — 카드·타이포·모션은 폭과 무관하게 앱과
/// 동일하고, 바뀌는 건 내비게이션의 위치뿐이다(docs/web-port.md 결정 1).
/// 좁은 화면에서는 아무것도 하지 않고 [child] 를 그대로 통과시킨다.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!useContentColumn(context)) return child;

    final column = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
        child: child,
      ),
    );

    return ColoredBox(
      // 컬럼 바깥은 Scaffold 가 칠하지 않으므로 셸이 배경을 깐다.
      color: context.colors.background,
      child: SafeArea(
        child: ValueListenableBuilder<NavRailConfig?>(
          valueListenable: navRail,
          builder: (context, cfg, _) {
            // 레일은 충분히 넓을 때만 — 그보다 좁으면 하단 바가 그대로 나온다.
            if (cfg == null || !useSideNav(context)) return column;
            return Row(
              children: [
                SpringyNavBar(
                  axis: Axis.vertical,
                  currentIndex: cfg.currentIndex,
                  onTap: cfg.onTap,
                  items: cfg.items,
                ),
                Expanded(child: column),
              ],
            );
          },
        ),
      ),
    );
  }
}
