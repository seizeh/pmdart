import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'session.dart';

/// 백그라운드/종료 상태 수신 핸들러(반드시 top-level, vm:entry-point).
/// 서버가 `notification` 페이로드를 보내므로 표시는 OS 가 자동으로 한다 — 여기선 별도 처리 불필요.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

/// OS 푸시(FCM) 연동.
///  · 앱 시작/로그인 시 FCM 토큰을 register_device_token 으로 서버에 등록(로그인 상태에서만).
///  · 백그라운드/종료: 서버 notification 페이로드 → OS 가 표시(코드 불필요).
///  · 포그라운드: onForeground 콜백(스낵바 등), 탭: onOpen 콜백(라우팅). main.dart 가 세팅.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  final FirebaseMessaging _fm = FirebaseMessaging.instance;
  bool _inited = false;

  /// 알림 탭으로 앱 진입 시(type, resourceType, resourceId).
  void Function(String type, String? resourceType, String? resourceId)? onOpen;

  /// 포그라운드 수신 시(title, body).
  void Function(String? title, String? body)? onForeground;

  Future<void> init() async {
    if (_inited) return;
    _inited = true;
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await _fm.requestPermission(alert: true, badge: true, sound: true);
    // iOS 포그라운드에서도 배너/사운드 표시.
    await _fm.setForegroundNotificationPresentationOptions(
        alert: true, badge: true, sound: true);

    _fm.onTokenRefresh.listen(_register);
    FirebaseMessaging.onMessage.listen((m) {
      onForeground?.call(m.notification?.title, m.notification?.body);
    });
    FirebaseMessaging.onMessageOpenedApp.listen(_handleOpen);
    final initial = await _fm.getInitialMessage(); // 종료 상태에서 탭으로 진입
    if (initial != null) _handleOpen(initial);

    if (SessionManager.instance.isLoggedIn) await registerToken();
  }

  /// 로그인 성공/앱 시작 시 호출 — 현재 FCM 토큰을 서버에 등록.
  Future<void> registerToken() async {
    if (!SessionManager.instance.isLoggedIn) return;
    try {
      if (Platform.isIOS) await _fm.getAPNSToken(); // APNs 토큰 준비 대기
      final token = await _fm.getToken();
      if (token != null) await _register(token);
    } catch (_) {/* APNs 미설정 등 — 조용히 무시 */}
  }

  Future<void> _register(String token) async {
    if (!SessionManager.instance.isLoggedIn) return;
    try {
      await Supabase.instance.client.rpc('register_device_token', params: {
        'p_token': token,
        'p_platform': Platform.isIOS ? 'ios' : 'android',
        'p_device_name': null,
      });
    } catch (_) {/* 네트워크/권한 — 다음 기회에 재등록 */}
  }

  /// 로그아웃/세션 무효화 시 — FCM 토큰 삭제. 서버 토큰은 다음 발송 실패로 자동 비활성화된다.
  Future<void> clearToken() async {
    try {
      await _fm.deleteToken();
    } catch (_) {}
  }

  void _handleOpen(RemoteMessage m) {
    final d = m.data;
    onOpen?.call(
        (d['type'] ?? '') as String, d['resource_type'] as String?, d['resource_id'] as String?);
  }
}
