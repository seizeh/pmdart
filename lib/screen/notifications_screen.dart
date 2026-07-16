import 'package:flutter/material.dart';
import '../main.dart' show openFromPush;
import '../theme/app_palette.dart';
import '../data/mock_data.dart' show timeAgo;
import '../models/notification.dart';
import '../services/notification_repository.dart';

/// 알림함 — 내 알림 목록 / 읽음 처리 / 관련 화면 이동.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _repo = NotificationRepository.instance;
  List<AppNotification> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _repo.fetch();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '알림을 불러오지 못했어요';
        _loading = false;
      });
    }
  }

  Future<void> _onTap(AppNotification n) async {
    if (!n.isRead) {
      _repo.markRead(n.id);
      final idx = _items.indexWhere((e) => e.id == n.id);
      if (idx >= 0) {
        setState(
          () => _items[idx] = AppNotification(
            id: n.id,
            type: n.type,
            title: n.title,
            body: n.body,
            isRead: true,
            createdAt: n.createdAt,
            resourceType: n.resourceType,
            resourceId: n.resourceId,
            aggregatedCount: n.aggregatedCount,
          ),
        );
      }
    }
    await _navigate(n);
  }

  Future<void> _navigate(AppNotification n) async {
    // 푸시 탭과 동일한 딥링크 라우팅 — 관련 탭으로 전환한 뒤 상세를 rise 로
    // 열어, 닫으면(쓸어내리기/뒤로가기) 채팅 목록 등 관련 탭이 나온다.
    await openFromPush(n.type, n.resourceType, n.resourceId);
  }

  Future<void> _markAll() async {
    await _repo.markAllRead();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = _items.any((n) => !n.isRead);
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: const Text('알림'),
        actions: [
          if (hasUnread)
            TextButton(onPressed: _markAll, child: const Text('모두 읽음')),
        ],
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _empty(_error!, retry: true);
    }
    if (_items.isEmpty) return _empty('받은 알림이 없어요');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _items.length,
        separatorBuilder: (_, _) =>
            Divider(height: 1, color: context.colors.border),
        itemBuilder: (_, i) => _NotificationTile(
          notification: _items[i],
          onTap: () => _onTap(_items[i]),
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
            TextButton(onPressed: _load, child: const Text('다시 시도')),
          ],
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final VoidCallback onTap;
  const _NotificationTile({required this.notification, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final n = notification;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: n.isRead
            ? Colors.white
            : context.colors.primarySoft.withValues(alpha: 0.18),
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
                    Text(
                      n.body!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: context.colors.textSecondary,
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
