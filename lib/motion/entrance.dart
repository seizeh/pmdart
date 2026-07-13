import 'dart:async';
import 'package:flutter/widgets.dart';
import 'app_motion.dart';

/// 리스트/그리드 아이템의 **계층적 등장(hierarchy)**.
///
/// index 에 따라 등장이 순차적으로 지연되어, 콘텐츠가 위에서 아래로
/// "쏟아져 들어오듯" 흐른다. 단순 페이드가 아니라 살짝 아래에서 위로 올라오며
/// 미세하게 확대되어, 새 콘텐츠가 사용자 쪽으로 다가오는 **방향(direction)** 을 가진다.
/// 모든 아이템이 같은 [SpringCurve] 를 쓰므로 화면 전체가 하나의 흐름으로 묶인다(continuity).
class Entrance extends StatefulWidget {
  const Entrance({
    super.key,
    required this.index,
    required this.child,
    this.offsetY = 22,
    this.fromScale = 0.96,
  });

  final int index;
  final Widget child;

  /// 시작 시 아래로 밀려있는 거리(px).
  final double offsetY;

  /// 시작 시 축소 비율.
  final double fromScale;

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: MotionDurations.base,
  );
  late final Animation<double> _a = CurvedAnimation(
    parent: _c,
    curve: SpringCurve.lively,
  );
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // index 기반 stagger — 부모(위쪽)가 먼저, 자식(아래쪽)이 뒤따른다.
    _timer = Timer(MotionStagger.delayFor(widget.index), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      // RepaintBoundary — 등장 애니메이션(불투명도·이동·확대) 동안 자식을 매 프레임
      // 다시 그리지 않고, 한 번 래스터한 레이어를 합성만 한다. 블러가 든 카드
      // (PostCard 등)가 스태거로 여럿 등장할 때 프레임 저하를 막는 핵심.
      child: RepaintBoundary(child: widget.child),
      builder: (context, child) {
        final t = _a.value;
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform(
            transform: Matrix4.identity()
              ..translateByDouble(0.0, (1 - t) * widget.offsetY, 0.0, 1.0)
              ..scaleByDouble(
                widget.fromScale + (1 - widget.fromScale) * t,
                widget.fromScale + (1 - widget.fromScale) * t,
                1.0,
                1.0,
              ),
            alignment: Alignment.topCenter,
            child: child,
          ),
        );
      },
    );
  }
}
