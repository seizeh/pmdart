import 'package:flutter/material.dart';
import '../theme/app_palette.dart';

/// PawMate 로고: 핀(눈물방울) 모양 안에 흰 원 + 발자국.
/// 첫 번째 레퍼런스 이미지의 로고를 CustomPaint 로 구현.
class PawMateLogo extends StatelessWidget {
  final double size;
  final bool showText;
  final Color? pinColor;

  const PawMateLogo({
    super.key,
    this.size = 96,
    this.showText = false,
    this.pinColor,
  });

  @override
  Widget build(BuildContext context) {
    final pawColor = context.colors.primaryDark;
    final pin = pinColor ?? context.colors.primary;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size * 1.18,
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              CustomPaint(
                size: Size(size, size * 1.18),
                painter: _PinPainter(color: pin),
              ),
              Positioned(
                top: size * 0.16,
                child: Container(
                  width: size * 0.62,
                  height: size * 0.62,
                  decoration: BoxDecoration(
                    color: context.colors.cream,
                    shape: BoxShape.circle,
                  ),
                  child: CustomPaint(
                    painter: _PawPrintPainter(color: pawColor),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showText) ...[
          SizedBox(height: size * 0.18),
          Text(
            'PawMate',
            style: TextStyle(
              fontSize: size * 0.30,
              fontWeight: FontWeight.w700,
              color: context.colors.primaryDark,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ],
    );
  }
}

/// 핀(눈물방울) 외곽 — 원 + 아래쪽 삼각형 결합.
class _PinPainter extends CustomPainter {
  final Color color;
  _PinPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final w = size.width;
    final cx = w / 2;
    final headRadius = w * 0.48;
    final headCenterY = w * 0.5;

    final path = Path()
      ..addOval(
        Rect.fromCircle(center: Offset(cx, headCenterY), radius: headRadius),
      )
      ..moveTo(cx - w * 0.22, headCenterY + headRadius * 0.7)
      ..quadraticBezierTo(
        cx,
        size.height + 4,
        cx + w * 0.22,
        headCenterY + headRadius * 0.7,
      )
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// 발자국 — 패드 1개 + 발가락 4개.
class _PawPrintPainter extends CustomPainter {
  final Color color;
  _PawPrintPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final w = size.width;
    final h = size.height;

    // 메인 패드 — 중앙 하단의 둥근 사다리꼴 (타원으로 표현)
    final padRect = Rect.fromCenter(
      center: Offset(w * 0.5, h * 0.66),
      width: w * 0.52,
      height: h * 0.42,
    );
    canvas.drawOval(padRect, paint);

    // 발가락 — 4개 타원 (위쪽 2개 / 양옆 2개)
    final toes = <Rect>[
      Rect.fromCenter(
        center: Offset(w * 0.30, h * 0.32),
        width: w * 0.18,
        height: h * 0.22,
      ),
      Rect.fromCenter(
        center: Offset(w * 0.70, h * 0.32),
        width: w * 0.18,
        height: h * 0.22,
      ),
      Rect.fromCenter(
        center: Offset(w * 0.16, h * 0.50),
        width: w * 0.16,
        height: h * 0.20,
      ),
      Rect.fromCenter(
        center: Offset(w * 0.84, h * 0.50),
        width: w * 0.16,
        height: h * 0.20,
      ),
    ];
    for (final t in toes) {
      canvas.drawOval(t, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
