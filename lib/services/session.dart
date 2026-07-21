import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 로그인된 사용자 정보(JWT 의 sub 에 해당하는 user_id 포함).
class AuthUser {
  final String id;
  final String username; // 로그인 아이디. 비공개 값이라 본인 세션에만 보관(공개 프로필엔 없음).
  final String nickname;
  final String userType;

  const AuthUser({
    required this.id,
    required this.username,
    required this.nickname,
    required this.userType,
  });

  factory AuthUser.fromJson(Map<dynamic, dynamic> json) => AuthUser(
    id: json['id'] as String,
    username: (json['username'] ?? '') as String,
    nickname: (json['nickname'] ?? '') as String,
    userType: (json['user_type'] ?? '') as String,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'nickname': nickname,
    'user_type': userType,
  };
}

/// 앱 전역 세션. 커스텀 JWT(access) + refresh 토큰을 보관하고 모든 Supabase 요청에
/// 첨부된다(main.dart 의 accessToken 콜백이 [token] 을 읽으며, 만료 임박 시 [refreshOnce]).
///
/// refresh-token phase 2:
///  · access/refresh 는 flutter_secure_storage(민감), user 는 SharedPreferences(비민감).
///  · access exp 임박 시 refresh 엔드포인트로 무중단 갱신(단일비행 — 동시 요청 1회만).
///  · refresh 실패(401 invalid_refresh) → 세션 clear(강제 로그아웃).
///  · refresh 미보유(레거시 30일 토큰) → 갱신 시도 안 함(만료 시 재로그인).
class SessionManager extends ChangeNotifier {
  SessionManager._();
  static final SessionManager instance = SessionManager._();

  static const _kAccess = 'session_access'; // secure
  static const _kRefresh = 'session_refresh'; // secure
  static const _kUser = 'session_user'; // prefs(비민감)
  static const _kLegacyToken = 'session_token'; // 구버전 prefs(마이그레이션)

  final _secure = const FlutterSecureStorage();

  String? _access;
  String? _refresh;
  AuthUser? _user;
  Future<void>? _refreshing; // 단일비행 갱신 진행 중 Future

  /// 세션이 서버에서 무효화되어 강제 로그아웃됐을 때 호출(앱이 로그인 화면으로 라우팅).
  /// 타 기기 비번변경/정지·refresh 회수 감지 시. main.dart 가 세팅한다.
  void Function()? onInvalidated;

  /// main.dart accessToken 콜백 호환(기존 이름 유지) = 현재 access.
  String? get token => _access;
  String? get access => _access;
  String? get refresh => _refresh;
  AuthUser? get user => _user;
  bool get isLoggedIn => _access != null && _user != null;
  bool get isAdmin => _user?.userType == 'admin';
  bool get isRefreshing => _refreshing != null;

