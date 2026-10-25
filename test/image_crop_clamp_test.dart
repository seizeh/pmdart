import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/screen/image_crop_screen.dart';
import 'package:pawmate/theme/app_theme.dart';

/// 사진 크롭 화면 드래그 회귀 가드.
///
/// 실제 사고(2026-10-25, iOS): 3:4 보다 넓은 사진(가로·정사각형)은 크롭 틀 높이가
/// 사진 높이와 같다. 그러면 `top.clamp(사진 위, 사진 아래 - 틀 높이)` 의 하한·상한이
/// 이론상 같은데, 부동소수점 오차로 상한이 하한보다 아주 조금 작아지는 배치가 있다
/// — `clamp` 는 그때 ArgumentError 를 던지고, 드래그 프레임마다 던져 1초에 30건이
/// 보고됐다(flutter.gesture). 던진 프레임엔 틀도 안 움직인다.
void main() {
  Future<Uint8List> png(int w, int h) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = const Color(0xFF3366FF),
    );
    final image = await recorder.endRecording().toImage(w, h);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  Rect frameOf(WidgetTester tester) {
    final paint = tester.widget<CustomPaint>(
      find.descendant(
        of: find.byType(ImageCropScreen),
        matching: find.byWidgetPredicate(
          (w) =>
              w is CustomPaint &&
              w.painter.runtimeType.toString() == '_FramePainter',
        ),
      ),
    );
    return (paint.painter as dynamic).frame as Rect;
  }

  for (final (w, h) in [(4, 3), (1, 1), (16, 9)]) {
    testWidgets('$w:$h 사진 — 화면 크기가 달라도 드래그에서 예외 없이 틀이 움직인다', (tester) async {
      final bytes = (await tester.runAsync(() => png(w * 40, h * 40)))!;
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 3;

      // 기기마다 남는 영역 높이가 달라 오차 방향도 달라진다 — 여러 높이를 훑는다.
      final failures = <String>[];
      for (var i = 0; i < 24; i++) {
        final logical = Size(393, 700 + i * 7.37);
        tester.view.physicalSize = logical * 3;
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey(i),
            theme: AppTheme.light(),
            home: ImageCropScreen(bytes: bytes),
          ),
        );
        // 디코딩은 실제 비동기 — 끝날 때까지 기다린다.
        for (
          var k = 0;
          k < 50 && find.byType(RawImage).evaluate().isEmpty;
          k++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(find.byType(RawImage), findsOneWidget);

        final before = frameOf(tester);
        // 틀을 살짝 줄여 둔 게 아니라 초기(최대) 틀 그대로 — 사고 조건.
        final g = await tester.startGesture(
          before.center + const Offset(16, 80),
        );
        await g.moveBy(const Offset(-20, 0)); // 슬롭 통과
        Object? error;
        for (var k = 0; k < 60 && error == null; k++) {
          await g.moveBy(const Offset(-1 / 3, 1 / 6)); // iOS 1/3pt 해상도
          await tester.pump();
          error = tester.takeException();
        }
        await g.up();
        await tester.pump();
        if (error != null) {
          failures.add('${logical.height}: $error');
        } else if (!(frameOf(tester).left < before.left)) {
          failures.add('${logical.height}: 틀이 안 움직임');
        }
      }
      expect(failures, isEmpty);
    });
  }
}
