import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// 권한이 허용돼 있어야만 표시할 수 있다. 여기서 권한을 **요청하지는 않는다** —
/// 요청은 푸시 토큰 발급(PushService)이 이미 담당한다.
bool get canShowWebNotification => web.Notification.permission == 'granted';

/// 브라우저 알림 1건.
///
/// 서비스워커의 `showNotification` 이 아니라 **페이지 레벨** `Notification` 을 쓴다.
/// 클릭을 페이지에서 받아야 인앱 라우팅(`onClick`)이 되기 때문이다 — 서비스워커로
/// 띄우면 클릭이 SW 의 `notificationclick` 으로 가고, 이미 열려 있는 탭을
/// `navigate()` 로 **리로드**하게 된다(포그라운드에서는 특히 손해다).
///
/// 대신 페이지 레벨 생성자는 **Android Chrome 에서 던진다**(그쪽은 SW 로만 가능).
/// 그 경우는 조용히 넘긴다 — 포그라운드라 사용자가 이미 앱을 보고 있고,
/// 백그라운드 알림은 어차피 SW 가 담당한다.
///
/// [tag] 가 같으면 브라우저가 기존 알림을 갱신한다(같은 채팅방 연속 메시지용).
Future<void> showWebNotification({
  required String? title,
  required String? body,
  required String tag,
  required void Function() onClick,
}) async {
  if (!canShowWebNotification) return;
  try {
    final n = web.Notification(
      (title ?? '').isEmpty ? 'PawMate' : title!,
      web.NotificationOptions(
        body: body ?? '',
        tag: tag,
        icon: 'icons/Icon-192.png',
      ),
    );
    n.onclick = (web.Event _) {
      web.window.focus(); // 다른 창을 보고 있었을 수 있다
      n.close();
      onClick();
    }.toJS;
  } catch (e) {
    // Android Chrome 등 — 페이지 레벨 생성자 미지원.
    debugPrint('webNotice: 표시 생략 — $e');
  }
}
