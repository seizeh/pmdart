import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// 아직 구현 전 기능용 공통 "준비 중" 화면.
class ComingSoonScreen extends StatelessWidget {
  final String title;
  const ComingSoonScreen({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(title)),
      body: const SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.construction_outlined,
                  size: 56, color: AppColors.textTertiary),
              SizedBox(height: 12),
              Text('준비 중인 기능이에요',
                  style:
                      TextStyle(fontSize: 15, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}
