/// 플랫폼 판별 — `dart:io` 의 `Platform` 을 쓰지 않는다.
///
/// `dart:io` 는 웹에서 **컴파일은 되지만** `Platform.isIOS` 등이 런타임에
/// `UnsupportedError` 를 던지는 스텁이다. 빌드가 통과하므로 CI 로는 못 잡고
/// 브라우저에서 흰 화면으로만 드러난다 — 그래서 앱 코드에서 `dart:io` import
/// 자체를 금지하고 여기를 거친다.
library;

import 'package:flutter/foundation.dart';

/// 웹이 아닌 iOS 기기.
bool get isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// 웹이 아닌 Android 기기.
bool get isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// 네이티브 전용 기능(지도·푸시·로컬 알림·영상 썸네일)을 쓸 수 있는 플랫폼인지.
/// 웹은 앱 유입 퍼널이라 이 기능들이 전부 앱 유도로 대체된다(docs/web-port.md).
bool get isNativeApp => !kIsWeb;
