import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../data/mock_data.dart' show categoryLabel, timeAgo;
import '../models/community.dart';
import '../services/community_repository.dart';
import '../services/social_repository.dart';
import '../services/chat_launcher.dart';
import '../services/session.dart';
import '../widgets/role_badge.dart';
import 'auth/auth_wall_dialog.dart';

/// 게시글 상세 — 본문 / 약속·위치 / 작성자 / 댓글(실데이터) / 하트·지원·댓글 작성.
class PostDetailScreen extends StatefulWidget {
  final Post post;
  final bool isGuest;

  const PostDetailScreen({
    super.key,
    required this.post,
    this.isGuest = false,
  });

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _repo = CommunityRepository.instance;
  final _commentCtrl = TextEditingController();

  late Post _post;
  List<Comment> _comments = [];
  bool _loadingComments = true;
  bool _sending = false;
  bool _applying = false;
  bool _following = false;

  bool get _isFreePost => _post.category == 'free';
  bool get _isMyPost => _post.userId == SessionManager.instance.user?.id;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _loadComments();
    if (!widget.isGuest && !_isMyPost) _loadFollowing();
  }

  Future<void> _loadFollowing() async {
    try {
      final f = await SocialRepository.instance.isFollowing(_post.userId);
      if (mounted) setState(() => _following = f);
    } catch (_) {}
  }

  Future<void> _toggleFollow() async {
    if (!_guard('팔로우는 로그인 후 할 수 있어요')) return;
    final was = _following;
    setState(() => _following = !was);
    try {
      if (was) {
        await SocialRepository.instance.unfollow(_post.userId);
      } else {
        await SocialRepository.instance.follow(_post.userId);
      }
    } catch (_) {
      if (mounted) setState(() => _following = was);
    }
  }

  void _startChat() {
    if (!_guard('채팅은 로그인 후 이용할 수 있어요')) return;
    openDirectChat(context, _post.userId);
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    try {
      final list = await _repo.fetchComments(_post.id);
      if (!mounted) return;
      setState(() {
        _comments = list;
        _loadingComments = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingComments = false);
    }
  }

  bool _guard(String message) {
    if (widget.isGuest) {
      AuthWallDialog.show(context, message: message);
      return false;
    }
    return true;
  }

  Future<void> _toggleHeart() async {
    if (!_guard('하트는 로그인 후 누를 수 있어요')) return;
    final wasHearted = _post.hearted;
    // 낙관적 업데이트
    setState(() => _post = _post.copyWith(
          hearted: !wasHearted,
          heartCount: _post.heartCount + (wasHearted ? -1 : 1),
        ));
    try {
      await _repo.toggleHeart(_post.id, wasHearted);
    } catch (_) {
      if (!mounted) return;
      setState(() => _post = _post.copyWith(
            hearted: wasHearted,
            heartCount: _post.heartCount + (wasHearted ? 1 : -1),
          ));
      _toast('잠시 후 다시 시도해주세요');
    }
  }

  Future<void> _sendComment() async {
    if (!_guard('댓글은 로그인 후 작성할 수 있어요')) return;
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await _repo.addComment(_post.id, text);
      _commentCtrl.clear();
      if (mounted) FocusScope.of(context).unfocus();
      await _loadComments();
    } catch (_) {
      _toast('댓글 작성에 실패했어요');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _apply() async {
    if (!_guard('지원은 로그인 후 할 수 있어요')) return;
    setState(() => _applying = true);
    try {
      await _repo.apply(_post.id);
      _toast('지원했어요');
    } catch (e) {
      _toast('이미 지원했거나 지원할 수 없는 게시글이에요');
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = categoryColor(_post.category);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        actions: [
          if (!_isMyPost)
            IconButton(
              icon: const Icon(Icons.chat_bubble_outline),
              tooltip: '채팅하기',
              onPressed: _startChat,
            ),
          IconButton(icon: const Icon(Icons.share_outlined), onPressed: () {}),
          IconButton(icon: const Icon(Icons.more_horiz), onPressed: () {}),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  categoryLabel(_post.category),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _post.title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 14),
            _AuthorRow(
              post: _post,
              showFollow: !widget.isGuest && !_isMyPost,
              following: _following,
              onFollow: _toggleFollow,
            ),
            const SizedBox(height: 20),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 20),
            Text(
              _post.content,
              style: const TextStyle(
                fontSize: 15,
                color: AppColors.textPrimary,
                height: 1.7,
              ),
            ),
            if (_post.imageUrl != null) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: AspectRatio(
                  aspectRatio: kPostImageAspectRatio, // 4284 : 5712
                  child: Image.network(
                    _post.imageUrl!,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const ColoredBox(color: AppColors.surfaceMuted),
                  ),
                ),
              ),
            ],
            if (_post.scheduledAt != null || _post.location != null) ...[
              const SizedBox(height: 24),
              _InfoBox(post: _post),
            ],
            if (!_isFreePost && _post.progressStatus == 'recruiting') ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _applying ? null : _apply,
                icon: _applying
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
                label: const Text('이 게시글에 지원하기'),
              ),
            ],
            const SizedBox(height: 28),
            Text(
              '댓글 ${_comments.length}',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            _CommentList(loading: _loadingComments, comments: _comments),
          ],
        ),
      ),
      bottomNavigationBar: _BottomBar(
        post: _post,
        controller: _commentCtrl,
        sending: _sending,
        onHeart: _toggleHeart,
        onSend: _sendComment,
      ),
    );
  }
}

