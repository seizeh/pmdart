import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/services/auth_service.dart';
import 'package:pawmate/services/phone_auth_service.dart';
import 'package:pawmate/services/session.dart';
import 'package:pawmate/utils/password_rule.dart';

void main() {
  group('AuthResult.message — 서버 에러코드 → 사용자 문구 매핑', () {
    String msg(String? code) => AuthResult(ok: false, errorCode: code).message;

    test('알려진 에러코드는 각각 한글 안내 문구로 매핑된다', () {
      expect(msg('invalid_credentials'), '아이디 또는 비밀번호가 올바르지 않아요');
      expect(msg('missing_fields'), '아이디와 비밀번호를 입력해주세요');
      expect(msg('server_misconfigured'), '서버 설정 오류로 로그인할 수 없어요');
      expect(msg('network_error'), '네트워크 연결을 확인해주세요');
      expect(msg('invalid_current'), '현재 비밀번호가 올바르지 않아요');
      // 가입·재설정과 같은 규칙을 안내한다(종전 '6자 이상'은 변경 화면만의
      // 옛 정책이었다 — 그 때문에 단순 비밀번호가 변경으로 우회됐다).
      expect(msg('weak_password'), kPasswordRuleMessage);
      expect(msg('rate_limited'), '요청이 많아요. 잠시 후 다시 시도해주세요');
      expect(msg('change_failed'), '비밀번호를 변경하지 못했어요');
    });

    test('재인증 계열(not_authenticated/unauthorized)은 재로그인 안내로 수렴', () {
      expect(msg('not_authenticated'), '다시 로그인해주세요');
      expect(msg('unauthorized'), '다시 로그인해주세요');
    });

    test('에러코드 없음(성공)과 미지의 코드는 각각 완료/실패 기본 문구', () {
      expect(const AuthResult(ok: true).message, '완료되었어요');
      expect(msg('what_is_this'), '처리에 실패했어요');
    });
  });

  group('AuthUser — 세션 사용자 직렬화', () {
    test('fromJson/toJson 왕복이 무손실이다', () {
      final u = AuthUser.fromJson(const {
        'id': 'u1',
        'username': 'paw',
        'nickname': '집사',
        'user_type': 'pet_owner',
      });
      expect(AuthUser.fromJson(u.toJson()).toJson(), u.toJson());
    });

    test('id 외 누락 필드는 빈 문자열 폴백', () {
      final u = AuthUser.fromJson(const {'id': 'u1'});
      expect(u.username, '');
      expect(u.nickname, '');
      expect(u.userType, '');
    });
  });

  group('PhoneVerifyResult.message — 전화 인증 에러코드 매핑', () {
    String msg(String? code) =>
        PhoneVerifyResult(verified: false, errorCode: code).message;

    // 서버가 대입 횟수를 제한하면서 새로 나오게 된 코드(pmdb: verify-phone-code).
    // 기본값으로 떨어지면 '인증에 실패했어요' 가 되는데, 그건 "틀렸다" 로 읽혀
    // 사용자를 같은 자리에서 계속 재시도하게 만든다 — 이미 막힌 구간이라
    // 무엇을 넣어도 실패한다.
    test('rate_limited 는 기다리라고 안내한다(실패로 뭉뚱그리지 않는다)', () {
      expect(msg('rate_limited'), '시도가 너무 많아요. 잠시 후 다시 시도해주세요');
      expect(msg('rate_limited'), isNot(msg('what_is_this')));
    });

    test('기존 코드 매핑은 그대로', () {
      expect(msg('code_mismatch_or_expired'), '인증번호가 일치하지 않거나 만료됐어요');
      expect(msg('invalid_code'), '6자리 인증번호를 입력해주세요');
      expect(msg('network_error'), '네트워크 연결을 확인해주세요');
    });

    test('에러코드 없음(성공)과 미지의 코드는 각각 완료/실패 기본 문구', () {
      expect(const PhoneVerifyResult(verified: true).message, '인증되었어요');
      expect(msg('what_is_this'), '인증에 실패했어요');
    });
  });

  group('PhoneCodeResult.message — 대기 시간 자릿수에 따라 문장이 바뀐다', () {
    String msg(int? sec) => PhoneCodeResult(
      ok: false,
      errorCode: 'rate_limited',
      retryAfterSec: sec,
    ).message;

    // 서버 버킷의 창이 제각각이다 — 번호별 재발송 쿨다운 60초 vs 출처별·전역
    // 상한 3600초. 초 단위로만 찍으면 1시간 막힌 사용자에게 "3600초 후" 가 뜬다.
    test('1시간 창은 시간 단위로 안내하고 "잠시 후" 라고 하지 않는다', () {
      expect(msg(3600), '요청이 너무 많아요. 최대 1시간 뒤 다시 시도할 수 있어요');
      expect(msg(3600), isNot(contains('3600')));
      // "잠시 후" 는 곧 될 것처럼 읽혀 같은 자리에서 계속 누르게 만든다.
      expect(msg(3600), isNot(contains('잠시 후')));
    });

    test('분 단위는 올림해서 분으로', () {
      expect(msg(600), '요청이 너무 많아요. 최대 10분 뒤 다시 시도할 수 있어요');
      expect(msg(90), contains('최대 2분'));
    });

    test('60초 미만은 종전 문구 유지(재발송 쿨다운)', () {
      expect(msg(30), '잠시 후 다시 시도해주세요 (30초 후 재발송 가능)');
    });

    test('서버가 값을 안 주면 60초로 가정한다(종전 동작)', () {
      expect(msg(null), contains('최대 1분'));
    });
  });
}
