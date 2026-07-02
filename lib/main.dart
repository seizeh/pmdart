import 'dart:async';
import 'motion/motion.dart';
import 'firebase_options.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/app_theme.dart';
import 'screen/welcome_screen.dart';
import 'screen/main_screen.dart';
import 'screen/admin/admin_home_screen.dart';
import 'screen/notifications_screen.dart';
import 'services/session.dart';
import 'services/push_service.dart';
import 'services/realtime_service.dart';
import 'services/keyboard_barrier.dart';

/// 강제 로그아웃(세션 무효화) 시 라우팅·안내를 위한 전역 키.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> messengerKey =
    GlobalKey<ScaffoldMessengerState>();

Future<void> main() async {
  // Flutter 엔진 초기화
  WidgetsFlutterBinding.ensureInitialized();

  // 저장된 로그인 세션 복원
  await SessionManager.instance.load();

  // 네이버 지도 SDK 초기화 (NCP Maps 신규 인증 - Client ID)
  await FlutterNaverMap().init(
    clientId: 'cy02y6r0d5',
    onAuthFailed: (ex) {
      switch (ex) {
        case NQuotaExceededException(:final message):
          debugPrint('네이버 지도 사용량 초과: $message');
        case NUnauthorizedClientException() ||
              NClientUnspecifiedException() ||
              NAnotherAuthFailedException():
          debugPrint('네이버 지도 인증 실패: $ex');
      }
    },
  );

  // Supabase 연결
  // publishableKey(공개 키)만 클라이언트에 둔다. service_role 키는 절대 포함 금지.
  // accessToken: 로그인 시 발급된 커스텀 JWT 를 모든 요청 Authorization 에 첨부 →
  // RLS 의 app.uid() 가 JWT 의 sub(user_id)를 읽는다. 비로그인 시 null → anon 으로 동작.
  // 매 요청 전 호출되므로 access 만료 임박 시 여기서 refresh 로 무중단 갱신(단일비행).
  //  · isRefreshing 중엔 재진입 금지 — refresh 엔드포인트 호출도 이 콜백을 거치므로
  //    무한재귀/데드락을 막는다(refresh 는 verify_jwt=false 라 stale access 로도 무해).
  await Supabase.initialize(
    url: 'https://vyatppuxmpulqtxevfpk.supabase.co',
    publishableKey: 'sb_publishable_T3dPO3-WMtkFDF_z5VIBBw_NKHwi-ZZ',
    accessToken: () async {
      final s = SessionManager.instance;
      if (!s.isRefreshing && s.isAccessExpiringSoon(skew: 60)) {
        await s.refreshOnce();
      }
      return s.token;
    },
  );

  // 로그인 상태면 realtime 재인증 + 알림 실시간 구독(벨/목록/채팅 목록 라이브 갱신).
  if (SessionManager.instance.isLoggedIn) RealtimeService.instance.start();

  runApp(const PawMateApp());

  // OS 푸시(FCM) 초기화는 앱 시작(runApp)을 막지 않도록 백그라운드로.
  // (init 이 iOS 권한 다이얼로그 응답 대기 + APNs 미설정 getToken 에서 블록될 수 있어,
  //  await 하면 흰 화면에서 멈춘다.)
  unawaited(_setupPush());
}

Future<void> _setupPush() async {
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    PushService.instance.onOpen = (type, resourceType, resourceId) {
      // 알림 탭 → 알림 목록으로(세부 리소스 라우팅은 후속).
      navigatorKey.currentState?.push(
        AppPageRoute(builder: (_) => const NotificationsScreen()),
      );
    };
    PushService.instance.onForeground = (title, body) {
      final text = [title, body].where((e) => e != null && e.isNotEmpty).join(' · ');
      if (text.isNotEmpty) {
        messengerKey.currentState?.showSnackBar(SnackBar(
          content: Text(text), behavior: SnackBarBehavior.floating));
      }
    };
    await PushService.instance.init();
  } catch (e) {
    debugPrint('푸시 초기화 건너뜀(Firebase/APNs 미설정?): $e');
  }
}

class PawMateApp extends StatefulWidget {
  const PawMateApp({super.key});

  @override
  State<PawMateApp> createState() => _PawMateAppState();
}

class _PawMateAppState extends State<PawMateApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 세션이 서버에서 무효화(타 기기 비번변경/정지·refresh 회수)되면 강제 로그아웃 라우팅.
    SessionManager.instance.onInvalidated = _handleInvalidated;
    // 시작 시 1회 세션 유효성 확인.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SessionManager.instance.checkAliveAndClearIfDead();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 포그라운드 복귀 시 세션 유효성 재확인 → 무효면 즉시 로그아웃.
    if (state == AppLifecycleState.resumed) {
      SessionManager.instance.checkAliveAndClearIfDead();
    }
  }

  void _handleInvalidated() {
    RealtimeService.instance.stop();
    PushService.instance.clearToken(); // 무효화된 기기의 FCM 토큰도 삭제
    navigatorKey.currentState?.pushAndRemoveUntil(
      AppPageRoute(builder: (_) => const WelcomeScreen()),
      (route) => false,
    );
    messengerKey.currentState?.showSnackBar(const SnackBar(
      content: Text('다른 기기에서 로그인하거나 비밀번호가 변경되어 로그아웃되었어요. 다시 로그인해주세요.'),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: messengerKey,
      title: 'PawMate',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      // 전 화면 공통 키보드 해제:
      //  · 스크롤: 하위 스크롤뷰의 드래그 시작을 받아 해제(알림은 계속 전파).
      //  · 탭: 키보드가 떠 있을 때만 전체 화면에 배리어를 깔아, 화면 탭을 '키보드 닫기'
      //    로 흡수(opaque)한다. 이 탭은 아래 위젯(게시글 등)에 전달되지 않으므로
      //    "키보드 닫으려다 게시글이 눌리는" 문제가 없다. 키보드가 없으면 배리어도
      //    없어 평소 탭은 정상 동작.
      builder: (context, child) {
        final keyboardUp = MediaQuery.of(context).viewInsets.bottom > 0;
        return NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n is ScrollStartNotification && n.dragDetails != null) {
              FocusManager.instance.primaryFocus?.unfocus();
            }
            return false;
          },
          child: ValueListenableBuilder<bool>(
            valueListenable: keyboardBarrierEnabled,
            builder: (_, barrierOn, _) => Stack(
              fit: StackFit.expand,
              children: [
                child ?? const SizedBox.shrink(),
                // 지도 등 자체 처리 화면(barrierOn=false)에서는 배리어를 끈다.
                if (keyboardUp && barrierOn)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () =>
                          FocusManager.instance.primaryFocus?.unfocus(),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
      home: !SessionManager.instance.isLoggedIn
          ? const WelcomeScreen()
          : SessionManager.instance.isAdmin
              ? const AdminHomeScreen()
              : const MainScreen(),
    );
  }
}
