import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../env.dart';
import '../utils/platform_info.dart';
import 'session.dart';

/// 백그라운드/종료 상태 수신 핸들러(반드시 top-level, vm:entry-point).
/// 서버가 `notification` 페이로드를 보내므로 표시는 OS 가 자동으로 한다 — 여기선 별도 처리 불필요.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

/// OS 푸시(FCM) 연동.
///  · 앱 시작/로그인 시 FCM 토큰을 register_device_token 으로 서버에 등록(로그인 상태에서만).
///  · 백그라운드/종료: 서버 notification 페이로드 → OS 가 표시(코드 불필요).
///  · 포그라운드: 인앱 배너는 realtime 알림 구독이 담당(FCM 아님), 탭: onOpen 콜백(라우팅).
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  /// ⚠️ 필드가 아니라 게터다. 필드로 두면 `PushService.instance` 를 만드는
  /// 순간 평가되는데, Firebase 초기화 전이면 `[core/no-app]` 로 던진다. 그러면
  /// 로그인 성공 직후 registerToken 호출에서 터져 "로그인이 안 된다"로 보인다
  /// (웹 이식 때 실제로 겪었다). 공개 진입점들이 [_enabled] 로 먼저 거르므로
  /// 초기화되지 않은 상태에서는 평가되지 않는다.
  FirebaseMessaging get _fm => FirebaseMessaging.instance;
  bool _inited = false;

  /// 알림 탭으로 앱 진입 시(type, resourceType, resourceId).
  void Function(String type, String? resourceType, String? resourceId)? onOpen;

  /// 이 플랫폼에서 푸시를 쓸 수 있는지.
  ///
  /// 웹은 VAPID 공개키가 있어야 토큰을 못 받는다 — 키 없이 진행하면 브라우저
  /// 알림 권한 팝업만 띄우고 등록은 실패하는, 사용자에게 가장 나쁜 상태가 된다.
  /// 그래서 키가 비면 아예 시작하지 않는다.
  static bool get _enabled => !kIsWeb || Env.webPushVapidKey.isNotEmpty;

  Future<void> init() async {
    if (!_enabled || _inited) return;
    _inited = true;

    // 웹은 아래 네이티브 전용 배선(백그라운드 핸들러·APNs·iOS 탭 채널)이 전부
    // 해당 없다. 표시는 firebase-messaging-sw.js 가, 탭 라우팅은 그 SW 의
    // notificationclick(webpush.fcm_options.link)이 담당한다.
    if (kIsWeb) {
      if (SessionManager.instance.isLoggedIn) await registerToken();
      return;
    }

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    final settings = await _fm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('push: 알림 권한 = ${settings.authorizationStatus}');
    // iOS 포그라운드도 OS 배너로 — 백그라운드 푸시와 동일한 형태의 알림.
    // (Android 포그라운드는 realtime → flutter_local_notifications 가 담당.
    //  iOS 에 그 플러그인을 쓰면 알림 델리게이트를 가로채 FCM 표시·탭 라우팅이
    //  깨져서, iOS 는 FCM 의 네이티브 포그라운드 표시를 쓴다.)
    // 한계: OS 배너는 건별 억제가 안 돼 "보고 있는 채팅방은 조용히" 규칙이
    // iOS 포그라운드에선 적용되지 않는다(네이티브 willPresent 확장으로 추후 개선).
    await _fm.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    _fm.onTokenRefresh.listen(_register);
    if (isIOS) {
      // SceneDelegate 환경에선 FCM 의 탭 스트림(onMessageOpenedApp)이 유실된다 —
      // 네이티브(AppDelegate)가 알림 탭을 이 채널로 전달한다(콜드 스타트는 버퍼 회수).
      _iosTapChannel.setMethodCallHandler((call) async {
        if (call.method == 'tap') _handleTapMap(call.arguments);
      });
      try {
        final pending = await _iosTapChannel.invokeMethod<dynamic>(
          'getPendingTap',
        );
        if (pending != null) _handleTapMap(pending);
      } catch (e) {
        debugPrint('push: pendingTap 회수 실패 — $e');
      }
    } else {
      FirebaseMessaging.onMessageOpenedApp.listen(_handleOpen);
      final initial = await _fm.getInitialMessage(); // 종료 상태에서 탭으로 진입
      if (initial != null) _handleOpen(initial);
    }

    if (SessionManager.instance.isLoggedIn) await registerToken();
  }

  /// 로그인 성공/앱 시작 시 호출 — 현재 FCM 토큰을 서버에 등록.
  Future<void> registerToken() async {
    if (!_enabled) return; // Firebase 미초기화 상태에서 만지면 [core/no-app] 로 던진다
    if (!SessionManager.instance.isLoggedIn) return;
    try {
      if (kIsWeb) {
        // 웹은 VAPID 공개키가 있어야 구독이 만들어진다. 이 호출이 루트의
        // /firebase-messaging-sw.js 를 등록하고 브라우저 알림 권한도 함께 묻는다.
        final token = await _fm.getToken(vapidKey: Env.webPushVapidKey);
        debugPrint('push(web): FCM token ${token == null ? '없음' : '수신됨'}');
        if (token != null) await _register(token);
        return;
      }
      if (isIOS) {
        // APNs 등록이 비동기라 앱 시작 직후엔 null 일 수 있다 — 준비될 때까지 재시도.
        String? apns;
        for (var i = 0; i < 10 && apns == null; i++) {
          apns = await _fm.getAPNSToken();
          if (apns == null) {
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }
        debugPrint('push: APNs token ${apns == null ? '없음' : '수신됨'}');
        if (apns == null) return; // getToken 이 어차피 실패 — 다음 onTokenRefresh 에 맡김
      }
      final token = await _fm.getToken();
      debugPrint('push: FCM token ${token == null ? '없음' : '수신됨'}');
      if (token != null) await _register(token);
    } catch (e) {
      debugPrint('push: 토큰 등록 실패 — $e'); // APNs 미설정 등
    }
  }

  Future<void> _register(String token) async {
    if (!SessionManager.instance.isLoggedIn) return;
    try {
      await Supabase.instance.client.rpc(
        'register_device_token',
        params: {
          'p_token': token,
          // ⚠️ 'web' 은 device_tokens_platform_check 에도 있어야 한다
          // (pmdb 20260728180000). 없으면 INSERT 가 거부돼 조용히 실패한다.
          'p_platform': kIsWeb
              ? 'web'
              : isIOS
              ? 'ios'
              : 'android',
          'p_device_name': null,
        },
      );
      debugPrint('push: 서버에 디바이스 토큰 등록 완료');
    } catch (e) {
      debugPrint('push: 서버 토큰 등록 실패 — $e'); // 네트워크/권한 — 다음 기회에 재등록
    }
  }

  /// 로그아웃/세션 무효화 시 — FCM 토큰 삭제. 서버 토큰은 다음 발송 실패로 자동 비활성화된다.
  Future<void> clearToken() async {
    if (!_enabled) return; // 로그아웃 경로가 여기서 죽으면 세션이 안 지워진다
    try {
      await _fm.deleteToken();
    } catch (e) {
      debugPrint('push: FCM 토큰 삭제 실패(서버측 자동 비활성화에 위임): $e');
    }
  }

  void _handleOpen(RemoteMessage m) {
    final d = m.data;
    onOpen?.call(
      (d['type'] ?? '') as String,
      d['resource_type'] as String?,
      d['resource_id'] as String?,
    );
  }

  static const MethodChannel _iosTapChannel = MethodChannel('pawmate/push_tap');

  /// 네이티브(AppDelegate)가 전달한 알림 탭 페이로드 — 빈 문자열은 null 로.
  void _handleTapMap(dynamic args) {
    final m = (args as Map?) ?? const {};
    String? nn(Object? v) {
      final s = v as String?;
      return (s == null || s.isEmpty) ? null : s;
    }

    onOpen?.call(
      (m['type'] as String?) ?? '',
      nn(m['resource_type']),
      nn(m['resource_id']),
    );
  }
}
