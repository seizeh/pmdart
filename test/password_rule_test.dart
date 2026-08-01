import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/utils/password_rule.dart';

/// 비밀번호 복잡도 규칙 — 가입·재설정·변경 세 화면이 같은 규칙을 쓰는지의 회귀 가드.
///
/// 이 테스트가 지키는 실제 사고: '변경'만 6자 길이 검사였고(구 app._set_password
/// 정책 잔재), 가입에서 막은 단순 비밀번호를 변경으로 우회할 수 있었다.
/// 서버 규칙(엣지 signup·reset-password·change-password)과 같은 값이어야 한다.
void main() {
  group('isStrongPassword — 통과', () {
    for (final pw in ['abcd1234', 'A1bcdefg', 'pass1234!', '12345678a']) {
      test(pw, () => expect(isStrongPassword(pw), isTrue));
    }
  });

  group('isStrongPassword — 거부', () {
    const cases = {
      'abcd123': '7자 — 길이 미달',
      'abcdefgh': '숫자 없음',
      '12345678': '영문 없음',
      '!@#\$%^&*': '영문·숫자 모두 없음',
      'a1': '너무 짧음',
      '': '빈 값',
    };
    cases.forEach((pw, why) {
      test('$why ("$pw")', () => expect(isStrongPassword(pw), isFalse));
    });
  });

  test('기호는 요구하지 않는다 — 서버 규칙과 동일', () {
    // 기호를 필수로 만들려면 엣지 함수 3개를 함께 고쳐야 한다(파일 주석 참고).
    expect(isStrongPassword('abcd1234'), isTrue);
  });

  test('6자 비밀번호는 거부된다 — 변경 화면 우회 경로 회귀 가드', () {
    expect(isStrongPassword('abc123'), isFalse);
  });

  test('안내 문구와 입력칸 힌트가 같은 규칙을 말한다', () {
    expect(kPasswordRuleMessage, contains('영문'));
    expect(kPasswordRuleMessage, contains('숫자'));
    expect(kPasswordRuleMessage, contains('8자'));
    expect(kPasswordRuleHint, contains('8자'));
  });
}