class _AuthorRow extends StatelessWidget {
  final Post post;
  final bool showFollow;
  final bool following;
  final VoidCallback onFollow;
  const _AuthorRow({
    required this.post,
    required this.showFollow,
    required this.following,
    required this.onFollow,
  });

  @override
  Widget build(BuildContext context) {
    final initial = post.authorNickname.isEmpty
        ? '?'
        : post.authorNickname.characters.first;
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: AppColors.primarySoft,
          child: Text(
            initial,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryDark,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              post.authorNickname,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              timeAgo(post.createdAt),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
        const Spacer(),
        if (showFollow) _FollowButton(following: following, onTap: onFollow),
      ],
    );
  }
}

/// 팔로우(Pawing) 토글 버튼.
class _FollowButton extends StatelessWidget {
  final bool following;
  final VoidCallback onTap;
  const _FollowButton({required this.following, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: following ? AppColors.surface : AppColors.primaryDark,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: following ? AppColors.border : AppColors.primaryDark,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              following ? Icons.check : Icons.add,
              size: 14,
              color: following ? AppColors.textSecondary : AppColors.textOnPrimary,
            ),
            const SizedBox(width: 4),
            Text(
              following ? 'Pawing 중' : 'Pawing',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: following
                    ? AppColors.textSecondary
                    : AppColors.textOnPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final Post post;
  const _InfoBox({required this.post});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Column(
        children: [
          if (post.scheduledAt != null)
            _row(
              Icons.event_outlined,
              '약속 일정',
              '${post.scheduledAt!.year}년 ${post.scheduledAt!.month}월 ${post.scheduledAt!.day}일 ${post.scheduledAt!.hour}시',
            ),
          if (post.scheduledAt != null && post.location != null)
            const SizedBox(height: 12),
          if (post.location != null)
            _row(Icons.place_outlined, '위치', post.location!),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) => Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primaryDark),
          const SizedBox(width: 10),
          Text(label,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      );
}

class _CommentList extends StatelessWidget {
  final bool loading;
  final List<Comment> comments;
  const _CommentList({required this.loading, required this.comments});

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (comments.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Text('첫 댓글을 남겨보세요',
              style: TextStyle(fontSize: 13, color: AppColors.textTertiary)),
        ),
      );
    }
    return Column(
      children: comments.map((c) {
        final initial =
            c.authorNickname.isEmpty ? '?' : c.authorNickname.characters.first;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.primarySoft,
                child: Text(
                  initial,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          c.authorNickname,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeAgo(c.createdAt),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      c.content,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final Post post;
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onHeart;
  final VoidCallback onSend;

  const _BottomBar({
    required this.post,
    required this.controller,
    required this.sending,
    required this.onHeart,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              GestureDetector(
                onTap: onHeart,
                behavior: HitTestBehavior.opaque,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      post.hearted ? Icons.favorite : Icons.favorite_border,
                      color: post.hearted
                          ? AppColors.danger
                          : AppColors.textSecondary,
                    ),
                    Text('${post.heartCount}',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: '댓글을 입력하세요',
                    filled: true,
                    fillColor: AppColors.surfaceMuted,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(100),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(100),
                      borderSide:
                          const BorderSide(color: AppColors.primary, width: 1.2),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.primaryDark,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.textOnPrimary,
                          ),
                        )
                      : const Icon(Icons.arrow_upward,
                          color: AppColors.textOnPrimary),
                  onPressed: sending ? null : onSend,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
