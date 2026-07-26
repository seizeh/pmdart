import 'package:web/web.dart' as web;

/// 웹 세션 저장소 — 전부 `sessionStorage`(탭 단위, 닫으면 소멸).
///
/// `localStorage` 도 `flutter_secure_storage` 도 쓰지 않는다. 후자의 웹 구현은
/// localStorage + AES 인데 복호화 키까지 같은 localStorage 에 있어 난독화에
/// 불과하다. 영속 저장소에 장기 자격증명을 두지 않는 편이 낫다.
///
/// refresh 는 [persistsRefresh] = false 라 아예 쓰이지 않는다 — 세션은 access
/// 수명(8시간)으로 상한이 걸리고 갱신되지 않는다.
class SessionStore {
  const SessionStore();

  /// 웹은 refresh 를 영속화하지 않는다.
  bool get persistsRefresh => false;

  String? _read(String key) => web.window.sessionStorage.getItem(key);
  void _write(String key, String value) =>
      web.window.sessionStorage.setItem(key, value);
  void _delete(String key) => web.window.sessionStorage.removeItem(key);

  // 웹에는 secure/plain 구분이 없다 — 둘 다 sessionStorage.
  Future<String?> readSecure(String key) async => _read(key);
  Future<void> writeSecure(String key, String value) async =>
      _write(key, value);
  Future<void> deleteSecure(String key) async => _delete(key);

  Future<String?> readPlain(String key) async => _read(key);
  Future<void> writePlain(String key, String value) async => _write(key, value);
  Future<void> deletePlain(String key) async => _delete(key);
}
