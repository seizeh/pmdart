import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'theme/app_theme.dart';
import 'screen/welcome_screen.dart';
import 'screen/main_screen.dart';
import 'services/session.dart';

Future<void> main() async {
  // Flutter 엔진 초기화
  WidgetsFlutterBinding.ensureInitialized();

  // 저장된 로그인 세션 복원
  await SessionManager.instance.load();

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
      home: SessionManager.instance.isLoggedIn
          ? const MainScreen()
          : const WelcomeScreen(),
    );
  }
}
