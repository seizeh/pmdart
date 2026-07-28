// 업체 후기 작성 화면 — 전체화면 에디터(WYSIWYG).
// 화면이 곧 후기 카드다: 본문은 화면 중앙 히어로, 별점·혜택 표시·첨부는 하단
// 오버레이에서 그 자리에서 편집한다(뒤로가기·제목 크롬 없음).
// 진입 시 저장소 호출이 없어 테스트 환경에서 안전.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/screen/facility_review_screen.dart';
import 'package:pawmate/services/facility_repository.dart';
import 'package:pawmate/theme/app_theme.dart';

const _facility = Facility(
  id: 'f1',
  category: 'cafe',
  name: '동탄 멍카페',
  address: '경기 화성시',
  phone: null,
  isOpen: true,
  lat: 0,
  lng: 0,
  distanceM: 0,
);

void main() {
  testWidgets('전체화면 에디터에서 본문·별점·혜택 표시를 카드 위에서 바로 고친다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const FacilityReviewScreen(facility: _facility),
      ),
    );
    await tester.pump();

    // 상단 크롬 없음 — 제목/뒤로가기 대신 등록 알약만.
    expect(find.text('후기 작성'), findsNothing);
    expect(find.byType(BackButton), findsNothing);
    expect(find.text('등록'), findsOneWidget);
    // 시설명은 카드 하단 정보로, 본문은 화면 중앙 히어로로.
    expect(find.text('동탄 멍카페'), findsOneWidget);
    expect(find.text('방문 후기를 남겨주세요'), findsOneWidget);

    // 본문 — 사진이 없으므로 유일한 입력창(중앙 히어로, 가운데 정렬).
    final content = find.byType(TextField).first;
    expect(tester.widget<TextField>(content).textAlign, TextAlign.center);
    await tester.enterText(content, '강아지 놀이터가 넓어요');
    await tester.pump();
    expect(find.text('강아지 놀이터가 넓어요'), findsOneWidget);

    // 별점 — 기본 5점, 두 번째 별을 탭하면 2점.
    expect(find.text('5'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.star_rounded).at(1));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsOneWidget);

    // 업체 혜택 표시 — 카드 위 알약 토글(켜면 우상단 배지가 붙는다).
    expect(find.text('업체 혜택'), findsNothing);
    await tester.tap(find.text('업체 혜택 받고 작성'));
    await tester.pumpAndSettle();
    expect(find.text('업체 혜택'), findsOneWidget);

    // 첨부 입구는 좌상단 버튼 하나뿐이고, 실제로 눌린다(투명 앱바가 탭을
    // 가로채면 여기서 잡힌다 — 시트가 안 열린다).
    expect(find.byTooltip('사진·동영상 첨부'), findsOneWidget);
    await tester.tap(find.byTooltip('사진·동영상 첨부'));
    await tester.pumpAndSettle();
    expect(find.text('첨부하기'), findsOneWidget);
  });
}
