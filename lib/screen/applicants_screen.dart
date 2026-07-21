import 'package:flutter/material.dart';

import '../data/mock_data.dart' show timeAgo;
import '../models/community.dart';
import '../services/activity_repository.dart';
import '../services/chat_launcher.dart';
import '../theme/app_palette.dart';

/// 지원자 목록 — 글 작성자 또는 공동보호자가 지원자를 확인하고 1명을 수락(선택)한다.
/// 수락 시 DB 트리거가 약속을 만들고 나머지 지원자는 자동 거절된다.
/// 공동보호자가 수락하면 약속은 작성자가 아닌 그 공동보호자↔지원자로 맺어진다.
class ApplicantsScreen extends StatefulWidget {
  final Post post;
  const ApplicantsScreen({super.key, required this.post});

  @override
  State<ApplicantsScreen> createState() => _ApplicantsScreenState();
}

class _ApplicantsScreenState extends State<ApplicantsScreen> {
  final _repo = ActivityRepository.instance;
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
  String? _accepting; // 수락 처리 중인 application id

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
      final items = await _repo.fetchApplicants(widget.post.id);
      if (!mounted) return;
      setState(() {
        _items = items;
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

  /// 아직 아무도 수락되지 않았는지 (수락 버튼 노출 여부).
  bool get _stillOpen =>
      !_items.any((a) => a['status'] == 'accepted') &&
      widget.post.progressStatus == 'recruiting';

  Future<void> _accept(Map<String, dynamic> app) async {
    final nickname = app['nickname'] as String;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('이 지원자를 선택할까요?'),
        content: Text('$nickname 님을 수락하면 약속이 생성되고,\n나머지 지원자는 자동으로 거절됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.primaryDark,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('수락'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _accepting = app['id'] as String);
    try {
      await _repo.acceptApplication(app['id'] as String);
      if (!mounted) return;
      _toast('$nickname 님을 수락했어요');
      await _load();
    } catch (_) {
      _toast('수락하지 못했어요. 잠시 후 다시 시도해주세요');
    } finally {
      if (mounted) setState(() => _accepting = null);
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
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('지원자 목록')),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_outline,
              size: 48,
              color: context.colors.textTertiary,
            ),
            SizedBox(height: 12),
            Text(
              '아직 지원자가 없어요',
              style: TextStyle(
                fontSize: 14,
                color: context.colors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: _items.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) {
          if (i == 0) return _header();
          return _ApplicantCard(
            app: _items[i - 1],
            canAccept: _stillOpen && _items[i - 1]['status'] == 'pending',
            accepting: _accepting == _items[i - 1]['id'],
            onAccept: () => _accept(_items[i - 1]),
            onChat: () => openDirectChat(
              context,
              _items[i - 1]['applicant_id'] as String,
            ),
          );
        },
      ),
    );
  }

  Widget _header() {
    final count = _items.length;
    final matched = !_stillOpen;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text(
            '지원자 $count명',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          if (matched)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: context.colors.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                '매칭 완료',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: context.colors.success,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ApplicantCard extends StatelessWidget {
  final Map<String, dynamic> app;
  final bool canAccept;
  final bool accepting;
  final VoidCallback onAccept;
  final VoidCallback onChat;
  const _ApplicantCard({
    required this.app,
    required this.canAccept,
    required this.accepting,
    required this.onAccept,
    required this.onChat,
  });

  @override
  Widget build(BuildContext context) {
    final nickname = app['nickname'] as String;
    final message = (app['message'] ?? '') as String;
    final status = (app['status'] ?? 'pending') as String;
    final initial = nickname.isEmpty ? '?' : nickname.characters.first;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: status == 'accepted'
              ? context.colors.success
              : context.colors.border,
          width: status == 'accepted' ? 1.2 : 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: context.colors.primarySoft,
                child: Text(
                  initial,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: context.colors.primaryDark,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  nickname,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
              _statusBadge(context, status),
            ],
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              message,
              style: TextStyle(
                fontSize: 14,
                color: context.colors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                timeAgo(DateTime.parse(app['created_at'] as String).toLocal()),
                style: TextStyle(
                  fontSize: 11,
                  color: context.colors.textTertiary,
                ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: onChat,
                icon: const Icon(Icons.chat_bubble_outline, size: 16),
                label: const Text('채팅'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.colors.primaryDark,
                  side: BorderSide(color: context.colors.border),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  minimumSize: const Size(0, 38),
                ),
              ),
              if (canAccept) ...[
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: accepting ? null : onAccept,
                  style: FilledButton.styleFrom(
                    backgroundColor: context.colors.primaryDark,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    minimumSize: const Size(0, 38),
                  ),
                  child: accepting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('수락'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(BuildContext context, String status) {
    final (label, color) = switch (status) {
      'accepted' => ('수락됨', context.colors.success),
      'completed' => ('완료', context.colors.success),
      'rejected' => ('거절됨', context.colors.danger),
      'cancelled' => ('취소됨', context.colors.danger),
      _ => ('대기 중', context.colors.warning),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
