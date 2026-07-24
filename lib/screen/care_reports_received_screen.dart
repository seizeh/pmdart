import 'package:flutter/material.dart';

import '../motion/motion.dart' show AppPageRoute;
import '../services/care_report_repository.dart';
import '../theme/app_palette.dart';
import 'boarding_thread_screen.dart';

/// 받은 케어 기록(보호자) — 업체가 보내준 전후 사진·알림장이 자동 연결되어 쌓인다.
class CareReportsReceivedScreen extends StatefulWidget {
  const CareReportsReceivedScreen({super.key});

  @override
  State<CareReportsReceivedScreen> createState() =>
      _CareReportsReceivedScreenState();
}

class _CareReportsReceivedScreenState extends State<CareReportsReceivedScreen> {
  List<ReceivedCareReport>? _reports; // null = 로딩

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // 화면 진입 시 claim 도 한 번 — 방금 발행된 기록이 바로 나타나게.
    await CareReportRepository.instance.claim();
    final rows = await CareReportRepository.instance.fetchReceived();
    if (!mounted) return;
    setState(() => _reports = rows);
  }

  String _date(DateTime? d) => d == null
      ? ''
      : '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final reports = _reports;
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('받은 케어 기록')),
      body: SafeArea(
        child: reports == null
            ? const Center(child: CircularProgressIndicator())
            : reports.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    '아직 받은 기록이 없어요.\n미용·위탁 업체가 보내준 우리 아이 사진이 여기에 자동으로 모여요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      height: 1.6,
                      color: context.colors.textSecondary,
                    ),
                  ),
                ),
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  itemCount: reports.length,
                  itemBuilder: (context, i) => _card(reports[i]),
                ),
              ),
      ),
    );
  }

  Widget _card(ReceivedCareReport r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${r.petLabel} · ${r.kind == 'boarding' ? '돌봄 기록' : '미용 기록'}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
              Text(
                _date(r.createdAt),
                style: TextStyle(
                  fontSize: 12,
                  color: context.colors.textTertiary,
                ),
              ),
            ],
          ),
          if ((r.businessName ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                r.businessName!,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: context.colors.primaryDark,
                ),
              ),
            ),
          if (r.photos.isNotEmpty) ...[
            const SizedBox(height: 10),
            // 전/후 나란히 — 뷰어·앱 공통 문법(2장이면 반반, 1장은 풀폭).
            r.photos.length == 1
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: 4 / 3,
                      child: Image.network(r.photos.first, fit: BoxFit.cover),
                    ),
                  )
                : Row(
                    children: [
                      for (var i = 0; i < r.photos.length && i < 2; i++) ...[
                        if (i > 0) const SizedBox(width: 6),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: Image.network(
                                r.photos[i],
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
          ],
          // 알림장 구조 필드(식사·배변 등) — boarding 기록.
          for (final e in r.body.entries)
            if ('${e.value}'.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${boardingBodyLabel(e.key)} · ${e.value}',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
          if ((r.note ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              r.note!,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: context.colors.textPrimary,
              ),
            ),
          ],
          // 알림장은 스레드 전체 타임라인으로 — 지난 기록까지 한 번에.
          if (r.kind == 'boarding' && r.threadId != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  AppPageRoute(
                    builder: (_) => BoardingThreadScreen(
                      threadId: r.threadId!,
                      petLabel: r.petLabel,
                    ),
                  ),
                ),
                icon: const Icon(Icons.menu_book_outlined, size: 16),
                label: const Text('알림장 전체 보기'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
