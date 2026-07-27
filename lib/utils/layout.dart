/// 화면 폭에 따른 크롬(내비게이션) 구성.
///
/// **본문 디자인은 분리하지 않는다** — 카드·타이포·모션은 모든 폭에서 앱과
/// 동일하다. 폭에 따라 달라지는 건 내비게이션을 어디에 두느냐(하단 바 / 좌측
/// 레일)와 본문 컬럼을 얼마나 넓게 두느냐뿐이다(docs/web-port.md 결정 1).
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

/// 본문 한 컬럼의 최대 폭 — 폰 화면 폭에 맞춘다. 이보다 넓어지면 카드가
/// 늘어나 앱과 다른 비율이 되므로 넘기지 않는다.
const double kContentMaxWidth = 460.0;

/// 좌측 내비 레일의 두께(= 하단 바 높이와 동일).
const double kNavThickness = 62.0;

// ── 마스터-디테일(피드 + 우측 상세 패널) ─────────────────────────────────
//
// 데스크톱에서 460 컬럼을 가운데 두면 1440 폭 기준 945px(66%)가 빈 배경이 된다.
// 그 폭을 상세 패널로 쓴다 — **피드 카드 자체는 그대로**이고(결정 1), 상세를
// 새 라우트로 덮는 대신 옆에 펼치는 것뿐이다. 커뮤니티 탭에만 적용한다.

/// 피드와 상세 패널 사이 간격.
const double kDetailPanelGap = 16.0;

/// 상세 패널의 최소 폭 — 폰 폭(460)보다 좁아지면 상세 본문이 앱과 달라진다.
const double kDetailPanelMinWidth = kContentMaxWidth;

/// 상세 패널의 최대 폭 — 더 넓히면 본문 줄이 길어져 읽기 어렵다.
/// 초광폭 모니터에서는 이 상한 때문에 우측에 여백이 남고, 피드+패널 묶음은
/// 레일 옆에 좌측 정렬로 붙는다.
const double kDetailPanelMaxWidth = 860.0;

/// 마스터-디테일로 갈 최소 **창** 폭.
/// 레일(86) + 피드(460) + 간격(16) + 패널 최소(460) = 1022 에 여유를 둔 값.
const double kMasterDetailMinWidth = 1100.0;

/// 피드+패널 묶음의 최대 폭 — [AppShell] 이 본문 컬럼 대신 이 폭을 건다.
const double kMasterDetailMaxWidth =
    kContentMaxWidth + kDetailPanelGap + kDetailPanelMaxWidth;

/// 셸 **바깥(창)** 크기를 컬럼 안쪽으로 전달한다.
///
/// 컬럼 안에서는 `MediaQuery` 가 컬럼 크기(460)로 덮여 있어(레이아웃·모프가
/// 실제 그려지는 크기를 알아야 하므로) 창 폭을 알 수 없다. 그런데 크롬 구성을
/// 정하는 [useSideNav] 는 **창 폭** 기준이어야 한다 — 안 그러면 컬럼 안에서
/// "좁은 화면"으로 오판해 좌측 레일과 하단 바가 **동시에** 나온다.
class ShellMetrics extends InheritedWidget {
  const ShellMetrics({
    super.key,
    required this.windowSize,
    required super.child,
  });

  final Size windowSize;

  static Size? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellMetrics>()?.windowSize;

  @override
  bool updateShouldNotify(ShellMetrics old) => old.windowSize != windowSize;
}

/// 크롬 구성 판단 기준 폭 — 셸 안이면 창 폭, 아니면 그냥 화면 폭.
double _chromeWidth(BuildContext context) =>
    ShellMetrics.maybeOf(context)?.width ?? MediaQuery.sizeOf(context).width;

/// 이 폭에서 좌측 레일을 쓸지. 모바일 브라우저(< 900)는 기존 하단 바 그대로.
/// 레일(62+여백) + 본문(460)이 답답하지 않게 들어가는 지점을 기준으로 잡았다.
///
/// 웹에서만 적용한다 — 네이티브 앱(아이패드 등 넓은 화면 포함)의 현재 레이아웃은
/// 이 작업의 범위가 아니므로 건드리지 않는다.
bool useSideNav(BuildContext context) => kIsWeb && _chromeWidth(context) >= 900;

