// 업체등록 주소검색 바텀시트 회귀 테스트 — 시트가 열리고 전환이 정상 종료되는지.
// 테마 기본 ElevatedButton minimumSize(Size.fromHeight = 최소 폭 무한)가 Row 안
// '검색' 버튼에 적용되면 무한 폭 레이아웃 예외로 화면이 배리어만 깔린 채 멈췄다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/screen/business_register_screen.dart';
import 'package:pawmate/theme/app_palette.dart';
import 'package:pawmate/theme/app_theme.dart';

void main() {
  Widget host(ThemeData theme) => MaterialApp(
    theme: theme,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: InkWell(
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: context.colors.cream,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              builder: (_) => const AddressSearchSheet(),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  for (final (label, theme) in [
    ('light', AppTheme.light()),
    ('dark', AppTheme.dark()),
  ]) {
    testWidgets('주소검색 시트가 열리고 전환이 정상 종료된다 ($label)', (tester) async {
      await tester.pumpWidget(host(theme));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('사업장 주소 검색'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
