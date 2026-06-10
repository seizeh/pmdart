import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';

/// 지도 탭 — 주변 산책 메이트·업체를 네이버 지도로 표시.
class MapTab extends StatefulWidget {
  const MapTab({super.key});

  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> {
  // 초기 카메라 위치 (서울시청). 추후 현재 위치로 대체 가능.
  static const _initialPosition = NCameraPosition(
    target: NLatLng(37.5666, 126.9784),
    zoom: 14,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: NaverMap(
        options: const NaverMapViewOptions(
          initialCameraPosition: _initialPosition,
          locationButtonEnable: true,
          consumeSymbolTapEvents: false,
        ),
        onMapReady: (controller) {
          // 추후 마커·카메라 제어 시 controller 보관해 사용.
          debugPrint('네이버 지도 준비 완료');
        },
      ),
    );
  }
}
