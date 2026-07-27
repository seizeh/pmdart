import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

/// 웹 전용 스크롤 동작 — 데스크톱 브라우저에서만 어긋나는 두 가지를 잡는다.
///
///  1. **스크롤바** — 데스크톱 웹은 기본으로 스크롤바를 그린다. 앱에는 없는
///     요소라 본문 컬럼 바깥에 뜬 채로 이물감을 준다. 지운다.
///  2. **마우스 드래그** — 기본 `dragDevices` 는 터치·스타일러스뿐이라 마우스로는
///     스크롤뷰를 끌 수 없다. 세로 목록은 휠로 되지만 **가로 목록(커뮤니티
///     카테고리 칩)은 마우스만 있는 PC 에서 사실상 도달 불가**였다. 마우스와
///     트랙패드를 드래그 장치에 추가한다.
///
/// 네이티브에는 적용하지 않는다(`main.dart` 에서 `kIsWeb` 일 때만 지정) — 앱의
/// 스크롤 감각을 건드릴 이유가 없다.
class WebScrollBehavior extends MaterialScrollBehavior {
  const WebScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}
