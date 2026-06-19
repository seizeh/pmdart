import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_events.dart';
import 'location_service.dart';

/// 동네 인증 시도 결과.
class LocationVerifyResult {
  final bool verified;
  final String? regionName; // 예: "동탄2동"
  final String? address; // 예: "경기 화성시 동탄2동"
  final String? errorCode; // 미인증 시 사유 코드
  final DateTime? blockedUntil; // 차단 만료 시각

  const LocationVerifyResult({
    required this.verified,
    this.regionName,
    this.address,
    this.errorCode,
    this.blockedUntil,
  });

  /// 사용자에게 보여줄 한글 메시지.
  String get message {
    if (verified) return '$regionName 인증을 완료했어요';
    switch (errorCode) {
      case 'blocked':
        return '연속 실패로 잠시 인증이 제한됐어요. 잠시 후 다시 시도해주세요';
      case 'mock_location':
        return '모의 위치가 감지됐어요. 실제 위치에서 다시 시도해주세요';
      case 'geocode_failed':
        return '현재 위치의 동네를 확인하지 못했어요. 잠시 후 다시 시도해주세요';
      case 'service_disabled':
        return '단말의 위치 서비스(GPS)를 켜주세요';
      case 'permission_denied':
        return '위치 권한이 필요해요';
      case 'permission_denied_forever':
        return '설정에서 위치 권한을 허용해주세요';
      case 'timeout':
        return '위치를 가져오지 못했어요. 실외에서 다시 시도해주세요';
      case 'unauthorized':
        return '로그인이 필요해요';
      case 'network_error':
        return '네트워크 연결을 확인해주세요';
      default:
        return '동네 인증에 실패했어요';
    }
  }
}

/// 동네 인증: GPS 좌표 획득(geolocator) → verify-location Edge Function 호출.
class LocationRepository {
  LocationRepository._();
  static final LocationRepository instance = LocationRepository._();

  SupabaseClient get _c => Supabase.instance.client;

  /// 현재 위치로 동네를 인증한다. 위치 획득 실패는 서버 호출 없이 즉시 반환.
  Future<LocationVerifyResult> verifyCurrentLocation() async {
    final loc = await LocationService.instance.getCurrentPosition();
    switch (loc.status) {
      case LocationStatus.serviceDisabled:
        return const LocationVerifyResult(
            verified: false, errorCode: 'service_disabled');
      case LocationStatus.denied:
        return const LocationVerifyResult(
            verified: false, errorCode: 'permission_denied');
      case LocationStatus.deniedForever:
        return const LocationVerifyResult(
            verified: false, errorCode: 'permission_denied_forever');
      case LocationStatus.timeout:
        return const LocationVerifyResult(
            verified: false, errorCode: 'timeout');
      case LocationStatus.error:
        return const LocationVerifyResult(
            verified: false, errorCode: 'error');
      case LocationStatus.ok:
        break;
    }

    final pos = loc.position!;
    try {
      final res = await _c.functions.invoke(
        'verify-location',
        body: {
          'lat': pos.latitude,
          'lng': pos.longitude,
          'accuracy': pos.accuracy,
          'isMocked': pos.isMocked,
        },
      );
      final data = (res.data as Map?) ?? const {};
      if (data['verified'] == true) {
        // 프로필(활동 지역 표시)이 즉시 갱신되도록 알린다.
        AppEvents.instance.notifyProfile();
        return LocationVerifyResult(
          verified: true,
          regionName: data['regionName'] as String?,
          address: data['address'] as String?,
        );
      }
      return LocationVerifyResult(
        verified: false,
        errorCode: data['reason'] as String?,
        blockedUntil: data['blockedUntil'] == null
            ? null
            : DateTime.tryParse(data['blockedUntil'] as String),
      );
    } on FunctionException catch (e) {
      final detail = e.details;
      final code = detail is Map ? detail['reason'] ?? detail['error'] : null;
      return LocationVerifyResult(
          verified: false, errorCode: code as String? ?? 'verify_failed');
    } catch (_) {
      return const LocationVerifyResult(
          verified: false, errorCode: 'network_error');
    }
  }
}
