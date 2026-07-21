import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/services/auth_service.dart';
import 'package:pawmate/services/session.dart';

void main() {
  group('AuthResult.message — 서버 에러코드 → 사용자 문구 매핑', () {
    String msg(String? code) => AuthResult(ok: false, errorCode: code).message;

    test('알려진 에러코드는 각각 한글 안내 문구로 매핑된다', () {
      expect(msg('invalid_credentials'), '아이디 또는 비밀번호가 올바르지 않아요');
      expect(msg('missing_fields'), '아이디와 비밀번호를 입력해주세요');
      expect(msg('server_misconfigured'), '서버 설정 오류로 로그인할 수 없어요');
      expect(msg('network_error'), '네트워크 연결을 확인해주세요');
      expect(msg('invalid_current'), '현재 비밀번호가 올바르지 않아요');
      expect(msg('weak_password'), '새 비밀번호는 6자 이상이어야 해요');
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
}
