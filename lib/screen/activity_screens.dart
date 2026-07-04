import 'package:flutter/material.dart';
import '../motion/motion.dart';
import '../theme/app_colors.dart';
import '../data/mock_data.dart' show categoryLabel, timeAgo;
import '../data/review_categories.dart';
import '../services/activity_repository.dart';
import '../services/session.dart';
import 'review_write_screen.dart';

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
      backgroundColor: Colors.white,
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

/// 약속 — 완료 처리 + 완료된 약속에 평가하기.
class MyAppointmentsScreen extends StatefulWidget {
  const MyAppointmentsScreen({super.key});

  @override
  State<MyAppointmentsScreen> createState() => _MyAppointmentsScreenState();
}

class _MyAppointmentsScreenState extends State<MyAppointmentsScreen> {
  final _repo = ActivityRepository.instance;
  List<Map<String, dynamic>> _items = [];
  Set<String> _reviewed = {};
  Map<String, String> _nameById = {};
  bool _loading = true;
  String? _error;
  String? _busy; // 처리 중인 appointment id

  String? get _uid => SessionManager.instance.user?.id;

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
      final items = await _repo.fetchMyAppointments();
      final reviewed = await _repo.fetchMyReviewedAppointmentIds();
      // 상대방 닉네임 조회
      final otherIds = <String>{
        for (final a in items)
          if (a['post_owner_id'] == _uid)
            a['applicant_id'] as String
          else
            a['post_owner_id'] as String
      };
      final names = await _repo.fetchNicknames(otherIds.toList());
      if (!mounted) return;
      setState(() {
        _items = items;
        _reviewed = reviewed;
        _nameById = names;
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

  String _otherId(Map<String, dynamic> a) => a['post_owner_id'] == _uid
      ? a['applicant_id'] as String
      : a['post_owner_id'] as String;

  Future<void> _complete(Map<String, dynamic> a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('약속을 완료 처리할까요?'),
        content: const Text('완료하면 서로 평가를 남길 수 있어요. 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primaryDark),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('완료'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = a['id'] as String);
    try {
      await _repo.completeAppointment(a['id'] as String);
      await _load();
    } catch (_) {
      _toast('완료 처리하지 못했어요');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _review(Map<String, dynamic> a) async {
    final otherId = _otherId(a);
    final done = await Navigator.push<bool>(
      context,
      AppPageRoute(
        builder: (_) => ReviewWriteScreen(
          appointmentId: a['id'] as String,
          revieweeId: otherId,
          revieweeNickname: _nameById[otherId] ?? '상대방',
        ),
      ),
    );
    if (done == true) _load();
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
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('약속')),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, style: const TextStyle(color: AppColors.textSecondary)),
          TextButton(onPressed: _load, child: const Text('다시 시도')),
        ]),
      );
    }
    if (_items.isEmpty) {
      return const Center(
        child: Text('진행 중인 약속이 없어요',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _appointmentCard(_items[i]),
      ),
    );
  }

  Widget _appointmentCard(Map<String, dynamic> a) {
    final post = a['posts'] as Map<String, dynamic>?;
    final status = (a['status'] ?? 'scheduled') as String;
    final at = _date(a['scheduled_at']);
    final otherName = _nameById[_otherId(a)] ?? '상대방';
    final reviewed = _reviewed.contains(a['id']);
    final busy = _busy == a['id'];

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
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.person_outline,
                  size: 15, color: AppColors.textTertiary),
              const SizedBox(width: 6),
              Text(otherName,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
              if (at != null) ...[
                const SizedBox(width: 12),
                const Icon(Icons.event_outlined,
                    size: 15, color: AppColors.primaryDark),
                const SizedBox(width: 6),
                Text('${at.year}.${at.month}.${at.day} ${at.hour}시',
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
              ],
            ],
          ),
          if (status == 'scheduled' || status == 'completed') ...[
            const SizedBox(height: 14),
            _actionRow(a, status, reviewed, busy),
          ],
        ],
      ),
    );
  }

  Widget _actionRow(
      Map<String, dynamic> a, String status, bool reviewed, bool busy) {
    if (status == 'scheduled') {
      return Align(
        alignment: Alignment.centerRight,
        child: FilledButton.icon(
          onPressed: busy ? null : () => _complete(a),
          icon: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check_circle_outline, size: 18),
          label: const Text('약속 완료'),
          style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryDark,
              minimumSize: const Size(0, 40)),
        ),
      );
    }
    // completed
    if (reviewed) {
      return Row(
        children: const [
          Icon(Icons.verified_outlined, size: 18, color: AppColors.success),
          SizedBox(width: 6),
          Text('평가 완료',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.success)),
        ],
      );
    }
    return Align(
      alignment: Alignment.centerRight,
      child: OutlinedButton.icon(
        onPressed: () => _review(a),
        icon: const Icon(Icons.star_outline, size: 18),
        label: const Text('평가하기'),
        style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primaryDark,
            side: const BorderSide(color: AppColors.primaryDark),
            minimumSize: const Size(0, 40)),
      ),
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

/// 받은 평가 — 8개 카테고리별로 얼마나 받았는지 수치화.
class MyReviewsScreen extends StatefulWidget {
  const MyReviewsScreen({super.key});

  @override
  State<MyReviewsScreen> createState() => _MyReviewsScreenState();
}

class _MyReviewsScreenState extends State<MyReviewsScreen> {
  Map<String, int> _counts = {};
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
      final counts = await ActivityRepository.instance.fetchReviewCounts();
      if (!mounted) return;
      setState(() {
        _counts = counts;
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

  int get _total =>
      _counts.values.fold(0, (sum, v) => sum + v);
  int get _maxCount =>
      _counts.values.fold(1, (m, v) => v > m ? v : m);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('받은 평가')),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, style: const TextStyle(color: AppColors.textSecondary)),
          TextButton(onPressed: _load, child: const Text('다시 시도')),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('총 $_total개의 평가를 받았어요',
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 24),
          _section('긍정 평가', ReviewCategories.positive, AppColors.success),
          const SizedBox(height: 20),
          _section('부정 평가', ReviewCategories.negative, AppColors.danger),
        ],
      ),
    );
  }

  Widget _section(String title, List<String> cats, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary)),
        const SizedBox(height: 12),
        ...cats.map((c) => _bar(c, _counts[c] ?? 0, color)),
      ],
    );
  }

  Widget _bar(String label, int count, Color color) {
    final ratio = count / _maxCount;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
              ),
              Text('$count',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: count > 0 ? color : AppColors.textTertiary)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: AppColors.surfaceMuted,
              valueColor: AlwaysStoppedAnimation(
                  count > 0 ? color : AppColors.surfaceMuted),
            ),
          ),
        ],
      ),
    );
  }
}
