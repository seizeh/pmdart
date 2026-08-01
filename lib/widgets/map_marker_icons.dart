import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:http/http.dart' as http;

import '../services/error_reporter.dart';
import '../services/facility_repository.dart';

/// 지도 마커 이미지 렌더러 — 캔버스에 그려 [NOverlayImage] 를 만든다.
///
/// `map_tab.dart` 에서 떼어냈다(#155). 이 코드가 화면 상태를 하나도 안 보기
/// 때문이다 — 지도 컨트롤러도, 위젯 트리도, `BuildContext` 도 필요 없고
/// 입력은 카테고리·다크모드 여부·평점뿐이다. 화면에 남아 있을 이유가 없었고,
/// 남아 있는 동안은 **테스트할 수도 없었다**(1,600줄 State 를 띄워야 하므로).
///
/// 캐시도 여기서 소유한다. 캐시 키가 곧 "무엇이 그림을 바꾸는가" 의 정의라
/// 렌더링과 같은 자리에 있어야 어긋나지 않는다.
class MapMarkerIcons {
  MapMarkerIcons({http.Client? httpClient}) : _http = httpClient;

  /// 업체 대표 사진을 받는 클라이언트. 테스트에서 갈아끼운다.
  final http.Client? _http;

  final Map<String, NOverlayImage?> _catIcons = {}; // 카테고리별
  final Map<String, NOverlayImage?> _bizIcons = {}; // 인증 업체별(사진 URL 기준)
  NOverlayImage? _searchIcon;

  // ── 색 ────────────────────────────────────────────────────────────────
  static const catAccent = Color(0xFFAC9466);
  static const markerIconLight = Color(0xFF5A4E38);
  static const markerIconDark = catAccent;
  static const markerShadow = Color(0x73000000);
  static const markerHaloLight = Colors.white;
  static const markerHaloDark = Color(0xFF1E1E1E);

  // ── 인증 마커 도형 ────────────────────────────────────────────────────
  // 캔버스 104px, 둥근 정사각형 84×84 r22.
  static const bizTarget = 104.0;
  static const bizBox = 84.0;
  static const bizRadius = 22.0;

  /// 평점 배지가 붙으면 캔버스가 아래로 길어진다(사진을 가리지 않게 프레임
  /// 바깥 하단에 알약을 그림). 앵커는 여전히 사진 중심(y=52)이어야 하므로
  /// 마커 생성부가 [bizRatingAnchor] 로 보정한다.
  static const bizRatingTarget = 140.0; // 104 + 배지 영역 36
  static const bizRatingAnchor = NPoint(0.5, (bizTarget / 2) / bizRatingTarget);

  /// 지도 마커 전용: 속이 채워진(filled) 변형으로 가독성↑. 단, 가위·침대는 채운
  /// 변형이 없거나 어색해 예외로 라인 아이콘 유지.
  static IconData markerIconForCat(String code) => switch (code) {
    'animal_hospital' => Icons.local_hospital,
    'grooming' => Icons.content_cut, // 예외(라인 유지)
    'pet_hotel' => Icons.hotel, // 예외(라인 유지)
    'pet_sales' => Icons.storefront,
    'pet_cafe' => Icons.local_cafe,
    'posts' => Icons.article,
    _ => Icons.place,
  };

  /// 카테고리 마커 아이콘(캐시). 인증 변형은 평점까지 별도 키 — 평점별로 배지가 다르다.
  Future<NOverlayImage?> categoryIcon(
    String category, {
    required bool dark,
    bool verified = false,
    String rating = '',
  }) async {
    final key = verified ? '$category|v|$rating' : category;
    if (_catIcons.containsKey(key)) return _catIcons[key];
    NOverlayImage? out;
    try {
      out = await renderMarkerIcon(
        category,
        dark ? markerIconDark : markerIconLight,
        verified: verified,
        dark: dark,
        rating: rating,
      );
    } catch (e) {
      ErrorReporter.ignored(
        e,
        where: 'map.categoryIcon',
        why: '카테고리 아이콘 렌더 실패 — 마커는 SDK 기본 아이콘으로 뜬다',
      );
      out = null;
    }
    _catIcons[key] = out;
    return out;
  }

