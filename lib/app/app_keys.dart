import 'package:flutter/material.dart';

/// 강제 로그아웃(세션 무효화) 시 라우팅·안내를 위한 전역 키.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> messengerKey =
    GlobalKey<ScaffoldMessengerState>();
