import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_motion.dart';

/// 누를 수 있는 모든 표면을 감싸는 **피드백(feedback) + 방향성(direction)** 래퍼.
///
/// - 누르면 스프링으로 살짝 가라앉고(scale down), 손을 떼면 탄력적으로 튕겨 되돌아온다.
/// - 손가락이 닿은 위치 쪽으로 3D 틸트가 일어나 "어디를 만졌는지" 가 모션의 방향으로 드러난다.
/// - 스프링이 속도를 이어받으므로 빠르게 연타해도 끊기지 않고 자연스럽게 이어진다(continuity).
///
/// InkWell/GestureDetector 를 대체해 카드·버튼·타일 어디에나 끼울 수 있다.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scaleTo = 0.96,
    this.maxTilt = 0.05,
    this.enableTilt = true,
    this.haptic = true,
    this.borderRadius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 눌렀을 때 도달하는 최소 스케일.
  final double scaleTo;

  /// 손가락 위치 방향으로 기우는 최대 각도(rad).
  final double maxTilt;
  final bool enableTilt;
  final bool haptic;
  final BorderRadius? borderRadius;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController.unbounded(vsync: this, value: 0);

  // -1..1 범위로 정규화된, 카드 중심 대비 터치 위치(틸트 방향).
  Offset _dir = Offset.zero;

  void _press(Offset local, Size size) {
    if (widget.enableTilt && size.width > 0 && size.height > 0) {
      _dir = Offset(
        ((local.dx / size.width) * 2 - 1).clamp(-1.0, 1.0),
        ((local.dy / size.height) * 2 - 1).clamp(-1.0, 1.0),
      );
    }
    _c.springTo(1, spring: MotionSprings.press);
  }

  void _release() {
    // 탄력 스프링으로 0 으로 — 0 아래로 살짝 오버슈트하며 "팝" 되돌아온다.
    _c.springTo(0, spring: MotionSprings.bounce);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) {
        final box = context.findRenderObject() as RenderBox?;
        _press(d.localPosition, box?.size ?? Size.zero);
      },
      onTapUp: (_) => _release(),
      onTapCancel: _release,
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.lightImpact();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.mediumImpact();
              widget.onLongPress!();
            },
      child: AnimatedBuilder(
        animation: _c,
        child: widget.borderRadius != null
            ? ClipRRect(borderRadius: widget.borderRadius!, child: widget.child)
            : widget.child,
        builder: (context, child) {
          final t = _c.value.clamp(-0.35, 1.5);
          final scale = 1 - (1 - widget.scaleTo) * t;
          final tilt = widget.maxTilt * t;
          final m = Matrix4.identity()
            ..setEntry(3, 2, 0.0012) // 원근 — 틸트에 입체감을 준다
            ..rotateX(-_dir.dy * tilt)
            ..rotateY(_dir.dx * tilt)
            ..scaleByDouble(scale, scale, 1.0, 1.0);
          return Transform(
            transform: m,
            alignment: Alignment.center,
            filterQuality: FilterQuality.low,
            child: child,
          );
        },
      ),
    );
  }
}
