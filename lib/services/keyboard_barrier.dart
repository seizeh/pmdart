import 'package:flutter/foundation.dart';

/// 전역 "키보드 닫기" 배리어 on/off.
///
/// 키보드가 떠 있을 때 화면 탭을 흡수해 키보드만 닫고 아래 위젯(게시글 등) 탭으로
/// 전달되지 않게 하는 배리어(main.dart)를 제어한다. 지도처럼 자동완성 제안을
/// 키보드가 떠 있는 상태로 탭해야 하는 화면은 진입 시 false 로 꺼서 제안 탭이
/// 가로채이지 않게 하고, 자체적으로(onMapTapped 등) 키보드를 닫는다.
final keyboardBarrierEnabled = ValueNotifier<bool>(true);
