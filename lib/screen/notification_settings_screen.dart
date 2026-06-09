import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/activity_repository.dart';

/// 알림 설정 — notification_preferences 토글.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final _repo = ActivityRepository.instance;
  Map<String, dynamic> _prefs = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await _repo.fetchNotificationPrefs();
      if (mounted) {
        setState(() {
          _prefs = p;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle(String key, bool value) async {
    setState(() => _prefs[key] = value);
    try {
      await _repo.setNotificationPref(key, value);
    } catch (_) {
      if (mounted) {
        setState(() => _prefs[key] = !value);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('변경에 실패했어요'),
              behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('알림 설정')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: ActivityRepository.notificationKeys.entries.map((e) {
                  // 컬럼 기본값 true → 행이 없거나 값이 null 이면 켜짐으로 간주
                  final on = _prefs[e.key] != false;
                  return SwitchListTile(
                    title: Text(e.value,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary)),
                    value: on,
                    activeThumbColor: AppColors.primary,
                    onChanged: (v) => _toggle(e.key, v),
                  );
                }).toList(),
              ),
      ),
    );
  }
}
