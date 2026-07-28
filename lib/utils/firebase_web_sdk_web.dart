import 'dart:js_interop';

@JS('__pawmateFirebaseSdkReady')
external JSPromise<JSAny?>? get _sdkReady;

/// `web/firebase-sdk.js` 가 심어 둔 프라미스를 기다린다.
/// 스크립트가 없거나(구 배포본 캐시 등) 실패해도 던지지 않는다 — 푸시만 없는
/// 상태로 폴백하고 앱은 정상 동작해야 한다.
Future<void> ensureFirebaseSdkReady() async {
  final p = _sdkReady;
  if (p == null) return;
  try {
    await p.toDart;
  } catch (_) {
    /* 선로드 실패 — 웹 푸시 없이 진행 */
  }
}
