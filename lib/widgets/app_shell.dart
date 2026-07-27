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
    this.wide = false,
  });

  final int currentIndex;
  final List<SpringyNavItem> items;
  final ValueChanged<int> onTap;

  /// 지금 탭이 폰 폭 컬럼 대신 **남는 폭까지** 쓰길 원하는지 — 마스터-디테일
  /// (커뮤니티 피드 + 우측 상세 패널)을 쓰는 탭만 켠다.
  ///
  /// 레일 설정에 얹어 보내는 이유: 별도 notifier 를 두면 로그인(`pushAndRemoveUntil`)
  /// 때 새 화면의 initState 와 옛 화면의 dispose 순서가 엇갈려 방금 켠 값이 지워진다
  /// (레일이 통째로 사라지던 것과 같은 함정 — [MainScreen.dispose] 참고).
  final bool wide;
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

    return ColoredBox(
      // 컬럼 바깥은 Scaffold 가 칠하지 않으므로 셸이 배경을 깐다.
      color: context.colors.background,
      child: SafeArea(
        child: ValueListenableBuilder<NavRailConfig?>(
          valueListenable: navRail,
          builder: (context, cfg, _) {
            // 마스터-디테일은 **탭이 원하고 + 창이 충분히 넓을 때만**. 둘 중 하나만
            // 봐서는 안 된다 — 탭만 보면 좁은 창에서 패널이 찌그러지고, 폭만 보면
            // 커뮤니티가 아닌 탭까지 폭이 늘어난다.
            final column = _column(context, wide: cfg?.wide == true);
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

  /// 본문을 담는 박스. 평소엔 폰 폭(460) 중앙 정렬, 마스터-디테일이면 피드+패널
  /// 폭으로 넓혀 **레일 옆에 좌측 정렬**한다(가운데 두면 좌우로 다시 갈라진다).
  Widget _column(BuildContext context, {required bool wide}) {
    final outer = MediaQuery.of(context);
    final masterDetail = wide && useMasterDetail(context);
    return Align(
      alignment: masterDetail ? Alignment.centerLeft : Alignment.center,
      child: ConstrainedBox(
        key: contentColumnKey, // toRouteRect 가 이 박스의 화면 위치를 읽는다
        constraints: BoxConstraints(
          maxWidth: masterDetail ? kMasterDetailMaxWidth : kContentMaxWidth,
        ),
        child: LayoutBuilder(
          // MediaQuery 를 컬럼 크기로 덮어쓴다 — 안 하면 화면이 460 인데 창 폭
          // (예: 1433)으로 보고돼 MediaQuery.size 로 재는 레이아웃·모프가 어긋난다.
          // 대신 창 크기는 ShellMetrics 로 따로 내려보낸다 — 크롬 구성(레일이냐
          // 하단 바냐)은 창 폭 기준이어야 하기 때문(둘 다 나오는 것 방지).
          builder: (context, c) => ShellMetrics(
            windowSize: outer.size,
            child: MediaQuery(
              data: outer.copyWith(size: Size(c.maxWidth, c.maxHeight)),
              // 이 박스가 라우트 좌표의 기준 — 상세 패널은 자기 것으로 덮어쓴다.
              child: RouteHost(hostKey: contentColumnKey, child: child),
            ),
          ),
        ),
      ),
    );
  }
}
