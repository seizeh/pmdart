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
      // 종전 문구는 "잠시 후 다시 시도하거나 고객센터로 문의" 였다. 그때는 앱이
      // 촬영 원본을 그대로 보냈고, 원인이 길이가 아니라 화질이라 **사용자가 할 수
      // 있는 게 없었다** — 그래서 실행 불가능한 지시를 주지 않는 쪽을 택했다.
      //
      // 이제는 앱이 720p 로 다시 굽고 나서 재므로(capturePetVideo) 그래도 넘친다면
      // 남은 변수는 **길이와 밝기**다. 둘 다 사용자가 바꿀 수 있다 —
      // 어두우면 노이즈 때문에 같은 길이도 파일이 커진다. 이제야 이 안내가 성립한다.
      case 'video_too_large':
        return '영상 용량이 커서 처리하지 못했어요. 조금 더 짧게, 밝은 곳에서 다시 촬영해주세요';
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

  /// 서버 `enroll-pet-identity` 의 `MAX_INLINE_B64_CHARS` 와 **같은 값**이어야 한다.
  /// (Gemini 요청당 20MB 보호선. 영상 + 프레임 base64 길이의 합.)
  ///
  /// 여기서 미리 재는 이유는 방어가 아니라 **낭비 방지**다. 서버가 어차피 거절하는데,
  /// 그 판정을 받으려면 25MB 를 모바일로 다 올려야 했다. 그동안 사용자는 진행률도
  /// 없는 화면을 보고, 실패해도 `aienroll` 레이트리밋(10회)은 그대로 소모된다.
  /// 2026-08-23 실사용에서 3회 중 2회가 그렇게 나갔다(pmdb#136).
  ///
  /// ⚠️ 서버 상수와 갈리면 **여기가 더 관대할 때만 안전하다.** 더 빡빡하면 서버가
  /// 받아 줄 영상을 앱이 먼저 막는다 — 값을 바꿀 일이 생기면 서버부터 올릴 것.
  static const int maxInlineB64Chars = 19000000;

  /// base64 인코딩 후 길이. 실제로 인코딩하지 않고 센다 — 25MB 문자열을 만들어
  /// 보고 나서 "너무 크네" 하는 건 재려는 낭비를 그대로 치르는 짓이다.
  static int b64Len(int bytes) => ((bytes + 2) ~/ 3) * 4;

  /// 이 조합이 서버 한도를 넘는지. [enroll] 이 전송 전에 부른다.
  static bool exceedsInlineLimit(int videoBytes, Iterable<int> frameBytes) {
    var chars = b64Len(videoBytes);
    for (final n in frameBytes) {
      chars += b64Len(n);
    }
    return chars > maxInlineB64Chars;
  }

  Future<PetEnrollResult> enroll({
    required String petId,
    required Uint8List videoBytes,
    String videoMime = 'video/mp4',
    required List<Uint8List> frames,
  }) async {
    // 전송 전 차단 — 서버와 같은 사유 코드를 돌려주므로 화면 문구는 그대로 쓴다.
    if (exceedsInlineLimit(videoBytes.length, frames.map((f) => f.length))) {
      return const PetEnrollResult(
        enrolled: false,
        errorCode: 'video_too_large',
      );
    }
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
