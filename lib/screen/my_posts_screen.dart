import 'dart:async';
import 'package:flutter/material.dart';

import '../models/community.dart';
import '../motion/motion.dart';
import '../services/community_repository.dart';
import '../services/session.dart';
import '../theme/app_palette.dart';
import '../widgets/post_card.dart';
import 'post_detail_screen.dart';

enum PostListMode { mine, hearted }

/// 내 게시글 / 하트한 게시글 목록.
///
/// 내 게시글에서는 우측 상단 "삭제하기"로 **선택 모드**에 진입한다.
/// 선택 모드에서는 카드가 살짝 작아지며(직접 조작 대상임을 알리는 피드백),
/// 탭이 상세보기 대신 선택 토글로 바뀐다. 모든 전환은 [SpringCurve] 물리를 공유한다
/// (continuity). 선택/해제는 즉각적인 스케일·체크 피드백으로 드러난다(feedback·direct manipulation).
class MyPostsScreen extends StatefulWidget {
  final PostListMode mode;
  const MyPostsScreen({super.key, required this.mode});

  @override
  State<MyPostsScreen> createState() => _MyPostsScreenState();
}

class _MyPostsScreenState extends State<MyPostsScreen> {
  final _repo = CommunityRepository.instance;
  List<Post> _posts = [];
  bool _loading = true;
  String? _error;

  // 선택(삭제) 모드 상태.
  bool _selectMode = false;
  final Set<String> _selectedIds = {};
  bool _deleting = false;

  bool get _isMine => widget.mode == PostListMode.mine;
  String get _title => _isMine ? '내 게시글' : '하트한 게시글';

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
      final posts = _isMine
          ? await _repo.fetchUserPosts(SessionManager.instance.user!.id)
          : await _repo.fetchHeartedPosts();
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _loading = false;
        // 목록이 갱신되면 사라진 게시글의 선택은 정리.
        _selectedIds.retainWhere((id) => posts.any((p) => p.id == id));
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '불러오지 못했어요';
        _loading = false;
      });
    }
  }

  void _enterSelect() => setState(() {
    _selectMode = true;
    _selectedIds.clear();
  });

  void _exitSelect() => setState(() {
    _selectMode = false;
    _selectedIds.clear();
  });

  void _toggle(String id) => setState(() {
    if (!_selectedIds.add(id)) _selectedIds.remove(id);
  });

  Future<void> _openDetail(Post post) async {
    await Navigator.push(
      context,
      AppPageRoute(
        builder: (_) => PostDetailScreen(
          post: post,
          // 내 글 작성자(나) 탭은 프로필을 쌓지 않고 되돌아온다(무한 왕복 방지).
          fromUserId: SessionManager.instance.user?.id,
        ),
      ),
    );
    unawaited(_load());
  }

  Future<void> _confirmDelete() async {
    final n = _selectedIds.length;
    if (n == 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('게시글 삭제'),
        content: Text('선택한 게시글 $n개를 삭제할까요?\n되돌릴 수 없어요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('삭제', style: TextStyle(color: context.colors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _deleting = true);
    try {
      final ids = _selectedIds.toList();
      await _repo.deletePosts(ids);
      if (!mounted) return;
      setState(() {
        _posts.removeWhere((p) => ids.contains(p.id));
        _selectedIds.clear();
        _selectMode = false;
        _deleting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('게시글 $n개를 삭제했어요'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('삭제에 실패했어요'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSelect =
        _isMine && !_loading && _error == null && _posts.isNotEmpty;
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        // 선택 모드에선 닫기(X)로 빠져나간다 — 진입/이탈의 연속성.
        leading: _selectMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _deleting ? null : _exitSelect,
              )
            : null,
        title: Text(_selectMode ? '${_selectedIds.length}개 선택' : _title),
        actions: [
          if (_selectMode)
            _DeleteAction(
              count: _selectedIds.length,
              busy: _deleting,
              onPressed: _selectedIds.isEmpty ? null : _confirmDelete,
            )
          else if (canSelect)
            TextButton(
              onPressed: _enterSelect,
              child: Text(
                '삭제하기',
                style: TextStyle(
                  color: context.colors.danger,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _empty(_error!, retry: true);
    if (_posts.isEmpty) {
      return _empty(_isMine ? '작성한 게시글이 없어요' : '하트한 게시글이 없어요');
    }
    return RefreshIndicator(
      // 선택 모드에선 당겨서 새로고침이 선택과 충돌하지 않도록 비활성.
      onRefresh: _selectMode ? () async {} : _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: _posts.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _SelectablePost(
          key: ValueKey(_posts[i].id),
          post: _posts[i],
          selectMode: _selectMode,
          selected: _selectedIds.contains(_posts[i].id),
          onTap: _selectMode
              ? () => _toggle(_posts[i].id)
              : () => _openDetail(_posts[i]),
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
            Icons.article_outlined,
            size: 48,
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

/// 선택 모드에서 카드를 감싸 스케일/선택 표시를 입힌다.
/// - selectMode 진입 시 살짝 작아진다(0.96) → "이제 만질 수 있는 대상" 신호(feedback).
/// - 선택되면 더 작아지고(0.93) danger 테두리 + 체크가 스프링으로 등장(direct manipulation).
class _SelectablePost extends StatelessWidget {
  final Post post;
  final bool selectMode;
  final bool selected;
  final VoidCallback onTap;

  const _SelectablePost({
    super.key,
    required this.post,
    required this.selectMode,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scale = !selectMode
        ? 1.0
        : selected
        ? 0.93
        : 0.96;
    return AnimatedScale(
      scale: scale,
      duration: MotionDurations.base,
      curve: SpringCurve.lively, // 전 화면과 같은 스프링 물리 공유(continuity)
      child: Stack(
        children: [
          PostCard(post: post, onTap: onTap),
          // 선택 강조 테두리/스크림 — 탭이 카드로 가도록 IgnorePointer.
          if (selectMode)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedContainer(
                  duration: MotionDurations.micro,
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected
                          ? context.colors.danger
                          : Colors.transparent,
                      width: 2,
                    ),
                    color: selected
                        ? context.colors.danger.withValues(alpha: 0.06)
                        : Colors.transparent,
                  ),
                ),
              ),
            ),
          if (selectMode)
            Positioned(
              top: 12,
              right: 12,
              child: IgnorePointer(child: _SelectDot(selected: selected)),
            ),
        ],
      ),
    );
  }
}

/// 선택 체크 표식 — 선택 시 danger 원 + 체크가 스프링으로 팝업.
class _SelectDot extends StatelessWidget {
  final bool selected;
  const _SelectDot({required this.selected});

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: selected ? 1.0 : 0.85,
      duration: MotionDurations.micro,
      curve: SpringCurve.lively,
      child: AnimatedContainer(
        duration: MotionDurations.micro,
        curve: Curves.easeOut,
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? context.colors.danger : Colors.white,
          border: Border.all(
            color: selected ? context.colors.danger : context.colors.border,
            width: 1.5,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: selected
            ? const Icon(Icons.check, size: 16, color: Colors.white)
            : null,
      ),
    );
  }
}

/// 선택 모드의 삭제 실행 액션(카운트 표시 + 진행 스피너).
class _DeleteAction extends StatelessWidget {
  final int count;
  final bool busy;
  final VoidCallback? onPressed;

  const _DeleteAction({
    required this.count,
    required this.busy,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    final enabled = onPressed != null;
    return TextButton(
      onPressed: onPressed,
      child: Text(
        count > 0 ? '삭제 ($count)' : '삭제',
        style: TextStyle(
          color: enabled ? context.colors.danger : context.colors.textTertiary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
