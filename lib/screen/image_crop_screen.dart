import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import '../models/community.dart' show kPostImageAspectRatio;

/// 갤러리 사진을 게시 표시 비율(3:4)에 맞게 "보여질 영역"을 고르는 화면.
///
/// 원본 사진은 전체가 보이도록(contain) **고정**해두고, 그 위에서 **3:4 크롭 틀이 이동·확대/축소**한다.
/// 사용자가 틀을 원하는 위치/크기로 맞추면(direct manipulation) 그 영역만 잘라 3:4 바이트로 돌려준다.
/// 반환: 크롭된 PNG [Uint8List] (취소 시 null).
class ImageCropScreen extends StatefulWidget {
  final Uint8List bytes;
  const ImageCropScreen({super.key, required this.bytes});

  @override
  State<ImageCropScreen> createState() => _ImageCropScreenState();
}

class _ImageCropScreenState extends State<ImageCropScreen> {
  static const double _frameAR = kPostImageAspectRatio; // 틀의 가로/세로 비

  ui.Image? _img;
  bool _saving = false;

  Size? _avail; // 제스처 영역 크기
  Rect _imageRect = Rect.zero; // contain 으로 그려진 원본 위치(고정)
  Rect _frame = Rect.zero; // 3:4 크롭 틀(이동/크기조절 대상)

  // 제스처 시작 스냅샷
  Rect _startFrame = Rect.zero;
  Offset _startFocal = Offset.zero;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    final codec = await ui.instantiateImageCodec(widget.bytes);
    final frame = await codec.getNextFrame();
    if (!mounted) return;
    setState(() => _img = frame.image);
  }

  /// 영역 크기가 정해지면 원본을 contain 배치하고, 그 안에 가장 큰 3:4 틀을 중앙 배치.
  void _initLayout(Size avail) {
    if (_img == null || _avail == avail) return;
    _avail = avail;
    final iw = _img!.width.toDouble();
    final ih = _img!.height.toDouble();
    final imgAR = iw / ih;
    final availAR = avail.width / avail.height;
    double dispW, dispH;
    if (imgAR > availAR) {
      dispW = avail.width;
      dispH = dispW / imgAR;
    } else {
      dispH = avail.height;
      dispW = dispH * imgAR;
    }
    _imageRect = Rect.fromLTWH(
      (avail.width - dispW) / 2,
      (avail.height - dispH) / 2,
      dispW,
      dispH,
    );
    // 원본 안에 들어가는 가장 큰 3:4 틀.
    double fw = dispW, fh = fw / _frameAR;
    if (fh > dispH) {
      fh = dispH;
      fw = fh * _frameAR;
    }
    _frame = Rect.fromCenter(center: _imageRect.center, width: fw, height: fh);
  }

  double get _maxW {
    final byH = _imageRect.height * _frameAR;
    return byH < _imageRect.width ? byH : _imageRect.width;
  }

  Rect _clampInside(Rect f) {
    var left = f.left.clamp(_imageRect.left, _imageRect.right - f.width);
    var top = f.top.clamp(_imageRect.top, _imageRect.bottom - f.height);
    return Rect.fromLTWH(left, top, f.width, f.height);
  }

  void _onScaleStart(ScaleStartDetails d) {
    _startFrame = _frame;
    _startFocal = d.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_img == null) return;
    Rect next;
    if (d.pointerCount >= 2) {
      // 핀치: 중심 고정한 채 크기 조절(3:4 유지).
      final minW = _maxW * 0.3;
      final w = (_startFrame.width * d.scale).clamp(minW, _maxW);
      next = Rect.fromCenter(
        center: _startFrame.center,
        width: w,
        height: w / _frameAR,
      );
    } else {
      // 드래그: 위치 이동.
      next = _startFrame.shift(d.localFocalPoint - _startFocal);
    }
    setState(() => _frame = _clampInside(next));
  }

  Future<void> _confirm() async {
    if (_img == null || _imageRect.width <= 0) return;
    setState(() => _saving = true);
    try {
      // 표시(논리) → 원본 픽셀 매핑.
      final s = _img!.width / _imageRect.width;
      final srcL = (_frame.left - _imageRect.left) * s;
      final srcT = (_frame.top - _imageRect.top) * s;
      final srcW = _frame.width * s;
      final srcH = _frame.height * s;

      final outW = srcW.round().clamp(1, 1600);
      final outH = (outW / _frameAR).round();

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        _img!,
        Rect.fromLTWH(srcL, srcT, srcW, srcH),
        Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
      final out = await recorder.endRecording().toImage(outW, outH);
      final data = await out.toByteData(format: ui.ImageByteFormat.png);
      if (!mounted) return;
      if (data == null) {
        setState(() => _saving = false);
        return;
      }
      Navigator.pop(context, data.buffer.asUint8List());
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('이미지 처리에 실패했어요'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('보여질 영역 조정'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _img == null ? null : _confirm,
              child: Text(
                '완료',
                style: TextStyle(
                  color: context.colors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(
                builder: (context, c) {
                  final avail = Size(c.maxWidth, c.maxHeight);
                  _initLayout(avail);
                  if (_img == null) {
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  }
                  return GestureDetector(
                    onScaleStart: _onScaleStart,
                    onScaleUpdate: _onScaleUpdate,
                    child: SizedBox(
                      width: avail.width,
                      height: avail.height,
                      child: Stack(
                        children: [
                          // 원본(고정, 전체 표시)
                          Positioned.fromRect(
                            rect: _imageRect,
                            child: RawImage(image: _img, fit: BoxFit.fill),
                          ),
                          // 틀 밖 어둡게 + 3:4 틀 + 가이드
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: _FramePainter(frame: _frame),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Text(
              '3:4 틀을 끌어서 옮기고, 손가락을 벌려 크기를 조절하세요',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// 크롭 틀: 바깥 스크림 + 흰 테두리 + 3분할 가이드.
class _FramePainter extends CustomPainter {
  final Rect frame;
  _FramePainter({required this.frame});

  @override
  void paint(Canvas canvas, Size size) {
    // 바깥 어둡게(evenOdd 로 틀 영역만 비움)
    final scrim = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(frame, const Radius.circular(8)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(
      scrim,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    // 틀 테두리
    canvas.drawRRect(
      RRect.fromRectAndRadius(frame, const Radius.circular(8)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white,
    );

    // 3분할 가이드
    final guide = Paint()
      ..color = Colors.white54
      ..strokeWidth = 0.5;
    for (var i = 1; i < 3; i++) {
      final dx = frame.left + frame.width * i / 3;
      final dy = frame.top + frame.height * i / 3;
      canvas.drawLine(Offset(dx, frame.top), Offset(dx, frame.bottom), guide);
      canvas.drawLine(Offset(frame.left, dy), Offset(frame.right, dy), guide);
    }
  }

  @override
  bool shouldRepaint(covariant _FramePainter old) => old.frame != frame;
}
