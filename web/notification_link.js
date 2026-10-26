// 웹 푸시 알림 탭 → 이 탭에서 해당 화면으로 이동.
//
// firebase-messaging-sw.js 의 notificationclick 이 열린 탭을 찾으면 그 탭에
// { pawmateOpenLink: '<주소>' } 를 보낸다. SW 가 앱 페이지를 제어하지 않아
// WindowClient.navigate 를 쓸 수 없기 때문이다(자세한 이유는 그 파일 주석).
// 같은 탭에서 옮겨야 로그인이 유지된다 — 웹 세션은 탭별 sessionStorage 다.
//
// 이동은 전체 다시 불러오기다. 앱은 진입 경로(/p/<id>·/u/<id>)를 첫 화면에서 읽어
// 그 화면을 연다(lib/utils/web_link.dart). 같은 오리진 주소만 따르고, 지금 주소와
// 같으면 아무것도 하지 않는다.
//
// CSP 가 인라인 스크립트를 막아(script-src 'self') 별도 파일로 둔다.
(function () {
  if (!('serviceWorker' in navigator)) return;
  navigator.serviceWorker.addEventListener('message', function (event) {
    var link = event.data && event.data.pawmateOpenLink;
    if (typeof link !== 'string' || !link) return;
    var url;
    try {
      url = new URL(link, window.location.href);
    } catch (e) {
      return;
    }
    if (url.origin !== window.location.origin) return;
    if (url.pathname + url.search === window.location.pathname + window.location.search) return;
    window.location.assign(url.href);
  });
})();
