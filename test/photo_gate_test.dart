// 사진 촬영 인증 게이트 — 펫마다 1·4·10번째 검증 카테고리 글에서만 요구한다.
// 서버 app.needs_photo_gate(pets.verify_post_count) 와 같은 규칙이어야 한다
// (다르면 앱은 "인증 필요 없음"으로 그려 놓고 서버가 거부한다).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/models/community.dart';
import 'package:pawmate/screen/post_create_screen.dart';
import 'package:pawmate/theme/app_theme.dart';

MyPet pet(int verifyPostCount) => MyPet(
  id: 'p',
  name: '콩이',
  species: '말티즈',
  role: 'owner',
  isIdentityVerified: true,
  verifyPostCount: verifyPostCount,
);

void main() {
  test('인증 요구 순번은 1·4·10번째 글뿐 — 그 뒤로는 계속 면제', () {
    // (누적 글 수 → 이번 글에 인증이 필요한가)
    const expected = {
      0: true, // 1번째
      1: false,
      2: false,
      3: true, // 4번째
      4: false,
      8: false,
      9: true, // 10번째
      10: false, // 11번째 — 세 번을 다 채웠다
      25: false,
    };
    for (final e in expected.entries) {
      expect(pet(e.key).needsPhotoGate, e.value, reason: '${e.key + 1}번째 글');
    }
  });

  test('다음 인증 순번 안내 — 셋을 마치면 없음', () {
    expect(pet(0).nextPostNo, 1);
    expect(pet(0).nextGatePostNo, 4); // 1번째를 하는 중 → 다음은 4번째
    expect(pet(1).nextGatePostNo, 4);
    expect(pet(3).nextGatePostNo, 10);
    expect(pet(4).nextGatePostNo, 10);
    expect(pet(9).nextGatePostNo, isNull); // 10번째가 마지막
    expect(pet(12).nextGatePostNo, isNull);
  });

  testWidgets('작성 화면 — 인증 카테고리면 규칙이 문구로 드러난다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const PostCreateScreen()),
    );
    await tester.pump();

    // 기본 카테고리(동반산책)는 인증 대상 — 규칙과 다음 행동이 함께 보인다.
    expect(find.text('촬영 인증은 반려동물마다 1·4·10번째 글에만 필요해요'), findsOneWidget);
    expect(find.text('반려동물을 선택하면 이번 글에 인증이 필요한지 알려드려요.'), findsOneWidget);

    // 자유 카테고리로 바꾸면 인증 자체가 없어 안내도 사라진다.
    await tester.ensureVisible(find.text('동반산책'));
    await tester.tap(find.text('동반산책'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('자유'));
    await tester.pumpAndSettle();
    expect(find.text('촬영 인증은 반려동물마다 1·4·10번째 글에만 필요해요'), findsNothing);
  });
}
