import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'error_reporter.dart';
import 'session_store.dart';

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
///  · 저장 위치는 플랫폼별 — [SessionStore] 참고(앱은 secure storage + prefs,
///    웹은 sessionStorage).
///  · access exp 임박 시 refresh 엔드포인트로 무중단 갱신(단일비행 — 동시 요청 1회만).
///  · refresh 실패(401 invalid_refresh) → 세션 clear(강제 로그아웃).
///  · refresh 미보유(레거시 30일 토큰) → 갱신 시도 안 함(만료 시 재로그인).
///
/// 웹 정책(docs/web-port.md 결정 7): refresh 를 **영속화하지 않고 갱신에도 쓰지
/// 않는다**. 메모리에만 들고 있다가 로그아웃 시 서버 family 회수에만 쓴다.
/// 결과적으로 웹 세션은 access 수명(8시간)이 상한이고, 탭을 닫으면 사라진다.
/// 로그인 요청의 `x-client-refresh:1` 헤더는 **그대로 유지해야 한다** — 빼면
/// 서버가 레거시로 보고 30일짜리 access 를 발급해 오히려 나빠진다.
class SessionManager extends ChangeNotifier {
  SessionManager._();
  static final SessionManager instance = SessionManager._();

  static const _kAccess = 'session_access'; // secure
  static const _kRefresh = 'session_refresh'; // secure
  static const _kUser = 'session_user'; // prefs(비민감)
  static const _kLegacyToken = 'session_token'; // 구버전 prefs(마이그레이션)

  final _store = const SessionStore();

  String? _access;
  String? _refresh;
  AuthUser? _user;
  Future<void>? _refreshing; // 단일비행 갱신 진행 중 Future

  /// 간이 회원(후기 전용, 0029) 단명 토큰 — **메모리에만** 둔다.
  ///
  /// 저장하지 않는 게 요구사항이다: 간이 회원은 비회원 취급이라 후기 한 건을 쓰는
  /// 동안만 존재하고, 다음 후기를 쓰려면 문자 인증을 다시 받아야 한다. 앱을 다시
  /// 켜면 흔적이 없어야 한다.
  ///
  /// [isLoggedIn] 은 [_user] 도 봐야 하므로 이 토큰이 있어도 여전히 false — 앱은
  /// 계속 게스트로 동작하고, 서버는 status='lite' 라 후기 외 모든 걸 막는다.
  String? _liteToken;
  String? _liteUserId;

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

  /// 간이 회원 토큰(있으면). main.dart 의 accessToken 콜백이 [token] 다음으로 읽는다.
  String? get liteToken => _liteToken;

  /// 후기를 쓸 자격이 있는가 — 정식 로그인이거나 간이 인증 구간이면 true.
  /// [isLoggedIn] 을 쓰면 간이 회원이 요청도 못 보내고 클라이언트에서 막힌다.
  bool get canWriteReview => isLoggedIn || _liteToken != null;

  /// Storage 경로(`<uid>/...`)에 쓸 사용자 id — 간이 구간이면 간이 계정 id.
  /// 버킷 RLS 가 첫 폴더를 본인 id 로 검사하므로 토큰의 주인과 반드시 일치해야 한다.
  String? get storageUserId => _user?.id ?? _liteUserId;

  /// 간이 후기 게시 구간 시작 — 이 토큰으로 사진 업로드와 후기 INSERT 가 나간다.
  /// 정식 세션이 있으면 무시한다(정식 회원은 자기 세션으로 써야 한다).
  void beginLiteSession(String token, String userId) {
    if (_access != null) return;
    _liteToken = token;
    _liteUserId = userId;
  }

  /// 간이 후기 게시 구간 종료 — 성공·실패와 무관하게 반드시 호출(finally).
  void endLiteSession() {
    _liteToken = null;
    _liteUserId = null;
  }

