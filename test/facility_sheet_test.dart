import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/services/facility_repository.dart';
import 'package:pawmate/widgets/facility_sheet.dart';

/// 시설 시트가 예외/블랭크 없이 렌더되는지 스모크 검증.
/// (후기 조회는 Supabase 미초기화로 실패하지만 내부에서 catch → 빈 목록으로 렌더)
void main() {
  testWidgets('시설 시트가 정보와 후기 버튼을 표시한다', (tester) async {
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

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () => showFacilitySheet(ctx, facility,
                  color: const Color(0xFFEF5350), label: '동물병원'),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    // 모달 애니메이션 + 후기 로드(에러→빈목록) 진행. pumpAndSettle 은 로딩 스피너로
    // 무한대기될 수 있어 고정 시간 pump.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    // 시트 콘텐츠가 실제로 그려졌는지(블랭크 아님) + 인터랙션 요소 존재.
    expect(find.text('테스트동물병원'), findsOneWidget);
    expect(find.text('후기 쓰기'), findsOneWidget);
    expect(find.text('동물병원'), findsOneWidget);
  });
}
