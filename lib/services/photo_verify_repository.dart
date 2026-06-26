import 'dart:convert';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'location_service.dart';

/// 게시글 사진 실존 검증 결과 (0018).
class PhotoVerifyResult {
  final bool pass;
  final String? token; // 통과 시 photo_verifications.id (게시글 등록에 사용)
  final String? imageUrl; // 서버가 업로드한 공개 URL (이 URL 로만 게시 가능)
  final String? species; // 'dog' | 'cat'
  final String? errorCode; // 실패 사유
  final String? expected; // region_mismatch 시 인증된 동네
  final String? got; // region_mismatch 시 촬영지 동네
  final bool matched; // 등록 펫과 개체 일치(소프트) (0019)
  final double? matchScore; // 개체 일치도 0~1

  const PhotoVerifyResult({
    required this.pass,
    this.token,
    this.imageUrl,
    this.species,
    this.errorCode,
    this.expected,
    this.got,
    this.matched = false,
    this.matchScore,
  });

  /// 사용자에게 보여줄 한글 메시지.
  String get message {
    if (pass) return '사진 인증을 완료했어요';
    switch (errorCode) {
      case 'not_verified':
        return '먼저 활동 지역(동네)을 인증해주세요';
      case 'mock_location':
        return '모의 위치가 감지됐어요. 실제 위치에서 다시 촬영해주세요';
      case 'geocode_failed':
        return '현재 위치의 동네를 확인하지 못했어요. 잠시 후 다시 시도해주세요';
      case 'region_mismatch':
        return '촬영 위치가 인증된 동네와 달라요. 활동 지역에서 촬영해주세요';
      case 'not_real_pet':
        return '실제 반려동물 사진이 아니에요. 반려동물이 또렷이 보이게 다시 촬영해주세요';
      case 'no_reference':
        return '이 반려동물의 인증용 사진을 먼저 등록해주세요';
      case 'forbidden':
      case 'forbidden_not_owner':
        return '이 반려동물의 보호자만 인증할 수 있어요';
      case 'pet_not_found':
        return '반려동물 정보를 찾을 수 없어요';
      case 'ai_unavailable':
        return '사진 인증 서버가 잠시 응답하지 않아요. 잠시 후 다시 시도해주세요';
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
        return '사진 인증에 실패했어요';
    }
  }
}

/// 게시글 사진 검증: 좌표 획득(0017 LocationService) → verify-post-photo Edge Function.
/// 카메라로 방금 찍은 사진(XFile)을 받아 좌표와 함께 서버로 보낸다.
class PhotoVerifyRepository {
  PhotoVerifyRepository._();
  static final PhotoVerifyRepository instance = PhotoVerifyRepository._();

  SupabaseClient get _c => Supabase.instance.client;

  /// 게시글 사진 검증 — [petId] 펫의 기준 사진과 개체 대조까지.
  Future<PhotoVerifyResult> verifyPostPhoto(XFile shot,
          {required String petId}) =>
      _invoke(shot, petId: petId, purpose: 'post');

  /// 펫 AI 인증 기준 사진 등록 — 실존+위치만 검사(대조 없음), owner 전용.
  Future<PhotoVerifyResult> verifyPetReference(XFile shot,
          {required String petId}) =>
      _invoke(shot, petId: petId, purpose: 'reference');

  /// 촬영본 + 현재 좌표를 서버로 보내 검증한다.
  /// 위치 획득 실패는 서버 호출 없이 즉시 반환.
  Future<PhotoVerifyResult> _invoke(
    XFile shot, {
    required String petId,
    required String purpose,
  }) async {
    final loc = await LocationService.instance.getCurrentPosition();
    switch (loc.status) {
      case LocationStatus.serviceDisabled:
        return const PhotoVerifyResult(pass: false, errorCode: 'service_disabled');
      case LocationStatus.denied:
        return const PhotoVerifyResult(pass: false, errorCode: 'permission_denied');
      case LocationStatus.deniedForever:
        return const PhotoVerifyResult(
            pass: false, errorCode: 'permission_denied_forever');
      case LocationStatus.timeout:
        return const PhotoVerifyResult(pass: false, errorCode: 'timeout');
      case LocationStatus.error:
        return const PhotoVerifyResult(pass: false, errorCode: 'error');
      case LocationStatus.ok:
        break;
    }

    final pos = loc.position!;
    try {
      final bytes = await shot.readAsBytes();
      final res = await _c.functions.invoke(
        'verify-post-photo',
        body: {
          'imageBase64': base64Encode(bytes),
          'mimeType': shot.mimeType ?? 'image/jpeg',
          'lat': pos.latitude,
          'lng': pos.longitude,
          'accuracy': pos.accuracy,
          'isMocked': pos.isMocked,
          'petId': petId,
          'purpose': purpose,
        },
      );
      final data = (res.data as Map?) ?? const {};
      if (data['pass'] == true) {
        final ms = data['matchScore'];
        return PhotoVerifyResult(
          pass: true,
          token: data['token'] as String?,
          imageUrl: data['imageUrl'] as String?,
          species: data['species'] as String?,
          matched: data['matched'] == true,
          matchScore: ms is num ? ms.toDouble() : null,
        );
      }
      return PhotoVerifyResult(
        pass: false,
        errorCode: data['reason'] as String?,
        expected: data['expected'] as String?,
        got: data['got'] as String?,
      );
    } on FunctionException catch (e) {
      final detail = e.details;
      final code = detail is Map ? detail['reason'] ?? detail['error'] : null;
      return PhotoVerifyResult(
          pass: false, errorCode: code as String? ?? 'verify_failed');
    } catch (_) {
      return const PhotoVerifyResult(pass: false, errorCode: 'network_error');
    }
  }
}
