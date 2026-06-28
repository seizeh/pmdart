import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

/// 신원 인증 동작 임무(challenge). 등록 영상에서 무작위로 1~2개를 지시한다 (0020).
class PetChallenge {
  final String code;
  final String label; // 사용자 지시 문구
  const PetChallenge(this.code, this.label);
}

const List<PetChallenge> kPetChallengePool = [
  PetChallenge('pat_head', '머리를 쓰다듬어 주세요'),
  PetChallenge('hold_paw', '앞발(손)을 잡아 주세요'),
  PetChallenge('scratch_chin', '턱·목을 쓰다듬어 주세요'),
  PetChallenge('stroke_back', '등을 쓰다듬어 주세요'),
  PetChallenge('hand_in_frame', '손을 반려동물 옆에 대주세요'),
];

/// 무작위 임무 [count]개 선택.
List<PetChallenge> pickRandomChallenges([int count = 2]) {
  final pool = List<PetChallenge>.of(kPetChallengePool)..shuffle(Random());
  return pool.take(count).toList();
}

/// 펫 신원 인증(영상) 결과.
class PetEnrollResult {
  final bool enrolled;
  final List<String> warnings; // species_kind / breed 소프트 경고
  final List<String> missing; // challenge_failed 시 못 한 임무 코드
  final String? errorCode;
  final String? detail; // 진단용(임시): 서버가 준 상세 사유
  final int? videoKb; // 진단용(임시): 전송 영상 크기

  const PetEnrollResult({
    required this.enrolled,
    this.warnings = const [],
    this.missing = const [],
    this.errorCode,
    this.detail,
    this.videoKb,
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
      case 'challenge_failed':
        return '지시한 동작이 확인되지 않았어요. 동작을 또렷이 하며 다시 촬영해주세요';
      case 'too_few_frames':
        return '영상이 너무 짧아요. 더 길게(약 11초) 다시 촬영해주세요';
      case 'ai_unavailable':
        return 'AI 사용량이 많아 잠시 지연되고 있어요. 잠시 후 다시 시도해주세요';
      case 'video_too_large':
        return '영상이 너무 커요. 더 짧게 다시 촬영해주세요';
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
    required List<String> challenge,
    required Uint8List videoBytes,
    String videoMime = 'video/mp4',
    required List<Uint8List> frames,
  }) async {
    try {
      final res = await _c.functions.invoke(
        'enroll-pet-identity',
        body: {
          'petId': petId,
          'challenge': challenge,
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
          warnings: [for (final w in (data['warnings'] as List? ?? const [])) '$w'],
        );
      }
      return PetEnrollResult(
        enrolled: false,
        errorCode: data['reason'] as String?,
        missing: [for (final m in (data['missing'] as List? ?? const [])) '$m'],
        detail: data['detail'] as String?,
        videoKb: data['videoKb'] is num ? (data['videoKb'] as num).toInt() : null,
      );
    } on FunctionException catch (e) {
      final detail = e.details;
      final code = detail is Map ? detail['reason'] ?? detail['error'] : null;
      return PetEnrollResult(
          enrolled: false, errorCode: code as String? ?? 'enroll_failed');
    } catch (_) {
      return const PetEnrollResult(enrolled: false, errorCode: 'network_error');
    }
  }
}
