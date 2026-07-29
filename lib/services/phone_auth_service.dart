import 'package:supabase_flutter/supabase_flutter.dart';

import 'error_reporter.dart';

/// 전화 인증코드 발급/검증 서비스.
///
/// 실제 코드 생성·SMS 발송·검증은 모두 Supabase Edge Function
/// (`send-phone-code` / `verify-phone-code`) 내부에서 service_role 로 처리된다.
/// 클라이언트는 publishable 키로 함수만 호출하며, service_role 키를 알지 못한다.
class PhoneAuthService {
  PhoneAuthService._();
  static final PhoneAuthService instance = PhoneAuthService._();

  SupabaseClient get _client => Supabase.instance.client;

  /// 인증코드 발송. 성공 시 [PhoneCodeResult.ok] == true.
  /// 실패 시 [PhoneCodeResult.errorCode] 에 서버 에러 코드가 담긴다.
  Future<PhoneCodeResult> sendCode(
    String phone, {
    String purpose = 'signup',
  }) async {
    try {
      final res = await _client.functions.invoke(
        'send-phone-code',
        body: {'phone': phone, 'purpose': purpose},
      );
      final data = (res.data as Map?) ?? const {};
      return PhoneCodeResult(
        ok: data['ok'] == true,
        expiresInSec: (data['expires_in_sec'] as num?)?.toInt(),
      );
    } on FunctionException catch (e) {
      return PhoneCodeResult.fromFunctionException(e);
    } catch (e, st) {
      // SMS 발송 실패는 가입 자체를 막는다 — 조용히 지나가면 안 된다.
      ErrorReporter.userFacing(e, where: 'phoneAuth.sendCode', stackTrace: st);
      return const PhoneCodeResult(ok: false, errorCode: 'network_error');
    }
  }

  /// 아이디 중복확인. 서버 RPC(`check_username_available`)로 존재 여부만 확인한다.
  /// (아이디는 비공개 값이라 클라이언트가 직접 조회할 수 없고, 이 RPC 만 허용됨.)
  /// [UsernameCheckResult.ok] == false 면 네트워크/서버 오류.
  Future<UsernameCheckResult> checkUsername(String username) async {
    try {
      final res = await _client.rpc(
        'check_username_available',
        params: {'p_username': username},
      );
      return UsernameCheckResult(ok: true, available: res == true);
    } catch (e) {
      ErrorReporter.ignored(
        e,
        where: 'phoneAuth.checkUsername',
        why: '중복확인 실패 시 화면이 "확인 불가" 로 폴백하고 가입은 서버가 최종 검증',
      );
      return const UsernameCheckResult(ok: false);
    }
  }

  /// 회원가입(계정 생성). 비밀번호 해싱·users INSERT 는 서버에서 처리된다.
  /// 성공 시 [SignupResult.ok] == true, [SignupResult.userId] 에 새 사용자 id.
  Future<SignupResult> signUp({
    required String username,
    required String password,
    required String nickname,
    required String userType,
    required String phone,
    bool marketingOptIn = false,
  }) async {
    try {
      final res = await _client.functions.invoke(
        'signup',
        body: {
          'username': username,
          'password': password,
          'nickname': nickname,
          'user_type': userType,
          'phone': phone,
          'marketing_opt_in': marketingOptIn,
        },
      );
      final data = (res.data as Map?) ?? const {};
      return SignupResult(
        ok: data['ok'] == true,
        userId: data['user_id'] as String?,
      );
    } on FunctionException catch (e) {
      final detail = e.details;
      final errorCode = detail is Map ? detail['error'] as String? : null;
      return SignupResult(ok: false, errorCode: errorCode ?? 'signup_failed');
    } catch (_) {
      return const SignupResult(ok: false, errorCode: 'network_error');
    }
  }

  /// 비밀번호 재설정. 전화 OTP(purpose='password_reset') 인증 완료 후 호출.
  /// 서버가 번호로 계정을 찾아 비번 갱신 + 전 세션 무효화. 성공 시 [ResetPasswordResult.ok].
  Future<ResetPasswordResult> resetPassword({
    required String phone,
    required String newPassword,
  }) async {
    try {
      final res = await _client.functions.invoke(
        'reset-password',
        body: {'phone': phone, 'new_password': newPassword},
      );
      final data = (res.data as Map?) ?? const {};
      return ResetPasswordResult(ok: data['ok'] == true);
    } on FunctionException catch (e) {
      final detail = e.details;
      final code = detail is Map ? detail['error'] as String? : null;
      return ResetPasswordResult(ok: false, errorCode: code ?? 'reset_failed');
    } catch (e, st) {
      ErrorReporter.userFacing(
        e,
        where: 'phoneAuth.resetPassword',
        stackTrace: st,
      );
      return const ResetPasswordResult(ok: false, errorCode: 'network_error');
    }
  }

