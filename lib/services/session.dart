import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  factory AuthUser.fromJson(Map json) => AuthUser(
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

/// 앱 전역 세션. 커스텀 JWT 를 보관하고 모든 Supabase 요청에 첨부된다
/// (main.dart 의 Supabase.initialize accessToken 콜백이 [token] 을 읽음).
class SessionManager extends ChangeNotifier {
  SessionManager._();
  static final SessionManager instance = SessionManager._();

  static const _kToken = 'session_token';
  static const _kUser = 'session_user';

  String? _token;
  AuthUser? _user;

  String? get token => _token;
  AuthUser? get user => _user;
  bool get isLoggedIn => _token != null && _user != null;

  /// 앱 시작 시 1회 호출 — 저장된 세션 복원.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_kToken);
    final userStr = prefs.getString(_kUser);
    if (userStr != null) {
      try {
        _user = AuthUser.fromJson(jsonDecode(userStr) as Map);
      } catch (_) {
        _user = null;
      }
    }
    // 토큰/유저 중 하나라도 없으면 비로그인으로 간주
    if (_token == null || _user == null) {
      _token = null;
      _user = null;
    }
  }

  Future<void> setSession(String token, AuthUser user) async {
    _token = token;
    _user = user;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToken, token);
    await prefs.setString(_kUser, jsonEncode(user.toJson()));
    notifyListeners();
  }

  Future<void> clear() async {
    _token = null;
    _user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    await prefs.remove(_kUser);
    notifyListeners();
  }
}
