import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// 전역 "키보드 닫기" 배리어 on/off.
///
/// 키보드가 떠 있을 때 화면 탭을 흡수해 키보드만 닫고 아래 위젯(게시글 등) 탭으로
/// 전달되지 않게 하는 배리어(main.dart)를 제어한다. 지도처럼 자동완성 제안을
/// 키보드가 떠 있는 상태로 탭해야 하는 화면은 진입 시 false 로 꺼서 제안 탭이
/// 가로채이지 않게 하고, 자체적으로(onMapTapped 등) 키보드를 닫는다.
final keyboardBarrierEnabled = ValueNotifier<bool>(true);

/// 배리어 예외 영역 — 등록된 rect(전역 좌표) 안에서는 배리어가 히트되지 않아,
/// 키보드가 떠 있어도 원래 위젯이 탭/스크롤을 그대로 받는다
/// (예: 커뮤니티 검색 중 카테고리 칩). getter 가 null 을 반환하면 무시된다.
/// 화면이 등록한 getter 는 dispose 에서 반드시 remove 해야 한다.
final keyboardBarrierExemptAreas = <Rect? Function()>[];

/// 예외 영역을 비켜가는 배리어 래퍼 — hitTest 단계에서 예외 rect 를 제외해,
/// 그 안의 포인터는 배리어를 거치지 않고 원래 위젯으로 간다(제스처 아레나에도
/// 배리어가 참가하지 않으므로 칩 탭이 '키보드 닫기'로 흡수되지 않는다).
class KeyboardBarrierHitFilter extends SingleChildRenderObjectWidget {
  const KeyboardBarrierHitFilter({super.key, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderKeyboardBarrierHitFilter();
}

class _RenderKeyboardBarrierHitFilter extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final global = localToGlobal(position);
    for (final area in keyboardBarrierExemptAreas) {
      final r = area();
      if (r != null && r.contains(global)) return false;
    }
    return super.hitTest(result, position: position);
  }
}
