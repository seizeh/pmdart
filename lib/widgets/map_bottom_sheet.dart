import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// 지도 위에 안전하게 띄우는 커스텀 바텀시트.
///
/// 살아있는 네이버 지도(PlatformView) 위에 `showModalBottomSheet`/
/// `DraggableScrollableSheet` 를 겹치면 합성·hit-test 충돌로 깨진다(pmdart #28). 그래서
/// `MapTab.showSheetOverMap` 이 지도를 **스냅샷 이미지로 얼린 뒤** 이 시트를 그 위에 올린다
/// (라이브 PlatformView 가 시트 밑에서 빠짐 → 안전).
///
/// 스냅샷-스왑이라 시트 밑엔 PlatformView 가 없어 본문은 **평범한 위젯 트리** —
/// `Expanded`/`Spacer`/머티리얼 위젯 모두 안전하다. 폭은 이 시트가 `Align>SizedBox(화면폭)`
/// 로 유한하게 고정해 준다(텍스트 줄바꿈/Expanded 정상).
class MapBottomSheet extends StatefulWidget {
  final Widget child;
  final VoidCallback onClose;

  /// 화면 높이 대비 시트 높이(0~1).
  final double heightFactor;
  const MapBottomSheet({
    super.key,
    required this.child,
    required this.onClose,
    this.heightFactor = 0.6,
  });

  @override
  State<MapBottomSheet> createState() => _MapBottomSheetState();
}

class _MapBottomSheetState extends State<MapBottomSheet>
    with SingleTickerProviderStateMixin {
  // 0 = 화면 아래로 숨음, 1 = 완전히 올라옴.
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
    value: 0,
  );
  double _panelH = 0;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _slide.forward();
  }

  @override
  void dispose() {
    _slide.dispose();
    super.dispose();
  }

  void _dismiss() {
    if (_closing) return;
    _closing = true;
    _slide
        .animateTo(0,
            duration: const Duration(milliseconds: 220), curve: Curves.easeIn)
        .whenComplete(() {
      if (mounted) widget.onClose();
    });
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_panelH <= 0) return;
    final dy = (1 - _slide.value) * _panelH + d.delta.dy;
    _slide.value = (1 - dy / _panelH).clamp(0.0, 1.0);
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.velocity.pixelsPerSecond.dy;
    if (_slide.value < 0.6 || v > 700) {
      _dismiss();
    } else {
      _slide.animateTo(1,
          duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final w = media.size.width;
    final available = (media.size.height - media.viewInsets.bottom)
        .clamp(0.0, media.size.height);
    final h = (available * widget.heightFactor).clamp(0.0, available);
    _panelH = h;

    return AnimatedBuilder(
      animation: _slide,
      builder: (ctx, _) {
        final t = _slide.value;
        return Stack(
          children: [
            // 스크림 — 바깥 탭 → 닫기.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _dismiss,
                child:
                    ColoredBox(color: Colors.black.withValues(alpha: 0.4 * t)),
              ),
            ),
            // 패널(아래 고정, 키보드 위로). bottom 값을 애니메이션해 서랍처럼 슬라이드
            // (Transform 레이어는 플랫폼뷰/스냅샷 위에서 합성 이슈가 있어 피함).
            Positioned(
              left: 0,
              width: w,
              height: h,
              bottom: media.viewInsets.bottom - (1 - t) * h,
              child: _panel(w),
            ),
          ],
        );
      },
    );
  }

  Widget _panel(double w) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
              color: Color(0x22000000), blurRadius: 16, offset: Offset(0, -2)),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            // 손잡이 — 아래로 쓸어내리면 닫힘.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: _onDragUpdate,
              onVerticalDragEnd: _onDragEnd,
              child: Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
            ),
            // 본문 — Align 이 제약을 loosen, SizedBox 가 폭을 화면폭으로 고정(#28 우회).
            Expanded(
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(width: w, child: widget.child),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
