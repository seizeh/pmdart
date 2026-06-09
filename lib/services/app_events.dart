import 'package:flutter/foundation.dart';

/// 화면 간 데이터 변경 알림 허브.
/// 한 화면의 액션(팔로우/채팅 시작 등)을 다른 탭이 구독해 자동 새로고침하도록 한다.
/// (탭들은 IndexedStack 으로 살아있어 재진입만으로는 갱신되지 않으므로 필요.)
class AppEvents {
  AppEvents._();
  static final AppEvents instance = AppEvents._();

  /// 팔로우(Pawing) 변경 — 내정보 통계/목록 새로고침 트리거.
  final ValueNotifier<int> social = ValueNotifier(0);

  /// 채팅방/메시지 변경 — 채팅 목록 새로고침 트리거.
  final ValueNotifier<int> chat = ValueNotifier(0);

  /// 프로필/반려동물 변경 — 내정보 새로고침 트리거.
  final ValueNotifier<int> profile = ValueNotifier(0);

  /// 알림 읽음/변경 — 벨 배지 새로고침 트리거.
  final ValueNotifier<int> notification = ValueNotifier(0);

  void notifySocial() => social.value++;
  void notifyChat() => chat.value++;
  void notifyProfile() => profile.value++;
  void notifyNotification() => notification.value++;
}
