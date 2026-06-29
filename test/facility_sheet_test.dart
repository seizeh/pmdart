import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/services/facility_repository.dart';
import 'package:pawmate/widgets/facility_sheet.dart';
import 'package:pawmate/widgets/map_bottom_sheet.dart';

/// 시설 상세 콘텐츠가 예외/블랭크 없이 렌더되는지 스모크 검증.
/// (지도 위에선 MapBottomSheet 안에 올라간다. 후기 조회는 Supabase 미초기화로 실패하지만
/// 내부 catch → 빈 목록으로 렌더.)
void main() {
  const facility = Facility(
    id: 'f1',
    category: 'animal_hospital',
    name: '테스트동물병원',
    address: '서울특별시 종로구 어딘가',
    phone: '021234567',
    isOpen: true,
    lat: 37.5,
    lng: 127.0,
    distanceM: 320,
  );

  testWidgets('시설 상세 콘텐츠가 정보와 후기 버튼을 표시한다', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: FacilityDetailContent(
          facility: facility,
          color: Color(0xFFEF5350),
          label: '동물병원',
        ),
      ),
    ));

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    expect(tester.takeException(), isNull);
    expect(find.text('테스트동물병원'), findsWidgets);
    expect(find.text('후기 쓰기'), findsOneWidget);
    expect(find.text('네이버'), findsOneWidget);
  });

  testWidgets('MapBottomSheet 가 콘텐츠를 띄우고 바깥 탭으로 닫힌다', (tester) async {
    var closed = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Colors.green)),
            Positioned.fill(
              child: MapBottomSheet(
                onClose: () => closed = true,
                child: const Center(child: Text('SHEET-BODY')),
              ),
            ),
          ],
        ),
      ),
    ));
    // 슬라이드 인.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.text('SHEET-BODY'), findsOneWidget);

    // 스크림(좌상단) 탭 → 닫힘 애니메이션 후 onClose.
    await tester.tapAt(const Offset(20, 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(closed, isTrue);
  });
}
