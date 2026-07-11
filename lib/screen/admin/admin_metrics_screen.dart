import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../services/admin_repository.dart';
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
        AdminRepository.instance.opsMetrics(),
        AdminRepository.instance.photoVerificationFailures(limit: 50),
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
      backgroundColor: Colors.white,
      appBar: adminAppBar('운영 지표 · 비용'),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : (_error != null || _m == null)
                  ? ListView(children: [
                      const SizedBox(height: 120),
                      Center(
                        child: Column(children: [
                          Text(_error ?? '지표를 불러오지 못했어요',
                              style: const TextStyle(
                                  color: AppColors.textSecondary)),
                          TextButton(
                              onPressed: _load, child: const Text('다시 시도')),
                        ]),
                      ),
                    ])
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
        _SuccessRateBar(
            pass: m.aiPass, fail: m.aiFail, rate: m.aiSuccessRate),
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
            decoration: _boxDeco(),
            child: const Text('실패한 인증이 없어요',
                style: TextStyle(color: AppColors.textSecondary)),
          )
        else
          ..._fails.map((f) => _FailTile(f: f)),
        const SizedBox(height: 8),
        const Text(
          '※ 비용은 로그가 없어 단가 × 건수로 추정한 값이에요. 실제 청구액과 다를 수 있어요.',
          style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

BoxDecoration _boxDeco({bool danger = false}) => BoxDecoration(
      color: danger
          ? AppColors.danger.withValues(alpha: 0.06)
          : AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: danger
            ? AppColors.danger.withValues(alpha: 0.35)
            : AppColors.border,
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
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: AppColors.textSecondary,
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
    final maxC =
        series.fold<int>(1, (p, e) => e.count > p ? e.count : p);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _boxDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${m.dauToday}',
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryDark,
                ),
              ),
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text('명 · 오늘',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
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
                            style: const TextStyle(
                                fontSize: 9, color: AppColors.textTertiary),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            height: (series[i].count / maxC) * 46 + 3,
                            decoration: BoxDecoration(
                              color: i == series.length - 1
                                  ? AppColors.adminAccent
                                  : AppColors.primary,
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
              Text(series.isEmpty ? '' : series.first.day,
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.textTertiary)),
              const Text('최근 14일',
                  style: TextStyle(
                      fontSize: 10, color: AppColors.textTertiary)),
              Text(series.isEmpty ? '' : series.last.day,
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.textTertiary)),
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
              Text(_n(v),
                  style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text(label,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: _boxDeco(),
      child: Row(
        children: [
          cell('오늘', today),
          _divider(),
          cell('7일', d7),
          _divider(),
          cell('30일', d30),
          _divider(),
          cell('전체', total),
        ],
      ),
    );
  }

  Widget _divider() => Container(
      width: 0.5, height: 34, color: AppColors.border);
}

/// AI 인증 성공률 막대.
class _SuccessRateBar extends StatelessWidget {
  final int pass, fail;
  final double rate;
  const _SuccessRateBar(
      {required this.pass, required this.fail, required this.rate});

  @override
  Widget build(BuildContext context) {
    final pct = (rate * 100);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _boxDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('인증 성공률',
                  style: TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
              Text('${pct.toStringAsFixed(pass + fail == 0 ? 0 : 1)}%',
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryDark)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: LinearProgressIndicator(
              value: rate.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: AppColors.danger.withValues(alpha: 0.18),
              valueColor:
                  const AlwaysStoppedAnimation(AppColors.primaryDark),
            ),
          ),
          const SizedBox(height: 8),
          Text('성공 ${_n(pass)}건 · 실패 ${_n(fail)}건',
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textTertiary)),
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
              Text(label,
                  style: TextStyle(
                      fontSize: strong ? 14 : 13,
                      fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
                      color: strong
                          ? AppColors.textPrimary
                          : AppColors.textSecondary)),
              Text(_won(v),
                  style: TextStyle(
                      fontSize: strong ? 16 : 14,
                      fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
                      color: strong
                          ? AppColors.primaryDark
                          : AppColors.textPrimary)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _boxDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          line('오늘', today),
          line('최근 7일', d7),
          line('최근 30일', d30),
          const Divider(height: 16, color: AppColors.border),
          line('누적(전체)', all, strong: true),
          const SizedBox(height: 8),
          Text(basis,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textTertiary)),
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
      decoration: _boxDeco(danger: true),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(f.failLabel,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.danger)),
              ),
              Text(_when(f.createdAt),
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textTertiary)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${f.nickname}'
            '${f.aiMatchScore != null ? ' · 유사도 ${(f.aiMatchScore! * 100).toStringAsFixed(0)}%' : ''}'
            '${f.regionMatched ? ' · 동네 일치' : ''}',
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
          ),
          if (f.aiReason != null && f.aiReason!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text('AI: ${f.aiReason}',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textTertiary)),
          ],
        ],
      ),
    );
  }
}
