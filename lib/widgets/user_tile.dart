import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../models/social.dart';
import '../services/social_repository.dart';
import '../services/chat_launcher.dart';

/// 사용자 한 명을 표시하는 공통 타일 — 채팅 시작 + 팔로우(Pawing) 토글.
/// 연결 목록 / 사용자 검색에서 재사용.
class UserTile extends StatefulWidget {
  final Connection connection;
  const UserTile({super.key, required this.connection});

  @override
  State<UserTile> createState() => _UserTileState();
}

class _UserTileState extends State<UserTile> {
  late bool _following;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _following =
        widget.connection.following ?? widget.connection.iFollowBack ?? false;
  }

  Future<void> _toggleFollow() async {
    if (_busy) return;
    final was = _following;
    setState(() {
      _busy = true;
      _following = !was;
    });
    try {
      if (was) {
        await SocialRepository.instance.unfollow(widget.connection.userId);
      } else {
        await SocialRepository.instance.follow(widget.connection.userId);
      }
    } catch (_) {
      if (mounted) setState(() => _following = was);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.connection;
    final initial = c.nickname.isEmpty ? '?' : c.nickname.characters.first;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.primarySoft,
            child: Text(
              initial,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryDark,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              c.nickname,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline,
                color: AppColors.primaryDark, size: 22),
            tooltip: '채팅',
            onPressed: () => openDirectChat(context, c.userId),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: _toggleFollow,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: _following ? AppColors.surface : AppColors.primaryDark,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: _following ? AppColors.border : AppColors.primaryDark,
                ),
              ),
              child: Text(
                _following ? 'Pawing 중' : 'Pawing',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _following
                      ? AppColors.textSecondary
                      : AppColors.textOnPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
