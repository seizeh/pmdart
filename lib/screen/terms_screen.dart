import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../theme/app_colors.dart';

/// 약관·처리방침 전문 뷰어 — 번들 에셋(assets/terms/*.md)을 표시.
/// 가입 동의 단계의 "보기" 와 내정보 하단 링크에서 공용.
///
/// [requireReadToAgree] 가 true 면(가입 동의용) 하단에 동의 버튼이 붙고,
/// **끝까지 스크롤해야** 버튼이 활성화된다. 동의 시 Navigator.pop(true).
class TermsScreen extends StatefulWidget {
  final String title;
  final String assetPath;
  final bool requireReadToAgree;
  const TermsScreen({
    super.key,
    required this.title,
    required this.assetPath,
    this.requireReadToAgree = false,
  });

  /// 서비스 이용약관.
  static TermsScreen service({bool agree = false}) => TermsScreen(
      title: '서비스 이용약관',
      assetPath: 'assets/terms/terms_of_service.md',
      requireReadToAgree: agree);

  /// 위치기반서비스 이용약관.
  static TermsScreen location({bool agree = false}) => TermsScreen(
      title: '위치기반서비스 이용약관',
      assetPath: 'assets/terms/location_terms.md',
      requireReadToAgree: agree);

  /// 개인정보 처리방침.
  static TermsScreen privacy({bool agree = false}) => TermsScreen(
      title: '개인정보 처리방침',
      assetPath: 'assets/terms/privacy_policy.md',
      requireReadToAgree: agree);

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  final _scroll = ScrollController();
  bool _readToEnd = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_checkReadToEnd);
  }

  @override
  void dispose() {
    _scroll.removeListener(_checkReadToEnd);
    _scroll.dispose();
    super.dispose();
  }

  /// 바닥 근처(24px 여유)까지 스크롤하면 읽음 처리. 한 번 읽으면 유지.
  void _checkReadToEnd() {
    if (_readToEnd || !_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 24) {
      setState(() => _readToEnd = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: Text(widget.title)),
      body: FutureBuilder<String>(
        future: rootBundle.loadString(widget.assetPath),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          // 본문이 화면보다 짧으면 스크롤 여지가 없으므로 즉시 읽음 처리.
          if (widget.requireReadToAgree && !_readToEnd) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _scroll.hasClients &&
                  _scroll.position.maxScrollExtent <= 0 && !_readToEnd) {
                setState(() => _readToEnd = true);
              }
            });
          }
          return Scrollbar(
            controller: _scroll,
            child: SingleChildScrollView(
              controller: _scroll,
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
      bottomNavigationBar: !widget.requireReadToAgree
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _readToEnd
                        ? () => Navigator.pop(context, true)
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.border,
                      disabledForegroundColor: AppColors.textTertiary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      _readToEnd ? '동의합니다' : '약관을 끝까지 읽어주세요',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
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
