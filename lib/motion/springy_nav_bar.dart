import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_motion.dart';

class SpringyNavItem {
  const SpringyNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// 바텀 내비게이션 — **연속성·방향·피드백**을 한 번에 보여주는 핵심 표면.
///
/// - 활성 표시 알약(pill)이 탭 사이를 스프링으로 "이동"한다. 끊겨 사라졌다 나타나는 게
///   아니라 공간을 가로질러 흐르므로 두 탭이 하나의 동작으로 연결된다(continuity).
/// - 알약은 이동 방향으로 살짝 늘어났다(스쿼시) 안착해 **방향(direction)** 과 관성을 드러낸다.
/// - 선택된 아이콘은 살짝 떠오르고 확대되며, 이동 중인 인접 아이콘도 거리에 따라
///   부드럽게 반응한다(feedback).
class SpringyNavBar extends StatefulWidget {
  const SpringyNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
    this.activeColor = const Color(0xFF5A4E3A),
    this.inactiveColor = const Color(0xFFB6AC9A),
    this.pillColor = const Color(0x145A4E3A),
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<SpringyNavItem> items;
  final Color activeColor;
  final Color inactiveColor;
  final Color pillColor;

  @override
  State<SpringyNavBar> createState() => _SpringyNavBarState();
}

class _SpringyNavBarState extends State<SpringyNavBar>
    with SingleTickerProviderStateMixin {
  // 연속 위치(0.0 ~ items.length-1) — 정수 인덱스 사이를 스프링으로 흐른다.
  late final AnimationController _c = AnimationController.unbounded(
    vsync: this,
    value: widget.currentIndex.toDouble(),
  );

  @override
  void didUpdateWidget(covariant SpringyNavBar old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex) {
      // 현재 속도를 이어받아 목표 탭으로 — 방향과 관성이 유지된다.
      _c.springTo(widget.currentIndex.toDouble(), spring: MotionSprings.lively);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _tap(int i) {
    if (i != widget.currentIndex) HapticFeedback.lightImpact();
    widget.onTap(i);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        // 흰색 셀로판지(반투명) — 뒤 콘텐츠가 선명하게 비치며 덮인다(상단 헤더와 동일 효과).
        color: Color(0xEBFFFFFF), // 흰색 alpha ≈ 0.92 (= AppColors.frostFilm)
        // 상단 좌우 모서리를 둥글게 — 각진 느낌 제거.
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        // 하드 보더 대신 위로 번지는 부드러운 그림자로 본문과 분리.
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 24,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final n = widget.items.length;
              final itemW = constraints.maxWidth / n;
              return AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final pos = _c.value; // 연속 위치
                  // 이동 속도로 알약을 진행 방향으로 늘림(스쿼시 & 스트레치).
                  final v = _c.velocity;
                  final stretch = (v.abs() * 0.04).clamp(0.0, 0.22);
                  const pillW = 56.0;
                  const pillH = 36.0;
                  final pillCenterX = (pos + 0.5) * itemW;

                  return Stack(
                    children: [
                      // 흐르는 알약 인디케이터
                      Positioned(
                        top: (62 - pillH) / 2,
                        left: pillCenterX - pillW / 2,
                        child: Transform.scale(
                          scaleX: 1 + stretch,
                          scaleY: 1 - stretch * 0.6,
                          child: Container(
                            width: pillW,
                            height: pillH,
                            decoration: BoxDecoration(
                              color: widget.pillColor,
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                        ),
                      ),
                      // 아이콘 + 라벨
                      Row(
                        children: [
                          for (var i = 0; i < n; i++) _buildItem(i, pos, itemW),
                        ],
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildItem(int i, double pos, double itemW) {
    final item = widget.items[i];
    // 알약과의 근접도(0~1): 가까울수록 활성에 가깝게 보간된다.
    final proximity = (1 - (pos - i).abs()).clamp(0.0, 1.0);
    final color = Color.lerp(
      widget.inactiveColor,
      widget.activeColor,
      proximity,
    )!;
    final lift = -3.0 * proximity; // 떠오름
    final iconScale = 1 + 0.12 * proximity; // 확대
    final selected = proximity > 0.5;

    return SizedBox(
      width: itemW,
      child: GestureDetector(
        onTap: () => _tap(i),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Transform.translate(
              offset: Offset(0, lift),
              child: Transform.scale(
                scale: iconScale,
                child: Icon(
                  selected ? item.activeIcon : item.icon,
                  color: color,
                  size: 25,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 11,
                height: 1,
                color: color,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
