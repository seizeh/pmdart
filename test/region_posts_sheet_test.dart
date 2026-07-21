import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/services/community_repository.dart';
import 'package:pawmate/theme/app_theme.dart';
import 'package:pawmate/widgets/region_posts_sheet.dart';

/// 동네 게시글 시트 콘텐츠가 예외 없이 렌더되는지 스모크 검증.
/// (Supabase 미초기화로 조회는 실패하지만 내부 catch → 안내 문구로 렌더.)
void main() {
  const cluster = PostCluster(
    regionCode: '1111051500',
    count: 3,
    lat: 37.5,
    lng: 127.0,
    postIds: ['p1', 'p2', 'p3'],
  );

  testWidgets('동네 게시글 콘텐츠가 헤더를 표시하고 예외 없이 렌더된다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: RegionPostsContent(cluster: cluster)),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    expect(tester.takeException(), isNull);
    expect(find.text('이 동네 게시글 3개'), findsOneWidget);
  });
}
