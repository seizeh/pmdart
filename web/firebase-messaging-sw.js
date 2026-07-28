// FCM 웹 푸시 서비스워커.
//
// Firebase JS SDK 가 `getToken()` 시점에 **오리진 루트의 이 파일**을 자동으로
// 등록한다(경로·파일명 고정 — 바꾸면 못 찾는다).
//
// ⚠️ importScripts 대상이 gstatic 이라 **CSP 의 script-src 에 www.gstatic.com 이
// 있어야 한다**(web/_headers). 서비스워커는 자기 스크립트와 함께 내려온 CSP 를
// 따르므로, 페이지가 되는데 여기서만 막히는 일이 생긴다.
//
// 버전은 firebase_core_web 의 supportedFirebaseJsSdkVersion 과 맞춘다. 어긋나면
// 페이지 쪽 SDK 와 서로 다른 인스턴스가 떠서 토큰 발급이 조용히 실패할 수 있다.
importScripts('https://www.gstatic.com/firebasejs/11.9.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/11.9.1/firebase-messaging-compat.js');

// lib/firebase_options.dart 의 web 설정과 같은 값. 여기 값들은 전부 공개용이다.
firebase.initializeApp({
  apiKey: 'AIzaSyBIuKt-dVaq2EZIoN5kpORiMtCYUahr3Tw',
  appId: '1:451837752323:web:8acd848728fd2d8f5f0a36',
  messagingSenderId: '451837752323',
  projectId: 'pawmate-7e881',
  authDomain: 'pawmate-7e881.firebaseapp.com',
  storageBucket: 'pawmate-7e881.firebasestorage.app',
});

// 서버(send-push)가 notification 페이로드를 실어 보내므로 표시는 SDK 가 한다 —
// onBackgroundMessage 를 따로 두지 않는다(두면 알림이 두 번 뜬다).

// 알림 탭 — webpush.fcm_options.link 로 온 주소를 연다. 이미 열려 있는 탭이
// 있으면 그 탭을 포커스하고 이동시킨다(새 탭이 계속 쌓이는 것 방지).
self.addEventListener('notificationclick', function (event) {
  var link =
    (event.notification && event.notification.data &&
      (event.notification.data.link ||
        (event.notification.data.FCM_MSG &&
          event.notification.data.FCM_MSG.notification &&
          event.notification.data.FCM_MSG.notification.click_action))) ||
    '/';
  event.notification.close();
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true })
      .then(function (list) {
        for (var i = 0; i < list.length; i++) {
          var c = list[i];
          if (c.url.indexOf(self.location.origin) === 0 && 'focus' in c) {
            if ('navigate' in c) c.navigate(link);
            return c.focus();
          }
        }
        if (self.clients.openWindow) return self.clients.openWindow(link);
      })
  );
});
