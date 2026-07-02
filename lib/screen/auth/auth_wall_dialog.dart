import 'package:flutter/material.dart';
import '../../motion/motion.dart';
import '../../theme/app_colors.dart';
import 'login_screen.dart';

/// 비회원이 쓰기 액션(글 작성/댓글/지원/하트/pawing/채팅)을 시도하면 띄우는 팝업.
/// "로그인 할래요" / "나중에 할래요" 두 선택지.
class AuthWallDialog extends StatelessWidget {
  final String message;

  const AuthWallDialog({
    super.key,
    this.message = '이 기능은 로그인 후 이용할 수 있어요',
  });

  static Future<void> show(BuildContext context, {String? message}) {
    return showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => AuthWallDialog(
        message: message ?? '이 기능은 로그인 후 이용할 수 있어요',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.lock_outline,
                  size: 32, color: AppColors.primaryDark),
            ),
            const SizedBox(height: 20),
            const Text(
              '로그인이 필요해요',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    AppPageRoute(builder: (_) => const LoginScreen()),
                  );
                },
                child: const Text('로그인 할래요'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  foregroundColor: AppColors.textSecondary,
                ),
                child: const Text('나중에 할래요'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}