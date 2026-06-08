import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../models/community.dart';
import '../services/community_repository.dart';
import '../services/session.dart';
import '../widgets/post_card.dart';
import 'post_detail_screen.dart';

enum PostListMode { mine, hearted }

/// 내 게시글 / 하트한 게시글 목록.
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

  String get _title =>
      widget.mode == PostListMode.mine ? '내 게시글' : '하트한 게시글';

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
      final posts = widget.mode == PostListMode.mine
          ? await _repo.fetchUserPosts(SessionManager.instance.user!.id)
          : await _repo.fetchHeartedPosts();
      if (!mounted) return;
      setState(() {
        _posts = posts;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '불러오지 못했어요';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(_title)),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _empty(_error!, retry: true);
    }
    if (_posts.isEmpty) {
      return _empty(widget.mode == PostListMode.mine
          ? '작성한 게시글이 없어요'
          : '하트한 게시글이 없어요');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: _posts.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) => PostCard(
          post: _posts[i],
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => PostDetailScreen(post: _posts[i])),
            );
            _load();
          },
        ),
      ),
    );
  }

  Widget _empty(String msg, {bool retry = false}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.article_outlined,
              size: 48, color: AppColors.textTertiary),
          const SizedBox(height: 12),
          Text(msg,
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textSecondary)),
          if (retry) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: _load, child: const Text('다시 시도')),
          ],
        ],
      ),
    );
  }
}