/// 본문 컬럼에 최대 폭을 걸지 — 웹에서 폭이 남을 때만. 네이티브는 무변경.
bool useContentColumn(BuildContext context) =>
    kIsWeb && _chromeWidth(context) > kContentMaxWidth;

/// 이 폭에서 마스터-디테일(피드 좌측 정렬 + 우측 상세 패널)을 쓸지.
///
/// [useSideNav] 와 마찬가지로 **창 폭** 기준이다. 900~1100 구간은 레일은 쓰되
/// 패널을 넣을 폭이 안 나오므로 지금까지의 460 중앙 컬럼 그대로 간다.
bool useMasterDetail(BuildContext context) =>
    kIsWeb && _chromeWidth(context) >= kMasterDetailMinWidth;

/// 본문 컬럼의 렌더박스 키 — `AppShell` 이 붙이고 [shellOrigin] 이 읽는다.
final GlobalKey contentColumnKey = GlobalKey();

/// 지금 라우트가 그려지는 박스 — 좌표 변환([toRouteRect])의 기준을 바꾼다.
///
/// 기본 기준은 [contentColumnKey](셸의 본문 컬럼)다. 그런데 마스터-디테일의
/// **상세 패널은 자기 Navigator 를 따로 갖고**, 그 라우트의 원점은 컬럼이 아니라
/// 패널의 좌상단이다. 기준을 바꾸지 않으면 카드에서 펼쳐지는 모프가 패널 폭만큼
/// 어긋난다 — 셸을 도입할 때 겪은 것과 **같은 종류의 버그**이므로(web-port.md
/// 결정 5 함정 1) 기준 자체를 트리에서 내려받게 만든다.
class RouteHost extends InheritedWidget {
  const RouteHost({super.key, required this.hostKey, required super.child});

  /// 라우트가 얹히는 박스의 키. `localToGlobal` 로 창 좌표 원점을 읽는다.
  final GlobalKey hostKey;

  static GlobalKey? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RouteHost>()?.hostKey;

  @override
  bool updateShouldNotify(RouteHost old) => old.hostKey != hostKey;
}

/// 라우트 원점의 창 좌표. 셸이 없거나(네이티브·좁은 화면) 아직 배치 전이면
/// `Offset.zero` — 즉 네이티브 동작은 그대로다.
///
/// [context] 를 주면 가장 가까운 [RouteHost] 를 기준으로 삼는다(상세 패널).
Offset shellOrigin([BuildContext? context]) {
  final key =
      (context == null ? null : RouteHost.maybeOf(context)) ?? contentColumnKey;
  final box = key.currentContext?.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize || !box.attached) return Offset.zero;
  return box.localToGlobal(Offset.zero);
}

/// 화면 좌표(`localToGlobal`)로 잡은 사각형을 **라우트 좌표계**로 옮긴다.
///
/// `AppShell` 은 Navigator **바깥**에서 본문을 가운데 컬럼으로 밀어 넣으므로
/// 라우트 안의 좌표 원점이 창 원점과 다르다. 카드 자리에서 펼쳐지는 모프
/// (`CollapsibleView`·`ExpandRoute`)는 화면 좌표로 잡은 사각형을 받으니
/// 그대로 쓰면 컬럼 오프셋만큼 어긋난 자리에서 펼쳐진다 — **창이 넓을수록 더
/// 크게 어긋난다**(데스크톱에서 상세가 화면 밖에서 열리던 증상).
///
/// 규약: `originRect` 는 언제나 **화면 좌표**로 넘긴다. 소비 지점에서 이 함수로
/// 변환한다. 셸이 없으면 오프셋이 0 이라 네이티브 동작은 그대로다.
///
/// [context] 로 기준 박스를 찾는다 — 상세 패널 안이면 패널 원점, 아니면 본문 컬럼.
Rect? toRouteRect(BuildContext context, Rect? r) {
  if (r == null) return null;
  final o = shellOrigin(context);
  return o == Offset.zero ? r : r.shift(-o);
}

/// 스크롤 목록이 하단 크롬에 가리지 않도록 확보할 여백.
/// 좌측 레일을 쓰면 하단에 가릴 것이 없으므로 0 이다(데스크톱에서 목록 끝에
/// 빈 공간이 뜨는 것을 막는다).
double bottomNavClearance(BuildContext context) => useSideNav(context)
    ? 0
    : kNavThickness + MediaQuery.paddingOf(context).bottom;
