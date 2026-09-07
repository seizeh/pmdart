import 'package:flutter/material.dart';

import '../app/push_routing.dart' show openFromPush;
import '../models/notification.dart';
import '../state/notifications_state.dart';
import '../theme/app_palette.dart';
import '../utils/labels.dart' show timeAgo;

/// 알림함 — 내 알림 목록 / 읽음 처리 / 관련 화면 이동.
///
/// 상태·로직은 [NotificationsState] 가 갖고, 이 위젯은 구독해 그리기만 한다
/// (#155·#156 상태 홀더 분리 파일럿 — 새 화면은 이 구조를 따른다).
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late final NotificationsState _state = NotificationsState();

  @override
  void initState() {
    super.initState();
    _state.load();
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  /// 제자리에서 본문을 펼쳐 둔 알림 id — 이동할 화면이 없는 알림의 "더 보기".
  final Set<String> _expanded = {};

  Future<void> _onTap(AppNotification n) async {
    _state.markRead(n);
    if (!n.hasDestination) {
      // 이동할 곳이 없다(공지 등) — 새 화면 대신 그 자리에서 본문을 아래로
      // 펼친다(다시 탭하면 접힘). 종전에는 아무 일도 안 일어나 2줄로 잘린
      // 본문을 읽을 방법이 없었다.
      setState(() {
        if (!_expanded.add(n.id)) _expanded.remove(n.id);
      });
      return;
    }
    // 푸시 탭과 동일한 딥링크 라우팅 — 관련 탭으로 전환한 뒤 상세를 rise 로
    // 열어, 닫으면(쓸어내리기/뒤로가기) 채팅 목록 등 관련 탭이 나온다.
    // 이미 알림함이므로 폴백(알림함 열기)은 끈다 — 재귀 방지.
    await openFromPush(
      n.type,
      n.resourceType,
      n.resourceId,
      fallbackToInbox: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _state,
      builder: (context, _) => Scaffold(
        backgroundColor: context.colors.background,
        appBar: AppBar(
          title: const Text('알림'),
          actions: [
            if (_state.hasUnread)
              TextButton(
                onPressed: _state.markAllRead,
                child: const Text('모두 읽음'),
              ),
          ],
        ),
        body: SafeArea(child: _body()),
      ),
    );
  }

  Widget _body() {
    if (_state.loading) return const Center(child: CircularProgressIndicator());
    final error = _state.error;
    if (error != null) return _empty(error, retry: true);
    final items = _state.items;
    if (items.isEmpty) return _empty('받은 알림이 없어요');
    return RefreshIndicator(
      onRefresh: _state.load,
      child: ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, _) =>
            Divider(height: 1, color: context.colors.border),
        itemBuilder: (_, i) => _NotificationTile(
          notification: items[i],
          expanded: _expanded.contains(items[i].id),
          onTap: () => _onTap(items[i]),
        ),
      ),
    );
  }

  Widget _empty(String msg, {bool retry = false}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.notifications_none,
            size: 56,
            color: context.colors.textTertiary,
          ),
          const SizedBox(height: 12),
          Text(
            msg,
            style: TextStyle(fontSize: 14, color: context.colors.textSecondary),
          ),
          if (retry) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: _state.load, child: const Text('다시 시도')),
          ],
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;

  /// 본문을 줄 제한 없이 아래로 펼침 — 이동할 화면이 없는 알림의 "더 보기".
  final bool expanded;
  final VoidCallback onTap;
  const _NotificationTile({
    required this.notification,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final n = notification;
    return InkWell(
      onTap: onTap,
      child: Container(
        // 읽음 = surface(테마 추종 — 흰색 하드코딩은 다크에서 눈부셨다),
        // 안읽음 = 연한 골드 브라운(unreadTint, 라이트/다크 공통 규칙).
        color: n.isRead ? context.colors.surface : context.colors.unreadTint,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: context.colors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: Icon(n.icon, size: 20, color: context.colors.primaryDark),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n.displayTitle,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: n.isRead ? FontWeight.w600 : FontWeight.w700,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  if (n.body != null && n.body!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    // 펼침/접힘이 제자리에서 아래로 자라도록 크기만 애니메이션.
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.topLeft,
                      child: Text(
                        n.body!,
                        maxLines: expanded ? null : 2,
                        overflow: expanded ? null : TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: context.colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    timeAgo(n.createdAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: context.colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            if (!n.isRead)
              Container(
                margin: const EdgeInsets.only(top: 4, left: 6),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: context.colors.danger,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
