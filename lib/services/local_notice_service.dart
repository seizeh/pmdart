import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../utils/platform_info.dart';
import '../utils/web_notification.dart';

/// 포그라운드 OS 알림(Android · **웹**) — 앱이 켜져 있을 때도 백그라운드 푸시와
/// 동일한 형태의 시스템 알림으로 보여준다(기존 하단 토스트 배너 대체).
///
/// 표시는 realtime 알림 구독(main.dart) 경로가 호출한다 — FCM 포그라운드가
/// 아니라 realtime 을 쓰는 이유(시뮬레이터·토큰 미등록에서도 도착)와
/// "보고 있는 채팅방은 조용히" 같은 건별 억제 규칙은 기존과 동일하다.
/// 백그라운드/종료 상태 표시는 그대로 서버 notification 페이로드 → OS 담당.
///
/// **웹도 이 경로가 필요하다.** Firebase JS SDK 는 보이는 탭이 있으면 메시지를
/// 서비스워커가 아니라 페이지로 보내고 **알림을 표시하지 않는다** — 그래서 웹
/// 포그라운드에는 표시 주체가 아무도 없었다(docs/web-port.md Phase D). 여기에
/// 붙이면 "보고 있는 채팅방은 조용히" 같은 기존 억제 규칙을 그대로 물려받는다.
///
/// ⚠️ iOS 에서는 이 플러그인을 초기화하지 않는다 — UNUserNotificationCenter
/// 델리게이트를 가로채 FCM 의 포그라운드 표시/알림 탭 라우팅(onMessageOpenedApp)
/// 을 깨뜨린다(표시 안 됨·탭해도 커뮤니티로 열리던 원인). iOS 포그라운드 표시는
/// FCM 의 OS 배너(setForegroundNotificationPresentationOptions)가 담당.
class LocalNoticeService {
  LocalNoticeService._();
  static final LocalNoticeService instance = LocalNoticeService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _inited = false;
  int _seq = 0;

  /// 알림 탭 시(type, resourceType, resourceId) — 푸시 탭과 동일한 라우팅에 연결.
  void Function(String type, String? resourceType, String? resourceId)? onTap;

  static const _channel = AndroidNotificationChannel(
    'default_high',
    '알림',
    description: '채팅·댓글·초대 등 앱 알림',
    importance: Importance.high,
  );

  Future<void> init() async {
    if (_inited) return;
    // 웹은 플러그인이 아니라 브라우저 Notification 을 쓴다 — 초기화할 것이 없다.
    if (kIsWeb) {
      _inited = true;
      return;
    }
    if (!isAndroid) return;
    _inited = true;
    try {
      // 권한 요청은 FCM(requestPermission)이 이미 담당 — 여기선 요청하지 않는다.
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: _handleTap,
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_channel);
      // 종료 상태에서 이 플러그인의 알림을 탭해 콜드스타트한 경우 —
      // onDidReceiveNotificationResponse 는 실행 중 탭만 받으므로 런치 상세를
      // 따로 확인해 같은 라우팅에 태운다(#239, 안 하면 payload 유실 → 홈 착지).
      // onTap 연결(main.dart)이 init 호출보다 먼저라 순서는 보장된다.
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final resp = launch?.notificationResponse;
      if (launch?.didNotificationLaunchApp == true && resp != null) {
        _handleTap(resp);
      }
    } catch (e) {
      debugPrint('localNotice: 초기화 실패 — $e');
    }
  }

  /// realtime 알림 1건을 OS 시스템 알림으로 표시.
  Future<void> show({
    required String? title,
    required String? body,
    required String type,
    String? resourceType,
    String? resourceId,
  }) async {
    if (!_inited) return; // iOS — FCM OS 배너가 담당
    if ((title ?? '').isEmpty && (body ?? '').isEmpty) return;
    if (kIsWeb) {
      await showWebNotification(
        title: title,
        body: body,
        // 같은 채팅방 연속 메시지는 갱신, 그 외는 개별 표시(아래 android 와 동일 규칙).
        tag: (type == 'chat_message' && resourceId != null)
            ? 'chat:$resourceId'
            : 'n:${_seq++}',
        onClick: () => onTap?.call(type, resourceType, resourceId),
      );
      return;
    }
    try {
      await _plugin.show(
        // 같은 채팅방 연속 메시지는 갱신, 그 외는 개별 표시.
        (type == 'chat_message' && resourceId != null)
            ? resourceId.hashCode
            : _seq++,
        (title ?? '').isEmpty ? null : title,
        (body ?? '').isEmpty ? null : body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'default_high',
            '알림',
            channelDescription: '채팅·댓글·초대 등 앱 알림',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: jsonEncode({
          'type': type,
          'resource_type': resourceType,
          'resource_id': resourceId,
        }),
      );
    } catch (e) {
      debugPrint('localNotice: 표시 실패 — $e');
    }
  }

  void _handleTap(NotificationResponse r) {
    final raw = r.payload;
    if (raw == null || raw.isEmpty) return;
    try {
      final d = jsonDecode(raw) as Map<String, dynamic>;
      onTap?.call(
        (d['type'] ?? '') as String,
        d['resource_type'] as String?,
        d['resource_id'] as String?,
      );
    } catch (e) {
      debugPrint('알림 탭 페이로드 파싱 실패(라우팅 생략): $e');
    }
  }
}
