import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../models/community.dart';
import '../../services/community_repository.dart';
import '../../widgets/post_card.dart';
import '../../widgets/role_badge.dart';
import '../../services/app_events.dart';
import '../../services/notification_repository.dart';
import '../auth/auth_wall_dialog.dart';
import '../post_detail_screen.dart';
import '../post_create_screen.dart';
import '../notifications_screen.dart';

/// 커뮤니티 탭 — 게시글 목록(실데이터) + 카테고리 필터 + 검색.
class CommunityTab extends StatefulWidget {
  final bool isGuest;
  const CommunityTab({super.key, this.isGuest = false});

  @override
  State<CommunityTab> createState() => _CommunityTabState();
}

class _CommunityTabState extends State<CommunityTab> {
  final _repo = CommunityRepository.instance;

  String? _selectedCategory; // null = 전체
  List<Post> _posts = [];
  bool _loading = true;
  String? _error;

  static const _categories = [
    'walk_together',
    'walk_proxy',
    'care',
    'give_away',
    'adoption',
    'free',
  ];

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
      final posts = await _repo.fetchFeed(category: _selectedCategory);
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '게시글을 불러오지 못했어요';
        _loading = false;
      });
    }
  }

  void _selectCategory(String? c) {
    setState(() => _selectedCategory = c);
    _load();
  }

  Future<void> _toggleHeart(int index) async {
    if (widget.isGuest) {
      AuthWallDialog.show(context, message: '하트는 로그인 후 누를 수 있어요');
      return;
    }
    final post = _posts[index];
    final was = post.hearted;
    setState(() => _posts[index] = post.copyWith(
          hearted: !was,
          heartCount: post.heartCount + (was ? -1 : 1),
        ));
    try {
      await _repo.toggleHeart(post.id, was);
    } catch (_) {
      if (!mounted) return;
      setState(() => _posts[index] = post); // 롤백
    }
  }

  Future<void> _openCreate() async {
    if (widget.isGuest) {
      AuthWallDialog.show(context, message: '게시글은 로그인 후 작성할 수 있어요');
      return;
    }
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const PostCreateScreen()),
    );
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(
            slivers: [
              _SliverHeader(isGuest: widget.isGuest),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: _SearchBar(onTap: () {}),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      _FilterChip(
                        label: '전체',
                        selected: _selectedCategory == null,
                        onTap: () => _selectCategory(null),
                      ),
                      const SizedBox(width: 8),
                      ..._categories.map((c) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: CategoryChip(
                              category: c,
                              selected: _selectedCategory == c,
                              onTap: () => _selectCategory(
                                  _selectedCategory == c ? null : c),
                            ),
                          )),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              _buildList(),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        backgroundColor: AppColors.primaryDark,
        foregroundColor: AppColors.textOnPrimary,
        elevation: 0,
        icon: const Icon(Icons.edit_outlined),
        label: const Text('글 쓰기', style: TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildList() {
    if (_loading) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 60),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (_error != null) {
      return SliverToBoxAdapter(child: _MessageState(message: _error!, onRetry: _load));
    }
    if (_posts.isEmpty) {
      return const SliverToBoxAdapter(
        child: _MessageState(message: '아직 게시글이 없어요.\n첫 게시글을 작성해보세요!'),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverList.separated(
        itemCount: _posts.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) => PostCard(
          post: _posts[i],
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    PostDetailScreen(post: _posts[i], isGuest: widget.isGuest),
              ),
            );
            _load(); // 상세에서 하트/댓글 변동 반영
          },
          onHeart: () => _toggleHeart(i),
        ),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const _MessageState({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 60),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('다시 시도')),
          ],
        ],
      ),
    );
  }
}

class _SliverHeader extends StatelessWidget {
  final bool isGuest;
  const _SliverHeader({required this.isGuest});

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      sliver: SliverToBoxAdapter(
        child: Row(
          children: [
            const Text(
              '커뮤니티',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryDark,
                letterSpacing: -0.3,
              ),
            ),
            const Spacer(),
            _NotificationBell(isGuest: isGuest),
          ],
        ),
      ),
    );
  }
}

/// 알림 벨 — 실제 안읽음 수 배지 + 알림함 열기. 변경 시 자동 갱신.
class _NotificationBell extends StatefulWidget {
  final bool isGuest;
  const _NotificationBell({required this.isGuest});

  @override
  State<_NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<_NotificationBell> {
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    if (!widget.isGuest) {
      _loadCount();
      AppEvents.instance.notification.addListener(_loadCount);
    }
  }

  @override
  void dispose() {
    AppEvents.instance.notification.removeListener(_loadCount);
    super.dispose();
  }

  Future<void> _loadCount() async {
    try {
      final c = await NotificationRepository.instance.unreadCount();
      if (mounted) setState(() => _unread = c);
    } catch (_) {}
  }

  Future<void> _open() async {
    if (widget.isGuest) {
      AuthWallDialog.show(context);
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationsScreen()),
    );
    _loadCount();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: _open,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_outlined,
              color: AppColors.primaryDark, size: 26),
          if (!widget.isGuest && _unread > 0)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 16),
                decoration: BoxDecoration(
                  color: AppColors.danger,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Text(
                  _unread > 99 ? '99+' : '$_unread',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final VoidCallback onTap;
  const _SearchBar({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          children: const [
            Icon(Icons.search, color: AppColors.textTertiary, size: 22),
            SizedBox(width: 10),
            Text(
              '게시글 검색...',
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryDark : AppColors.surface,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: selected ? AppColors.primaryDark : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.textOnPrimary : AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}