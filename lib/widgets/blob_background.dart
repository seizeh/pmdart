import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../theme/app_palette.dart';

/// 사진 없는 게시글의 뿌연 색 배경 — 카테고리 색 블롭들을 강하게 블러시킨
/// 아웃포커스 필드. [seed](게시글 id 등)로 블롭의 개수·위치·크기·색을
/// 결정하므로 글마다 패턴이 다르되, 같은 글은 항상 같은 패턴을 유지한다.
/// 베이스는 흰색 대신 앱의 크림 톤(+카테고리 틴트)이라 눈이 편하다.
class BlobBackground extends StatelessWidget {
  final Object seed;
  final Color color;
  const BlobBackground({super.key, required this.seed, required this.color});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        final rnd = math.Random(seed.hashCode);

        // 채도 부스트 — 무채색 계열 카테고리(자유 등)도 알록달록하게.
        final raw = HSLColor.fromColor(color);
        final hsl = raw
            .withSaturation(math.max(raw.saturation, 0.55))
            .withLightness(raw.lightness.clamp(0.55, 0.75));
        final boosted = hsl.toColor();

        // 부스트된 카테고리 색 + 색상환에서 살짝 비튼 변주 + 브랜드 골드.
        Color shift(double deg) =>
            hsl.withHue((hsl.hue + deg + 360) % 360).toColor();
        final palette = [
          boosted,
          boosted,
          shift(28),
          shift(-28),
          context.colors.primarySoft,
        ];

        final count = 3 + rnd.nextInt(3); // 3~5개
        final blobs = List.generate(count, (_) {
          final size = (0.45 + rnd.nextDouble() * 0.55) * math.max(w, h);
          return _Blob(
            left: (rnd.nextDouble() * 1.2 - 0.35) * w,
            top: (rnd.nextDouble() * 1.2 - 0.35) * h,
            size: size,
            color: palette[rnd.nextInt(palette.length)].withValues(
              alpha: 0.35 + rnd.nextDouble() * 0.3,
            ),
          );
        });

        return Stack(
          fit: StackFit.expand,
          children: [
            // 크림 베이스 + 카테고리 틴트 — 순백보다 눈이 편한 바탕.
            ColoredBox(
              color: Color.alphaBlend(
                boosted.withValues(alpha: 0.10),
                context.colors.cream,
              ),
            ),
            ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 42, sigmaY: 42),
              child: Stack(
                children: [
                  for (final b in blobs)
                    Positioned(
                      left: b.left,
                      top: b.top,
                      child: Container(
                        width: b.size,
                        height: b.size,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: b.color,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Blob {
  final double left;
  final double top;
  final double size;
  final Color color;
  const _Blob({
    required this.left,
    required this.top,
    required this.size,
    required this.color,
  });
}
