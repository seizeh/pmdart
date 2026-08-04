import 'package:flutter/material.dart';

import '../../models/admin.dart';
import '../../services/admin/admin_ops_repository.dart';
import '../../theme/app_palette.dart';
import 'admin_theme.dart';

/// 관리자 운영 지표·비용 화면.
/// - 일일 활성 사용자(DAU) + 최근 14일 추이
/// - AI 사진 인증: 횟수·성공률·예상 비용 + 실패 로그
/// - Solapi 문자 인증: 발송 횟수·예상 비용
class AdminMetricsScreen extends StatefulWidget {
  const AdminMetricsScreen({super.key});

  @override
  State<AdminMetricsScreen> createState() => _AdminMetricsScreenState();
}

class _AdminMetricsScreenState extends State<AdminMetricsScreen> {
  AdminOpsMetrics? _m;
  List<PhotoVerifyFailure> _fails = const [];
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
      final results = await Future.wait([
        AdminOpsRepository.instance.opsMetrics(),
        AdminOpsRepository.instance.photoVerificationFailures(limit: 50),
      ]);
      if (!mounted) return;
      setState(() {
        _m = results[0] as AdminOpsMetrics;
        _fails = results[1] as List<PhotoVerifyFailure>;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '지표를 불러오지 못했어요';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: adminAppBar(context, '운영 지표 · 비용'),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : (_error != null || _m == null)
              ? ListView(
                  children: [
                    const SizedBox(height: 120),
                    Center(
                      child: Column(
                        children: [
                          Text(
                            _error ?? '지표를 불러오지 못했어요',
                            style: TextStyle(
                              color: context.colors.textSecondary,
                            ),
                          ),
                          TextButton(
                            onPressed: _load,
                            child: const Text('다시 시도'),
                          ),
                        ],
                      ),
                    ),
                  ],
                )
              : _content(_m!),
        ),
      ),
    );
  }

  Widget _content(AdminOpsMetrics m) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // ── 일일 활성 사용자 ──────────────────────────────
        const _SectionTitle('일일 활성 사용자 (DAU)'),
        const SizedBox(height: 10),
        _DauCard(m: m),
        const SizedBox(height: 24),

        // ── AI 사진 인증 ─────────────────────────────────
        const _SectionTitle('AI 사진 인증'),
        const SizedBox(height: 10),
        _PeriodCounts(
          total: m.aiTotal,
          today: m.aiToday,
          d7: m.aiD7,
          d30: m.aiD30,
          unit: '건',
        ),
        const SizedBox(height: 10),
        _SuccessRateBar(pass: m.aiPass, fail: m.aiFail, rate: m.aiSuccessRate),
        const SizedBox(height: 10),
        _CostCard(
          title: 'AI 예상 비용',
          all: m.aiCostAll,
          today: m.aiCostToday,
          d7: m.aiCostD7,
          d30: m.aiCostD30,
          basis: '건당 ₩${m.aiUnitKrw} · Gemini 2.5 Pro 추정',
        ),
        const SizedBox(height: 24),

        // ── Solapi 문자 인증 ─────────────────────────────
        const _SectionTitle('문자 인증 (Solapi)'),
        const SizedBox(height: 10),
        _PeriodCounts(
          total: m.smsTotal,
          today: m.smsToday,
          d7: m.smsD7,
          d30: m.smsD30,
          unit: '건',
        ),
        const SizedBox(height: 10),
        _CostCard(
          title: '문자 예상 비용',
          all: m.smsCostAll,
          today: m.smsCostToday,
          d7: m.smsCostD7,
          d30: m.smsCostD30,
          basis: '건당 ₩${m.smsUnitKrw} · SMS 단문 기준',
        ),
        const SizedBox(height: 24),

        // ── 인증 실패 로그 ───────────────────────────────
        _SectionTitle('인증 실패 로그 (${_fails.length})'),
        const SizedBox(height: 10),
        if (_fails.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24),
            alignment: Alignment.center,
            decoration: _boxDeco(context),
            child: Text(
              '실패한 인증이 없어요',
              style: TextStyle(color: context.colors.textSecondary),
            ),
          )
        else
          ..._fails.map((f) => _FailTile(f: f)),
        const SizedBox(height: 8),
        Text(
          '※ 비용은 로그가 없어 단가 × 건수로 추정한 값이에요. 실제 청구액과 다를 수 있어요.',
          style: TextStyle(fontSize: 11, color: context.colors.textTertiary),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

BoxDecoration _boxDeco(BuildContext context, {bool danger = false}) =>
    BoxDecoration(
      color: danger
          ? context.colors.danger.withValues(alpha: 0.06)
          : context.colors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: danger
            ? context.colors.danger.withValues(alpha: 0.35)
            : context.colors.border,
        width: 0.5,
      ),
    );

/// 천단위 콤마.
String _n(int v) {
  final s = v.abs().toString();
  final b = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return (v < 0 ? '-' : '') + b.toString();
}

String _won(int v) => '₩${_n(v)}';

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: context.colors.textSecondary,
      ),
    );
  }
}

