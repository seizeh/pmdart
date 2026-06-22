import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../services/location_repository.dart';
import '../services/location_service.dart';

/// 동네 인증 화면 — 현재 위치(GPS)로 활동 지역(행정동)을 인증한다.
///
/// 사용자는 주소를 입력하지 않는다. [이 위치로 인증] → GPS 좌표 획득 →
/// verify-location Edge Function 서버 검증 → 결과 표시(0017 §4).
class LocationVerifyScreen extends StatefulWidget {
  /// 현재 인증된 동네명(있으면 재인증 화면으로 표시).
  final String? currentRegion;
  const LocationVerifyScreen({super.key, this.currentRegion});

  @override
  State<LocationVerifyScreen> createState() => _LocationVerifyScreenState();
}

class _LocationVerifyScreenState extends State<LocationVerifyScreen> {
  bool _loading = false;
  LocationVerifyResult? _result;

  Future<void> _verify() async {
    setState(() {
      _loading = true;
      _result = null;
    });
    final res = await LocationRepository.instance.verifyCurrentLocation();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _result = res;
    });

    if (res.verified) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message), behavior: SnackBarBehavior.floating),
      );
      // 성공 시 잠시 결과를 보여준 뒤 내정보로 복귀.
      await Future.delayed(const Duration(milliseconds: 900));
      if (mounted) Navigator.pop(context, true);
    } else if (res.errorCode == 'permission_denied_forever') {
      _promptOpenSettings();
    }
  }

  void _promptOpenSettings() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('위치 권한 필요'),
        content: const Text('동네 인증을 위해 설정에서 위치 권한을 허용해주세요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              LocationService.instance.openSettings();
            },
            child: const Text('설정 열기'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isReverify = widget.currentRegion != null;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: Text(isReverify ? '동네 재인증' : '동네 인증')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(32),
                  ),
                  child: const Icon(Icons.my_location,
                      size: 44, color: AppColors.primaryDark),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                isReverify ? '활동 지역을 다시 인증해요' : '현재 계신 동네를 인증해요',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                '실제 위치(GPS)로 동네를 인증합니다.\n위치 권한이 필요해요.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              if (widget.currentRegion != null) ...[
                const SizedBox(height: 16),
                _chip('현재 인증: ${widget.currentRegion}'),
              ],
              const SizedBox(height: 28),
              if (_result != null) _ResultBanner(result: _result!),
              const Spacer(),
              ElevatedButton(
                onPressed: _loading ? null : _verify,
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('이 위치로 인증'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String text) => Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(text,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
        ),
      );
}

class _ResultBanner extends StatelessWidget {
  final LocationVerifyResult result;
  const _ResultBanner({required this.result});

  @override
  Widget build(BuildContext context) {
    final ok = result.verified;
    final color = ok ? AppColors.success : AppColors.danger;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle_outline : Icons.error_outline,
              color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              result.message,
              style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
