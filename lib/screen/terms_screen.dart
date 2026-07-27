import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../theme/app_palette.dart';

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
    requireReadToAgree: agree,
  );

  /// 위치기반서비스 이용약관.
  static TermsScreen location({bool agree = false}) => TermsScreen(
    title: '위치기반서비스 이용약관',
    assetPath: 'assets/terms/location_terms.md',
    requireReadToAgree: agree,
  );

  /// 개인정보 처리방침.
  static TermsScreen privacy({bool agree = false}) => TermsScreen(
    title: '개인정보 처리방침',
    assetPath: 'assets/terms/privacy_policy.md',
    requireReadToAgree: agree,
  );

  /// 간이 후기 이용조건 + 전화번호 수집·이용 동의(0029) — 비회원 후기 작성용.
  static TermsScreen liteReview({bool agree = false}) => TermsScreen(
    title: '간이 후기 이용조건',
    assetPath: 'assets/terms/lite_review_terms.md',
    requireReadToAgree: agree,
  );

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
      backgroundColor: context.colors.background,
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
              if (mounted &&
                  _scroll.hasClients &&
                  _scroll.position.maxScrollExtent <= 0 &&
                  !_readToEnd) {
                setState(() => _readToEnd = true);
              }
            });
          }
          return Scrollbar(
            controller: _scroll,
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _buildBlocks(context, snap.data!),
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
                      backgroundColor: context.colors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: context.colors.border,
                      disabledForegroundColor: context.colors.textTertiary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      _readToEnd ? '동의합니다' : '약관을 끝까지 읽어주세요',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  // ── 경량 마크다운 렌더러 — 약관 문서가 쓰는 문법만 지원:
  //    제목(#~######)·굵게(**)·표(|…|)·불릿(-/*)·구분선(---).
  //    표를 평문으로 뭉개면 | 구분자가 그대로 노출돼 가독성이 무너지던 문제 수정.

  List<Widget> _buildBlocks(BuildContext context, String md) {
    final lines = md.split('\n');
    final blocks = <Widget>[];
    final para = <String>[];

    void flushPara() {
      if (para.isEmpty) return;
      blocks.add(_paragraph(context, para.join('\n')));
      para.clear();
    }

    for (var i = 0; i < lines.length; i++) {
      final t = lines[i].trim();
      if (t.isEmpty) {
        flushPara();
        continue;
      }
      if (RegExp(r'^-{3,}$').hasMatch(t)) {
        flushPara();
        blocks.add(
          Divider(height: 28, color: context.colors.border, thickness: 0.5),
        );
        continue;
      }
      final h = RegExp(r'^(#{1,6})\s*(.*)$').firstMatch(t);
      if (h != null) {
        flushPara();
        blocks.add(_heading(context, h.group(1)!.length, h.group(2)!));
        continue;
      }
      if (t.startsWith('|')) {
        flushPara();
        final tableLines = <String>[];
        while (i < lines.length && lines[i].trim().startsWith('|')) {
          tableLines.add(lines[i].trim());
          i++;
        }
        i--;
        blocks.add(_table(context, tableLines));
        continue;
      }
      para.add(lines[i]);
    }
    flushPara();
    return blocks;
  }

  Widget _heading(BuildContext context, int level, String text) {
    final (size, weight) = switch (level) {
      1 => (19.0, FontWeight.w800),
      2 => (16.5, FontWeight.w800),
      _ => (14.5, FontWeight.w700),
    };
    return Padding(
      padding: EdgeInsets.only(top: level <= 2 ? 18 : 14, bottom: 6),
      child: Text(
        _stripBold(text),
        style: TextStyle(
          fontSize: size,
          fontWeight: weight,
          height: 1.4,
          color: context.colors.textPrimary,
        ),
      ),
    );
  }

  Widget _paragraph(BuildContext context, String text) {
    final body = text.replaceAll(RegExp(r'^\s*[-*]\s', multiLine: true), '· ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SelectableText.rich(
        TextSpan(
          children: _boldSpans(context, body),
          style: TextStyle(
            fontSize: 13.5,
            height: 1.65,
            color: context.colors.textPrimary,
          ),
        ),
      ),
    );
  }

  /// **굵게** 인라인 파싱.
  List<TextSpan> _boldSpans(BuildContext context, String text) {
    final spans = <TextSpan>[];
    var rest = text;
    final re = RegExp(r'\*\*(.+?)\*\*');
    while (true) {
      final m = re.firstMatch(rest);
      if (m == null) {
        if (rest.isNotEmpty) spans.add(TextSpan(text: rest));
        break;
      }
      if (m.start > 0) spans.add(TextSpan(text: rest.substring(0, m.start)));
      spans.add(
        TextSpan(
          text: m.group(1),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      );
      rest = rest.substring(m.end);
    }
    return spans;
  }

  String _stripBold(String s) => s.replaceAll('**', '');

  Widget _table(BuildContext context, List<String> tableLines) {
    // 셀 분해 — 앞뒤 빈 조각 제거, |---|:--| 구분선 행 제외.
    final rows = <List<String>>[];
    for (final line in tableLines) {
      final cells = line
          .split('|')
          .map((c) => c.trim())
          .toList()
          .sublist(1); // 선행 | 앞의 빈 조각 제거
      if (cells.isNotEmpty && cells.last.isEmpty) cells.removeLast();
      if (cells.isEmpty) continue;
      if (cells.every((c) => RegExp(r'^[:\-\s]*$').hasMatch(c))) continue;
      rows.add(cells.map(_stripBold).toList());
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    final colCount = rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);

    // 열 폭: 내용이 긴 열이 넓게 — 열별 최장 셀 길이에 비례(과도 편중 방지 클램프).
    final widths = <int, TableColumnWidth>{};
    for (var c = 0; c < colCount; c++) {
      var maxLen = 0;
      for (final r in rows) {
        if (c < r.length && r[c].length > maxLen) maxLen = r[c].length;
      }
      widths[c] = FlexColumnWidth(maxLen.clamp(6, 30).toDouble());
    }

    TableRow buildRow(List<String> cells, {required bool header}) => TableRow(
      decoration: header ? BoxDecoration(color: context.colors.surface) : null,
      children: List.generate(colCount, (c) {
        final text = c < cells.length ? cells[c] : '';
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              fontWeight: header ? FontWeight.w700 : FontWeight.w400,
              color: context.colors.textPrimary,
            ),
          ),
        );
      }),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Table(
        border: TableBorder.all(color: context.colors.border, width: 0.5),
        columnWidths: widths,
        defaultVerticalAlignment: TableCellVerticalAlignment.top,
        children: [
          buildRow(rows.first, header: true),
          for (final r in rows.skip(1)) buildRow(r, header: false),
        ],
      ),
    );
  }
}
