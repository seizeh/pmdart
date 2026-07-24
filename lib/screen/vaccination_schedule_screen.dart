import 'package:flutter/material.dart';

import '../motion/motion.dart';
import '../services/vaccination_repository.dart';
import '../theme/app_palette.dart';
import '../utils/vaccination_schedule.dart';

/// 접종 일정(0028 P3 — 분양 스타터).
///
/// - 저장된 일정이 있으면: 리스트(완료 체크·D-day) 뷰.
/// - 없으면: 생년월일 기반 표준 일정 미리보기 + "접종 알림 받기" 등록 유도 뷰.
/// - [birthDate] 가 없으면 인라인 날짜 선택으로 기준일만 받는다(펫 정보는 수정하지 않음).
/// - [source] 는 퍼널 계측용('onboarding' = 가입 분기, 'manage' = 펫 화면 등).
class VaccinationScheduleScreen extends StatefulWidget {
  final String petId;
  final String? petName;
  final DateTime? birthDate;
  final String? speciesKind; // 'dog' | 'cat'
  final String source;

  const VaccinationScheduleScreen({
    super.key,
    required this.petId,
    this.petName,
    this.birthDate,
    this.speciesKind,
    this.source = 'manage',
  });

  @override
  State<VaccinationScheduleScreen> createState() =>
      _VaccinationScheduleScreenState();
}

class _VaccinationScheduleScreenState extends State<VaccinationScheduleScreen> {
  final _repo = VaccinationRepository.instance;
  List<VaccinationEvent>? _events; // null = 로딩/실패 (아래 _failed 로 구분)
  bool _failed = false;
  bool _saving = false;
  DateTime? _birthDate; // 화면 로컬 기준일 — 펫 정보는 건드리지 않는다

  String get _petLabel => widget.petName ?? '아이';

  @override
  void initState() {
    super.initState();
    _birthDate = widget.birthDate;
    _load();
  }

