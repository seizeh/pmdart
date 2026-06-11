import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;
import 'session.dart';

/// 로그인/로그아웃. 성공 시 [SessionManager] 에 JWT 세션을 저장한다.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  SupabaseClient get _client => Supabase.instance.client;

  /// 아이디/비밀번호 로그인. 성공 시 세션 저장 후 ok=true.
  Future<AuthResult> login(String username, String password) async {
    try {
      final res = await _client.functions.invoke(
        'login',
        body: {'username': username, 'password': password},
      );
      final data = (res.data as Map?) ?? const {};
      if (data['ok'] == true && data['token'] is String) {
        await SessionManager.instance.setSession(
          data['token'] as String,
          AuthUser.fromJson(data['user'] as Map),
        );
        return const AuthResult(ok: true);
      }
      return const AuthResult(ok: false, errorCode: 'login_failed');
    } on FunctionException catch (e) {
      final detail = e.details;
      final code = detail is Map ? detail['error'] as String? : null;
      return AuthResult(ok: false, errorCode: code ?? 'login_failed');
    } catch (_) {
      return const AuthResult(ok: false, errorCode: 'network_error');
    }
  }

  Future<void> logout() => SessionManager.instance.clear();

  /// 본인 비밀번호 변경. 현재 비밀번호 확인 후 새 비밀번호로 갱신.
  Future<AuthResult> changePassword(String current, String next) async {
    try {
      await _client.rpc('change_password',
          params: {'p_current': current, 'p_new': next});
      return const AuthResult(ok: true);
    } on PostgrestException catch (e) {
      final msg = e.message;
      final code = msg.contains('invalid_current')
          ? 'invalid_current'
          : msg.contains('weak_password')
              ? 'weak_password'
              : msg.contains('not_authenticated')
                  ? 'not_authenticated'
                  : 'change_failed';
      return AuthResult(ok: false, errorCode: code);
    } catch (_) {
      return const AuthResult(ok: false, errorCode: 'network_error');
    }
  }
}

class AuthResult {
  final bool ok;
  final String? errorCode;
  const AuthResult({required this.ok, this.errorCode});

  String get message => switch (errorCode) {
        'invalid_credentials' => '아이디 또는 비밀번호가 올바르지 않아요',
        'missing_fields' => '아이디와 비밀번호를 입력해주세요',
        'server_misconfigured' => '서버 설정 오류로 로그인할 수 없어요',
        'network_error' => '네트워크 연결을 확인해주세요',
        'invalid_current' => '현재 비밀번호가 올바르지 않아요',
        'weak_password' => '새 비밀번호는 6자 이상이어야 해요',
        'not_authenticated' => '다시 로그인해주세요',
        'change_failed' => '비밀번호를 변경하지 못했어요',
        null => '완료되었어요',
        _ => '처리에 실패했어요',
      };
}
