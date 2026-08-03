import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import 'error_reporter.dart';
import 'push_service.dart';
import 'realtime_service.dart';
import 'session.dart';

/// 로그인/로그아웃. 성공 시 [SessionManager] 에 JWT 세션을 저장한다.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  SupabaseClient get _client => Supabase.instance.client;

  /// 아이디/비밀번호 로그인. 성공 시 세션 저장 후 ok=true.
  /// x-client-refresh:1 → 서버가 짧은 access + refresh 를 발급(refresh 지원 클라).
  Future<AuthResult> login(String username, String password) async {
    try {
      final res = await _client.functions.invoke(
        'login',
        headers: const {'x-client-refresh': '1'},
        body: {'username': username, 'password': password},
      );
      final data = (res.data as Map?) ?? const {};
      if (data['ok'] == true && data['token'] is String) {
        await SessionManager.instance.setSession(
          data['token'] as String,
          AuthUser.fromJson(data['user'] as Map),
          refresh: data['refresh_token'] as String?,
        );
        await PushService.instance.registerToken(); // FCM 토큰 등록
        // 서버 안읽음 카운터 보정(#232) — 트리거 캐시가 원본과 어긋난 채 남아
        // 푸시 배지만 틀리는 일이 실제로 있었다(운영 80 vs 2). 로그인 때 한 번만.
        unawaited(PushService.instance.reconcileUnreadCounts());
        RealtimeService.instance.start(); // realtime 재인증 + 알림 구독
        return const AuthResult(ok: true);
      }
      return const AuthResult(ok: false, errorCode: 'login_failed');
    } on FunctionException catch (e) {
      final detail = e.details;
      final code = detail is Map ? detail['error'] as String? : null;
      return AuthResult(ok: false, errorCode: code ?? 'login_failed');
    } catch (e, st) {
      // 로그인은 첫 관문이라 실패가 곧 이탈이다 — 빈도를 봐야 한다.
      ErrorReporter.userFacing(e, where: 'auth.login', stackTrace: st);
      return const AuthResult(ok: false, errorCode: 'network_error');
    }
  }

  /// 로그아웃. 서버에서 이 기기 refresh family 를 회수 후 로컬 세션 clear.
  Future<void> logout() async {
    RealtimeService.instance.stop(); // 알림 realtime 구독 해제
    await PushService.instance.clearToken(); // FCM 토큰 삭제(타 사용자 푸시 방지)
    final r = SessionManager.instance.refresh;
    if (r != null) {
      try {
        await _client.functions.invoke('logout', body: {'refresh_token': r});
      } catch (e) {
        ErrorReporter.ignored(
          e,
          where: 'auth.logout.revoke',
          why: '서버 회수 실패해도 로컬 세션은 정리한다(토큰은 만료로 무효화)',
        );
      }
    }
    await SessionManager.instance.clear();
  }

  /// 본인 비밀번호 변경(change-password 엣지). 성공 시 서버가 전 세션 무효화(token_version
  /// bump + 타 기기 refresh 회수) 후 현재 기기용 새 쌍을 재발급 → 세션 교체.
  Future<AuthResult> changePassword(String current, String next) async {
    try {
      final res = await _client.functions.invoke(
        'change-password',
        body: {'current_password': current, 'new_password': next},
      );
      final data = (res.data as Map?) ?? const {};
      if (data['ok'] == true && data['token'] is String) {
        final user = SessionManager.instance.user;
        if (user != null) {
          await SessionManager.instance.setSession(
            data['token'] as String,
            user,
            refresh: data['refresh_token'] as String?,
          );
        }
        return const AuthResult(ok: true);
      }
      return const AuthResult(ok: false, errorCode: 'change_failed');
    } on FunctionException catch (e) {
      final detail = e.details;
      final code = detail is Map ? detail['error'] as String? : null;
      return AuthResult(ok: false, errorCode: code ?? 'change_failed');
    } catch (e, st) {
      ErrorReporter.userFacing(e, where: 'auth.changePassword', stackTrace: st);
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
    'not_authenticated' || 'unauthorized' => '다시 로그인해주세요',
    'rate_limited' => '요청이 많아요. 잠시 후 다시 시도해주세요',
    'change_failed' => '비밀번호를 변경하지 못했어요',
    null => '완료되었어요',
    _ => '처리에 실패했어요',
  };
}
