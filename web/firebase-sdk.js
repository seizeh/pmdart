// Firebase JS SDK 선(先)로드 — CSP 를 열지 않기 위한 우회.
//
// firebase_core_web 는 SDK 를 이렇게 가져온다: **인라인 <script>** 를 만들어
// head 에 넣고, 그 안에서 `import(gstatic…)` 를 실행한 뒤 결과 모듈을
// `window.firebase_core` / `window.firebase_messaging` 에 심는다.
//
// 그 인라인 스크립트가 우리 CSP(script-src 에 'unsafe-inline' 없음)에 막힌다.
// Trusted Types 래핑은 통과하지만 script-src 는 별개다. 막히면 트리거 함수가
// 정의되지 않아 `_this[method] is not a function` 으로 초기화가 죽는다
// (정책은 만들어지고 gstatic 요청은 0건인 상태가 증상).
//
// 해법: 같은 전역을 **우리가 먼저 채운다**. firebase_core_web 의 _initializeCore 는
//   if (globalContext['firebase_core'] != null) return;
// 로 시작하므로, 채워져 있으면 주입 자체를 하지 않는다. 이 파일은 외부 파일이라
// script-src 'self' 로 실행되고, 아래 import() 는 script-src 의 www.gstatic.com 이 받는다.
//
// ⚠️ 전역 이름과 SDK 버전은 firebase_core_web 이 정한 규약이다.
//    · 전역: `firebase_<service.override ?? service.name>` → core / messaging
//    · 버전: firebase_core_web 의 supportedFirebaseJsSdkVersion (현재 11.9.1)
//    firebase_core_web 을 올릴 때 이 값들도 같이 맞춰야 한다. 어긋나면 플러그인이
//    자기 버전으로 다시 주입을 시도하다 위 증상으로 돌아간다.
const V = '11.9.1';
const BASE = `https://www.gstatic.com/firebasejs/${V}`;

// main.dart 가 Firebase.initializeApp 전에 이 프라미스를 기다린다 —
// 안 기다리면 CanvasKit 이 빨리 뜬 경우 초기화가 로드를 앞질러 주입 경로로 샌다.
window.__pawmateFirebaseSdkReady = (async () => {
  const [core, messaging] = await Promise.all([
    import(`${BASE}/firebase-app.js`),
    import(`${BASE}/firebase-messaging.js`),
  ]);
  window.firebase_core = core;
  window.firebase_messaging = messaging;
})().catch((e) => {
  // 실패해도 앱은 그대로 뜬다 — 푸시만 없는 상태로 폴백(PushService 가 예외를 삼킨다).
  console.warn('[pawmate] Firebase SDK 선로드 실패 — 웹 푸시 비활성:', e);
});
