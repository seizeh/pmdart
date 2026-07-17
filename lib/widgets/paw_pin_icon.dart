import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// 브랜드 발바닥 핀 아이콘 — 로고(IMG_3) 실루엣을 벡터로 그린다.
///
/// PNG(ImageIcon) 방식은 GPU 텍스처 쿼드 가장자리에 헤어라인이 비치는
/// 아티팩트가 있어(에뮬레이터 Impeller), 아이콘은 패스로 직접 그린다 —
/// 어떤 크기·색에서도 선명하고 텍스처 계열 문제가 없다.
class PawPinIcon extends StatelessWidget {
  final double size;
  final Color color;
  const PawPinIcon({super.key, required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _PawPinPainter(color),
    );
  }
}

class _PawPinPainter extends CustomPainter {
  final Color color;
  const _PawPinPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    Offset p(double x, double y) => Offset(x * s, y * s);
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;

    // ── 핀 몸통: 하단 55°~125° 구간만 비운 원호 + 팁으로 떨어지는 베지어 ──
    const cx = 0.5, cy = 0.40, r = 0.36;
    double rad(double deg) => deg * math.pi / 180;
    Offset onCircle(double deg) =>
        p(cx + r * math.cos(rad(deg)), cy + r * math.sin(rad(deg)));
    final rect = Rect.fromCircle(center: p(cx, cy), radius: r * s);
    final leftAttach = onCircle(125); // 좌하단 접점(원호 시작·꼬리 복귀점)
    var pin = Path()
      // 125° → (180° → 270° → 0°) → 55° : 하단 틈만 남기고 크게 도는 원호
      ..moveTo(leftAttach.dx, leftAttach.dy)
      ..arcTo(rect, rad(125), rad(290), false)
      // 우하단 접점 → 팁 → 좌하단 접점 (곡선 꼬리)
      ..quadraticBezierTo(0.660 * s, 0.870 * s, 0.5 * s, 0.975 * s)
      ..quadraticBezierTo(0.340 * s, 0.870 * s, leftAttach.dx, leftAttach.dy)
      ..close();
    // 내부 원형 컷아웃(발바닥이 앉는 자리).
    final hole = Path()
      ..addOval(Rect.fromCircle(center: p(cx, cy), radius: 0.28 * s));
    pin = Path.combine(PathOperation.difference, pin, hole);
    canvas.drawPath(pin, paint);

    // ── 발바닥: 발가락 4개 + 메인 패드 ──
    final paw = Path();
    // 발가락(바깥 두 개는 살짝 기울임): (cx, cy, w, h, 회전)
    const toes = [
      (0.385, 0.290, 0.090, 0.122, -0.45),
      (0.458, 0.243, 0.088, 0.122, -0.12),
      (0.548, 0.246, 0.088, 0.122, 0.18),
      (0.620, 0.305, 0.090, 0.118, 0.50),
    ];
    for (final (tx, ty, tw, th, rot) in toes) {
      final m = Matrix4.identity()
        ..translateByDouble(tx * s, ty * s, 0, 1)
        ..rotateZ(rot);
      paw.addPath(
        Path()..addOval(
          Rect.fromCenter(
            center: Offset.zero,
            width: tw * s,
            height: th * s,
          ),
        ),
        Offset.zero,
        matrix4: m.storage,
      );
    }
    // 메인 패드 — 위가 둥글고 아래로 살짝 퍼지는 빵 모양(베지어).
    final pad = Path()
      ..moveTo(0.50 * s, 0.345 * s)
      ..cubicTo(0.585 * s, 0.345 * s, 0.640 * s, 0.415 * s, 0.635 * s, 0.475 * s)
      ..cubicTo(0.630 * s, 0.535 * s, 0.565 * s, 0.545 * s, 0.50 * s, 0.545 * s)
      ..cubicTo(0.435 * s, 0.545 * s, 0.370 * s, 0.535 * s, 0.365 * s, 0.475 * s)
      ..cubicTo(0.360 * s, 0.415 * s, 0.415 * s, 0.345 * s, 0.50 * s, 0.345 * s)
      ..close();
    paw.addPath(pad, Offset.zero);
    canvas.drawPath(paw, paint);
  }

  @override
  bool shouldRepaint(_PawPinPainter old) => old.color != color;
}