  /// 간이 회원(후기 전용) 인증 — 코드 검증 + 계정 확보 + 단명 토큰 발급을 한 번에.
  ///
  /// 정식 가입과 달리 [verifyCode] 를 따로 부르지 않는다. 코드 소지가 곧 세션인
  /// 경로라, 검증과 토큰 발급 사이가 벌어지면 남이 받은 인증으로 세션을 가로챌
  /// 창이 생기기 때문이다(서버 signup-lite 주석 참고).
  ///
  /// [privacyConsent] 는 전화번호 수집·이용 동의. 서버도 false 면 거부한다.
  Future<LiteSignupResult> signUpLite({
    required String phone,
    required String code,
    required bool privacyConsent,
  }) async {
    try {
      final res = await _client.functions.invoke(
        'signup-lite',
        body: {'phone': phone, 'code': code, 'privacy_consent': privacyConsent},
      );
      final data = (res.data as Map?) ?? const {};
      final user = (data['user'] as Map?) ?? const {};
      return LiteSignupResult(
        ok: data['ok'] == true,
        token: data['token'] as String?,
        userId: user['id'] as String?,
        displayName: user['display_name'] as String?,
      );
    } on FunctionException catch (e) {
      final detail = e.details;
      final err = detail is Map ? detail['error'] as String? : null;
      return LiteSignupResult(
        ok: false,
        errorCode: err ?? 'lite_signup_failed',
      );
    } catch (e, st) {
      ErrorReporter.userFacing(
        e,
        where: 'phoneAuth.liteSignup',
        stackTrace: st,
      );
      return const LiteSignupResult(ok: false, errorCode: 'network_error');
    }
  }

  /// 인증코드 검증. 성공 시 [PhoneVerifyResult.verified] == true.
  Future<PhoneVerifyResult> verifyCode(
    String phone,
    String code, {
    String purpose = 'signup',
  }) async {
    try {
      final res = await _client.functions.invoke(
        'verify-phone-code',
        body: {'phone': phone, 'code': code, 'purpose': purpose},
      );
      final data = (res.data as Map?) ?? const {};
      return PhoneVerifyResult(verified: data['verified'] == true);
    } on FunctionException catch (e) {
      // 코드 불일치/만료는 400 + { verified:false, error:'code_mismatch_or_expired' }
      final detail = e.details;
      final errorCode = detail is Map ? detail['error'] as String? : null;
      return PhoneVerifyResult(
        verified: false,
        errorCode: errorCode ?? 'verify_failed',
      );
    } catch (e, st) {
      ErrorReporter.userFacing(
        e,
        where: 'phoneAuth.verifyCode',
        stackTrace: st,
      );
      return const PhoneVerifyResult(
        verified: false,
        errorCode: 'network_error',
      );
    }
  }
}

/// 발송 결과.
class PhoneCodeResult {
  final bool ok;
  final int? expiresInSec;
  final String? errorCode;
  final int? retryAfterSec;

  const PhoneCodeResult({
    required this.ok,
    this.expiresInSec,
    this.errorCode,
    this.retryAfterSec,
  });

  factory PhoneCodeResult.fromFunctionException(FunctionException e) {
    final detail = e.details;
    final map = detail is Map ? detail : const {};
    return PhoneCodeResult(
      ok: false,
      errorCode: (map['error'] as String?) ?? 'send_failed',
      retryAfterSec: (map['retry_after_sec'] as num?)?.toInt(),
    );
  }