  /// 인증 업체 마커 — 둥근 정사각형 안에 대표 사진(업체 프로필 얼굴).
  /// 사진이 없거나 로드 실패면 같은 실루엣의 글리프 폴백.
  ///
  /// 캐시 키는 사진 URL+초점+평점 기준 — 다중 카테고리(같은 업체의 형제 행)가
  /// 같은 사진을 행마다 다시 받아 렌더하지 않게. 사진 없으면 카테고리 기준.
  Future<NOverlayImage?> verifiedIcon(Facility f, {required bool dark}) async {
    final rating = f.avgRating > 0 ? f.avgRating.toStringAsFixed(1) : '';
    final key = f.ownerPhotoUrl != null
        ? 'p|${f.ownerPhotoUrl}|${f.ownerPhotoAlignY}|$rating'
        : 'g|${f.category}|$rating';
    if (_bizIcons.containsKey(key)) return _bizIcons[key];
    NOverlayImage? out;
    try {
      ui.Image? photo;
      final url = f.ownerPhotoUrl;
      if (url != null) {
        final res =
            await (_http?.get(Uri.parse(url)) ?? http.get(Uri.parse(url)));
        if (res.statusCode == 200) {
          // 마커 크기로만 쓰므로 소형 디코딩(원본 비율 유지).
          final codec = await ui.instantiateImageCodec(
            res.bodyBytes,
            targetWidth: 240,
          );
          photo = (await codec.getNextFrame()).image;
        }
      }
      if (photo != null) {
        out = await renderBizPhotoIcon(photo, f.ownerPhotoAlignY, dark, rating);
        photo.dispose();
      } else {
        out = await categoryIcon(
          f.category,
          dark: dark,
          verified: true,
          rating: rating,
        );
      }
    } catch (e) {
      ErrorReporter.ignored(
        e,
        where: 'map.bizPhotoIcon',
        why: '업체 사진 마커 실패 — 카테고리 아이콘으로 폴백한다',
      );
      out = null;
    }
    _bizIcons[key] = out;
    return out;
  }

  /// 검색 강조 마커 아이콘(IMG_3 핀). 투명 여백을 잘라 렌더(캐시).
  Future<NOverlayImage?> searchIcon() async {
    if (_searchIcon != null) return _searchIcon;
    try {
      const targetH = 120.0; // 핀 높이(px) — 너무 크지도 작지도 않은 크기.
      final data = await rootBundle.load('assets/images/IMG_3.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final src = await opaqueBounds(img); // 투명 여백 제거(원본 여백이 큼)
      final scale = targetH / src.height;
      final w = (src.width * scale).round();
      final h = targetH.round();
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImageRect(
        img,
        src,
        Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
      img.dispose();
      final image = await recorder.endRecording().toImage(w, h);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes != null) {
        _searchIcon = await NOverlayImage.fromByteArray(
          bytes.buffer.asUint8List(),
        );
      }
    } catch (e) {
      ErrorReporter.ignored(
        e,
        where: 'map.searchIcon',
        why: '검색 강조 아이콘 렌더 실패 — 기본 마커로 뜨고 위치 이동은 그대로',
      );
      _searchIcon = null;
    }
    return _searchIcon;
  }

  /// 테마가 바뀌면 색이 달라지므로 캐시를 버린다.
  void clearCache() {
    _catIcons.clear();
    _bizIcons.clear();
    _searchIcon = null;
  }

  // ── 이하 순수 렌더링(캐시 무관) ───────────────────────────────────────

  /// 이미지의 불투명 픽셀 경계상자(투명 여백 제외). 불투명 픽셀이 없으면 전체.
  @visibleForTesting
  static Future<Rect> opaqueBounds(ui.Image img) async {
    final w = img.width, h = img.height;
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) return Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
    final px = data.buffer.asUint8List();
    int minX = w, minY = h, maxX = -1, maxY = -1;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (px[(y * w + x) * 4 + 3] > 16) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    if (maxX < minX) return Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
    return Rect.fromLTRB(
      minX.toDouble(),
      minY.toDouble(),
      (maxX + 1).toDouble(),
      (maxY + 1).toDouble(),
    );
  }

  /// 인증 마커의 둥근 정사각형 프레임 도형.
  @visibleForTesting
  static RRect bizFrameRRect() => RRect.fromRectAndRadius(
    Rect.fromCenter(
      center: const Offset(bizTarget / 2, bizTarget / 2),
      width: bizBox,
      height: bizBox,
    ),
    const Radius.circular(bizRadius),
  );

