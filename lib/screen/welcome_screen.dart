import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../widgets/pawmate_logo.dart';
import 'auth/login_screen.dart';
import 'auth/signup_phone_screen.dart';
import 'main_screen.dart';

/// 첫 진입 화면 — 로그인 / 회원가입 / 둘러보기(게스트) 분기.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Column(
            children: [
              const Spacer(flex: 3),
              const PawMateLogo(size: 120, showText: true),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  '반려동물 보호자가 모이는 공간',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ),
              const Spacer(flex: 4),
              ElevatedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SignupPhoneScreen()),
                ),
                child: const Text('전화번호로 시작하기'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                ),
                child: const Text('로그인'),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MainScreen(isGuest: true),
                  ),
                ),
                child: const Text(
                  '로그인 없이 둘러보기',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    decoration: TextDecoration.underline,
                    decorationColor: AppColors.textTertiary,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}