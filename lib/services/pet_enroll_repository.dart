import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// 펫 신원 인증(영상) 결과.
class PetEnrollResult {
  final bool enrolled;
  final List<String> warnings; // species_kind / breed 소프트 경고
  final String? errorCode;

  const PetEnrollResult({
    required this.enrolled,
    this.warnings = const [],
    this.errorCode,
  });

  /// 실패 사유 한글 메시지.
  String get message {
    switch (errorCode) {
      case 'not_guardian':
        return '이 반려동물의 보호자만 인증할 수 있어요';
      case 'not_real_pet':
        return '실제 반려동물이 또렷이 보이게 다시 촬영해주세요';
      case 'not_consistent_pet':
        return '영상에 여러 동물이 보여요. 한 마리만 나오게 다시 촬영해주세요';
      case 'frames_not_from_video':
        return '영상 확인에 실패했어요. 처음부터 다시 촬영해주세요';
      case 'species_mismatch':
        return '등록한 종과 영상 속 동물이 달라요. 종(강아지/고양이)을 확인해주세요';
      case 'too_few_frames':
        return '영상이 너무 짧아요. 더 길게(약 5초) 다시 촬영해주세요';
      case 'ai_unavailable':
        return 'AI 사용량이 많아 잠시 지연되고 있어요. 잠시 후 다시 시도해주세요';
      // 원인은 길이가 아니라 해상도·비트레이트(촬영 화질 제한 없음) — "짧게
      // 다시" 류의 사용자가 실행 불가능한 지시를 주지 않는다.
      case 'video_too_large':
        return '영상 용량이 커서 처리하지 못했어요. 잠시 후 다시 시도하거나 고객센터로 문의해주세요';
      default:
        return '신원 인증에 실패했어요. 다시 시도해주세요';
    }
  }
}

/// 펫 신원 인증: 무작위 임무 영상 + 추출 프레임을 enroll-pet-identity 로 전송.
/// 영상은 AI 검증용으로만 전송되고 서버에 저장되지 않는다(프레임만 저장).
class PetEnrollRepository {
  PetEnrollRepository._();
  static final PetEnrollRepository instance = PetEnrollRepository._();

  SupabaseClient get _c => Supabase.instance.client;

  Future<PetEnrollResult> enroll({
    required String petId,
    required Uint8List videoBytes,
    String videoMime = 'video/mp4',
    required List<Uint8List> frames,
  }) async {
    try {
      final res = await _c.functions.invoke(
        'enroll-pet-identity',
        body: {
          'petId': petId,
          'videoBase64': base64Encode(videoBytes),
          'videoMime': videoMime,
          'frames': [for (final f in frames) base64Encode(f)],
          'mimeType': 'image/jpeg',
        },
      );
      final data = (res.data as Map?) ?? const {};
      if (data['enrolled'] == true) {
        return PetEnrollResult(
          enrolled: true,
          warnings: [
            for (final w in (data['warnings'] as List? ?? const [])) '$w',
          ],
        );
      }
      return PetEnrollResult(
        enrolled: false,
        errorCode: data['reason'] as String?,
      );
    } on FunctionException catch (e) {
      final d = e.details;
      final code = d is Map ? (d['reason'] ?? d['error']) : null;
      return PetEnrollResult(
        enrolled: false,
        errorCode: code as String? ?? 'enroll_failed',
      );
    } catch (_) {
      return const PetEnrollResult(enrolled: false, errorCode: 'network_error');
    }
  }
}
