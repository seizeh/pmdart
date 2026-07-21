import 'package:flutter/material.dart';

import '../../data/mock_data.dart' show timeAgo;
import '../../services/admin_repository.dart';
import '../../theme/app_palette.dart';
import 'admin_chat_history_screen.dart';
import 'admin_theme.dart';

/// 신고 상세 — 신고된 실제 대상(게시글/댓글/회원/채팅)을 보고 바로 조치.
class AdminReportDetailScreen extends StatefulWidget {
  final AdminReport report;
  const AdminReportDetailScreen({super.key, required this.report});

  @override
  State<AdminReportDetailScreen> createState() =>
      _AdminReportDetailScreenState();
}

class _AdminReportDetailScreenState extends State<AdminReportDetailScreen> {
  final _repo = AdminRepository.instance;
  ReportTarget? _target;
  bool _loading = true;
  String? _error;
  bool _busy = false;
  late String _status;

  @override
  void initState() {
    super.initState();
    _status = widget.report.status;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final t = await _repo.getReportTarget(widget.report.id);
      if (!mounted) return;
      setState(() {
        _target = t;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '신고 대상을 불러오지 못했어요';
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

  Future<void> _act(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      _toast(done);
      await _load();
    } catch (_) {
      _toast('처리하지 못했어요');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setReportStatus(String s) async {
    await _act(() => _repo.setReportStatus(widget.report.id, s), '신고를 처리했어요');
    if (mounted) setState(() => _status = s);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: adminAppBar(context, '신고 상세'),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _reportInfo(),
                  const SizedBox(height: 16),
                  _targetSection(),
                  const SizedBox(height: 20),
                  _reportStatusActions(),
                ],
              ),
      ),
    );
  }

