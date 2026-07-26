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

/// 이 폭에서 좌측 레일을 쓸지. 모바일 브라우저(< 900)는 기존 하단 바 그대로.
/// 레일(62+여백) + 본문(460)이 답답하지 않게 들어가는 지점을 기준으로 잡았다.
///
/// 웹에서만 적용한다 — 네이티브 앱(아이패드 등 넓은 화면 포함)의 현재 레이아웃은
/// 이 작업의 범위가 아니므로 건드리지 않는다.
bool useSideNav(BuildContext context) =>
    kIsWeb && MediaQuery.sizeOf(context).width >= 900;

/// 본문 컬럼에 최대 폭을 걸지 — 웹에서 폭이 남을 때만. 네이티브는 무변경.
bool useContentColumn(BuildContext context) =>
    kIsWeb && MediaQuery.sizeOf(context).width > kContentMaxWidth;

/// 스크롤 목록이 하단 크롬에 가리지 않도록 확보할 여백.
/// 좌측 레일을 쓰면 하단에 가릴 것이 없으므로 0 이다(데스크톱에서 목록 끝에
/// 빈 공간이 뜨는 것을 막는다).
double bottomNavClearance(BuildContext context) => useSideNav(context)
    ? 0
    : kNavThickness + MediaQuery.paddingOf(context).bottom;