  /// 그림자 + 채움/클립 + 모드별 분리 링.
  /// [fillColor] 를 주면 채우고(글리프 폴백), 없으면 클립만 남긴다(사진 마커 —
  /// 호출자가 클립 안에 사진을 그린 뒤 [drawBizFrameRing] 으로 링을 얹는다).
  static void drawBizFrame(Canvas canvas, bool dark, {Color? fillColor}) {
    final rrect = bizFrameRRect();
    canvas.drawRRect(
      rrect.shift(const Offset(0, 2)),
      Paint()
        ..color = markerShadow
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4),
    );
    if (fillColor != null) canvas.drawRRect(rrect, Paint()..color = fillColor);
    drawBizFrameRing(canvas, dark);
  }

  static void drawBizFrameRing(Canvas canvas, bool dark) {
    canvas.drawRRect(
      bizFrameRRect(),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = dark ? markerHaloDark : markerHaloLight,
    );
  }

  /// 평점 배지 — 사진 프레임 **아래** 중앙에 골드(액센트) 알약, 흰 별 + 평균
  /// 별점(체크 배지 대체). 프레임 위 오버레이는 사진을 가리고 글자가 작아
  /// 캔버스를 세로로 늘려([bizRatingTarget]) 바깥에 크게 그린다.
  /// 후기가 없으면(rating 빈 문자열) 호출부에서 그리지 않는다 — 인증 여부는
  /// 둥근 정사각형 실루엣 자체가 이미 담당하므로 빈 평점을 배지로 채우지 않는다.
  static void drawRatingBadge(Canvas canvas, bool dark, String label) {
    final star = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(Icons.star_rounded.codePoint),
        style: TextStyle(
          fontSize: 24,
          fontFamily: Icons.star_rounded.fontFamily,
          color: Colors.white,
        ),
      )
      ..layout();
    final text = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: label,
        style: const TextStyle(
          fontSize: 23,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          height: 1,
        ),
      )
      ..layout();
    const h = 34.0;
    const padX = 10.0;
    const top = (bizTarget + bizBox) / 2 + 4; // 프레임 하단(94) + 간격 4
    final w = padX + star.width + 2 + text.width + padX;
    final rect = Rect.fromLTWH((bizTarget - w) / 2, top, w, h);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(h / 2));
    canvas.drawRRect(
      rrect.shift(const Offset(0, 2)),
      Paint()
        ..color = markerShadow
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 3),
    );
    canvas.drawRRect(rrect, Paint()..color = catAccent);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = dark ? markerHaloDark : markerHaloLight,
    );
    final cy = rect.center.dy;
    star.paint(canvas, Offset(rect.left + padX, cy - star.height / 2));
    text.paint(
      canvas,
      Offset(rect.left + padX + star.width + 2, cy - text.height / 2),
    );
  }

  /// 둥근 정사각형 사진 마커 렌더 — cover 크롭 + 업주 세로 초점(alignY,
  /// 상세 히어로와 동일 문법) + 분리 링 + 평점 배지(후기 있을 때만).
  static Future<NOverlayImage?> renderBizPhotoIcon(
    ui.Image photo,
    double alignY,
    bool dark,
    String rating,
  ) async {
    final png = await renderBizPhotoPng(photo, alignY, dark, rating);
    return png == null ? null : NOverlayImage.fromByteArray(png);
  }

  /// [renderBizPhotoIcon] 의 PNG 바이트까지. `NOverlayImage` 포장은 path_provider
  /// 를 타서 테스트에서 못 부르므로, 그림 그리는 본체는 여기서 끝낸다.
  @visibleForTesting
  static Future<Uint8List?> renderBizPhotoPng(
    ui.Image photo,
    double alignY,
    bool dark,
    String rating,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rrect = bizFrameRRect();
    final dst = rrect.outerRect;
    drawBizFrame(canvas, dark); // 그림자 + 링(사진은 클립 안에)
    canvas.save();
    canvas.clipRRect(rrect);
    final scale = math.max(dst.width / photo.width, dst.height / photo.height);
    final srcW = dst.width / scale, srcH = dst.height / scale;
    final srcX = (photo.width - srcW) / 2;
    final srcY = (photo.height - srcH) * (alignY.clamp(-1.0, 1.0) + 1) / 2;
    canvas.drawImageRect(
      photo,
      Rect.fromLTWH(srcX, srcY, srcW, srcH),
      dst,
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();
    drawBizFrameRing(canvas, dark); // 링은 사진 위에 다시(경계 또렷하게)
    if (rating.isNotEmpty) drawRatingBadge(canvas, dark, rating);
    final image = await recorder.endRecording().toImage(
      bizTarget.toInt(),
      // 평점 배지가 붙으면 세로로 긴 캔버스(마커 앵커는 bizRatingAnchor 보정)
      (rating.isNotEmpty ? bizRatingTarget : bizTarget).toInt(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes?.buffer.asUint8List();
  }

  /// 마커 아이콘: 분양은 IMG_4.png, 나머지는 채운 Material 아이콘을 #5a4e38 로 렌더.
  /// 흰 배경 없음. 가독성용 흰 외곽선은 블러 없이 오프셋으로 그려 Impeller 안전.
  ///
  /// [verified] (사진 없는 인증 업체 폴백)는 실루엣 자체가 다르게 — 브랜드
  /// 컬러로 채운 둥근 정사각형 위에 반전색 글리프, 하단에 평점 배지.
  static Future<NOverlayImage?> renderMarkerIcon(
    String category,
    Color iconColor, {
    bool verified = false,
    bool dark = false,
    String rating = '',
  }) async {
    final png = await renderMarkerPng(
      category,
      iconColor,
      verified: verified,
      dark: dark,
      rating: rating,
    );
    return png == null ? null : NOverlayImage.fromByteArray(png);
  }

  /// [renderMarkerIcon] 의 PNG 바이트까지(테스트 진입점 — 위 주석 참고).
  @visibleForTesting
  static Future<Uint8List?> renderMarkerPng(
    String category,
    Color iconColor, {
    bool verified = false,
    bool dark = false,
    String rating = '',
  }) async {
    final iconSize = verified ? 50.0 : 88.0; // 디스크 안에 들어가는 글리프는 축소
    const target = 104.0; // 88 + pad 8*2 — 앵커 계산이 같도록 캔버스 크기 고정
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 인증 업체(사진 없음 폴백): 브랜드 컬러로 채운 둥근 정사각형 —
    // 사진 마커(renderBizPhotoIcon)와 같은 실루엣. 글리프는 반전색.
    final contentColor = verified
        ? (dark ? const Color(0xFF241F16) : Colors.white)
        : iconColor;
    if (verified) {
      final fill = dark ? const Color(0xFFD8C7A9) : const Color(0xFF5A4E3A);
      drawBizFrame(canvas, dark, fillColor: fill);
    }

    if (category == 'pet_sales') {
      // 분양: IMG_4.png(브라운 발바닥)를 투명 여백 잘라 중앙 배치 —
      // 다른 마커와 같은 흰색으로 틴트하고, 그림자로 지도와 대비.
      final data = await rootBundle.load('assets/images/IMG_4.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final src = await opaqueBounds(img);
      final s = iconSize / (src.width > src.height ? src.width : src.height);
      final dw = src.width * s, dh = src.height * s;
      final dx = (target - dw) / 2, dy = (target - dh) / 2;
      final dst = Rect.fromLTWH(dx, dy, dw, dh);
      // 디스크가 그림자를 담당 — 글리프 그림자는 비인증만.
      if (!verified) {
        canvas.drawImageRect(
          img,
          src,
          dst.shift(const Offset(0, 2)),
          Paint()
            ..filterQuality = FilterQuality.high
            ..colorFilter = const ui.ColorFilter.mode(
              markerShadow,
              ui.BlendMode.srcIn,
            )
            ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4),
        );
      }
      canvas.drawImageRect(
        img,
        src,
        dst,
        Paint()
          ..filterQuality = FilterQuality.high
          ..colorFilter = ui.ColorFilter.mode(contentColor, ui.BlendMode.srcIn),
      );
      img.dispose();
    } else {
      final iconData = markerIconForCat(category);
      final ch = String.fromCharCode(iconData.codePoint);
      TextPainter glyph(Color color) {
        return TextPainter(textDirection: TextDirection.ltr)
          ..text = TextSpan(
            text: ch,
            style: TextStyle(
              fontSize: iconSize,
              fontFamily: iconData.fontFamily,
              package: iconData.fontPackage,
              color: color,
            ),
          )
          ..layout();
      }

      final base = glyph(contentColor);
      final origin = Offset(
        (target - base.width) / 2,
        (target - base.height) / 2,
      );
      // 아이콘 전체를 외곽선 색(흰색) 단색으로 — 부드러운 그림자만으로
      // 라이트/나이트 지도 어느 쪽에서도 대비를 확보한다.
      // (인증 마커는 디스크가 그림자·대비를 담당하므로 글리프 그림자 생략.)
      if (!verified) {
        final shadow = glyph(markerShadow);
        canvas.saveLayer(
          null,
          Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        );
        shadow.paint(canvas, origin + const Offset(0, 2));
        canvas.restore();
      }
      base.paint(canvas, origin);
    }

    final withRating = verified && rating.isNotEmpty;
    if (withRating) drawRatingBadge(canvas, dark, rating);

    final image = await recorder.endRecording().toImage(
      target.toInt(),
      // 평점 배지가 붙으면 세로로 긴 캔버스(마커 앵커는 bizRatingAnchor 보정)
      (withRating ? bizRatingTarget : target).toInt(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes?.buffer.asUint8List();
  }
}
