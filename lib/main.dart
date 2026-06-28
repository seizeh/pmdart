import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/app_theme.dart';
import 'screen/welcome_screen.dart';
import 'screen/main_screen.dart';
import 'screen/admin/admin_home_screen.dart';
import 'services/session.dart';

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
  await Supabase.initialize(
    url: 'https://vyatppuxmpulqtxevfpk.supabase.co',
    publishableKey: 'sb_publishable_T3dPO3-WMtkFDF_z5VIBBw_NKHwi-ZZ',
    accessToken: () async => SessionManager.instance.token,
  );

  runApp(const PawMateApp());
}

class PawMateApp extends StatelessWidget {
  const PawMateApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PawMate',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      // 전 화면 공통: 입력창/키보드 외 빈 곳 탭 또는 스크롤 시 포커스 해제
      // → 키보드 내려가고 검색 등 입력이 중단된다.
      //  · 탭: GestureDetector(translucent) — 버튼 등 자식 탭은 그대로 동작.
      //  · 스크롤: 루트 NotificationListener 가 하위 스크롤뷰의 드래그 시작을 받아 해제
      //    (return false 로 알림은 계속 전파, 프로그래매틱 스크롤은 제외).
      builder: (context, child) => NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n is ScrollStartNotification && n.dragDetails != null) {
            FocusManager.instance.primaryFocus?.unfocus();
          }
          return false;
        },
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: child,
        ),
      ),
      home: !SessionManager.instance.isLoggedIn
          ? const WelcomeScreen()
          : SessionManager.instance.isAdmin
              ? const AdminHomeScreen()
              : const MainScreen(),
    );
  }
}