  /// 앱 시작 시 1회 호출 — 저장된 세션 복원(+ 구버전 SharedPreferences 토큰 마이그레이션).
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _access = await _secure.read(key: _kAccess);
    _refresh = await _secure.read(key: _kRefresh);
    // 레거시: 구버전은 access 를 SharedPreferences 에 보관 → secure 로 이전.
    if (_access == null) {
      final legacy = prefs.getString(_kLegacyToken);
      if (legacy != null) {
        _access = legacy;
        await _secure.write(key: _kAccess, value: legacy);
        await prefs.remove(_kLegacyToken);
      }
    }
    final userStr = prefs.getString(_kUser);
    if (userStr != null) {
      try {
        _user = AuthUser.fromJson(jsonDecode(userStr) as Map);
      } catch (_) {
        _user = null;
      }
    }
    if (_access == null || _user == null) {
      _access = null;
      _refresh = null;
      _user = null;
    }
  }

  /// 로그인/비번변경 성공 시 세션 저장(refresh 없으면 레거시로 간주).
  Future<void> setSession(
    String access,
    AuthUser user, {
    String? refresh,
  }) async {
    _access = access;
    _user = user;
    _refresh = refresh;
    await _secure.write(key: _kAccess, value: access);
    if (refresh != null) {
      await _secure.write(key: _kRefresh, value: refresh);
    } else {
      await _secure.delete(key: _kRefresh);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUser, jsonEncode(user.toJson()));
    notifyListeners();
  }

  /// 사용자 정보만 갱신(access/refresh 토큰 유지). 프로필 수정(닉네임 등)용.
  Future<void> updateUser(AuthUser user) async {
    _user = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUser, jsonEncode(user.toJson()));
    notifyListeners();
  }

  Future<void> clear() async {
    _access = null;
    _refresh = null;
    _user = null;
    await _secure.delete(key: _kAccess);
    await _secure.delete(key: _kRefresh);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUser);
    await prefs.remove(_kLegacyToken);
    notifyListeners();
  }

  /// access exp 가 [skew] 초 내로 임박하면 true. refresh 없으면(레거시) 항상 false.
  bool isAccessExpiringSoon({int skew = 60}) {
    final a = _access;
    if (a == null || _refresh == null) return false;
    final exp = _jwtExp(a);
    if (exp == null) return false;
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return exp - nowSec <= skew;
  }

  /// 단일비행 갱신 — 동시에 여러 요청이 호출해도 refresh 는 1회만.
  Future<void> refreshOnce() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<void> _doRefresh() async {
    final r = _refresh;
    if (r == null) return;
    try {
      final res = await _invokeRefreshWithRetry(r);
      final data = (res.data as Map?) ?? const {};
      if (data['ok'] == true && data['token'] is String) {
        // 새 refresh 를 access 보다 먼저 영속화 — 이 사이에 프로세스가 죽어도
        // 다음 실행이 새 refresh 로 이어갈 수 있다(회전 응답 유실 창 최소화).
        final nr = data['refresh_token'] as String?;
        if (nr != null) {
          await _secure.write(key: _kRefresh, value: nr);
          _refresh = nr;
        }
        _access = data['token'] as String;
        await _secure.write(key: _kAccess, value: _access!);
        // realtime(채팅) 연결도 새 토큰으로 재인증 — 안 하면 8h 후 만료로 끊길 수 있음.
        try {
          unawaited(Supabase.instance.client.realtime.setAuth(_access));
        } catch (_) {
          /* realtime 미연결 등 */
        }
        // notifyListeners 안 함 — 로그인 상태 변화 없음(토큰만 교체, 리빌드 불필요).
      } else {
        await _invalidate(); // 예상 밖 응답 → 세션 만료 처리
      }
    } on FunctionException catch (_) {
      await _invalidate(); // 401 invalid_refresh 등 → 강제 로그아웃
    } catch (_) {
      // 네트워크 오류: 세션 유지(다음 요청에서 재시도). 기존 access 로 계속 시도.
      // (서버가 이미 회전을 커밋했더라도 rt_rotate 의 유실 복구가 세션을 살린다.)
    }
  }

  /// refresh 호출 — 일시 오류(타임아웃 등)는 1초 후 1회 즉시 재시도.
  /// 서버가 회전을 커밋한 뒤 응답이 유실된 경우 grace(30초) 안에 재요청해야
  /// 같은 패밀리로 매끄럽게 이어지므로, 다음 요청을 기다리지 않고 바로 재시도한다.
  Future<FunctionResponse> _invokeRefreshWithRetry(String r) async {
    try {
      return await Supabase.instance.client.functions.invoke(
        'refresh',
        body: {'refresh_token': r},
      );
    } on FunctionException {
      rethrow; // 401 등 명시적 거절은 재시도 대상 아님
    } catch (_) {
      await Future.delayed(const Duration(seconds: 1));
      return await Supabase.instance.client.functions.invoke(
        'refresh',
        body: {'refresh_token': r},
      );
    }
  }

  /// 로그인 상태면 서버에 세션 유효성 확인(session_alive). 무효면 강제 로그아웃 후 true 반환.
  /// 앱 시작/포그라운드 복귀 시 호출 → 타 기기 비번변경·정지로 무효화된 세션 감지.
  Future<bool> checkAliveAndClearIfDead() async {
    if (!isLoggedIn) return false;
    try {
      final res = await Supabase.instance.client.rpc('session_alive');
      if (res == false) {
        await _invalidate();
        return true;
      }
    } catch (_) {
      // 네트워크/일시 오류: 무효로 단정하지 않음(오탐 로그아웃 방지).
    }
    return false;
  }

  /// 세션 무효화 → 저장소 clear + onInvalidated(앱 라우팅) 호출.
  Future<void> _invalidate() async {
    await clear();
    onInvalidated?.call();
  }

  int? _jwtExp(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return null;
      final payload =
          jsonDecode(
                utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
              )
              as Map;
      final exp = payload['exp'];
      return exp is int ? exp : null;
    } catch (_) {
      return null;
    }
  }
}
