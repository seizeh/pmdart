import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../theme/app_colors.dart';

/// 약관·처리방침 전문 뷰어 — 번들 에셋(assets/terms/*.md)을 표시.
/// 가입 동의 단계의 "보기" 와 내정보 하단 링크에서 공용.
class TermsScreen extends StatelessWidget {
  final String title;
  final String assetPath;
  const TermsScreen({super.key, required this.title, required this.assetPath});

  /// 서비스 이용약관.
  static TermsScreen service() => const TermsScreen(
      title: '서비스 이용약관', assetPath: 'assets/terms/terms_of_service.md');

  /// 위치기반서비스 이용약관.
  static TermsScreen location() => const TermsScreen(
      title: '위치기반서비스 이용약관', assetPath: 'assets/terms/location_terms.md');

  /// 개인정보 처리방침.
  static TermsScreen privacy() => const TermsScreen(
      title: '개인정보 처리방침', assetPath: 'assets/terms/privacy_policy.md');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: Text(title)),
      body: FutureBuilder<String>(
        future: rootBundle.loadString(assetPath),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return Scrollbar(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
              child: SelectableText(
                _plain(snap.data!),
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.65,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// 마크다운 문서를 읽기 쉬운 평문으로 정리.
  /// 헤더(#)·굵게(**)·불릿 기호만 정리하고, 표는 내용 보존을 위해 그대로 둔다
  /// (구분선 |---| 행만 제거).
  String _plain(String md) {
    return md
        .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
        .replaceAll('**', '')
        .replaceAll(RegExp(r'^\s*[-*]\s', multiLine: true), '· ')
        .replaceAll(RegExp(r'^\|[\s|:-]+\|$\n?', multiLine: true), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}
