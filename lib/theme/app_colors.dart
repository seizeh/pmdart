import 'package:flutter/material.dart';

/// PawMate 색상 시스템.
/// 브랜드 컬러는 골든 탠(#ad9466) + 다크 브라운(#5a4e3a).
/// 배경은 크림 톤으로 따뜻한 분위기를 유지.
class AppColors {
  AppColors._();

  // 브랜드
  static const Color primary = Color(0xFFAD9466); // 골든 탠 (로고/CTA)
  static const Color primaryDark = Color(0xFF5A4E3A); // 다크 브라운 (강조 텍스트·아이콘)
  static const Color primarySoft = Color(0xFFD9CBA8); // 옅은 탠 (배지·하이라이트)

  // 표면
  static const Color background = Color(0xFFF5EFE3); // 크림 배경
  static const Color surface = Color(0xFFFFFFFF); // 카드 표면
  static const Color surfaceMuted = Color(0xFFFAF6EC); // 살짝 톤 다운된 카드

  // 흰색 셀로판지 필름(반투명) — 상단 헤더·하단 바가 뒤 콘텐츠를 선명하게 비치며 덮는다.
  static const Color frostFilm = Color(0xCCFFFFFF); // 흰색 alpha ≈ 0.8

  // 텍스트
  static const Color textPrimary = Color(0xFF5A4E3A); // 본문/제목
  static const Color textSecondary = Color(0xFF8C8273); // 보조 텍스트
  static const Color textTertiary = Color(0xFFB6AC9A); // 비활성/플레이스홀더
  static const Color textOnPrimary = Color(0xFFFFFBF1); // primary 위 텍스트

  // 보더
  static const Color border = Color(0xFFE5DDD0);
  static const Color borderStrong = Color(0xFFCFC3AC);

  // 관리자 모드 (브랜드와 대비되는 딥 슬레이트로 '관리자' 임을 한눈에 구분)
  static const Color adminAccent = Color(0xFF2F3A4A); // 딥 슬레이트
  static const Color adminAccentSoft = Color(0xFFE6E9EE); // 옅은 슬레이트 (배경/배지)
  static const Color adminOnAccent = Color(0xFFFFFFFF);

  // 시맨틱
  static const Color success = Color(0xFF7CA77E);
  static const Color warning = Color(0xFFD4A658);
  static const Color danger = Color(0xFFC97565);
  static const Color info = Color(0xFF7B96B0);

  // 카테고리(게시글 카테고리별 색상 — 카드 강조용)
  static const Color catWalk = Color(0xFFAD9466); // 동반산책
  static const Color catWalkProxy = Color(0xFF8C9B7C); // 대리산책
  static const Color catCare = Color(0xFFB07B5C); // 돌봄
  static const Color catGiveAway = Color(0xFFC97565); // 분양
  static const Color catAdoption = Color(0xFF7B96B0); // 입양
  static const Color catFree = Color(0xFF8C8273); // 자유
}
