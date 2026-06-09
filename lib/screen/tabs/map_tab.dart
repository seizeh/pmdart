import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// 지도 탭 — 주변 산책 메이트·업체 지도. (개발 예정)
class MapTab extends StatelessWidget {
  const MapTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: const Icon(Icons.map_outlined,
                      size: 48, color: AppColors.primaryDark),
                ),
                const SizedBox(height: 20),
                const Text(
                  '지도 기능 준비 중',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '주변 산책 메이트와 반려동물 업체를\n지도에서 찾을 수 있도록 준비하고 있어요',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
