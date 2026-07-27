import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';

/// 위치 권한/좌표 획득 결과 코드.
enum LocationStatus {
  ok, // 좌표 획득 성공
  serviceDisabled, // 단말 위치 서비스(GPS) 꺼짐
  denied, // 권한 거부 (재요청 가능)
  deniedForever, // 권한 영구 거부 → 설정에서 직접 허용 필요
  timeout, // GPS 미획득(실내 등)
  error, // 기타 오류
}

/// 동네 인증용 좌표 획득 결과.
class LocationResult {
  final LocationStatus status;
  final Position? position;
  const LocationResult(this.status, [this.position]);
}

/// GPS 좌표 + 정확도(accuracy) + 모의위치(isMocked) 획득.
///
/// 지도 SDK(flutter_naver_map)와 무관하게 geolocator 로 직접 얻는다.
/// 서버 검증에 필요한 accuracy/isMocked 를 SDK 가 제공하지 않기 때문(0017 §11).
class LocationService {
  LocationService._();
  static final LocationService instance = LocationService._();

  /// 권한 확인/요청 후 고정확도 현재 좌표를 1회 획득한다.
  ///
  /// **웹에서는 위치를 수집하지 않는다(하드 가드).** 두 가지 이유다.
  ///  · 법: 위치정보는 별도 동의·약관 체계가 걸린 정보다. 앱에서만 받도록
  ///    설계·고지돼 있으므로 웹에서 브라우저 위치 권한을 띄우는 일 자체가 없어야
  ///    한다.
  ///  · 신뢰성: 브라우저 Geolocation 에는 `isMocked` 가 없어 조작을 걸러낼 수
  ///    없다 — 동네 인증(0017)의 전제가 무너진다.
  ///
  /// 현재 호출부(글쓰기·지역인증·지도·촬영인증)는 모두 웹에서 도달 불가지만,
  /// **도달 불가에 기대지 않는다** — 나중에 경로가 하나 열려도 권한 프롬프트가
  /// 뜨지 않도록 여기서 막는다.
  Future<LocationResult> getCurrentPosition() async {
    if (kIsWeb) return const LocationResult(LocationStatus.deniedForever);

    // 1) 단말 위치 서비스 on/off
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const LocationResult(LocationStatus.serviceDisabled);
    }

    // 2) 권한
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) {
      return const LocationResult(LocationStatus.deniedForever);
    }
    if (perm == LocationPermission.denied) {
      return const LocationResult(LocationStatus.denied);
    }

    // 3) 좌표 획득
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return LocationResult(LocationStatus.ok, pos);
    } on TimeoutException {
      return const LocationResult(LocationStatus.timeout);
    } catch (_) {
      return const LocationResult(LocationStatus.error);
    }
  }

  /// 권한 영구 거부 시 앱 설정 화면 열기.
  Future<void> openSettings() => Geolocator.openAppSettings();

  /// 위치 서비스(GPS) 꺼짐 시 설정 화면 열기.
  Future<void> openLocationSettings() => Geolocator.openLocationSettings();
}