  Future<void> _load() async {
    final rows = await _repo.fetchEvents(widget.petId);
    if (!mounted) return;
    setState(() {
      _events = rows;
      _failed = rows == null;
    });
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), behavior: SnackBarBehavior.floating),
    );
  }

  String _date(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  /// D-day 문구 — 오늘/내일/N일 후/N일 지남.
  String _dday(DateTime due) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final diff = DateTime(due.year, due.month, due.day).difference(today).inDays;
    if (diff == 0) return '오늘';
    if (diff == 1) return '내일';
    if (diff > 1) return '$diff일 후';
    return '${-diff}일 지남';
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 30),
      lastDate: now,
      initialDate: _birthDate ?? DateTime(now.year, now.month - 2, now.day),
      helpText: '생년월일을 알려주세요',
    );
    if (picked != null && mounted) setState(() => _birthDate = picked);
  }

  /// 표준 일정 계산 → 서버 저장(미완료분 교체). 성공 시 리스트 뷰로 전환.
  Future<void> _saveSchedule() async {
    final birth = _birthDate;
    if (birth == null) {
      await _pickBirthDate();
      return;
    }
    final plan = upcomingVaccinationSchedule(
      birthDate: birth,
      speciesKind: widget.speciesKind,
    );
    if (plan.upcoming.isEmpty) {
      _toast('남은 표준 일정이 없어요. 접종 계획은 동물병원과 상의해주세요');
      return;
    }
    setState(() => _saving = true);
    final res = await _repo.setSchedule(
      petId: widget.petId,
      events: [
        for (final v in plan.upcoming) (label: v.label, dueDate: v.dueDate),
      ],
      source: widget.source,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.error != null) {
      _toast(switch (res.error) {
        'not_guardian' => '이 아이의 보호자만 일정을 등록할 수 있어요',
        'invalid_events' => '일정을 만들 수 없어요. 생년월일을 확인해주세요',
        _ => '저장에 실패했어요. 잠시 후 다시 시도해주세요',
      });
      return;
    }
    _toast('접종일 전날과 당일 아침에 알려드려요');
    await _load();
  }

  /// "일정 다시 만들기" — 재계산·저장. 완료 체크분은 서버가 기록으로 보존한다.
  Future<void> _confirmRebuild() async {
    if (_birthDate == null) {
      await _pickBirthDate();
      if (_birthDate == null || !mounted) return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('일정 다시 만들기'),
        content: Text(
          '${_date(_birthDate!)} 생일 기준 표준 일정으로 다시 만들까요?\n'
          '완료 체크한 접종 기록은 그대로 보존돼요.',
          style: const TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('다시 만들기'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await _saveSchedule();
  }

  /// 완료 체크 토글 — 낙관 갱신 후 실패 시 원복.
  Future<void> _toggleDone(VaccinationEvent e) async {
    final events = _events;
    if (events == null) return;
    final next = !e.done;
    setState(() {
      _events = [
        for (final v in events)
          if (v.id == e.id)
            next ? v.copyWith(doneAt: DateTime.now()) : v.copyWith(clearDone: true)
          else
            v,
      ];
    });
    final ok = await _repo.setDone(e.id, next);
    if (!ok && mounted) {
      setState(() => _events = events); // 원복
      _toast('변경에 실패했어요');
    }
  }

  @override
  Widget build(BuildContext context) {
    final events = _events;
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: Text('$_petLabel 접종 일정'),
        actions: [
          if (events != null && events.isNotEmpty)
            TextButton.icon(
              onPressed: _saving ? null : _confirmRebuild,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('다시 만들기'),
            ),
        ],
      ),
      body: SafeArea(
        child: _failed
            ? _errorView()
            : events == null
            ? const Center(child: CircularProgressIndicator())
            : events.isEmpty
            ? _setupView()
            : _listView(events),
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '일정을 불러오지 못했어요',
            style: TextStyle(color: context.colors.textSecondary),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              setState(() => _failed = false);
              _load();
            },
            child: const Text('다시 시도'),
          ),
        ],
      ),
    );
  }

  // ── 등록 유도 뷰 — 표준 일정 미리보기 + "접종 알림 받기" ──

  Widget _setupView() {
    final birth = _birthDate;
    final plan = birth == null
        ? null
        : upcomingVaccinationSchedule(
            birthDate: birth,
            speciesKind: widget.speciesKind,
          );
    var i = 0;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
            children: [
              Entrance(
                index: i++,
                child: Text(
                  '$_petLabel의 접종,\n놓치지 않게 챙겨드려요',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Entrance(
                index: i++,
                child: Text(
                  '생년월일 기준 표준 일정을 등록하면 접종일 전날과 당일 아침에 알림을 보내드려요.',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.colors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Entrance(index: i++, child: _birthRow()),
              if (plan != null) ...[
                const SizedBox(height: 16),
                if (plan.excluded > 0)
                  Entrance(
                    index: i++,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '이미 지난 일정 ${plan.excluded}건은 제외했어요',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.colors.textTertiary,
                        ),
                      ),
                    ),
                  ),
                if (plan.upcoming.isEmpty)
                  Entrance(
                    index: i++,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: context.colors.surfaceMuted,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: context.colors.border,
                          width: 0.5,
                        ),
                      ),
                      child: Text(
                        '표준 일정(생후 20주 이내)이 모두 지났어요. 추가 접종 계획은 동물병원과 상의해주세요.',
                        style: TextStyle(
                          fontSize: 13,
                          color: context.colors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ),
                  )
                else
                  ...plan.upcoming.map(
                    (v) => Entrance(
                      index: i++,
                      child: _previewRow(v),
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              _disclaimer(),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: ElevatedButton(
            onPressed:
                _saving || (plan != null && plan.upcoming.isEmpty)
                ? null
                : _saveSchedule,
            child: _saving
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: context.colors.textOnPrimary,
                    ),
                  )
                : Text(_birthDate == null ? '생년월일 선택하고 시작하기' : '접종 알림 받기'),
          ),
        ),
      ],
    );
  }

  /// 기준 생년월일 행 — 펫 정보에 생일이 없으면 여기서만 받아 계산한다.
  Widget _birthRow() {
    final birth = _birthDate;
    return Pressable(
      onTap: _pickBirthDate,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: context.colors.surfaceMuted,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.colors.border, width: 0.5),
        ),
        child: Row(
          children: [
            Icon(
              Icons.cake_outlined,
              color: context.colors.primaryDark,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                birth == null ? '생년월일을 알려주세요' : '생년월일  ${_date(birth)}',
                style: TextStyle(
                  fontSize: 14,
                  color: birth == null
                      ? context.colors.textTertiary
                      : context.colors.textPrimary,
                ),
              ),
            ),
            Text(
              birth == null ? '선택' : '변경',
              style: TextStyle(
                fontSize: 13,
                color: context.colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewRow(SuggestedVaccination v) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.border, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(
            Icons.vaccines_outlined,
            size: 18,
            color: context.colors.primaryDark,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              v.label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.colors.textPrimary,
              ),
            ),
          ),
          Text(
            _date(v.dueDate),
            style: TextStyle(
              fontSize: 13,
              color: context.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // ── 저장된 일정 리스트 뷰 — 완료 체크 + D-day ──

  Widget _listView(List<VaccinationEvent> events) {
    var i = 0;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        children: [
          Entrance(
            index: i++,
            child: Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: context.colors.primarySoft.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.notifications_active_outlined,
                    size: 18,
                    color: context.colors.primaryDark,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '접종일 전날과 당일 아침에 알려드려요',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.colors.textPrimary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ...events.map((e) => Entrance(index: i++, child: _eventRow(e))),
          const SizedBox(height: 8),
          _disclaimer(),
        ],
      ),
    );
  }

  Widget _eventRow(VaccinationEvent e) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(e.dueDate.year, e.dueDate.month, e.dueDate.day);
    final overdue = !e.done && due.isBefore(today);
    final muted = e.done || overdue;
    return Pressable(
      onTap: () => _toggleDone(e),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: e.done ? context.colors.surfaceMuted : context.colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.colors.border, width: 0.5),
        ),
        child: Row(
          children: [
            Icon(
              e.done ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 22,
              color: e.done
                  ? context.colors.success
                  : context.colors.textTertiary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.label,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: muted
                          ? context.colors.textSecondary
                          : context.colors.textPrimary,
                      decoration: e.done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _date(e.dueDate),
                    style: TextStyle(
                      fontSize: 12.5,
                      color: context.colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            if (e.done)
              _chip('완료', context.colors.success)
            else if (overdue)
              _chip(_dday(e.dueDate), context.colors.danger)
            else
              _chip(
                _dday(e.dueDate),
                due == today || due.difference(today).inDays == 1
                    ? context.colors.warning
                    : context.colors.primaryDark,
              ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _disclaimer() {
    return Text(
      '일반적인 표준 일정 안내이며, 정확한 접종 시기는 동물병원과 상의하세요.',
      style: TextStyle(
        fontSize: 11.5,
        color: context.colors.textTertiary,
        height: 1.5,
      ),
    );
  }
}
