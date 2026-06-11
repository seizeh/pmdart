import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../data/mock_data.dart' show timeAgo;
import '../../services/admin_repository.dart';
import 'admin_theme.dart';

/// 감사 로그 — 관리자 조치 이력(정지·숨김·삭제·신고처리 등).
class AdminLogsScreen extends StatefulWidget {
  const AdminLogsScreen({super.key});

  @override
  State<AdminLogsScreen> createState() => _AdminLogsScreenState();
}

class _AdminLogsScreenState extends State<AdminLogsScreen> {
  List<AdminLog> _items = [];
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
      final items = await AdminRepository.instance.listLogs();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '로그를 불러오지 못했어요';
        _loading = false;
      });
    }
  }

  static String _actionLabel(String t) => switch (t) {
        'set_user_status' => '회원 상태 변경',
        'set_report_status' => '신고 상태 변경',
        'set_post_visibility' => '게시글 가시성 변경',
        'hide_post' => '게시글 숨김',
        'delete_post' => '게시글 삭제',
        'set_comment_deleted' => '댓글 처리',
        'delete_comment' => '댓글 숨김',
        'set_chat_message_deleted' => '채팅 메시지 처리',
        _ => t,
      };

  static String _targetLabel(String? t) => switch (t) {
        'post' => '게시글',
        'comment' => '댓글',
        'user' => '회원',
        'chat_message' => '채팅',
        'report' => '신고',
        _ => t ?? '',
      };

  String _detailText(AdminLog l) {
    final d = l.detail;
    if (d == null || d.isEmpty) return '';
    if (d['status'] != null) return '→ ${d['status']}';
    if (d['visibility'] != null) return '→ ${d['visibility']}';
    if (d['deleted'] != null) return d['deleted'] == true ? '숨김' : '복원';
    if (d['after'] is Map && (d['after'] as Map)['visibility_status'] != null) {
      return '→ ${(d['after'] as Map)['visibility_status']}';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: adminAppBar('감사 로그'),
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
            Text(_error!, style: const TextStyle(color: AppColors.textSecondary)),
            TextButton(onPressed: _load, child: const Text('다시 시도')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(
        child: Text('기록된 조치가 없어요',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _items.length,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, color: AppColors.border),
        itemBuilder: (_, i) {
          final l = _items[i];
          final detail = _detailText(l);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.adminAccentSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.shield_outlined,
                      size: 18, color: AppColors.adminAccent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_actionLabel(l.actionType)}'
                              '${detail.isNotEmpty ? '  $detail' : ''}',
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary),
                            ),
                          ),
                          Text(timeAgo(l.createdAt),
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.textTertiary)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${l.adminNickname}'
                        '${l.targetType != null ? '  ·  ${_targetLabel(l.targetType)}' : ''}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
