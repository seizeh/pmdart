// 게시글 작성 화면 — 편집형 미리보기 카드(WYSIWYG).
// 제목은 카드 위 인라인 입력, 내용은 아래 별도 입력이 카드 히어로에 실시간 반영.
// 저장소 호출은 전부 내부 catch 라 테스트 환경에서 안전.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/screen/post_create_screen.dart';
import 'package:pawmate/theme/app_theme.dart';

void main() {
  testWidgets('미리보기 카드에서 제목을 직접 입력하고 내용이 실시간 반영된다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const PostCreateScreen()),
    );
    await tester.pump();

    expect(find.text('미리보기'), findsOneWidget);
    // 카드 위 제목 인라인 입력 + 내용 히어로 플레이스홀더.
    expect(find.text('제목을 입력하세요'), findsOneWidget);
    expect(find.text('내용이 여기에 표시돼요'), findsOneWidget);
    // 좌상단 사진 버튼(펫 미선택 상태 → 일반 추가 툴팁).
    expect(find.byTooltip('사진 추가'), findsOneWidget);

    // 카드 위 제목 입력(첫 번째 TextField = 카드 제목).
    await tester.enterText(find.byType(TextField).first, '산책 메이트 구해요');
    await tester.pump();
    expect(find.text('산책 메이트 구해요'), findsOneWidget);

    // 아래 '내용' 입력 → 카드 히어로에 실시간 반영.
    await tester.enterText(find.byType(TextField).at(1), '동탄 센트럴파크 한 바퀴!');
    await tester.pump();
    expect(find.text('동탄 센트럴파크 한 바퀴!'), findsNWidgets(2)); // 입력창 + 카드 히어로
    expect(find.text('내용이 여기에 표시돼요'), findsNothing);

    // 카테고리 태그 탭 → 제자리 인라인 확장(전체 목록) → 선택하면 접힘.
    // (카드가 테스트 뷰포트보다 커서 태그 위치까지 스크롤 필요)
    expect(find.text('자유'), findsNothing);
    await tester.ensureVisible(find.text('동반산책'));
    await tester.tap(find.text('동반산책'));
    await tester.pumpAndSettle();
    expect(find.text('자유'), findsOneWidget);
    expect(find.text('돌봄'), findsOneWidget);
    await tester.tap(find.text('자유'));
    await tester.pumpAndSettle();
    expect(find.text('돌봄'), findsNothing); // 접혔고
    expect(find.text('자유'), findsOneWidget); // 선택이 반영됐다
  });
}
