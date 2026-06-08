import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../data/mock_data.dart' show categoryLabel, timeAgo;
import '../services/activity_repository.dart';

DateTime? _date(dynamic v) =>
    v == null ? null : DateTime.parse(v as String).toLocal();

/// 공용 목록 스캐폴드 — 비동기 로드 + 빈/에러 상태.
class _ListScaffold extends StatefulWidget {
  final String title;
  final String emptyMessage;
  final Future<List<Map<String, dynamic>>> Function() load;
  final Widget Function(Map<String, dynamic>) itemBuilder;
  const _ListScaffold({
    required this.title,
    required this.emptyMessage,
    required this.load,
    required this.itemBuilder,
  });

  @override
  State<_ListScaffold> createState() => _ListScaffoldState();
}

class _ListScaffoldState extends State<_ListScaffold> {
  List<Map<String, dynamic>> _items = [];
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
      final items = await widget.load();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _center(_error!, retry: true);
    }
    if (_items.isEmpty) return _center(widget.emptyMessage);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) => widget.itemBuilder(_items[i]),
      ),
    );
  }

  Widget _center(String msg, {bool retry = false}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox_outlined,
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

Widget _card({required Widget child}) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: child,
    );

Widget _statusBadge(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );

/// 내 지원 내역
class MyApplicationsScreen extends StatelessWidget {
  const MyApplicationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _ListScaffold(
      title: '내 지원 내역',
      emptyMessage: '지원한 게시글이 없어요',
      load: ActivityRepository.instance.fetchMyApplications,
      itemBuilder: (a) {
        final post = a['posts'] as Map<String, dynamic>?;
        final status = (a['status'] ?? 'pending') as String;
        return _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (post != null)
                    _statusBadge(categoryLabel(post['category'] as String),
                        AppColors.primary),
                  const Spacer(),
                  _statusBadge(_appStatus(status), _appStatusColor(status)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                post?['title'] as String? ?? '(삭제된 게시글)',
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary),
              ),
              if (a['message'] != null &&
                  (a['message'] as String).isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(a['message'] as String,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
              ],
              const SizedBox(height: 8),
              Text(timeAgo(_date(a['created_at'])!),
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textTertiary)),
            ],
          ),
        );
      },
    );
  }

  String _appStatus(String s) => switch (s) {
        'pending' => '대기 중',
        'accepted' => '수락됨',
        'rejected' => '거절됨',
        'cancelled' => '취소됨',
        'completed' => '완료',
        _ => s,
      };
  Color _appStatusColor(String s) => switch (s) {
        'accepted' || 'completed' => AppColors.success,
        'rejected' || 'cancelled' => AppColors.danger,
        _ => AppColors.warning,
      };
}

/// 약속
class MyAppointmentsScreen extends StatelessWidget {
  const MyAppointmentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _ListScaffold(
      title: '약속',
      emptyMessage: '진행 중인 약속이 없어요',
      load: ActivityRepository.instance.fetchMyAppointments,
      itemBuilder: (a) {
        final post = a['posts'] as Map<String, dynamic>?;
        final status = (a['status'] ?? 'scheduled') as String;
        final at = _date(a['scheduled_at']);
        return _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      post?['title'] as String? ?? '(삭제된 게시글)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _statusBadge(_apptStatus(status), _apptColor(status)),
                ],
              ),
              if (at != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.event_outlined,
                        size: 15, color: AppColors.primaryDark),
                    const SizedBox(width: 6),
                    Text(
                      '${at.year}.${at.month}.${at.day} ${at.hour}시',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _apptStatus(String s) => switch (s) {
        'scheduled' => '예정',
        'completed' => '완료',
        'cancelled' => '취소',
        _ => s,
      };
  Color _apptColor(String s) => switch (s) {
        'completed' => AppColors.success,
        'cancelled' => AppColors.danger,
        _ => AppColors.info,
      };
}

/// 받은 평가
class MyReviewsScreen extends StatelessWidget {
  const MyReviewsScreen({super.key});

  static const _labels = <String, String>{
    'kind': '친절해요',
    'punctual': '시간 약속을 잘 지켜요',
    'communicative': '소통이 원활해요',
    'responsible': '책임감 있어요',
  };

  @override
  Widget build(BuildContext context) {
    return _ListScaffold(
      title: '받은 평가',
      emptyMessage: '아직 받은 평가가 없어요',
      load: ActivityRepository.instance.fetchMyReviews,
      itemBuilder: (r) {
        final cats = (r['categories'] as List?)?.cast<String>() ?? const [];
        return _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: cats
                    .map((c) => _statusBadge(_labels[c] ?? c, AppColors.primary))
                    .toList(),
              ),
              const SizedBox(height: 8),
              Text(timeAgo(_date(r['created_at'])!),
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textTertiary)),
            ],
          ),
        );
      },
    );
  }
}
