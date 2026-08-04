import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/admin.dart';
import '../../motion/motion.dart';
import '../../services/admin/admin_moderation_repository.dart';
import '../../theme/app_palette.dart';
import '../../utils/labels.dart' show timeAgo, categoryLabel;
import 'admin_theme.dart';

/// 게시글/댓글 관리 — 게시글 검색/조회 + 숨김·삭제, 댓글 관리로 이동.
class AdminPostsScreen extends StatefulWidget {
  const AdminPostsScreen({super.key});

  @override
  State<AdminPostsScreen> createState() => _AdminPostsScreenState();
}

class _AdminPostsScreenState extends State<AdminPostsScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  int _reqId = 0;

  List<AdminPost> _items = [];
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
      final items = await AdminModerationRepository.instance.listPosts(
        search: q,
      );
      if (!mounted || myReq != _reqId) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || myReq != _reqId) return;
      setState(() {
        _error = '게시글을 불러오지 못했어요';
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

  Future<void> _setVisibility(AdminPost p, String vis) async {
    if (vis == 'deleted_by_admin') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('게시글 삭제'),
          content: const Text('이 게시글을 삭제(숨김) 처리할까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('삭제', style: TextStyle(color: context.colors.danger)),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = p.id);
    try {
      await AdminModerationRepository.instance.setPostVisibility(p.id, vis);
      await _load(_ctrl.text);
    } catch (_) {
      _toast('처리하지 못했어요');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: adminAppBar(context, '게시글/댓글 관리'),
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
                  hintText: '제목 · 내용으로 검색',
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
          '게시글이 없어요',
          style: TextStyle(fontSize: 14, color: context.colors.textSecondary),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _load(_ctrl.text),
      child: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _PostCard(
          post: _items[i],
          busy: _busy == _items[i].id,
          onSetVisibility: (v) => _setVisibility(_items[i], v),
          onComments: () => Navigator.push(
            context,
            AppPageRoute(
              builder: (_) => AdminPostCommentsScreen(
                postId: _items[i].id,
                postTitle: _items[i].title,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  final AdminPost post;
  final bool busy;
  final ValueChanged<String> onSetVisibility;
  final VoidCallback onComments;
  const _PostCard({
    required this.post,
    required this.busy,
    required this.onSetVisibility,
    required this.onComments,
  });

  bool get _hidden => post.visibilityStatus != 'visible';

  @override
  Widget build(BuildContext context) {
    final p = post;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                categoryLabel(p.category),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: context.colors.primaryDark,
                ),
              ),
              const SizedBox(width: 8),
              _visBadge(context, p.visibilityStatus),
              const Spacer(),
              if (busy)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    color: context.colors.textSecondary,
                    size: 20,
                  ),
                  onSelected: onSetVisibility,
                  itemBuilder: (_) => [
                    if (_hidden)
                      const PopupMenuItem(
                        value: 'visible',
                        child: Text('공개로 전환'),
                      ),
                    if (p.visibilityStatus != 'hidden_by_admin')
                      const PopupMenuItem(
                        value: 'hidden_by_admin',
                        child: Text('숨김'),
                      ),
                    PopupMenuItem(
                      value: 'deleted_by_admin',
                      child: Text(
                        '삭제',
                        style: TextStyle(color: context.colors.danger),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            p.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            p.content,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: context.colors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '${p.authorNickname}  ·  ${timeAgo(p.createdAt)}',
                style: TextStyle(
                  fontSize: 11,
                  color: context.colors.textTertiary,
                ),
              ),
              const Spacer(),
              _stat(context, Icons.favorite_border, p.heartCount),
              const SizedBox(width: 10),
              _stat(context, Icons.visibility_outlined, p.viewCount),
            ],
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: context.colors.border),
          TextButton.icon(
            onPressed: onComments,
            icon: const Icon(Icons.mode_comment_outlined, size: 16),
            label: Text('댓글 ${p.commentCount} 관리'),
            style: TextButton.styleFrom(
              foregroundColor: context.colors.primaryDark,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, IconData icon, int v) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14, color: context.colors.textTertiary),
      const SizedBox(width: 3),
      Text(
        '$v',
        style: TextStyle(fontSize: 11, color: context.colors.textTertiary),
      ),
    ],
  );

  Widget _visBadge(BuildContext context, String status) {
    final (label, color) = switch (status) {
      'visible' => ('공개', context.colors.success),
      'hidden_by_admin' => ('숨김(관리자)', context.colors.danger),
      'hidden_by_user' => ('숨김(작성자)', context.colors.textSecondary),
      'deleted_by_admin' => ('삭제(관리자)', context.colors.danger),
      'deleted_by_user' => ('삭제(작성자)', context.colors.textSecondary),
      _ => (status, context.colors.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// 특정 게시글의 댓글 관리 — 숨김/복원.
class AdminPostCommentsScreen extends StatefulWidget {
  final String postId;
  final String postTitle;
  const AdminPostCommentsScreen({
    super.key,
    required this.postId,
    required this.postTitle,
  });

  @override
  State<AdminPostCommentsScreen> createState() =>
      _AdminPostCommentsScreenState();
}

class _AdminPostCommentsScreenState extends State<AdminPostCommentsScreen> {
  List<AdminComment> _items = [];
  bool _loading = true;
  String? _error;
  String? _busy;

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
      final items = await AdminModerationRepository.instance.listComments(
        widget.postId,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '댓글을 불러오지 못했어요';
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

  Future<void> _toggle(AdminComment c) async {
    setState(() => _busy = c.id);
    try {
      await AdminModerationRepository.instance.setCommentDeleted(
        c.id,
        !c.isDeleted,
      );
      await _load();
    } catch (_) {
      _toast('처리하지 못했어요');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: adminAppBar(context, '댓글 관리'),
      body: SafeArea(child: _body()),
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
            TextButton(onPressed: _load, child: const Text('다시 시도')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(
          '댓글이 없어요',
          style: TextStyle(fontSize: 14, color: context.colors.textSecondary),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: _items.length,
        separatorBuilder: (_, _) =>
            Divider(height: 20, color: context.colors.border),
        itemBuilder: (_, i) {
          final c = _items[i];
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          c.authorNickname,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: context.colors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeAgo(c.createdAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: context.colors.textTertiary,
                          ),
                        ),
                        if (c.isDeleted) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: context.colors.danger.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              '숨김',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: context.colors.danger,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      c.content,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: c.isDeleted
                            ? context.colors.textTertiary
                            : context.colors.textPrimary,
                        decoration: c.isDeleted
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _busy == c.id
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : TextButton(
                      onPressed: () => _toggle(c),
                      child: Text(
                        c.isDeleted ? '복원' : '숨김',
                        style: TextStyle(
                          color: c.isDeleted
                              ? context.colors.primaryDark
                              : context.colors.danger,
                        ),
                      ),
                    ),
            ],
          );
        },
      ),
    );
  }
}
