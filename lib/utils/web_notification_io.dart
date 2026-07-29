/// 네이티브 — 브라우저 알림이라는 개념이 없다(Android 는 flutter_local_notifications).
bool get canShowWebNotification => false;

Future<void> showWebNotification({
  required String? title,
  required String? body,
  required String tag,
  required void Function() onClick,
}) async {}
