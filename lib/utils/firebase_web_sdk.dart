/// 웹에서 Firebase JS SDK 선로드가 끝나기를 기다린다(웹 외에는 즉시 완료).
///
/// 왜 필요한지는 `web/firebase-sdk.js` 주석 참고 — 요약하면 CSP 를 열지 않으려고
/// SDK 를 우리가 먼저 로드하는데, `Firebase.initializeApp` 이 그보다 먼저 돌면
/// 플러그인이 (막혀 있는) 인라인 주입 경로로 새기 때문이다.
library;

export 'firebase_web_sdk_io.dart'
    if (dart.library.js_interop) 'firebase_web_sdk_web.dart';