  /// 앱 시작 시 1회 호출 — 저장된 세션 복원(+ 구버전 SharedPreferences 토큰 마이그레이션).
  Future<void> load() async {
    _access = await _store.readSecure(_kAccess);
    // 웹은 refresh 를 저장하지 않으므로 복원할 것도 없다(항상 null).
    _refresh = _store.persistsRefresh
        ? await _store.readSecure(_kRefresh)
        : null;
    // 레거시: 구버전은 access 를 SharedPreferences 에 보관 → secure 로 이전.
    if (_access == null) {
      final legacy = await _store.readPlain(_kLegacyToken);
      if (legacy != null) {
        _access = legacy;
        await _store.writeSecure(_kAccess, legacy);
        await _store.deletePlain(_kLegacyToken);
      }
    }
    final userStr = await _store.readPlain(_kUser);
    if (userStr != null) {
      try {
        _user = AuthUser.fromJson(jsonDecode(userStr) as Map);
      } catch (e, st) {
        // 저장된 사용자 JSON 이 깨졌다 = 모델 변경과 저장본이 어긋났다는 뜻.
        // 로그인 상태가 조용히 풀리는 원인이라 반드시 알아야 한다.
        ErrorReporter.report(e, where: 'session.restoreUser', stackTrace: st);
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
    // 웹도 메모리에는 들고 있는다 — 로그아웃 시 서버 family 회수에 필요하다.
    // 다만 아래에서 저장하지 않고, isAccessExpiringSoon 이 갱신도 막는다.
    _refresh = refresh;
    await _store.writeSecure(_kAccess, access);
    if (_store.persistsRefresh) {
      if (refresh != null) {
        await _store.writeSecure(_kRefresh, refresh);
      } else {
        await _store.deleteSecure(_kRefresh);
      }
    }
    await _store.writePlain(_kUser, jsonEncode(user.toJson()));
    notifyListeners();
  }

  /// 사용자 정보만 갱신(access/refresh 토큰 유지). 프로필 수정(닉네임 등)용.
  Future<void> updateUser(AuthUser user) async {
    _user = user;
    await _store.writePlain(_kUser, jsonEncode(user.toJson()));
    notifyListeners();
  }

  Future<void> clear() async {
    _access = null;
    _refresh = null;
    _user = null;
    await _store.deleteSecure(_kAccess);
    await _store.deleteSecure(_kRefresh);
    await _store.deletePlain(_kUser);
    await _store.deletePlain(_kLegacyToken);
    notifyListeners();
  }

  /// access exp 가 [skew] 초 내로 임박하면 true. refresh 없으면(레거시) 항상 false.
  /// 웹은 refresh 를 갱신에 쓰지 않으므로(결정 7) 항상 false — 세션 상한이
  /// access 수명(8시간)으로 고정된다.
  bool isAccessExpiringSoon({int skew = 60}) {
    if (!_store.persistsRefresh) return false;
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
    // 웹은 갱신하지 않는다 — 회전된 새 refresh 를 저장할 곳이 없고, 8시간 상한이
    // 이 정책의 핵심이다(결정 7).
    if (!_store.persistsRefresh) return;
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
          await _store.writeSecure(_kRefresh, nr);
          _refresh = nr;
        }
        _access = data['token'] as String;
        await _store.writeSecure(_kAccess, _access!);
        // realtime(채팅) 연결도 새 토큰으로 재인증 — 안 하면 8h 후 만료로 끊길 수 있음.
        try {
          unawaited(Supabase.instance.client.realtime.setAuth(_access));
        } catch (e) {
          ErrorReporter.ignored(
            e,
            where: 'session.realtimeReauth',
            why: 'realtime 미연결 — 다음 연결 시 새 토큰으로 붙는다',
          );
        }
        // notifyListeners 안 함 — 로그인 상태 변화 없음(토큰만 교체, 리빌드 불필요).
      } else {
        await _invalidate(); // 예상 밖 응답 → 세션 만료 처리
      }
    } on FunctionException catch (e) {
      // 강제 로그아웃은 사용자가 바로 체감한다 — 빈도가 튀면 서버 쪽 문제다.
      ErrorReporter.userFacing(e, where: 'session.refresh.rejected');
      await _invalidate(); // 401 invalid_refresh 등 → 강제 로그아웃
    } catch (e) {
      // 네트워크 오류: 세션 유지(다음 요청에서 재시도). 기존 access 로 계속 시도.
      // (서버가 이미 회전을 커밋했더라도 rt_rotate 의 유실 복구가 세션을 살린다.)
      ErrorReporter.ignored(
        e,
        where: 'session.refresh',
        why: '네트워크 오류 — 세션 유지하고 다음 요청에서 재시도',
      );
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
    } catch (e) {
      ErrorReporter.ignored(
        e,
        where: 'session.refresh.retry',
        why: '1회 재시도로 흡수 — 실패하면 위에서 다시 잡힌다',
      );
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
    } catch (e) {
      // 네트워크/일시 오류: 무효로 단정하지 않음(오탐 로그아웃 방지).
      ErrorReporter.ignored(
        e,
        where: 'session.aliveCheck',
        why: '일시 오류를 세션 무효로 단정하면 오탐 로그아웃이 난다',
      );
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
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map;
      final exp = payload['exp'];
      return exp is int ? exp : null;
    } catch (e) {
      // 만료시각을 못 읽으면 호출부가 '알 수 없음' 으로 다루고 갱신을 시도한다.
      ErrorReporter.ignored(
        e,
        where: 'session.jwtExp',
        why: '해독 실패 시 호출부가 갱신을 시도하므로 동작에 영향 없음',
      );
      return null;
    }
  }
}
