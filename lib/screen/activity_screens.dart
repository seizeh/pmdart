import 'dart:async';
import 'package:flutter/material.dart';

import '../data/mock_data.dart' show categoryLabel, timeAgo;
import '../data/review_categories.dart';
import '../motion/motion.dart';
import '../services/activity_repository.dart';
import '../services/session.dart';
import '../theme/app_palette.dart';
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
      backgroundColor: context.colors.background,
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
          Icon(
            Icons.inbox_outlined,
            size: 48,
            color: context.colors.textTertiary,
          ),
          const SizedBox(height: 12),
          Text(
            msg,
            style: TextStyle(fontSize: 14, color: context.colors.textSecondary),
          ),
          if (retry) ...[
            const SizedBox(height: 12),
            TextButton(onPressed: _load, child: const Text('다시 시도')),
          ],
        ],
      ),
    );
  }
}

Widget _card(BuildContext context, {required Widget child}) => Container(
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: context.colors.surface,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: context.colors.border, width: 0.5),
  ),
  child: child,
);

Widget _statusBadge(String label, Color color) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
  decoration: BoxDecoration(
    color: color.withValues(alpha: 0.12),
    borderRadius: BorderRadius.circular(100),
  ),
  child: Text(
    label,
    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
  ),
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
          context,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (post != null)
                    _statusBadge(
                      categoryLabel(post['category'] as String),
                      context.colors.primary,
                    ),
                  const Spacer(),
                  _statusBadge(
                    _appStatus(status),
                    _appStatusColor(context, status),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                post?['title'] as String? ?? '(삭제된 게시글)',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textPrimary,
                ),
              ),
              if (a['message'] != null &&
                  (a['message'] as String).isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  a['message'] as String,
                  style: TextStyle(
                    fontSize: 13,
                    color: context.colors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                timeAgo(_date(a['created_at'])!),
                style: TextStyle(
                  fontSize: 11,
                  color: context.colors.textTertiary,
                ),
              ),
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
  Color _appStatusColor(BuildContext context, String s) => switch (s) {
    'accepted' || 'completed' => context.colors.success,
    'rejected' || 'cancelled' => context.colors.danger,
    _ => context.colors.warning,
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

  // 캘린더 — 표시 중인 달과 선택 날짜(null=전체 목록).
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selectedDay;

  String? get _uid => SessionManager.instance.user?.id;

  DateTime? _apptDay(Map<String, dynamic> a) {
    final at = _date(a['scheduled_at']);
    return at == null ? null : DateTime(at.year, at.month, at.day);
  }

  /// 날짜별 약속 수 — 캘린더 점 표시용.
  Map<DateTime, int> get _countByDay {
    final m = <DateTime, int>{};
    for (final a in _items) {
      final d = _apptDay(a);
      if (d != null) m[d] = (m[d] ?? 0) + 1;
    }
    return m;
  }

  /// 목록 — 날짜를 선택했으면 그 날의 약속만.
  List<Map<String, dynamic>> get _visibleItems => _selectedDay == null
      ? _items
      : _items.where((a) => _apptDay(a) == _selectedDay).toList();

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
            a['post_owner_id'] as String,
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
        content: const Text('완료하면 서로 후기를 남길 수 있어요. 되돌릴 수 없습니다.'),
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
    if (done == true) unawaited(_load());
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
      appBar: AppBar(title: const Text('약속')),
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
    // 캘린더는 항상 상단 고정 — 약속이 없어도 달력은 보인다.
    final visible = _visibleItems;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          _calendar(),
          const SizedBox(height: 16),
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  _selectedDay == null ? '진행 중인 약속이 없어요' : '이 날짜에 약속이 없어요',
                  style: TextStyle(
                    fontSize: 14,
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
            )
          else
            for (final a in visible) ...[
              _appointmentCard(a),
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }

  // ── 월간 캘린더: 약속 있는 날에 점, 탭하면 그 날만 필터 ──

  Widget _calendar() {
    final counts = _countByDay;
    final today = DateTime.now();
    final todayKey = DateTime(today.year, today.month, today.day);
    final firstWeekday = DateTime(_month.year, _month.month, 1).weekday % 7;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.colors.border, width: 0.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                color: context.colors.textSecondary,
                onPressed: () => setState(() {
                  _month = DateTime(_month.year, _month.month - 1);
                  _selectedDay = null;
                }),
              ),
              Expanded(
                child: Text(
                  '${_month.year}년 ${_month.month}월',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                color: context.colors.textSecondary,
                onPressed: () => setState(() {
                  _month = DateTime(_month.year, _month.month + 1);
                  _selectedDay = null;
                }),
              ),
            ],
          ),
          Row(
            children: [
              for (final (i, w) in const [
                '일',
                '월',
                '화',
                '수',
                '목',
                '금',
                '토',
              ].indexed)
                Expanded(
                  child: Center(
                    child: Text(
                      w,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: i == 0
                            ? context.colors.danger
                            : context.colors.textTertiary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (var week = 0; week * 7 < firstWeekday + daysInMonth; week++)
            Row(
              children: [
                for (var dow = 0; dow < 7; dow++)
                  Expanded(
                    child: _dayCell(
                      week * 7 + dow - firstWeekday + 1,
                      daysInMonth,
                      counts,
                      todayKey,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _dayCell(
    int day,
    int daysInMonth,
    Map<DateTime, int> counts,
    DateTime todayKey,
  ) {
    if (day < 1 || day > daysInMonth) return const SizedBox(height: 44);
    final date = DateTime(_month.year, _month.month, day);
    final hasAppt = counts.containsKey(date);
    final selected = _selectedDay == date;
    final isToday = date == todayKey;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      // 탭: 선택/해제 토글 — 선택하면 아래 목록이 그 날짜 약속만 보여준다.
      onTap: () => setState(() => _selectedDay = selected ? null : date),
      child: SizedBox(
        height: 44,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? context.colors.primaryDark : null,
                shape: BoxShape.circle,
                border: isToday && !selected
                    ? Border.all(color: context.colors.primaryDark, width: 1)
                    : null,
              ),
              child: Text(
                '$day',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: hasAppt ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? context.colors.textOnPrimary
                      : context.colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 2),
            // 약속 있는 날 점 표시(없으면 자리만 유지해 줄 높이 고정).
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: hasAppt
                    ? (selected
                          ? context.colors.primaryDark
                          : context.colors.primary)
                    : Colors.transparent,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
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
      context,
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
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _statusBadge(_apptStatus(status), _apptColor(status)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.person_outline,
                size: 15,
                color: context.colors.textTertiary,
              ),
              const SizedBox(width: 6),
              Text(
                otherName,
                style: TextStyle(
                  fontSize: 13,
                  color: context.colors.textSecondary,
                ),
              ),
              if (at != null) ...[
                const SizedBox(width: 12),
                Icon(
                  Icons.event_outlined,
                  size: 15,
                  color: context.colors.primaryDark,
                ),
                const SizedBox(width: 6),
                Text(
                  '${at.year}.${at.month}.${at.day} ${at.hour}시',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.colors.textSecondary,
                  ),
                ),
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
    Map<String, dynamic> a,
    String status,
    bool reviewed,
    bool busy,
  ) {
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
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check_circle_outline, size: 18),
          label: const Text('약속 완료'),
          style: FilledButton.styleFrom(
            backgroundColor: context.colors.primaryDark,
            minimumSize: const Size(0, 40),
          ),
        ),
      );
    }
    // completed
    if (reviewed) {
      return Row(
        children: [
          Icon(
            Icons.verified_outlined,
            size: 18,
            color: context.colors.success,
          ),
          SizedBox(width: 6),
          Text(
            '후기 완료',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.colors.success,
            ),
          ),
        ],
      );
    }
    return Align(
      alignment: Alignment.centerRight,
      child: OutlinedButton.icon(
        onPressed: () => _review(a),
        icon: const Icon(Icons.star_outline, size: 18),
        label: const Text('후기 남기기'),
        style: OutlinedButton.styleFrom(
          foregroundColor: context.colors.primaryDark,
          side: BorderSide(color: context.colors.primaryDark),
          minimumSize: const Size(0, 40),
        ),
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
    'completed' => context.colors.success,
    'cancelled' => context.colors.danger,
    _ => context.colors.info,
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

  int get _total => _counts.values.fold(0, (sum, v) => sum + v);
  int get _maxCount => _counts.values.fold(1, (m, v) => v > m ? v : m);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('받은 후기')),
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
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            '총 $_total개의 후기를 받았어요',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 24),
          _section('긍정 후기', ReviewCategories.positive, context.colors.success),
          const SizedBox(height: 20),
          _section('부정 후기', ReviewCategories.negative, context.colors.danger),
        ],
      ),
    );
  }

  Widget _section(String title, List<String> cats, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: context.colors.textSecondary,
          ),
        ),
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
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: count > 0 ? color : context.colors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: context.colors.surfaceMuted,
              valueColor: AlwaysStoppedAnimation(
                count > 0 ? color : context.colors.surfaceMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
