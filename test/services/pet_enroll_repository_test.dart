// PetEnrollRepository 의 전송 전 용량 판정 (pmdb#136).
//
// 이 판정이 서버(`enroll-pet-identity` 의 MAX_INLINE_B64_CHARS)와 어긋나면 두 방향
// 모두 비용이 있다:
//   느슨하면 — 종전과 같다. 25MB 를 다 올린 뒤 거절당하고 레이트리밋만 소모한다.
//   빡빡하면 — **서버가 받아 줄 영상을 앱이 먼저 막는다.** 사용자는 멀쩡한 영상으로
//              계속 거절당하고, 서버 로그에는 아무 흔적도 없어 원인을 찾을 수 없다.
// 후자가 더 나쁘다. 그래서 경계를 정확히 못 박는다.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/services/pet_enroll_repository.dart';

void main() {
  group('b64Len — 실제 base64Encode 길이와 일치해야 한다', () {
    test('경계 길이에서 정확히 맞는다(패딩 포함)', () {
      // base64 는 3바이트 → 4문자다. 3의 배수 경계에서 어긋나기 쉬워 그 주변을 훑는다.
      for (final n in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 100, 1000, 1001, 1002]) {
        final actual = base64Encode(Uint8List(n)).length;
        expect(PetEnrollRepository.b64Len(n), actual, reason: '$n 바이트에서 어긋난다');
      }
    });

    test('실측 규모(17MB)에서도 맞는다', () {
      // 실제로 17MB 를 인코딩해 보지는 않는다(테스트가 느려진다) — 공식만 확인한다.
      // 4 * ceil(n/3) 이므로 3의 배수면 정확히 4/3 배다.
      expect(PetEnrollRepository.b64Len(3 * 1000000), 4 * 1000000);
    });
  });

  group('exceedsInlineLimit — 서버 한도와 같은 경계', () {
    // 서버: MAX_INLINE_B64_CHARS = 19_000_000 (초과 시 거절, 같으면 통과)
    const limit = PetEnrollRepository.maxInlineB64Chars;

    test('상수가 서버 값과 같다', () {
      // 서버를 고치지 않고 이 값만 바꾸면 위 주석의 '빡빡한' 실패가 난다.
      expect(limit, 19000000);
    });

    test('한도와 정확히 같으면 통과시킨다(서버가 > 로 거절하므로)', () {
      final bytes = limit ~/ 4 * 3; // b64Len 이 정확히 limit 이 되는 크기
      expect(PetEnrollRepository.b64Len(bytes), limit);
      expect(PetEnrollRepository.exceedsInlineLimit(bytes, const []), isFalse);
    });

    test('한 바이트만 넘어도 거절한다', () {
      final bytes = limit ~/ 4 * 3;
      expect(
        PetEnrollRepository.exceedsInlineLimit(bytes + 1, const []),
        isTrue,
      );
    });

    test('프레임도 예산을 함께 쓴다 — 영상만 재면 안 된다', () {
      // 영상 단독으로는 통과하지만 프레임을 더하면 넘는 조합.
      // 야간 프레임이 장당 0.45MB 까지 커졌던 실측(주간 0.21MB)에서 나온 경계다.
      final video = limit ~/ 4 * 3 - 1000000; // 여유 100만 바이트
      expect(PetEnrollRepository.exceedsInlineLimit(video, const []), isFalse);
      expect(
        PetEnrollRepository.exceedsInlineLimit(
          video,
          List.filled(4, 450000), // 0.45MB × 4
        ),
        isTrue,
        reason: '프레임을 빼고 재면 서버가 거절할 조합을 통과시킨다',
      );
    });
  });

  group('실측 시나리오 (2026-08-23 야간 3연속)', () {
    // 그날 서버가 받은 총량은 25M chars 였고 한도는 19M 이었다.
    const nightFrames = [430000, 440000, 470000, 470000]; // 실제 저장된 프레임 크기

    test('압축 전 원본(17MB)은 막힌다 — 올리기 전에', () {
      expect(
        PetEnrollRepository.exceedsInlineLimit(17 * 1000000, nightFrames),
        isTrue,
      );
    });

    test('720p 재인코딩 후(약 2~3MB)는 통과한다', () {
      // capturePetVideo 가 이 크기로 만들어 준다. 11초를 꽉 채워도 이 범위다.
      for (final mb in [2, 3, 5]) {
        expect(
          PetEnrollRepository.exceedsInlineLimit(mb * 1000000, nightFrames),
          isFalse,
          reason: '${mb}MB 는 통과해야 한다',
        );
      }
    });

    test('프레임이 야간이라 2배여도 압축본이면 여유가 있다', () {
      // 주간(0.21MB)과 야간(0.45MB) 프레임 모두에서 판정이 같아야 한다.
      const dayFrames = [200000, 210000, 210000, 230000];
      expect(
        PetEnrollRepository.exceedsInlineLimit(3 * 1000000, dayFrames),
        isFalse,
      );
      expect(
        PetEnrollRepository.exceedsInlineLimit(3 * 1000000, nightFrames),
        isFalse,
      );
    });
  });

  group('PetEnrollResult.message — video_too_large 안내', () {
    test('이제는 사용자가 실행할 수 있는 지시를 준다', () {
      // 앱이 720p 로 굽고 나서도 넘친 경우다. 남은 변수는 길이와 밝기뿐이고
      // 둘 다 사용자가 바꿀 수 있다(종전 문구는 "고객센터 문의" 였다).
      const r = PetEnrollResult(enrolled: false, errorCode: 'video_too_large');
      expect(r.message, contains('짧게'));
      expect(r.message, contains('밝은'));
    });

    test('기존 사유 매핑은 그대로', () {
      String msg(String c) =>
          PetEnrollResult(enrolled: false, errorCode: c).message;
      expect(msg('not_guardian'), contains('보호자만'));
      expect(msg('too_few_frames'), contains('짧아요'));
      expect(msg('ai_unavailable'), contains('잠시 후'));
      expect(msg('what_is_this'), '신원 인증에 실패했어요. 다시 시도해주세요');
    });
  });
}
