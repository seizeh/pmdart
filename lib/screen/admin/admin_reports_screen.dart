import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/admin.dart';
import '../../motion/motion.dart';
import '../../services/admin/admin_moderation_repository.dart';
import '../../theme/app_palette.dart';
import '../../utils/labels.dart' show timeAgo;
import 'admin_report_detail_screen.dart';
import 'admin_theme.dart';

/// 신고 처리 — 미처리/전체 신고 조회 + 상태 변경(검토중/처리완료/반려).
class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  String _filter = 'open'; // open / all
  List<AdminReport> _items = [];
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
      final items = await AdminModerationRepository.instance.listReports(
        status: _filter == 'open' ? 'open' : null,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '신고를 불러오지 못했어요';
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

  Future<void> _setStatus(AdminReport r, String status) async {
    setState(() => _busy = r.id);
    try {
      await AdminModerationRepository.instance.setReportStatus(r.id, status);
      _toast('처리했어요');
      await _load();
    } catch (_) {
      _toast('상태를 변경하지 못했어요');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: adminAppBar(context, '신고 처리'),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  _chip('미처리', 'open'),
                  const SizedBox(width: 8),
                  _chip('전체', 'all'),
                ],
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String value) {
    final sel = _filter == value;
    return GestureDetector(
      onTap: () {
        if (_filter == value) return;
        setState(() => _filter = value);
        _load();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: sel ? context.colors.adminAccent : context.colors.surface,
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: sel ? context.colors.adminAccent : context.colors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: sel ? Colors.white : context.colors.textSecondary,
          ),
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
            TextButton(onPressed: _load, child: const Text('다시 시도')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(
          '신고가 없어요',
          style: TextStyle(fontSize: 14, color: context.colors.textSecondary),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) => InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            await Navigator.push(
              context,
              AppPageRoute(
                builder: (_) => AdminReportDetailScreen(report: _items[i]),
              ),
            );
            if (mounted) unawaited(_load());
          },
          child: _ReportCard(
            report: _items[i],
            busy: _busy == _items[i].id,
            onSetStatus: (s) => _setStatus(_items[i], s),
          ),
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final AdminReport report;
  final bool busy;
  final ValueChanged<String> onSetStatus;
  const _ReportCard({
    required this.report,
    required this.busy,
    required this.onSetStatus,
  });

  static String _targetLabel(String t) => switch (t) {
    'post' => '게시글',
    'comment' => '댓글',
    'chat_message' => '채팅',
    'user' => '회원',
    _ => t,
  };

  @override
  Widget build(BuildContext context) {
    final r = report;
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: context.colors.surfaceMuted,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_targetLabel(r.targetType)} 신고',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
              const Spacer(),
              _statusBadge(context, r.status),
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
          const SizedBox(height: 10),
          Text(
            '신고자 ${r.reporterNickname}  ·  ${timeAgo(r.createdAt)}',
            style: TextStyle(fontSize: 11, color: context.colors.textTertiary),
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: context.colors.border),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Wrap(
                    spacing: 4,
                    children: [
                      if (r.status != 'reviewing')
                        TextButton(
                          onPressed: () => onSetStatus('reviewing'),
                          child: const Text('검토중'),
                        ),
                      if (r.status != 'dismissed')
                        TextButton(
                          onPressed: () => onSetStatus('dismissed'),
                          child: const Text('반려'),
                        ),
                      if (r.status != 'resolved')
                        TextButton(
                          onPressed: () => onSetStatus('resolved'),
                          child: const Text('처리완료'),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge(BuildContext context, String status) {
    final (label, color) = switch (status) {
      'submitted' => ('접수', context.colors.warning),
      'reviewing' => ('검토중', context.colors.primaryDark),
      'resolved' => ('처리완료', context.colors.success),
      'dismissed' => ('반려', context.colors.textSecondary),
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
