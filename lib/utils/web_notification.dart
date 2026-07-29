/// 브라우저 알림 1건 표시(웹 전용, 그 외 플랫폼은 no-op).
///
/// **포그라운드 전용 경로**다. 탭이 보이는 동안 Firebase JS SDK 는 메시지를
/// 서비스워커가 아니라 페이지로 보내고 알림을 **표시하지 않으므로**, 그 구간을
/// realtime → `LocalNoticeService` 가 메운다(docs/web-port.md Phase D).
library;

export 'web_notification_io.dart'
    if (dart.library.js_interop) 'web_notification_web.dart';
