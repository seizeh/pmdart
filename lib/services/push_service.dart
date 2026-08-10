import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../env.dart';
import '../utils/platform_info.dart';
import 'error_reporter.dart';
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

  /// 로그아웃/세션 무효화 시 — **서버 먼저, 기기 나중**(#237).
  ///
  /// 예전엔 기기측 `deleteToken()` 만 하고 서버는 "다음 발송 실패로 자동 비활성화"
  /// 에 맡겼다. 그 기대가 틀렸다 — 토큰이 유효하면 발송이 **성공**하므로 실패가
  /// 없고, 따라서 비활성화도 없다. 오프라인 로그아웃이면 `deleteToken()` 도 실패해
  /// (로그아웃을 막지 않으려 삼킨다) FCM 토큰과 서버 행이 둘 다 살아남는다.
  /// 결과: 그 기기가 이전 계정의 채팅 내용을 무기한 계속 받는다.
  ///
  /// 그래서 순서가 중요하다. 서버 해제를 **먼저** 시도한다 — 여기까지 성공하면
  /// 기기측 삭제가 실패해도 발송 대상에서 빠진다. 반대 순서면 토큰을 지운 뒤
  /// 무엇을 해제해야 할지 모르게 된다.
  Future<void> clearToken() async {
    if (!_enabled) return; // 로그아웃 경로가 여기서 죽으면 세션이 안 지워진다
    // 서버 해제에 쓸 토큰을 먼저 확보(삭제 후엔 못 읽는다).
    String? token;
    try {
      // 웹은 VAPID 키가 있어야 토큰을 돌려준다(registerToken 과 같은 조건).
      token = kIsWeb
          ? await _fm.getToken(vapidKey: Env.webPushVapidKey)
          : await _fm.getToken();
    } catch (e) {
      ErrorReporter.ignored(
        e,
        where: 'push.clearToken.getToken',
        why: '토큰을 못 읽으면 서버 해제를 건너뛴다 — 아래 기기측 삭제는 그대로 시도',
      );
    }
    // 세션이 이미 회수돼 RPC 를 부를 자격이 없는 상태인가.
    // app.uid() 가 token_version 불일치·비활성 상태에서 null 을 주면 RLS 가
    // 42501(not_authenticated)로 막는다 — 강제 로그아웃의 정상 결과다.
    bool isSessionRevoked(Object e) =>
        e is PostgrestException &&
        (e.code == '42501' || e.message.contains('not_authenticated'));

    if (token != null && SessionManager.instance.isLoggedIn) {
      try {
        await Supabase.instance.client.rpc(
          'release_device_token',
          params: {'p_token': token},
        );
      } catch (e, st) {
        // 세션이 이미 회수된 경우(다른 기기 비밀번호 변경·정지·탈퇴)는 실패가
        // **정상이다.** app.uid() 가 token_version 을 보므로 부를 자격이 없고,
        // 기기 토큰은 DB 트리거(users_revoke_device_tokens)가 이미 껐다.
        // 이걸 오류로 올리면 있지도 않은 누수를 알리는 거짓 경보가 된다.
        //
        // 그 밖의 실패(오프라인 로그아웃 등)는 진짜 누수다 — #237 의 재현이므로
        // 얼마나 자주 새는지 계속 본다.
        if (isSessionRevoked(e)) {
          ErrorReporter.ignored(
            e,
            where: 'push.releaseToken',
            why: '세션이 이미 회수됨 — 기기 토큰은 DB 트리거가 껐다',
          );
        } else {
          ErrorReporter.report(e, where: 'push.releaseToken', stackTrace: st);
        }
      }
    }
    try {
      await _fm.deleteToken();
    } catch (e) {
      ErrorReporter.ignored(
        e,
        where: 'push.clearToken.deleteToken',
        why: '기기측 삭제 실패 — 위 서버 해제가 됐다면 발송 대상에선 이미 빠졌다',
      );
    }
  }

  /// 로그인 성공 직후 — 서버 안읽음 카운터를 원본에서 재계산(#232).
  ///
  /// 카운터는 트리거로 증감하는 캐시라 원본과 어긋날 수 있고, 실제로 어긋나 있었다
  /// (운영에서 80 vs 2). 앱 안의 목록 카운트는 매번 재계산이라 멀쩡해 보이고
  /// **푸시 배지만 조용히 틀린다** — 사용자가 신고하기 어려운 종류다.
  /// 로그인은 하루 몇 번뿐이라 비용이 무시할 만하고, 드리프트 수명을 그만큼 줄인다.
  Future<void> reconcileUnreadCounts() async {
    if (!SessionManager.instance.isLoggedIn) return;
    try {
      await Supabase.instance.client.rpc('reconcile_my_unread_counts');
    } catch (e) {
      ErrorReporter.ignored(
        e,
        where: 'push.reconcileUnread',
        why: '보정 실패해도 기능은 정상 — 다음 로그인에 다시 시도한다',
      );
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
