import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 네이티브 세션 저장소 — 기존 동작 그대로.
/// 민감(access/refresh)은 secure storage, 비민감(user)은 SharedPreferences.
class SessionStore {
  const SessionStore();

  static const _secure = FlutterSecureStorage();

  /// 이 플랫폼이 refresh 토큰을 영속화하는가. 네이티브는 한다(30일 회전 세션).
  bool get persistsRefresh => true;

  Future<String?> readSecure(String key) => _secure.read(key: key);

  Future<void> writeSecure(String key, String value) =>
      _secure.write(key: key, value: value);

  Future<void> deleteSecure(String key) => _secure.delete(key: key);

  Future<String?> readPlain(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

  Future<void> writePlain(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);

  Future<void> deletePlain(String key) async =>
      (await SharedPreferences.getInstance()).remove(key);
}
