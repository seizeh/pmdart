/// 세션 영속 저장소 — 플랫폼별로 정책이 다르다.
///
///  · 앱(네이티브): access/refresh 는 `flutter_secure_storage`(Keychain·Keystore),
///    user 는 `SharedPreferences`. 30일 회전 세션을 그대로 유지한다.
///  · 웹: 전부 `sessionStorage` — **탭을 닫으면 사라진다.** refresh 는 아예
///    영속화하지 않아 XSS 로 새어나갈 수 있는 최대치가 access 하나(8시간)이고
///    갱신도 불가능하다. 웹은 앱 유입 퍼널이라 이 정도 제약이 맞는 교환이다
///    (docs/web-port.md 결정 7).
///
/// 웹에서 localStorage 를 쓰지 않는 이유: `flutter_secure_storage` 의 웹 구현이
/// localStorage + AES 인데 키도 같은 localStorage 에 있어 사실상 난독화다.
/// 영속 저장소에 장기 자격증명을 두지 않는 쪽이 낫다.
library;

export 'session_store_io.dart'
    if (dart.library.js_interop) 'session_store_web.dart';
