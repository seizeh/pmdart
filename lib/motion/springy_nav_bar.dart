import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_motion.dart';
import '../theme/app_palette.dart';

class SpringyNavItem {
  const SpringyNavItem({required this.icon, IconData? activeIcon})
    : activeIcon = activeIcon ?? icon;
  final IconData icon;
  final IconData activeIcon;
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
    this.activeColor,
    this.inactiveColor,
    this.pillColor,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<SpringyNavItem> items;

  /// null 이면 테마 팔레트([AppPalette])에서 가져온다.
  final Color? activeColor;
  final Color? inactiveColor;
  final Color? pillColor;

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
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    // 화면 가장자리에서 띄운 둥근 직사각형 바 — 네 모서리 모두 동일 곡률(24,
    // 상단 헤더 패널과 통일). SafeArea 대신 하단 여백으로 홈 인디케이터를 피한다.
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 0, 12, bottomInset + 8),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          // 셀로판지(반투명) — 뒤 콘텐츠가 선명하게 비치며 덮인다(상단 헤더와 동일 효과).
          color: context.colors.frostFilm,
          borderRadius: const BorderRadius.all(Radius.circular(24)),
          // 하드 보더 대신 부드럽게 번지는 그림자로 본문과 분리.
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 24,
              offset: Offset(0, 6),
            ),
          ],
        ),
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
                  // 아이콘 단독 구성 — 알약도 원에 가깝게(앱 전반의 둥근 무드).
                  const pillW = 52.0;
                  const pillH = 42.0;
                  final pillCenterX = (pos + 0.5) * itemW;

                  final pill =
                      widget.pillColor ??
                      context.colors.primaryDark.withValues(alpha: 0.08);
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
                              color: pill,
                              borderRadius: BorderRadius.circular(21),
                            ),
                          ),
                        ),
                      ),
                      // 아이콘 (라벨 없음 — 아이콘이 곧 아이덴티티)
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
      widget.inactiveColor ?? context.colors.textTertiary,
      widget.activeColor ?? context.colors.primaryDark,
      proximity,
    )!;
    final lift = -1.5 * proximity; // 떠오름(라벨이 없어 과하지 않게)
    final iconScale = 1 + 0.16 * proximity; // 확대 — 아이콘이 곧 상태 표시
    final selected = proximity > 0.5;

    return SizedBox(
      width: itemW,
      child: GestureDetector(
        onTap: () => _tap(i),
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: Transform.translate(
            offset: Offset(0, lift),
            child: Transform.scale(
              scale: iconScale,
              child: Icon(
                selected ? item.activeIcon : item.icon,
                color: color,
                size: 26,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