/// DAU 카드 — 오늘 수치 + 최근 14일 막대.
class _DauCard extends StatelessWidget {
  final AdminOpsMetrics m;
  const _DauCard({required this.m});

  @override
  Widget build(BuildContext context) {
    final series = m.dauSeries;
    final maxC = series.fold<int>(1, (p, e) => e.count > p ? e.count : p);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _boxDeco(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${m.dauToday}',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: context.colors.primaryDark,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  '명 · 오늘',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 72,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (int i = 0; i < series.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            series[i].count == 0 ? '' : '${series[i].count}',
                            style: TextStyle(
                              fontSize: 9,
                              color: context.colors.textTertiary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            height: (series[i].count / maxC) * 46 + 3,
                            decoration: BoxDecoration(
                              color: i == series.length - 1
                                  ? context.colors.adminAccent
                                  : context.colors.primary,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                series.isEmpty ? '' : series.first.day,
                style: TextStyle(
                  fontSize: 10,
                  color: context.colors.textTertiary,
                ),
              ),
              Text(
                '최근 14일',
                style: TextStyle(
                  fontSize: 10,
                  color: context.colors.textTertiary,
                ),
              ),
              Text(
                series.isEmpty ? '' : series.last.day,
                style: TextStyle(
                  fontSize: 10,
                  color: context.colors.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 기간별 건수(전체/오늘/7일/30일).
class _PeriodCounts extends StatelessWidget {
  final int total, today, d7, d30;
  final String unit;
  const _PeriodCounts({
    required this.total,
    required this.today,
    required this.d7,
    required this.d30,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    Widget cell(String label, int v) => Expanded(
      child: Column(
        children: [
          Text(
            _n(v),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: context.colors.textSecondary),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: _boxDeco(context),
      child: Row(
        children: [
          cell('오늘', today),
          _divider(context),
          cell('7일', d7),
          _divider(context),
          cell('30일', d30),
          _divider(context),
          cell('전체', total),
        ],
      ),
    );
  }

  Widget _divider(BuildContext context) =>
      Container(width: 0.5, height: 34, color: context.colors.border);
}

/// AI 인증 성공률 막대.
class _SuccessRateBar extends StatelessWidget {
  final int pass, fail;
  final double rate;
  const _SuccessRateBar({
    required this.pass,
    required this.fail,
    required this.rate,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (rate * 100);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _boxDeco(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '인증 성공률',
                style: TextStyle(
                  fontSize: 13,
                  color: context.colors.textSecondary,
                ),
              ),
              Text(
                '${pct.toStringAsFixed(pass + fail == 0 ? 0 : 1)}%',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: context.colors.primaryDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: LinearProgressIndicator(
              value: rate.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: context.colors.danger.withValues(alpha: 0.18),
              valueColor: AlwaysStoppedAnimation(context.colors.primaryDark),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '성공 ${_n(pass)}건 · 실패 ${_n(fail)}건',
            style: TextStyle(fontSize: 11, color: context.colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// 예상 비용 카드(전체/오늘/7일/30일 + 산정 기준).
class _CostCard extends StatelessWidget {
  final String title;
  final int all, today, d7, d30;
  final String basis;
  const _CostCard({
    required this.title,
    required this.all,
    required this.today,
    required this.d7,
    required this.d30,
    required this.basis,
  });

  @override
  Widget build(BuildContext context) {
    Widget line(String label, int v, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: strong ? 14 : 13,
              fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
              color: strong
                  ? context.colors.textPrimary
                  : context.colors.textSecondary,
            ),
          ),
          Text(
            _won(v),
            style: TextStyle(
              fontSize: strong ? 16 : 14,
              fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
              color: strong
                  ? context.colors.primaryDark
                  : context.colors.textPrimary,
            ),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _boxDeco(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          line('오늘', today),
          line('최근 7일', d7),
          line('최근 30일', d30),
          Divider(height: 16, color: context.colors.border),
          line('누적(전체)', all, strong: true),
          const SizedBox(height: 8),
          Text(
            basis,
            style: TextStyle(fontSize: 11, color: context.colors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// 실패 로그 1줄.
class _FailTile extends StatelessWidget {
  final PhotoVerifyFailure f;
  const _FailTile({required this.f});

  String _when(DateTime t) =>
      '${t.month.toString().padLeft(2, '0')}/${t.day.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: _boxDeco(context, danger: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  f.failLabel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: context.colors.danger,
                  ),
                ),
              ),
              Text(
                _when(f.createdAt),
                style: TextStyle(
                  fontSize: 11,
                  color: context.colors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${f.nickname}'
            '${f.aiMatchScore != null ? ' · 유사도 ${(f.aiMatchScore! * 100).toStringAsFixed(0)}%' : ''}'
            '${f.regionMatched ? ' · 동네 일치' : ''}',
            style: TextStyle(fontSize: 12, color: context.colors.textSecondary),
          ),
          if (f.aiReason != null && f.aiReason!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'AI: ${f.aiReason}',
              style: TextStyle(
                fontSize: 11,
                color: context.colors.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
