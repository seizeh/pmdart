import 'package:flutter/material.dart';

import '../../motion/motion.dart';
import '../../services/auth_service.dart';
import '../../services/session.dart';
import '../../theme/app_palette.dart';
import '../admin/admin_home_screen.dart';
import '../main_screen.dart';
import 'reset_password_screen.dart';
import 'signup_phone_screen.dart';

/// 로그인 — 아이디/비밀번호 기반.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _idCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _idCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final username = _idCtrl.text.trim();
    final password = _pwCtrl.text;
    if (username.isEmpty || password.isEmpty) {
      _toast('아이디와 비밀번호를 입력해주세요');
      return;
    }
    setState(() => _loading = true);
    final result = await AuthService.instance.login(username, password);
    if (!mounted) return;
    setState(() => _loading = false);
    if (result.ok) {
      // 관리자 계정이면 관리자 화면으로 진입
      final isAdmin = SessionManager.instance.isAdmin;
      Navigator.pushAndRemoveUntil(
        context,
        AppPageRoute(
          builder: (_) =>
              isAdmin ? const AdminHomeScreen() : const MainScreen(),
        ),
        (route) => false,
      );
    } else {
      _toast(result.message);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.cream,
      appBar: AppBar(
        backgroundColor: context.colors.cream,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Center(
                child: Image.asset(
                  'assets/images/IMG_3.png',
                  width: 300,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                '다시 만나서\n반가워요',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textPrimary,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _idCtrl,
                decoration: InputDecoration(
                  labelText: '아이디',
                  prefixIcon: Icon(
                    Icons.person_outline,
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pwCtrl,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: '비밀번호',
                  prefixIcon: Icon(
                    Icons.lock_outline,
                    color: context.colors.textSecondary,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_off : Icons.visibility,
                      color: context.colors.textTertiary,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    AppPageRoute(builder: (_) => const ResetPasswordScreen()),
                  ),
                  child: const Text('비밀번호를 잊으셨나요?'),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loading ? null : _login,
                child: _loading
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: context.colors.textOnPrimary,
                        ),
                      )
                    : const Text('로그인'),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '아직 회원이 아니신가요?',
                    style: TextStyle(
                      fontSize: 13,
                      color: context.colors.textSecondary,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pushReplacement(
                      context,
                      AppPageRoute(builder: (_) => const SignupPhoneScreen()),
                    ),
                    child: const Text('회원가입'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
