import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_motion.dart';

/// 좋아요 버튼 — 누르는 순간의 **즉각적 피드백(feedback)**.
///
/// 활성화될 때:
/// 1) 하트가 스프링으로 "팝"(과확대 후 안착) — 손맛 있는 반응
/// 2) 사방으로 입자가 방사 — 에너지가 바깥으로 퍼지는 **방향(direction)**
/// 3) 링이 번지며 사라짐
/// 비활성화는 조용히 되돌린다(과한 모션 자제).
class HeartButton extends StatefulWidget {
  const HeartButton({
    super.key,
    required this.active,
    required this.count,
    this.onTap,
    this.size = 16,
  });

  final bool active;
  final int count;
  final VoidCallback? onTap;
  final double size;

  @override
  State<HeartButton> createState() => _HeartButtonState();
}

class _HeartButtonState extends State<HeartButton>
    with TickerProviderStateMixin {
  // 하트 팝(스프링) — 0 안착, 1 눌림 직후 상태.
  late final AnimationController _pop =
      AnimationController.unbounded(vsync: this, value: 0);
  // 입자/링 버스트 — 0→1 한 번 재생.
  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: MotionDurations.base,
  );

  @override
  void dispose() {
    _pop.dispose();
    _burst.dispose();
    super.dispose();
  }

  void _handleTap() {
    final activating = !widget.active;
    if (activating) {
      HapticFeedback.mediumImpact();
      _pop.value = 1; // 즉시 부풀린 뒤
      _pop.springTo(0, spring: MotionSprings.bounce); // 탄력적으로 안착(오버슈트)
      _burst.forward(from: 0);
    } else {
      HapticFeedback.selectionClick();
      _pop.springTo(0, spring: MotionSprings.standard);
    }
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.active ? const Color(0xFFC97565) : const Color(0xFFB6AC9A);

    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: widget.size + 12,
            height: widget.size + 12,
            child: Center(
              child: AnimatedBuilder(
                animation: Listenable.merge([_pop, _burst]),
                builder: (context, _) {
                  // pop 값: 0 안착, 양수=부풀음. bounce 로 0 아래 오버슈트 시 살짝 수축.
                  final p = _pop.value;
                  final scale = 1 + 0.55 * p.clamp(-0.25, 1.0);
                  return Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      if (_burst.isAnimating)
                        CustomPaint(
                          size: Size.square(widget.size + 24),
                          painter: _BurstPainter(
                            progress: _burst.value,
                            color: color,
                          ),
                        ),
                      Transform.scale(
                        scale: scale,
                        child: Icon(
                          widget.active
                              ? Icons.favorite
                              : Icons.favorite_border,
                          size: widget.size,
                          color: color,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 2),
          // 숫자도 부드럽게 교체(연속성).
          AnimatedSwitcher(
            duration: MotionDurations.micro,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SizeTransition(
                axis: Axis.vertical,
                sizeFactor: anim,
                child: child,
              ),
            ),
            child: Text(
              '${widget.count}',
              key: ValueKey(widget.count),
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF8C8273),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 방사 입자 + 번지는 링.
class _BurstPainter extends CustomPainter {
  _BurstPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final eased = Curves.easeOut.transform(progress);
    final fade = (1 - progress).clamp(0.0, 1.0);

    // 번지는 링
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 * fade
      ..color = color.withValues(alpha: 0.5 * fade);
    canvas.drawCircle(center, size.width * 0.5 * eased, ringPaint);

    // 방사 입자 6개
    const count = 6;
    final dotPaint = Paint()..color = color.withValues(alpha: fade);
    final radius = size.width * 0.46 * eased;
    for (var i = 0; i < count; i++) {
      final angle = (i / count) * 2 * math.pi - math.pi / 2;
      final p = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      canvas.drawCircle(p, 1.6 * fade, dotPaint);
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) =>
      old.progress != progress || old.color != color;
}
