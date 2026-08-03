import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/services/phone_auth_service.dart';

// 별도 파일인 이유: auth_result_test.dart 는 열려 있는 PR(#255)이 같은 자리에
// 그룹을 덧붙이는 중이라, 여기 얹으면 머지 충돌이 난다.
void main() {
  group('ResetPasswordResult.message — 비밀번호 재설정 에러코드 매핑', () {
    String msg(String? code) =>
        ResetPasswordResult(ok: false, errorCode: code).message;

    // 서버가 재설정 요청에 상한을 두면서 새로 나오게 된 코드
    // (pmdb reset-password: pwreset:phone 10/10분 + pwreset:ip 30/10분).
    // 기본값 '비밀번호 재설정에 실패했어요' 로 떨어지면 *틀렸다* 는 뜻으로 읽혀
    // 같은 자리에서 계속 재시도하게 되는데, 이미 막힌 구간이라 재시도가 창만 늘린다.
    test('rate_limited 는 기다리라고 안내한다(실패로 뭉뚱그리지 않는다)', () {
      expect(msg('rate_limited'), '시도가 너무 많아요. 잠시 후 다시 시도해주세요');
      expect(msg('rate_limited'), isNot(msg('what_is_this')));
    });

    test('기존 코드 매핑은 그대로', () {
      expect(msg('invalid_phone'), '전화번호 형식이 올바르지 않아요');
      expect(msg('invalid_password'), '비밀번호는 영문과 숫자를 포함해 8자 이상이어야 해요');
      expect(msg('phone_not_verified'), '전화번호 인증을 먼저 완료해주세요');
      expect(msg('user_not_found'), '해당 번호로 가입된 계정이 없어요');
      expect(msg('network_error'), '네트워크 연결을 확인해주세요');
    });

    test('에러코드 없음(성공)과 미지의 코드는 각각 완료/실패 기본 문구', () {
      expect(const ResetPasswordResult(ok: true).message, '비밀번호가 변경됐어요');
      expect(msg('what_is_this'), '비밀번호 재설정에 실패했어요');
    });
  });
}
