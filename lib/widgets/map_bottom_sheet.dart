import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// 지도 위에 안전하게 띄우는 커스텀 바텀시트.
///
/// `MapTab.showSheetOverMap` 이 **라이브 네이버 지도 위에 바로** 이 시트를 올린다.
/// 과거엔 "PlatformView 위 모달은 합성 충돌로 깨진다"고 보고 지도를 스냅샷으로 얼려
/// 우회했지만, 실제 원인은 본문의 **무한 너비** 버그였다(pmdart #28). 그건 이 시트가
/// 본문 폭을 `Align>SizedBox(화면폭)` 로 유한 고정해 해결한다(텍스트 줄바꿈/Expanded 정상).
///
/// 따라서 지도를 트리에서 빼거나 스냅샷으로 덮을 필요가 없다 → **닫아도 지도 재생성/재로딩
/// 없음**(#29 후속, 실기기 검증). 스크림이 라이브 지도를 어둡게 덮어 진짜 바텀시트처럼 보인다.
/// 본문엔 `Expanded`/`Spacer`/머티리얼 위젯 모두 안전.
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
        .animateTo(
          0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeIn,
        )
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
      _slide.animateTo(
        1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final w = media.size.width;
    final available = (media.size.height - media.viewInsets.bottom).clamp(
      0.0,
      media.size.height,
    );
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
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.4 * t),
                ),
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
            color: Color(0x22000000),
            blurRadius: 16,
            offset: Offset(0, -2),
          ),
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
            // 지도 탭은 MainScreen extendBody 로 하단 바 뒤까지 확장되므로, 키보드가 없을 때
            // 하단 바 위로 살짝만 올라오게 여백을 준다(리스트 자체 하단 패딩이 버퍼 역할).
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom > 0
                      ? 0
                      : 1 + MediaQuery.of(context).padding.bottom,
                ),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(width: w, child: widget.child),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