  Widget _reportInfo() {
    final r = widget.report;
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
                '${_targetTypeLabel(r.targetType)} 신고',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textPrimary,
                ),
              ),
              const Spacer(),
              _statusBadge(_status),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: r.categories
                .map(
                  (c) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: context.colors.danger.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      c,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: context.colors.danger,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          if (r.extraDescription != null && r.extraDescription!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              r.extraDescription!,
              style: TextStyle(
                fontSize: 13,
                color: context.colors.textPrimary,
                height: 1.4,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            '신고자 ${r.reporterNickname}  ·  ${timeAgo(r.createdAt)}',
            style: TextStyle(fontSize: 11, color: context.colors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _targetSection() {
    if (_error != null) {
      return _box(
        Center(
          child: Column(
            children: [
              Text(
                _error!,
                style: TextStyle(color: context.colors.textSecondary),
              ),
              TextButton(onPressed: _load, child: const Text('다시 시도')),
            ],
          ),
        ),
      );
    }
    final t = _target;
    if (t == null) return const SizedBox.shrink();
    if (!t.exists) {
      return _box(
        Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            '대상이 삭제되었거나 찾을 수 없어요',
            style: TextStyle(color: context.colors.textSecondary),
          ),
        ),
      );
    }
    return switch (t.kind) {
      'post' => _postTarget(t.data),
      'comment' => _commentTarget(t.data),
      'user' => _userTarget(t.data),
      'chat_message' => _chatTarget(t.data),
      _ => _box(Text('알 수 없는 대상 (${t.kind})')),
    };
  }

  Widget _sectionTitle(String s) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      s,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: context.colors.textSecondary,
      ),
    ),
  );

  Widget _box(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: context.colors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: context.colors.border, width: 0.5),
    ),
    child: child,
  );

  Widget _postTarget(Map<String, dynamic> d) {
    final vis = (d['visibility_status'] ?? 'visible') as String;
    final img = d['image_url'] as String?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('신고된 게시글'),
        _box(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      (d['title'] ?? '') as String,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: context.colors.textPrimary,
                      ),
                    ),
                  ),
                  _visBadge(vis),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                (d['content'] ?? '') as String,
                style: TextStyle(
                  fontSize: 14,
                  color: context.colors.textPrimary,
                  height: 1.5,
                ),
              ),
              if (img != null) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    img,
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox(height: 0),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                '작성자 ${d['author_nickname'] ?? ''}  ·  ${_fmt(d['created_at'])}',
                style: TextStyle(
                  fontSize: 11,
                  color: context.colors.textTertiary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _actionRow([
          if (vis != 'visible')
            _btn(
              '공개',
              () => _act(
                () => _repo.setPostVisibility(d['id'] as String, 'visible'),
                '공개로 전환했어요',
              ),
            ),
          if (vis != 'hidden_by_admin')
            _btn(
              '숨김',
              () => _act(
                () => _repo.setPostVisibility(
                  d['id'] as String,
                  'hidden_by_admin',
                ),
                '숨김 처리했어요',
              ),
            ),
          _btn(
            '삭제',
            danger: true,
            () => _act(
              () => _repo.setPostVisibility(
                d['id'] as String,
                'deleted_by_admin',
              ),
              '삭제 처리했어요',
            ),
          ),
        ]),
      ],
    );
  }

  Widget _commentTarget(Map<String, dynamic> d) {
    final deleted = d['is_deleted'] == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('신고된 댓글'),
        _box(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (d['post_title'] != null)
                Text(
                  '게시글: ${d['post_title']}',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.colors.textTertiary,
                  ),
                ),
              const SizedBox(height: 6),
              Text(
                (d['content'] ?? '') as String,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: deleted
                      ? context.colors.textTertiary
                      : context.colors.textPrimary,
                  decoration: deleted ? TextDecoration.lineThrough : null,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '작성자 ${d['author_nickname'] ?? ''}  ·  ${_fmt(d['created_at'])}',
                style: TextStyle(
                  fontSize: 11,
                  color: context.colors.textTertiary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _actionRow([
          _btn(
            deleted ? '복원' : '숨김',
            danger: !deleted,
            () => _act(
              () => _repo.setCommentDeleted(d['id'] as String, !deleted),
              deleted ? '복원했어요' : '숨김 처리했어요',
            ),
          ),
        ]),
      ],
    );
  }

  Widget _userTarget(Map<String, dynamic> d) {
    final status = (d['status'] ?? 'active') as String;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('신고된 회원'),
        _box(
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: context.colors.primarySoft,
                child: Text(
                  ((d['nickname'] ?? '?') as String).characters.first,
                  style: TextStyle(
                    fontSize: 16,
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
                    Text(
                      (d['nickname'] ?? '') as String,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: context.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '@${d['username'] ?? ''}  ·  ${_fmt(d['created_at'])}',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              _userStatusBadge(status),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _actionRow([
          if (status != 'suspended')
            _btn(
              '정지',
              danger: true,
              () => _act(
                () => _repo.setUserStatus(d['id'] as String, 'suspended'),
                '정지했어요',
              ),
            ),
          if (status != 'inactive')
            _btn(
              '휴면',
              () => _act(
                () => _repo.setUserStatus(d['id'] as String, 'inactive'),
                '휴면 처리했어요',
              ),
            ),
          if (status != 'active')
            _btn(
              '활성',
              () => _act(
                () => _repo.setUserStatus(d['id'] as String, 'active'),
                '활성으로 전환했어요',
              ),
            ),
        ]),
      ],
    );
  }

  Widget _chatTarget(Map<String, dynamic> d) {
    final deleted = d['is_deleted'] == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('신고된 채팅 메시지'),
        _box(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (d['content'] ?? '') as String,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: deleted
                      ? context.colors.textTertiary
                      : context.colors.textPrimary,
                  decoration: deleted ? TextDecoration.lineThrough : null,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '보낸 사람 ${d['sender_nickname'] ?? ''}  ·  ${_fmt(d['created_at'])}',
                style: TextStyle(
                  fontSize: 11,
                  color: context.colors.textTertiary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _actionRow([
          // 신고 메시지 앞뒤 맥락 확인 — 삭제된 메시지 포함 전체 대화 내역.
          if (d['room_id'] != null)
            _btn(
              '대화 내역',
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AdminChatHistoryScreen(
                    roomId: d['room_id'] as String,
                    highlightMessageId: d['id'] as String?,
                  ),
                ),
              ),
            ),
          _btn(
            deleted ? '복원' : '숨김',
            danger: !deleted,
            () => _act(
              () => _repo.setChatMessageDeleted(d['id'] as String, !deleted),
              deleted ? '복원했어요' : '숨김 처리했어요',
            ),
          ),
        ]),
      ],
    );
  }

  Widget _reportStatusActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('신고 처리 상태'),
        _actionRow([
          if (_status != 'reviewing')
            _btn('검토중', () => _setReportStatus('reviewing')),
          if (_status != 'dismissed')
            _btn('반려', () => _setReportStatus('dismissed')),
          if (_status != 'resolved')
            _btn('처리완료', primary: true, () => _setReportStatus('resolved')),
        ]),
      ],
    );
  }

  Widget _actionRow(List<Widget> buttons) {
    if (_busy) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return Wrap(spacing: 8, runSpacing: 8, children: buttons);
  }

  Widget _btn(
    String label,
    VoidCallback onTap, {
    bool danger = false,
    bool primary = false,
  }) {
    if (primary) {
      return FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: context.colors.adminAccent,
          visualDensity: VisualDensity.compact,
        ),
        child: Text(label),
      );
    }
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: danger
            ? context.colors.danger
            : context.colors.adminAccent,
        side: BorderSide(
          color: danger
              ? context.colors.danger.withValues(alpha: 0.5)
              : context.colors.border,
        ),
        visualDensity: VisualDensity.compact,
      ),
      child: Text(label),
    );
  }

  static String _targetTypeLabel(String t) => switch (t) {
    'post' => '게시글',
    'comment' => '댓글',
    'chat_message' => '채팅',
    'user' => '회원',
    _ => t,
  };

  String _fmt(dynamic iso) {
    if (iso == null) return '';
    try {
      return timeAgo(DateTime.parse(iso as String).toLocal());
    } catch (_) {
      return '';
    }
  }

  Widget _statusBadge(String status) {
    final (label, color) = switch (status) {
      'submitted' => ('접수', context.colors.warning),
      'reviewing' => ('검토중', context.colors.adminAccent),
      'resolved' => ('처리완료', context.colors.success),
      'dismissed' => ('반려', context.colors.textSecondary),
      _ => (status, context.colors.textSecondary),
    };
    return _tag(label, color);
  }

  Widget _visBadge(String status) {
    final (label, color) = switch (status) {
      'visible' => ('공개', context.colors.success),
      'hidden_by_admin' => ('숨김', context.colors.danger),
      'hidden_by_user' => ('숨김(작성자)', context.colors.textSecondary),
      'deleted_by_admin' => ('삭제', context.colors.danger),
      'deleted_by_user' => ('삭제(작성자)', context.colors.textSecondary),
      _ => (status, context.colors.textSecondary),
    };
    return _tag(label, color);
  }

  Widget _userStatusBadge(String status) {
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
