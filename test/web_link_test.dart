import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/utils/web_link.dart';

/// 공유 링크 진입 경로 파싱 — `go.pawmate.kr/s` 의 '웹에서 계속 보기' CTA 가
/// `app.pawmate.kr/p/<postId>` 로 보낸다(docs/web-port.md 결정 6).
void main() {
  const id = '3f2504e0-4f89-11d3-9a0c-0305e82c3301';

  group('sharedPostIdOf', () {
    test('/p/<uuid> 에서 id 를 읽는다', () {
      expect(sharedPostIdOf(Uri.parse('https://app.pawmate.kr/p/$id')), id);
    });

    test('쿼리·프래그먼트가 붙어도 읽는다', () {
      expect(
        sharedPostIdOf(Uri.parse('https://app.pawmate.kr/p/$id?from=share#x')),
        id,
      );
    });

    test('하위 경로 배포(--base-href)에서도 읽는다', () {
      expect(sharedPostIdOf(Uri.parse('https://x.kr/web/p/$id')), id);
    });

    test('대문자 uuid 도 허용한다', () {
      final upper = id.toUpperCase();
      expect(sharedPostIdOf(Uri.parse('https://x.kr/p/$upper')), upper);
    });

    test('uuid 가 아니면 무시한다 — 잘못된 링크로 조회를 낭비하지 않는다', () {
      expect(sharedPostIdOf(Uri.parse('https://x.kr/p/not-a-uuid')), isNull);
      expect(sharedPostIdOf(Uri.parse('https://x.kr/p/123')), isNull);
    });

    test('id 없는 /p 는 무시한다', () {
      expect(sharedPostIdOf(Uri.parse('https://x.kr/p')), isNull);
      expect(sharedPostIdOf(Uri.parse('https://x.kr/p/')), isNull);
    });

    test('평범한 진입(루트)은 null', () {
      expect(sharedPostIdOf(Uri.parse('https://app.pawmate.kr/')), isNull);
    });

    test('다른 경로의 uuid 는 잡지 않는다', () {
      expect(sharedPostIdOf(Uri.parse('https://x.kr/u/$id')), isNull);
    });
  });
}
