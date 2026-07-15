import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/screen/terms_screen.dart';
import 'package:pawmate/theme/app_theme.dart';

/// 약관 뷰어 마크다운 렌더링 — 표가 | 원문으로 노출되지 않고 Table 위젯으로
/// 그려지는지(처리방침 스크린샷 가독성 문제 회귀 방지).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('개인정보 처리방침 — 표는 Table 위젯, | 원문 미노출', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: TermsScreen.privacy()),
    );
    await tester.pumpAndSettle();

    // 수집 항목 표가 실제 Table 로 렌더링된다.
    expect(find.byType(Table), findsWidgets);

    // 표 원문(| 구분 | ...)이 텍스트로 노출되지 않는다.
    expect(find.textContaining('| 구분 |'), findsNothing);
    expect(find.textContaining('|---'), findsNothing);

    // 표 머리글·본문 셀이 개별 텍스트로 존재.
    expect(find.text('수집 항목'), findsWidgets);

    // 제목이 # 기호 없이 렌더링된다.
    expect(find.textContaining('## '), findsNothing);
  });

  testWidgets('서비스 이용약관 — 제6조 유형 표 렌더링', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: TermsScreen.service()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Table), findsWidgets);
    expect(find.textContaining('| 유형 |'), findsNothing);
  });
}
