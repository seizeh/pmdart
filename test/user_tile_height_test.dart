// 개인/업체 타일 높이 통일 회귀 테스트 — 배지 한 줄이 추가되는 업체 타일과
// 개인 타일이 같은 높이로 렌더링되는지 실측한다(목록에서 섞일 때 들쭉날쭉 방지).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/models/social.dart';
import 'package:pawmate/theme/app_theme.dart';
import 'package:pawmate/widgets/user_tile.dart';

void main() {
  testWidgets('개인 타일과 업체 타일의 높이가 같다', (tester) async {
    const personal = Connection(
      userId: 'u1',
      nickname: '일반사용자',
      userType: 'pet_owner',
    );
    const business = Connection(
      userId: 'u2',
      nickname: '사장님',
      userType: 'pet_owner',
      isBusiness: true,
      businessName: '포메이트 테스트샵',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Column(
            key: const Key('col'),
            children: const [
              UserTile(connection: personal),
              UserTile(connection: business),
            ],
          ),
        ),
      ),
    );
    final sizes = tester
        .widgetList(find.byType(UserTile))
        .map((w) => tester.getSize(find.byWidget(w)))
        .toList();
    expect(sizes, hasLength(2));
    expect(
      sizes[0].height,
      sizes[1].height,
      reason: '개인(${sizes[0].height}) vs 업체(${sizes[1].height}) 높이 불일치',
    );
  });
}
