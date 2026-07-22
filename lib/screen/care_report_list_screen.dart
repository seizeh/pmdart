import 'package:flutter/material.dart';

import '../motion/motion.dart' show AppPageRoute;
import '../services/care_report_repository.dart';
import '../theme/app_palette.dart';
import 'care_report_send_screen.dart';

/// 보낸 케어 기록(업체) — 발행 목록 + 수령 상태(오연결 발견용) + 재공유.
class CareReportListScreen extends StatefulWidget {
  const CareReportListScreen({super.key});

  @override
  State<CareReportListScreen> createState() => _CareReportListScreenState();
}

class _CareReportListScreenState extends State<CareReportListScreen> {
  List<IssuedCareReport>? _reports; // null = 로딩

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await CareReportRepository.instance.fetchMine();
    if (!mounted) return;
    setState(() => _reports = rows);
  }

  Future<void> _openSend() async {
    final sent = await Navigator.push<bool>(
      context,
      AppPageRoute(builder: (_) => const CareReportSendScreen()),
    );
    if (sent == true) await _load();
  }

  String _date(DateTime? d) => d == null
      ? ''
      : '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final reports = _reports;
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: const Text('보낸 케어 기록'),
        actions: [
          TextButton.icon(
            onPressed: _openSend,
            icon: const Icon(Icons.add_a_photo_outlined, size: 18),
            label: const Text('보내기'),
          ),
        ],
      ),
      body: SafeArea(
        child: reports == null
            ? const Center(child: CircularProgressIndicator())
            : reports.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '아직 보낸 기록이 없어요',
                      style: TextStyle(color: context.colors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _openSend,
                      child: const Text('첫 전후 사진 보내기'),
                    ),
                  ],
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

  Widget _card(IssuedCareReport r) {
    final claimed = r.claimedNickname != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.border, width: 0.5),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: r.photos.isEmpty
            ? null
            : ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  r.photos.first,
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      ColoredBox(color: context.colors.surfaceMuted),
                ),
              ),
        title: Text(
          r.petLabel,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: context.colors.textPrimary,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            '${_date(r.createdAt)} · 열람 ${r.viewCount}'
            ' · ${claimed ? '@${r.claimedNickname} 연결됨' : '미연결'}',
            style: TextStyle(
              fontSize: 12,
              color: claimed
                  ? context.colors.primaryDark
                  : context.colors.textSecondary,
            ),
          ),
        ),
        trailing: IconButton(
          tooltip: '다시 공유',
          icon: Icon(Icons.ios_share, color: context.colors.primaryDark),
          onPressed: r.token == null
              ? null
              : () => showCareReportShareSheet(
                  context,
                  petLabel: r.petLabel,
                  token: r.token!,
                ),
        ),
      ),
    );
  }
}
