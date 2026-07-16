import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 포그라운드 OS 알림(Android 전용) — 앱이 켜져 있을 때도 백그라운드 푸시와
/// 동일한 형태의 시스템 알림으로 보여준다(기존 하단 토스트 배너 대체).
///
/// 표시는 realtime 알림 구독(main.dart) 경로가 호출한다 — FCM 포그라운드가
/// 아니라 realtime 을 쓰는 이유(시뮬레이터·토큰 미등록에서도 도착)와
/// "보고 있는 채팅방은 조용히" 같은 건별 억제 규칙은 기존과 동일하다.
/// 백그라운드/종료 상태 표시는 그대로 서버 notification 페이로드 → OS 담당.
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
    if (_inited || !Platform.isAndroid) return;
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
    } catch (_) {}
  }
}
