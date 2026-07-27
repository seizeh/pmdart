import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_palette.dart';
import 'app_motion.dart';

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
///
/// [axis] 로 세로(좌측 레일) 구성도 만든다 — 넓은 화면(데스크톱 웹)에서 쓰며,
/// 스프링·스쿼시·근접 보간은 **같은 코드**를 탄다. 바뀌는 건 진행 축뿐이라
/// 두 형태가 영원히 같은 모션 언어를 유지한다.
class SpringyNavBar extends StatefulWidget {
  const SpringyNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
    this.axis = Axis.horizontal,
    this.activeColor,
    this.inactiveColor,
    this.pillColor,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<SpringyNavItem> items;

  /// 가로 = 하단 바(기본), 세로 = 좌측 레일.
  final Axis axis;

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

  /// 바 두께 — 가로면 높이, 세로면 너비.
  static const double _thickness = 62.0;

  @override
  Widget build(BuildContext context) {
    final vertical = widget.axis == Axis.vertical;
    final n = widget.items.length;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    // 화면 가장자리에서 띄운 둥근 직사각형 바 — 네 모서리 모두 동일 곡률(24,
    // 상단 헤더 패널과 통일). SafeArea 대신 하단 여백으로 홈 인디케이터를 피한다.
    return Padding(
      padding: vertical
          ? const EdgeInsets.fromLTRB(12, 8, 8, 8)
          : EdgeInsets.fromLTRB(12, 0, 12, bottomInset + 8),
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
        // 세로 레일은 항목 수만큼 정확히 자란다(가로는 폭을 n 등분).
        child: vertical
            ? SizedBox(
                width: _thickness,
                height: _thickness * n,
                child: _track(n, _thickness),
              )
            : SizedBox(
                height: _thickness,
                child: LayoutBuilder(
                  builder: (context, constraints) =>
                      _track(n, constraints.maxWidth / n),
                ),
              ),
      ),
    );
  }

  /// 알약 + 아이콘 — 가로/세로 공용. [itemExtent] 는 진행 축 방향의 항목 크기.
  Widget _track(int n, double itemExtent) {
    final vertical = widget.axis == Axis.vertical;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final pos = _c.value; // 연속 위치
        // 이동 속도로 알약을 진행 방향으로 늘림(스쿼시 & 스트레치).
        final v = _c.velocity;
        final stretch = (v.abs() * 0.04).clamp(0.0, 0.22);
        // 아이콘 단독 구성 — 알약도 원에 가깝게(앱 전반의 둥근 무드).
        // 세로 레일에서는 같은 알약을 90° 돌려 진행 축을 따르게 한다.
        final pillW = vertical ? 42.0 : 52.0;
        final pillH = vertical ? 52.0 : 42.0;
        final pillCenter = (pos + 0.5) * itemExtent;

        final pill =
            widget.pillColor ??
            context.colors.primaryDark.withValues(alpha: 0.08);
        return Stack(
          children: [
            // 흐르는 알약 인디케이터
            Positioned(
              top: vertical ? pillCenter - pillH / 2 : (_thickness - pillH) / 2,
              left: vertical
                  ? (_thickness - pillW) / 2
                  : pillCenter - pillW / 2,
              child: Transform.scale(
                // 늘어남은 언제나 진행 축, 수축은 그 직교 축.
                scaleX: vertical ? 1 - stretch * 0.6 : 1 + stretch,
                scaleY: vertical ? 1 + stretch : 1 - stretch * 0.6,
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
            if (vertical)
              Column(
                children: [
                  for (var i = 0; i < n; i++) _buildItem(i, pos, itemExtent),
                ],
              )
            else
              Row(
                children: [
                  for (var i = 0; i < n; i++) _buildItem(i, pos, itemExtent),
                ],
              ),
          ],
        );
      },
    );
  }

  Widget _buildItem(int i, double pos, double itemExtent) {
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
    final vertical = widget.axis == Axis.vertical;

    return SizedBox(
      // 진행 축은 itemExtent, 직교 축은 바 두께.
      width: vertical ? _thickness : itemExtent,
      height: vertical ? itemExtent : _thickness,
      child: GestureDetector(
        onTap: () => _tap(i),
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: Transform.translate(
            // 떠오름도 바 안쪽(직교 축) 방향으로 — 세로 레일은 왼쪽으로.
            offset: vertical ? Offset(lift, 0) : Offset(0, lift),
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