  /// 사용자에게 보여줄 한글 메시지.
  String get message => switch (errorCode) {
    'invalid_phone' => '전화번호 형식이 올바르지 않아요',
    'phone_taken' => '이미 가입된 전화번호예요. 로그인하거나 비밀번호 찾기를 이용해주세요',
    'user_not_found' => '가입되지 않은 전화번호예요',
    'rate_limited' => '잠시 후 다시 시도해주세요 (${retryAfterSec ?? 60}초 후 재발송 가능)',
    'sms_send_failed' => '문자 발송에 실패했어요. 잠시 후 다시 시도해주세요',
    'server_misconfigured' => '서버 설정 오류로 발송할 수 없어요',
    'network_error' => '네트워크 연결을 확인해주세요',
    null => '인증번호를 보냈어요',
    _ => '인증번호 발송에 실패했어요',
  };
}

/// 회원가입 결과.
class SignupResult {
  final bool ok;
  final String? userId;
  final String? errorCode;

  const SignupResult({required this.ok, this.userId, this.errorCode});

  String get message => switch (errorCode) {
    'invalid_username' => '아이디는 영문/숫자 4~20자로 입력해주세요',
    'invalid_password' => '비밀번호는 영문과 숫자를 포함해 8자 이상이어야 해요',
    'invalid_nickname' => '닉네임을 입력해주세요',
    'invalid_user_type' => '사용자 유형을 선택해주세요',
    'invalid_phone' => '전화번호 형식이 올바르지 않아요',
    'phone_not_verified' => '전화번호 인증을 먼저 완료해주세요',
    'username_taken' => '이미 사용 중인 아이디예요',
    'nickname_taken' => '이미 사용 중인 닉네임이에요',
    'phone_taken' => '이미 가입된 전화번호예요',
    'network_error' => '네트워크 연결을 확인해주세요',
    null => '가입이 완료됐어요',
    _ => '회원가입에 실패했어요',
  };
}

/// 간이 회원 인증 결과 — 성공 시 [token] 으로 후기 한 건을 게시할 수 있다.
class LiteSignupResult {
  final bool ok;
  final String? token; // 단명(15분) JWT — 저장 금지, 게시 후 폐기
  final String? userId;
  final String? displayName; // 마스크된 표시명(***-1***-**78)
  final String? errorCode;

  const LiteSignupResult({
    required this.ok,
    this.token,
    this.userId,
    this.displayName,
    this.errorCode,
  });

  String get message => switch (errorCode) {
    'code_mismatch_or_expired' => '인증번호가 일치하지 않거나 만료됐어요',
    'invalid_code' => '6자리 인증번호를 입력해주세요',
    'invalid_phone' => '전화번호 형식이 올바르지 않아요',
    'privacy_consent_required' => '전화번호 수집·이용에 동의해야 후기를 남길 수 있어요',
    'account_unavailable' => '이 번호로는 후기를 남길 수 없어요',
    'rate_limited' => '시도가 너무 많아요. 잠시 후 다시 시도해주세요',
    'server_misconfigured' => '서버 설정 오류로 진행할 수 없어요',
    'network_error' => '네트워크 연결을 확인해주세요',
    null => '인증되었어요',
    _ => '인증에 실패했어요',
  };
}

/// 검증 결과.
class PhoneVerifyResult {
  final bool verified;
  final String? errorCode;

  const PhoneVerifyResult({required this.verified, this.errorCode});

  String get message => switch (errorCode) {
    'code_mismatch_or_expired' => '인증번호가 일치하지 않거나 만료됐어요',
    'invalid_code' => '6자리 인증번호를 입력해주세요',
    'network_error' => '네트워크 연결을 확인해주세요',
    null => '인증되었어요',
    _ => '인증에 실패했어요',
  };
}

/// 비밀번호 재설정 결과.
class ResetPasswordResult {
  final bool ok;
  final String? errorCode;

  const ResetPasswordResult({required this.ok, this.errorCode});

  String get message => switch (errorCode) {
    'invalid_phone' => '전화번호 형식이 올바르지 않아요',
    'invalid_password' => '비밀번호는 영문과 숫자를 포함해 8자 이상이어야 해요',
    'phone_not_verified' => '전화번호 인증을 먼저 완료해주세요',
    'user_not_found' => '해당 번호로 가입된 계정이 없어요',
    'network_error' => '네트워크 연결을 확인해주세요',
    null => '비밀번호가 변경됐어요',
    _ => '비밀번호 재설정에 실패했어요',
  };
}

/// 아이디 중복확인 결과.
class UsernameCheckResult {
  final bool ok; // 서버 응답 성공 여부 (false 면 네트워크/서버 오류)
  final bool available; // 사용 가능 여부

  const UsernameCheckResult({required this.ok, this.available = false});
}
