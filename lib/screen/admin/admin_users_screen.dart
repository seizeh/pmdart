import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/admin_repository.dart';
import '../../services/session.dart';
import '../../theme/app_palette.dart';
import '../../utils/labels.dart' show timeAgo;
import 'admin_theme.dart';

/// 회원 관리 — 검색/조회 + 상태 변경(정지/휴면/활성).
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  int _reqId = 0;

  List<AdminUser> _items = [];
  bool _loading = true;
  String? _error;
  String? _busy;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _load(v));
  }

  Future<void> _load(String q) async {
    final myReq = ++_reqId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await AdminRepository.instance.listUsers(search: q);
      if (!mounted || myReq != _reqId) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || myReq != _reqId) return;
      setState(() {
        _error = '회원을 불러오지 못했어요';
        _loading = false;
      });
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _setStatus(AdminUser u, String status) async {
    setState(() => _busy = u.id);
    try {
      await AdminRepository.instance.setUserStatus(u.id, status);
      _toast('${u.nickname} · ${_statusLabel(status)} 처리했어요');
      await _load(_ctrl.text);
    } catch (_) {
      _toast('상태를 변경하지 못했어요');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  static String _statusLabel(String s) => switch (s) {
    'active' => '활성',
    'inactive' => '휴면',
    'suspended' => '정지',
    _ => s,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: adminAppBar(context, '회원 관리'),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: TextField(
                controller: _ctrl,
                onChanged: _onChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: '닉네임 · 아이디 · 전화로 검색',
                  prefixIcon: Icon(
                    Icons.search,
                    color: context.colors.textSecondary,
                  ),
                  suffixIcon: _ctrl.text.isEmpty
                      ? null
                      : IconButton(
                          icon: Icon(
                            Icons.close,
                            color: context.colors.textTertiary,
                          ),
                          onPressed: () {
                            _ctrl.clear();
                            _load('');
                          },
                        ),
                ),
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              style: TextStyle(color: context.colors.textSecondary),
            ),
            TextButton(
              onPressed: () => _load(_ctrl.text),
              child: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(
          '회원이 없어요',
          style: TextStyle(fontSize: 14, color: context.colors.textSecondary),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(_ctrl.text),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _items.length,
        separatorBuilder: (_, _) =>
            Divider(height: 1, color: context.colors.border),
        itemBuilder: (_, i) => _UserRow(
          user: _items[i],
          busy: _busy == _items[i].id,
          onSetStatus: (s) => _setStatus(_items[i], s),
        ),
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  final AdminUser user;
  final bool busy;
  final ValueChanged<String> onSetStatus;
  const _UserRow({
    required this.user,
    required this.busy,
    required this.onSetStatus,
  });

  @override
  Widget build(BuildContext context) {
    final isSelf = user.id == SessionManager.instance.user?.id;
    final canModerate = !user.isAdmin && !isSelf;
    final sub = [
      '@${user.username}',
      if (user.phone != null && user.phone!.isNotEmpty) user.phone!,
      timeAgo(user.createdAt),
    ].join('  ·  ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: context.colors.primarySoft,
            child: Text(
              user.nickname.isEmpty ? '?' : user.nickname.characters.first,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: context.colors.primaryDark,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        user.nickname,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: context.colors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (user.isAdmin) _tag('관리자', context.colors.primaryDark),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _statusBadge(context, user.status),
          if (canModerate) ...[
            const SizedBox(width: 4),
            busy
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: Padding(
                      padding: EdgeInsets.all(4),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert,
                      color: context.colors.textSecondary,
                    ),
                    onSelected: onSetStatus,
                    itemBuilder: (_) => [
                      if (user.status != 'active')
                        const PopupMenuItem(
                          value: 'active',
                          child: Text('활성으로'),
                        ),
                      if (user.status != 'suspended')
                        const PopupMenuItem(
                          value: 'suspended',
                          child: Text('정지'),
                        ),
                      if (user.status != 'inactive')
                        const PopupMenuItem(
                          value: 'inactive',
                          child: Text('휴면'),
                        ),
                    ],
                  ),
          ],
        ],
      ),
    );
  }

  Widget _statusBadge(BuildContext context, String status) {
    final (label, color) = switch (status) {
      'active' => ('활성', context.colors.success),
      'inactive' => ('휴면', context.colors.warning),
      'suspended' => ('정지', context.colors.danger),
      _ => (status, context.colors.textSecondary),
    };
    return _tag(label, color);
  }

  Widget _tag(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(100),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
    ),
  );
}
