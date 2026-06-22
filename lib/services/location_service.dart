import 'dart:async';

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
  Future<LocationResult> getCurrentPosition() async {
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
