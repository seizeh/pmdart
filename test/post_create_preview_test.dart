// 게시글 작성 화면 — 전체화면 에디터(WYSIWYG).
// 화면이 곧 게시글 카드다: 본문은 화면 중앙 히어로에서, 제목·카테고리·일정은
// 하단 오버레이에서 그 자리에서 입력한다(뒤로가기·제목 크롬 없음).
// 저장소 호출은 전부 내부 catch 라 테스트 환경에서 안전.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/screen/post_create_screen.dart';
import 'package:pawmate/theme/app_theme.dart';

void main() {
  testWidgets('전체화면 에디터에서 본문·제목을 카드 위에서 직접 입력한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const PostCreateScreen()),
    );
    await tester.pump();

    // 상단 크롬 없음 — 제목/뒤로가기 대신 등록 알약만.
    expect(find.text('새 게시글'), findsNothing);
    expect(find.byType(BackButton), findsNothing);
    expect(find.text('등록'), findsOneWidget);
    // 본문 히어로 + 카드 제목 인라인 입력.
    expect(find.text('내용을 입력하세요'), findsOneWidget);
    expect(find.text('제목을 입력하세요'), findsOneWidget);
    // 좌상단 사진 버튼(펫 미선택 상태 → 일반 추가 툴팁).
    expect(find.byTooltip('사진 추가'), findsOneWidget);

    // 사진 없는 글 — 첫 TextField 가 화면 중앙 본문 히어로, 두 번째가 제목.
    final content = find.byType(TextField).first;
    final title = find.byType(TextField).at(1);
    expect(tester.widget<TextField>(content).textAlign, TextAlign.center);

    await tester.enterText(content, '동탄 센트럴파크 한 바퀴!');
    await tester.enterText(title, '산책 메이트 구해요');
    await tester.pump();
    expect(find.text('동탄 센트럴파크 한 바퀴!'), findsOneWidget);
    expect(find.text('산책 메이트 구해요'), findsOneWidget);

    // 카테고리 태그 탭 → 제자리 인라인 확장(전체 목록) → 선택하면 접힘.
    expect(find.text('자유'), findsNothing);
    await tester.tap(find.text('동반산책'));
    await tester.pumpAndSettle();
    expect(find.text('자유'), findsOneWidget);
    expect(find.text('돌봄'), findsOneWidget);
    await tester.tap(find.text('자유'));
    await tester.pumpAndSettle();
    expect(find.text('돌봄'), findsNothing); // 접혔고
    expect(find.text('자유'), findsOneWidget); // 선택이 반영됐다

    // 좌상단 사진 버튼이 실제로 눌린다 — 자유 글이라 사진·동영상 선택 시트.
    // (투명 앱바가 그 띠의 탭을 가로채면 시트가 안 열려 여기서 잡힌다.)
    await tester.tap(find.byTooltip('사진·동영상 추가'));
    await tester.pumpAndSettle();
    expect(find.text('첨부하기'), findsOneWidget);
  });
}
