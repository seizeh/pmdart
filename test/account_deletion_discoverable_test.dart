import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pawmate/screen/tabs/my_info_tab.dart';
import 'package:pawmate/theme/app_theme.dart';

/// 계정 삭제 경로의 **발견 가능성** 회귀 방지 (App Store 5.1.1(v) 2회 지적).
///
/// 심사관은 한국어를 읽지 못하고, 종전에는 라벨 없는 프로필 카드 탭이 설정으로
/// 가는 유일한 길이었다. 그 안 맨 아래 '회원 탈퇴' 까지 도달해야 했다.
/// 여기서 지키는 것은 두 가지다 — **보이는 진입점**과 **영문 병기**.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('내정보 헤더에 설정 진입 아이콘이 있다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        // 게스트가 아닌 경로는 세션·네트워크가 필요하므로 헤더만 검증한다.
        home: const MyInfoTab(),
      ),
    );
    await tester.pump();

    final gear = find.byIcon(Icons.settings_outlined);
    expect(gear, findsOneWidget, reason: '설정으로 가는 눈에 보이는 길이 있어야 한다');

    // 툴팁에 영문 병기 — 한국어를 못 읽어도 무엇인지 알 수 있어야 한다.
    final tooltip = tester.widget<IconButton>(
      find.ancestor(of: gear, matching: find.byType(IconButton)),
    );
    expect(tooltip.tooltip, contains('Settings'));
  });

  // 설정 화면(ProfileEditScreen)을 위젯 테스트로 띄우려면 세션·리포지토리가
  // 필요해 비용이 크다. 지켜야 할 것은 **문구가 남아 있는지** 하나뿐이므로
  // CI 의 `catch (_)` 래칫과 같은 방식으로 소스에서 직접 확인한다.
  test('설정 화면에 계정 삭제·설정의 영문 병기가 남아 있다', () {
    final src = File('lib/screen/profile_edit_screen.dart').readAsStringSync();

    expect(
      src,
      contains("labelEn: 'Delete Account'"),
      reason: '한국어를 못 읽는 심사관이 계정 삭제를 찾지 못해 두 번 반려됐다',
    );
    expect(src, contains("title: '설정 (Settings)'"));
    // 삭제는 여전히 설정 목록에 있어야 한다(다른 곳으로 옮겼다면 이 테스트도 함께 고칠 것).
    expect(src, contains("label: '회원 탈퇴'"));
  });
}
