import 'package:flutter/material.dart';

import '../../services/admin_repository.dart';
import '../../services/error_reporter.dart';
import '../../theme/app_palette.dart';
import '../../utils/labels.dart' show timeAgo;
import 'admin_theme.dart';

/// 클라이언트 오류 — 앱·웹에서 올라온 `reported` 등급 오류(30일 보존).
///
/// 외부 리포팅 서비스를 쓰지 않으므로 **그룹핑이 없다.** 대신 상단의 발생 지점별
/// 집계로 "어디가 자주 터지나" 를 먼저 보고, 칩을 눌러 그 지점만 걸러 본다.
class AdminClientErrorsScreen extends StatefulWidget {
  const AdminClientErrorsScreen({super.key});

  @override
  State<AdminClientErrorsScreen> createState() =>
      _AdminClientErrorsScreenState();
}

class _AdminClientErrorsScreenState extends State<AdminClientErrorsScreen> {
  List<AdminClientErrorStat> _stats = const [];
  List<AdminClientError> _items = const [];
  String? _filter; // null = 전체
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
      final repo = AdminRepository.instance;
      final stats = await repo.clientErrorSummary();
      final items = await repo.listClientErrors(where: _filter);
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _items = items;
        _loading = false;
      });
    } catch (e, st) {
      ErrorReporter.userFacing(e, where: 'admin.clientErrors', stackTrace: st);
      if (!mounted) return;
      setState(() {
        _error = '오류 목록을 불러오지 못했어요';
        _loading = false;
      });
    }
  }

  Future<void> _applyFilter(String? where) async {
    setState(() => _filter = where);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: adminAppBar(context, '클라이언트 오류'),
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
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _summary()),
          if (_items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  _filter == null ? '올라온 오류가 없어요' : '이 지점에서 올라온 오류가 없어요',
                  style: TextStyle(
                    fontSize: 14,
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
            )
          else
            SliverList.separated(
              itemCount: _items.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: context.colors.border),
              itemBuilder: (_, i) => _tile(_items[i]),
            ),
        ],
      ),
    );
  }

  /// 최근 24시간 발생 지점 상위 — 칩을 누르면 그 지점만 본다.
  Widget _summary() {
    if (_stats.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '최근 24시간 · 발생 지점 ${_stats.length}곳',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _chip(
                label: '전체',
                selected: _filter == null,
                onTap: () => _applyFilter(null),
              ),
              for (final s in _stats)
                _chip(
                  label: '${s.where}  ${s.hits}',
                  selected: _filter == s.where,
                  onTap: () => _applyFilter(s.where),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? context.colors.primary : context.colors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.colors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? Colors.white : context.colors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _tile(AdminClientError e) {
    return ListTile(
      title: Text(
        e.where,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Text(
            e.message,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: context.colors.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            [
              timeAgo(e.createdAt),
              if (e.platform != null) e.platform!,
              if (e.release != null) e.release!,
              e.nickname,
            ].join(' · '),
            style: TextStyle(fontSize: 11, color: context.colors.textSecondary),
          ),
        ],
      ),
      trailing: e.stack == null
          ? null
          : Icon(Icons.chevron_right, color: context.colors.textSecondary),
      onTap: e.stack == null ? null : () => _showStack(e),
    );
  }

  void _showStack(AdminClientError e) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surface,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (_, controller) => Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            controller: controller,
            children: [
              Text(
                e.where,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                e.message,
                style: TextStyle(
                  fontSize: 13,
                  color: context.colors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(
                e.stack ?? '',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  fontFamily: 'monospace',
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
