import 'package:flutter/material.dart';

/// PawMate 시맨틱 색 토큰 — 라이트/다크 팔레트를 [ThemeExtension] 으로 제공.
///
/// 정적 [AppColors] 는 라이트 고정값이라 다크모드에 반응하지 못한다.
/// 새 코드는 `context.colors.x` 로 접근하고, 기존 `AppColors.x` 사용처는
/// 화면 단위로 점진 이행한다(마이그레이션 전 화면은 라이트 값으로 보임).
///
/// 다크 팔레트 원칙: 회색 반전이 아니라 **웜 다크 브라운** — 크림·골든탠
/// 정체성을 밤 톤으로 옮긴다. 라이트에서 어두웠던 강조(primaryDark)는
/// 다크에선 밝은 모래색으로 반전되고, 표면은 밝을수록 위에 뜬다(elevation).
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.primary,
    required this.primaryDark,
    required this.primarySoft,
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.frostFilm,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textOnPrimary,
    required this.border,
    required this.borderStrong,
    required this.adminAccent,
    required this.adminAccentSoft,
    required this.adminOnAccent,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.catWalk,
    required this.catWalkProxy,
    required this.catCare,
    required this.catGiveAway,
    required this.catAdoption,
    required this.catFree,
  });

  // 브랜드
  final Color primary; // 골든 탠 (로고/CTA)
  final Color primaryDark; // 강조 텍스트·아이콘 (다크에선 밝은 모래색)
  final Color primarySoft; // 배지·하이라이트 배경

  // 표면
  final Color background;
  final Color surface;
  final Color surfaceMuted;

  /// 셀로판지 필름(반투명) — 헤더·하단 바가 뒤 콘텐츠를 비치며 덮는다.
  final Color frostFilm;

  // 텍스트
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textOnPrimary; // primaryDark(강조면) 위 텍스트

  // 보더
  final Color border;
  final Color borderStrong;

  // 관리자 모드
  final Color adminAccent;
  final Color adminAccentSoft;
  final Color adminOnAccent;

  // 시맨틱
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;

  // 게시글 카테고리
  final Color catWalk;
  final Color catWalkProxy;
  final Color catCare;
  final Color catGiveAway;
  final Color catAdoption;
  final Color catFree;

  /// 라이트 — 기존 [AppColors] 값 기반.
  /// background 는 앱의 실질 페이지 배경(흰색) — 크림(F5EFE3)은 인증/웰컴
  /// 화면 전용이라 추후 별도 토큰으로 분리한다.
  static const light = AppPalette(
    primary: Color(0xFFAD9466),
    primaryDark: Color(0xFF5A4E3A),
    primarySoft: Color(0xFFD9CBA8),
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFFAF6EC),
    frostFilm: Color(0xEBFFFFFF),
    textPrimary: Color(0xFF5A4E3A),
    textSecondary: Color(0xFF8C8273),
    textTertiary: Color(0xFFB6AC9A),
    textOnPrimary: Color(0xFFFFFBF1),
    border: Color(0xFFE5DDD0),
    borderStrong: Color(0xFFCFC3AC),
    adminAccent: Color(0xFF2F3A4A),
    adminAccentSoft: Color(0xFFE6E9EE),
    adminOnAccent: Color(0xFFFFFFFF),
    success: Color(0xFF7CA77E),
    warning: Color(0xFFD4A658),
    danger: Color(0xFFC97565),
    info: Color(0xFF7B96B0),
    catWalk: Color(0xFFAD9466),
    catWalkProxy: Color(0xFF8C9B7C),
    catCare: Color(0xFFB07B5C),
    catGiveAway: Color(0xFFC97565),
    catAdoption: Color(0xFF7B96B0),
    catFree: Color(0xFF8C8273),
  );

  /// 다크 — 어두운 회색(뉴트럴) 기준. 표면은 밝을수록 elevated,
  /// 브랜드 골든탠은 강조(포인트)로만 남긴다.
  static const dark = AppPalette(
    primary: Color(0xFFC2A97A), // 골든 탠(포인트)
    primaryDark: Color(0xFFD8C7A9), // 강조 반전 — 어두운 회색 위 밝은 모래
    primarySoft: Color(0xFF35322B), // 배지/하이라이트 — 탠 기운 살짝 도는 다크 그레이
    background: Color(0xFF121212),
    surface: Color(0xFF1E1E1E),
    surfaceMuted: Color(0xFF191919),
    frostFilm: Color(0xEB1B1B1B), // 다크 셀로판지(같은 92% 불투명)
    textPrimary: Color(0xFFECEAE5),
    textSecondary: Color(0xFFABA79E),
    textTertiary: Color(0xFF6F6C66),
    textOnPrimary: Color(0xFF1E1B15), // 밝은 강조면 위 다크
    border: Color(0xFF2E2E2E),
    borderStrong: Color(0xFF454545),
    adminAccent: Color(0xFF8FA5BE),
    adminAccentSoft: Color(0xFF1F252D),
    adminOnAccent: Color(0xFF0F141B),
    success: Color(0xFF8FBC91),
    warning: Color(0xFFE0B76B),
    danger: Color(0xFFD98B7C),
    info: Color(0xFF92ACC6),
    catWalk: Color(0xFFC2A97A),
    catWalkProxy: Color(0xFFA3B394),
    catCare: Color(0xFFC79273),
    catGiveAway: Color(0xFFD98B7C),
    catAdoption: Color(0xFF92ACC6),
    catFree: Color(0xFFA39E94),
  );

  @override
  AppPalette copyWith({
    Color? primary,
    Color? primaryDark,
    Color? primarySoft,
    Color? background,
    Color? surface,
    Color? surfaceMuted,
    Color? frostFilm,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textOnPrimary,
    Color? border,
    Color? borderStrong,
    Color? adminAccent,
    Color? adminAccentSoft,
    Color? adminOnAccent,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
    Color? catWalk,
    Color? catWalkProxy,
    Color? catCare,
    Color? catGiveAway,
    Color? catAdoption,
    Color? catFree,
  }) {
    return AppPalette(
      primary: primary ?? this.primary,
      primaryDark: primaryDark ?? this.primaryDark,
      primarySoft: primarySoft ?? this.primarySoft,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      frostFilm: frostFilm ?? this.frostFilm,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textOnPrimary: textOnPrimary ?? this.textOnPrimary,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      adminAccent: adminAccent ?? this.adminAccent,
      adminAccentSoft: adminAccentSoft ?? this.adminAccentSoft,
      adminOnAccent: adminOnAccent ?? this.adminOnAccent,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      catWalk: catWalk ?? this.catWalk,
      catWalkProxy: catWalkProxy ?? this.catWalkProxy,
      catCare: catCare ?? this.catCare,
      catGiveAway: catGiveAway ?? this.catGiveAway,
      catAdoption: catAdoption ?? this.catAdoption,
      catFree: catFree ?? this.catFree,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      primary: l(primary, other.primary),
      primaryDark: l(primaryDark, other.primaryDark),
      primarySoft: l(primarySoft, other.primarySoft),
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceMuted: l(surfaceMuted, other.surfaceMuted),
      frostFilm: l(frostFilm, other.frostFilm),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textTertiary: l(textTertiary, other.textTertiary),
      textOnPrimary: l(textOnPrimary, other.textOnPrimary),
      border: l(border, other.border),
      borderStrong: l(borderStrong, other.borderStrong),
      adminAccent: l(adminAccent, other.adminAccent),
      adminAccentSoft: l(adminAccentSoft, other.adminAccentSoft),
      adminOnAccent: l(adminOnAccent, other.adminOnAccent),
      success: l(success, other.success),
      warning: l(warning, other.warning),
      danger: l(danger, other.danger),
      info: l(info, other.info),
      catWalk: l(catWalk, other.catWalk),
      catWalkProxy: l(catWalkProxy, other.catWalkProxy),
      catCare: l(catCare, other.catCare),
      catGiveAway: l(catGiveAway, other.catGiveAway),
      catAdoption: l(catAdoption, other.catAdoption),
      catFree: l(catFree, other.catFree),
    );
  }

  /// 게시글 카테고리 코드 → 색.
  Color categoryColor(String category) => switch (category) {
        'walk_together' => catWalk,
        'walk_proxy' => catWalkProxy,
        'care' => catCare,
        'give_away' => catGiveAway,
        'adoption' => catAdoption,
        'free' => catFree,
        _ => primary,
      };
}

/// `context.colors.textPrimary` 처럼 짧게 접근하기 위한 헬퍼.
extension AppPaletteContext on BuildContext {
  AppPalette get colors => Theme.of(this).extension<AppPalette>()!;

  /// 현재 다크모드 여부(테마 기준).
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}
