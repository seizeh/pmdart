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

// 알림 탭 — 서버(send-push)가 웹 토큰에 실은 webpush.fcm_options.link 로 보낸다.
// 링크는 게시글(/p/<id>)·사용자(/u/<id>) 알림에만 있다. 채팅·공지처럼 웹 화면이
// 없는 알림은 링크가 없어 열린 탭을 앞으로 가져오기만 한다.
//
// ⚠️ 이 처리기는 아래 firebase.messaging() 보다 **먼저** 등록해야 한다. SDK 도
// notificationclick 처리기를 거는데, 링크가 없으면 아무 데도 열지 않고 링크가 있으면
// 그 주소의 탭이 없을 때마다 새 창을 연다. 먼저 등록된 이 처리기가
// stopImmediatePropagation 으로 같은 클릭을 SDK 에 넘기지 않는다.
//
// 열린 탭이 있으면 그 탭에서 옮긴다. 웹 세션은 탭별 sessionStorage 라 새 창을 열면
// 로그아웃 상태로 열리기 때문이다. 다만 이 SW 는 FCM 전용 범위
// (/firebase-cloud-messaging-push-scope)에 등록돼 앱 페이지를 제어하지 않으므로
// WindowClient.navigate 를 쓸 수 없다(제어하지 않는 탭에는 거절된다). 그래서 링크를
// postMessage 로 넘기고, 페이지의 notification_link.js 가 같은 탭에서 그 주소로 옮긴다.
self.addEventListener('notificationclick', function (event) {
  var data = (event.notification && event.notification.data) || {};
  var msg = data.FCM_MSG || {};
  var link =
    (msg.fcmOptions && msg.fcmOptions.link) ||
    (msg.notification && msg.notification.click_action) ||
    data.link ||
    null;
  event.stopImmediatePropagation();
  event.notification.close();
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true })
      .then(function (list) {
        // 우리 오리진의 탭 중 포커스된 것 → 보이는 것 → 아무거나 순으로 고른다.
        var tab = null;
        for (var i = 0; i < list.length; i++) {
          var c = list[i];
          if (c.url.indexOf(self.location.origin) !== 0 || !('focus' in c)) continue;
          if (!tab || c.focused || (c.visibilityState === 'visible' && !tab.focused)) tab = c;
        }
        if (tab) {
          if (link) tab.postMessage({ pawmateOpenLink: link });
          return tab.focus();
        }
        if (self.clients.openWindow) return self.clients.openWindow(link || '/');
      })
  );
});

// SDK 의 push·pushsubscriptionchange·notificationclick 처리기는 이 인스턴스를 만들 때
// 등록된다(compat SDK 는 지연 생성이다). 부르지 않으면 백그라운드에서 온 푸시를
// SDK 가 표시하지 못한다 — 2026-10-26 까지 이 줄이 없었다. 탭이 보이는 동안 온 푸시는
// SDK 가 시스템 알림 대신 페이지로 넘기고, 앱은 그 메시지를 쓰지 않는다(그 동안의
// 표시는 실시간 구독의 인앱 배너가 맡는다).
firebase.messaging();
