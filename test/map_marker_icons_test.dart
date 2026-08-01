import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/widgets/map_marker_icons.dart';

/// 마커 렌더러 테스트.
///
/// map_tab.dart 안에 있을 때는 못 쓰던 것들이다 — 1,600줄짜리 State 를 띄우고
/// 네이버 지도 컨트롤러까지 붙여야 도달하는 코드였다. 화면에서 떼어내니
/// 캔버스만 있으면 되는 순수 함수가 됐고, 그래서 여기서 잰다(#155).
///
/// 픽셀을 눈으로 비교하지 않는다. 대신 **깨지면 마커가 어긋나는 성질**을 고정한다:
/// 앵커 보정값, 투명 여백 절단, 캐시 키 동작.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // NOverlayImage.fromByteArray 는 바이트를 임시 파일로 떨어뜨린다(path_provider).
  // 그림 자체와 무관한 의존이라 목으로 세운다 — 캐시 동작을 재려면 실제
  // NOverlayImage 가 나와야 하기 때문이다.
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async =>
              Directory.systemTemp.createTempSync('marker_test').path,
        );
  });

  /// PNG IHDR 에서 높이를 읽는다(바이트 16~19, 빅엔디언).
  int pngHeight(List<int> png) =>
      (png[20] << 24) | (png[21] << 16) | (png[22] << 8) | png[23];

  /// [w]×[h] 이미지를 만들고, [opaque] 사각형만 불투명하게 칠한다.
  Future<ui.Image> makeImage(int w, int h, Rect opaque) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    );
    canvas.drawRect(opaque, Paint()..color = const Color(0xFF000000));
    return recorder.endRecording().toImage(w, h);
  }

  group('opaqueBounds — 투명 여백 절단', () {
    test('불투명 영역만 정확히 감싼다', () async {
      final img = await makeImage(40, 40, const Rect.fromLTWH(10, 12, 8, 6));
      expect(
        await MapMarkerIcons.opaqueBounds(img),
        const Rect.fromLTRB(10, 12, 18, 18),
      );
      img.dispose();
    });

    test('전부 투명하면 전체 크기로 폴백한다', () async {
      // 폴백이 없으면 scale 계산이 0 나눗셈이 되어 마커가 사라진다.
      final img = await makeImage(24, 30, Rect.zero);
      expect(
        await MapMarkerIcons.opaqueBounds(img),
        const Rect.fromLTRB(0, 0, 24, 30),
      );
      img.dispose();
    });
  });

  group('인증 마커 도형', () {
    test('프레임이 캔버스 중앙에 온다', () {
      final r = MapMarkerIcons.bizFrameRRect().outerRect;
      expect(r.center.dx, MapMarkerIcons.bizTarget / 2);
      expect(r.center.dy, MapMarkerIcons.bizTarget / 2);
      expect(r.width, MapMarkerIcons.bizBox);
      expect(r.height, MapMarkerIcons.bizBox);
    });

    test('평점 배지가 프레임 바깥 아래에 들어갈 자리가 있다', () {
      // 배지를 프레임 위에 얹으면 사진을 가린다. 캔버스를 늘려 바깥에 그리는
      // 설계라, 늘어난 높이가 프레임 하단보다 커야 한다.
      final frameBottom = MapMarkerIcons.bizFrameRRect().outerRect.bottom;
      expect(MapMarkerIcons.bizRatingTarget, greaterThan(frameBottom));
    });

    test('앵커 보정이 사진 중심을 가리킨다', () {
      // 캔버스가 세로로 길어져도 마커가 가리키는 지점은 사진 중심(y=52)이어야
      // 한다. 이 값이 틀어지면 인증 업체 마커만 좌표에서 어긋나 뜬다.
      const anchor = MapMarkerIcons.bizRatingAnchor;
      expect(anchor.x, 0.5);
      expect(
        anchor.y * MapMarkerIcons.bizRatingTarget,
        closeTo(MapMarkerIcons.bizTarget / 2, 0.001),
      );
    });
  });

  group('markerIconForCat', () {
    test('알려진 카테고리를 매핑한다', () {
      expect(
        MapMarkerIcons.markerIconForCat('animal_hospital'),
        Icons.local_hospital,
      );
      expect(MapMarkerIcons.markerIconForCat('pet_cafe'), Icons.local_cafe);
      expect(MapMarkerIcons.markerIconForCat('posts'), Icons.article);
    });

    test('모르는 코드는 기본 핀으로 떨어진다', () {
      // 서버가 새 카테고리를 보내도 마커가 비지 않아야 한다.
      expect(MapMarkerIcons.markerIconForCat('brand_new_cat'), Icons.place);
    });
  });

  group('renderMarkerPng — 실제로 그려지는가', () {
    test('PNG 바이트가 나온다', () async {
      final png = await MapMarkerIcons.renderMarkerPng(
        'pet_cafe',
        MapMarkerIcons.markerIconLight,
      );
      expect(png, isNotNull);
      // PNG 시그니처 — 빈 버퍼를 통과시키지 않기 위해.
      expect(png!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    });

    test('인증 변형은 다른 그림이다', () async {
      // 같은 카테고리라도 인증 마커는 실루엣(둥근 정사각형)이 다르다.
      final plain = await MapMarkerIcons.renderMarkerPng(
        'pet_cafe',
        MapMarkerIcons.markerIconLight,
      );
      final verified = await MapMarkerIcons.renderMarkerPng(
        'pet_cafe',
        MapMarkerIcons.markerIconLight,
        verified: true,
      );
      expect(verified, isNot(equals(plain)));
    });

    test('평점이 있으면 캔버스가 세로로 길어진다', () async {
      // 배지를 프레임 바깥에 그리려고 캔버스를 늘린다. 안 늘어나면 배지가 잘린다.
      final withRating = await MapMarkerIcons.renderMarkerPng(
        'pet_cafe',
        MapMarkerIcons.markerIconLight,
        verified: true,
        rating: '4.5',
      );
      final without = await MapMarkerIcons.renderMarkerPng(
        'pet_cafe',
        MapMarkerIcons.markerIconLight,
        verified: true,
      );
      expect(pngHeight(withRating!), MapMarkerIcons.bizRatingTarget.toInt());
      expect(pngHeight(without!), MapMarkerIcons.bizTarget.toInt());
    });
  });

  group('캐시', () {
    test('clearCache 후에는 다시 렌더한다', () async {
      // 테마가 바뀌면 링·배지 색이 달라진다. 캐시를 안 비우면 이전 모드의
      // 마커가 그대로 남는다 — 실제로 겪은 증상이라 성질로 고정한다.
      final icons = MapMarkerIcons();
      final a = await icons.categoryIcon('animal_hospital', dark: false);
      expect(a, isNotNull, reason: '렌더 자체가 실패하면 이 테스트는 무의미하다');
      final cached = await icons.categoryIcon('animal_hospital', dark: false);
      expect(identical(a, cached), isTrue, reason: '같은 키는 캐시가 돌려줘야 한다');

      icons.clearCache();
      final afterClear = await icons.categoryIcon(
        'animal_hospital',
        dark: false,
      );
      expect(identical(a, afterClear), isFalse, reason: '비운 뒤엔 새로 만들어야 한다');
    });

    test('인증 변형과 평점이 캐시 키를 가른다', () async {
      // 같은 카테고리라도 인증 여부·평점에 따라 그림이 다르다. 키가 뭉개지면
      // 평점 3.0 업체에 4.5 배지가 붙는다.
      final icons = MapMarkerIcons();
      final plain = await icons.categoryIcon('pet_cafe', dark: false);
      expect(plain, isNotNull, reason: '렌더 실패면 전부 null 이라 비교가 무의미하다');
      final verified = await icons.categoryIcon(
        'pet_cafe',
        dark: false,
        verified: true,
        rating: '4.5',
      );
      final other = await icons.categoryIcon(
        'pet_cafe',
        dark: false,
        verified: true,
        rating: '3.0',
      );
      expect(identical(plain, verified), isFalse);
      expect(identical(verified, other), isFalse);
    });
  });
}
