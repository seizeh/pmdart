import Flutter
import UIKit
import UserNotifications
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// 알림 탭 → Dart(openFromPush) 전달 채널. 엔진 준비 전(콜드 스타트) 탭은 버퍼.
  private var pushTapChannel: FlutterMethodChannel?
  private var pendingTap: [String: Any]?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    // SceneDelegate 환경에선 firebase_messaging 의 swizzling 이 알림센터 델리게이트를
    // 잡지 못해 포그라운드 표시(willPresent)·알림 탭(didReceive)이 유실된다.
    // 아래 override 두 개가 표시와 탭을 직접 처리한다 — 지우면 조용히 죽음.
    // (APNs 토큰 명시 전달과 같은 계열의 SceneDelegate 함정.)
    UNUserNotificationCenter.current().delegate = self
    application.registerForRemoteNotifications()
    print("push-native: UN delegate 지정 + APNs 등록 요청")
    return result
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    print("push-native: APNs 토큰 수신 (\(deviceToken.count) bytes)")
    Messaging.messaging().apnsToken = deviceToken
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    print("push-native: APNs 등록 실패 — \(error.localizedDescription)")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }

  /// 포그라운드 도착 알림 — 앱이 켜져 있어도 백그라운드와 동일한 OS 배너로.
  /// (FCM 플러그인의 presentation options 포워딩이 이 구성에선 동작하지 않아
  ///  네이티브에서 직접 표시 옵션을 지정한다.)
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    print("push-native: willPresent — 포그라운드 배너 표시")
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
  }

  /// 알림 탭 — FCM data(type/resource_type/resource_id)를 Dart 라우팅으로 전달.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let info = response.notification.request.content.userInfo
    let payload: [String: Any] = [
      "type": info["type"] as? String ?? "",
      "resource_type": info["resource_type"] as? String ?? "",
      "resource_id": info["resource_id"] as? String ?? "",
    ]
    print("push-native: 알림 탭 — \(payload)")
    if let channel = pushTapChannel {
      channel.invokeMethod("tap", arguments: payload)
    } else {
      pendingTap = payload // 콜드 스타트 — Dart 가 getPendingTap 으로 회수
    }
    completionHandler()
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PawmatePushTap") {
      let channel = FlutterMethodChannel(
        name: "pawmate/push_tap",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { [weak self] call, result in
        if call.method == "getPendingTap" {
          result(self?.pendingTap)
          self?.pendingTap = nil
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
      pushTapChannel = channel
    }
  }
}
