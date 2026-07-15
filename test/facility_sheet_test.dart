import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/screen/user_profile_screen.dart';
import 'package:pawmate/theme/app_theme.dart';
import 'package:pawmate/services/facility_repository.dart';
import 'package:pawmate/widgets/facility_sheet.dart';
import 'package:pawmate/widgets/map_bottom_sheet.dart';

/// 히어로 탭 → 업체 프로필 push 검증용 라우트 기록 옵저버.
class _RecordingObserver extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }
}

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
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
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
      theme: AppTheme.light(),
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

  testWidgets('대표 사진 히어로 탭 → 업체 프로필(UserProfileScreen) push', (tester) async {
    const hero = Facility(
      id: 'f2',
      category: 'pet_sales',
      name: '포메이트 테스트샵',
      address: '경기도 화성시 동탄',
      phone: '0311234567',
      isOpen: true,
      lat: 37.2,
      lng: 127.1,
      distanceM: 120,
      ownerPhotoUrl: 'https://example.com/photo.jpg',
      ownerUserId: 'owner-uid',
    );
    final obs = _RecordingObserver();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      navigatorObservers: [obs],
      home: Scaffold(
        body: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Colors.green)),
            Positioned.fill(
              child: MapBottomSheet(
                onClose: () {},
                child: FacilityDetailContent(
                  facility: hero,
                  color: const Color(0xFFEF5350),
                  label: '분양',
                ),
              ),
            ),
          ],
        ),
      ),
    ));
    // 슬라이드 인 + 후기 로드 폴백.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final before = obs.pushed.length;

    // ownerUserId 가 전달되면 배지가 보인다.
    expect(find.text('업체 프로필'), findsOneWidget);

    await tester.tap(find.text('업체 프로필'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(obs.pushed.length, before + 1, reason: '히어로 탭이 라우트를 push 해야 한다');
    expect(find.byType(UserProfileScreen), findsOneWidget);
  });
}
