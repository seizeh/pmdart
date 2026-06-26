import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../models/community.dart' show kPostImageAspectRatio;

/// 갤러리 사진을 게시 표시 비율(3:4)에 맞게 "보여질 영역"을 직접 조정(팬·핀치줌)하는 화면.
///
/// 원본 비율이 표시 프레임과 달라 [BoxFit.cover] 가 중앙만 보여주는 문제를 해결한다.
/// 사용자가 프레임 안에서 이미지를 직접 끌고 확대해(direct manipulation) 원하는 부분을 맞추면,
/// 그 영역만 잘라 3:4 바이트로 돌려준다(표시 로직 변경 없이 어디서나 정확히 보임).
/// 반환: 크롭된 PNG [Uint8List] (취소 시 null).
class ImageCropScreen extends StatefulWidget {
  final Uint8List bytes;
  const ImageCropScreen({super.key, required this.bytes});

  @override
  State<ImageCropScreen> createState() => _ImageCropScreenState();
}

class _ImageCropScreenState extends State<ImageCropScreen> {
  ui.Image? _img; // 디코드된 원본(크롭 소스)
  bool _saving = false;

  // 표시 모델: _scale = 원본 1px 당 논리 px, _offset = 뷰포트 좌상단 기준 이미지 좌상단 위치.
  double _scale = 1;
  Offset _offset = Offset.zero;
  double _minScale = 1;

  // 제스처 시작 스냅샷.
  double _startScale = 1;
  Offset _startOffset = Offset.zero;

  Size? _viewport;

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

  /// 뷰포트가 정해지면 cover 기준으로 초기 배치.
  void _initLayout(Size vp) {
    if (_viewport == vp || _img == null) return;
    _viewport = vp;
    final iw = _img!.width.toDouble();
    final ih = _img!.height.toDouble();
    _minScale = (vp.width / iw) > (vp.height / ih)
        ? vp.width / iw
        : vp.height / ih; // cover
    _scale = _minScale;
    // 중앙 정렬
    _offset = Offset(
      (vp.width - iw * _scale) / 2,
      (vp.height - ih * _scale) / 2,
    );
  }

  Offset _clampOffset(Offset o, double scale) {
    final vp = _viewport!;
    final dw = _img!.width * scale;
    final dh = _img!.height * scale;
    // 뷰포트가 항상 이미지 안에 있도록(빈 여백 금지).
    final minX = vp.width - dw;
    final minY = vp.height - dh;
    return Offset(
      o.dx.clamp(minX <= 0 ? minX : 0.0, 0.0),
      o.dy.clamp(minY <= 0 ? minY : 0.0, 0.0),
    );
  }

  void _onScaleStart(ScaleStartDetails d) {
    _startScale = _scale;
    _startOffset = _offset;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final newScale = (_startScale * d.scale).clamp(_minScale, _minScale * 5);
    // focal 아래의 이미지 점이 그대로 focal 아래 머물도록(팬+줌 결합).
    final focal = d.localFocalPoint;
    final imagePt = (focal - _startOffset) / _startScale;
    final newOffset = focal - imagePt * newScale;
    setState(() {
      _scale = newScale;
      _offset = _clampOffset(newOffset, newScale);
    });
  }

  Future<void> _confirm() async {
    if (_img == null || _viewport == null) return;
    setState(() => _saving = true);
    try {
      final vp = _viewport!;
      // 뷰포트(논리) → 원본 픽셀 영역.
      final srcL = -_offset.dx / _scale;
      final srcT = -_offset.dy / _scale;
      final srcW = vp.width / _scale;
      final srcH = vp.height / _scale;

      // 출력: 3:4 유지, 가로 최대 1600.
      final outW = srcW.round().clamp(1, 1600);
      final outH = (outW / kPostImageAspectRatio).round();

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final paint = Paint()..filterQuality = FilterQuality.high;
      canvas.drawImageRect(
        _img!,
        Rect.fromLTWH(srcL, srcT, srcW, srcH),
        Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
        paint,
      );
      final picture = recorder.endRecording();
      final out = await picture.toImage(outW, outH);
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
            behavior: SnackBarBehavior.floating),
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
                        strokeWidth: 2, color: Colors.white)),
              ),
            )
          else
            TextButton(
              onPressed: _img == null ? null : _confirm,
              child: const Text('완료',
                  style: TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: AspectRatio(
                  aspectRatio: kPostImageAspectRatio,
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final vp = Size(c.maxWidth, c.maxHeight);
                      _initLayout(vp);
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: _img == null
                            ? const ColoredBox(color: Colors.white10)
                            : GestureDetector(
                                onScaleStart: _onScaleStart,
                                onScaleUpdate: _onScaleUpdate,
                                child: Stack(
                                  children: [
                                    Positioned(
                                      left: _offset.dx,
                                      top: _offset.dy,
                                      width: _img!.width * _scale,
                                      height: _img!.height * _scale,
                                      child: RawImage(
                                          image: _img, fit: BoxFit.fill),
                                    ),
                                    // 3분할 가이드 — 구도 잡기 보조(hierarchy).
                                    const Positioned.fill(
                                      child: IgnorePointer(
                                          child: _GridGuide()),
                                    ),
                                  ],
                                ),
                              ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: Text(
              '끌어서 위치를 옮기고, 손가락을 벌려 확대해 보여질 부분을 맞춰주세요',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// 3분할(rule of thirds) 가이드 라인.
class _GridGuide extends StatelessWidget {
  const _GridGuide();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _GridPainter());
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white24
      ..strokeWidth = 0.5;
    for (var i = 1; i < 3; i++) {
      final dx = size.width * i / 3;
      final dy = size.height * i / 3;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), p);
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
