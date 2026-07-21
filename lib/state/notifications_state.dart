import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/notification.dart';
import '../services/notification_repository.dart';

/// 알림함 화면 상태 홀더 — 로딩/에러/목록과 읽음 처리 로직. (#155·#156 파일럿)
///
/// 규칙: 화면(위젯)은 이 홀더를 `ListenableBuilder` 로 구독해 **그리기만** 하고,
/// 데이터 로딩·낙관적 갱신·리포지토리 호출은 전부 여기에 둔다. 홀더는 위젯
/// 트리와 무관하므로 FakeSupabase(http 목킹)로 단위 테스트한다.
class NotificationsState extends ChangeNotifier {
  NotificationsState({NotificationRepository? repo})
    : _repo = repo ?? NotificationRepository.instance;

  final NotificationRepository _repo;

  List<AppNotification> _items = const [];
  bool _loading = true;
  String? _error;

  List<AppNotification> get items => _items;
  bool get loading => _loading;
  String? get error => _error;
  bool get hasUnread => _items.any((n) => !n.isRead);

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _items = await _repo.fetch();
      _loading = false;
    } catch (e) {
      debugPrint('알림함: 목록 조회 실패: $e');
      _error = '알림을 불러오지 못했어요';
      _loading = false;
    }
    notifyListeners();
  }

  /// 탭한 알림의 낙관적 읽음 처리 — 목록은 즉시 갱신하고 서버 반영은
  /// fire-and-forget(실패해도 다음 load 에서 서버 상태로 수렴).
  void markRead(AppNotification n) {
    if (n.isRead) return;
    unawaited(_repo.markRead(n.id));
    final idx = _items.indexWhere((e) => e.id == n.id);
    if (idx < 0) return;
    _items = [..._items]..[idx] = n.copyWith(isRead: true);
    notifyListeners();
  }

  Future<void> markAllRead() async {
    await _repo.markAllRead();
    await load();
  }
}
