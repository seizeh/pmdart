import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 앱 테마 모드(시스템/라이트/다크) — 전역 노티파이어 + SharedPreferences 저장.
///
/// [load] 를 runApp 전에 호출해 저장값을 복원하고, MaterialApp 이
/// [ThemeController.mode] 를 구독해 즉시 반영한다.
class ThemeController {
  ThemeController._();

  static const _prefKey = 'theme_mode';

  /// 현재 테마 모드. 기본은 시스템 설정 따름.
  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.system);

  /// 저장된 모드 복원(없으면 system 유지).
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      mode.value = switch (saved) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } catch (_) {
      // 복원 실패 시 시스템 기본 유지.
    }
  }

  /// 모드 변경 + 저장.
  static Future<void> set(ThemeMode m) async {
    mode.value = m;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, switch (m) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      });
    } catch (_) {
      // 저장 실패해도 세션 내 반영은 유지.
    }
  }

  static String label(ThemeMode m) => switch (m) {
    ThemeMode.system => '시스템 설정',
    ThemeMode.light => '라이트',
    ThemeMode.dark => '다크',
  };
}
