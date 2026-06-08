import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import '../data/mock_data.dart';
import '../widgets/role_badge.dart';
import 'auth/auth_wall_dialog.dart';

class PostDetailScreen extends StatefulWidget {
  final MockPost post;
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
  late bool _hearted = widget.post.hearted;
  late int _heartCount = widget.post.heartCount;

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: AppColors.background,
            elevation: 0,
            pinned: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.flag_outlined),
                onPressed: () => _maybeAuth(() {}),
              ),
              IconButton(
                icon: const Icon(Icons.more_horiz),
                onPressed: () {},
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CategoryChip(category: post.category),
                  const SizedBox(height: 16),
                  Text(
                    post.title,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: AppColors.primarySoft,
                        child: Text(
                          post.authorNickname.characters.first,
                          style: const TextStyle(
                            fontSize: 14,
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
                                color: AppColors.textPrimary),
                          ),
                          Text(
                            DateFormat('M월 d일 HH:mm').format(post.createdAt),
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textTertiary),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (post.scheduledAt != null)
                    _meta(Icons.event,
                        DateFormat('M월 d일 EEEE HH:mm', 'ko').format(post.scheduledAt!)),
                  _meta(Icons.location_on_outlined, post.region),
                  if (post.petNames.isNotEmpty)
                    _meta(Icons.pets, post.petNames.join(', ')),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(18),
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border:
                          Border.all(color: AppColors.border, width: 0.5),
                    ),
                    child: Text(
                      post.content,
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.textPrimary,
                        height: 1.7,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      _statChip(
                        Icons.remove_red_eye_outlined,
                        '${post.viewCount}',
                      ),
                      const SizedBox(width: 8),
                      _statChip(
                        Icons.chat_bubble_outline,
                        '${post.commentCount}',
                      ),
                      const SizedBox(width: 8),
                      _statChip(
                        _hearted ? Icons.favorite : Icons.favorite_border,
                        '$_heartCount',
                        active: _hearted,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border:
                Border(top: BorderSide(color: AppColors.border, width: 0.5)),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: () => _maybeAuth(() {
                  setState(() {
                    _hearted = !_hearted;
                    _heartCount += _hearted ? 1 : -1;
                  });
                }),
                icon: Icon(
                  _hearted ? Icons.favorite : Icons.favorite_border,
                  color: _hearted ? AppColors.danger : AppColors.textSecondary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _maybeAuth(() {}),
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: const Text('1:1 채팅'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: post.progressStatus == 'recruiting'
                      ? () => _maybeAuth(_showApply)
                      : null,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: Text(
                    post.progressStatus == 'recruiting'
                        ? '지원하기'
                        : post.progressStatus == 'matched'
                            ? '매칭 완료'
                            : '마감',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 8),
            Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );

  Widget _statChip(IconData icon, String value, {bool active = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.danger.withOpacity(0.1) : AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 14,
                color: active ? AppColors.danger : AppColors.textSecondary),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? AppColors.danger : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      );

  void _maybeAuth(VoidCallback action) {
    if (widget.isGuest) {
      AuthWallDialog.show(context);
    } else {
      action();
    }
  }

  void _showApply() {
    final msgCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '지원 메시지',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '간단한 인사말을 남겨보세요 (선택)',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: msgCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: '안녕하세요! 저도 같이 산책해요',
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('지원했어요. 작성자가 수락하면 약속이 잡혀요'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: const Text('지원하기'),
            ),
          ],
        ),
      ),
    );
  }
}