import 'package:flutter/material.dart';

import '../motion/motion.dart' show AppPageRoute;
import '../services/care_report_repository.dart';
import '../theme/app_palette.dart';
import 'boarding_thread_screen.dart';

/// 알림장 스레드 목록(업체) — 스레드 = 아이×업체 상시 1개 (0028 §4.4).
/// 무입력 7일 지난 스레드는 '보관됨'으로 하단 접힘(파생값 — 새 기록 오면 복귀).
class BoardingThreadListScreen extends StatefulWidget {
  const BoardingThreadListScreen({super.key});

  @override
  State<BoardingThreadListScreen> createState() =>
      _BoardingThreadListScreenState();
}

class _BoardingThreadListScreenState extends State<BoardingThreadListScreen> {
  List<CareThread>? _threads; // null = 로딩
  bool _archivedOpen = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await CareReportRepository.instance.fetchThreads();
    if (!mounted) return;
    setState(() => _threads = rows);
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), behavior: SnackBarBehavior.floating),
    );
  }

  /// 새 알림장(스레드) 만들기 — 아이 이름 + 보호자 번호(선택).
  Future<void> _createThread() async {
    final petCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 20,
          bottom: 24 + MediaQuery.of(sheetCtx).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '새 알림장',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: sheetCtx.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '아이마다 알림장 하나예요. 맡길 때마다 새로 만들 필요 없이 이 알림장에 계속 기록해요.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: sheetCtx.colors.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: petCtrl,
              autofocus: true,
              maxLength: 50,
              decoration: const InputDecoration(
                labelText: '아이 이름',
                hintText: '예: 구름',
                counterText: '',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: '보호자 전화번호 (선택)',
                helperText: '넣으면 보호자가 가입할 때 알림장이 자동으로 연결돼요.',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.pop(sheetCtx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: sheetCtx.colors.primaryDark,
                foregroundColor: sheetCtx.colors.textOnPrimary,
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text(
                '만들기',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
    // 시트가 닫혔으니 값만 남기고 컨트롤러는 해제(#239 — 반복 열기 누수).
    // 닫힘 전환·IME 마무리가 끝난 뒤 해제되도록 지연한다.
    final petLabel = petCtrl.text.trim();
    final phone = phoneCtrl.text;
    Future.delayed(const Duration(seconds: 1), petCtrl.dispose);
    Future.delayed(const Duration(seconds: 1), phoneCtrl.dispose);
    if (ok != true) return;
    if (petLabel.isEmpty) {
      _toast('아이 이름을 입력해 주세요');
      return;
    }
    final res = await CareReportRepository.instance.createThread(
      petLabel: petLabel,
      recipientPhone: phone,
    );
    if (!mounted) return;
    final id = res.id;
    if (id == null) {
      _toast(switch (res.error) {
        'license_required' => '동물위탁관리업 인증 후 사용할 수 있어요',
        'invalid_phone' => '전화번호 형식을 확인해 주세요',
        _ => '알림장 생성에 실패했어요',
      });
      return;
    }
    await _load();
    if (!mounted) return;
    await Navigator.push(
      context,
      AppPageRoute(
        builder: (_) => BoardingThreadScreen(
          threadId: id,
          petLabel: petLabel,
          canPost: true,
        ),
      ),
    );
    await _load();
  }

  Future<void> _openThread(CareThread t) async {
    await Navigator.push(
      context,
      AppPageRoute(
        builder: (_) => BoardingThreadScreen(
          threadId: t.id,
          petLabel: t.petLabel,
          canPost: true,
        ),
      ),
    );
    await _load(); // 발행 후 목록 상태(보관 복귀 등) 반영
  }

  String _ago(DateTime? d) {
    if (d == null) return '기록 없음';
    final diff = DateTime.now().difference(d);
    if (diff.inDays > 0) return '${diff.inDays}일 전';
    if (diff.inHours > 0) return '${diff.inHours}시간 전';
    return '방금';
  }

  @override
  Widget build(BuildContext context) {
    final threads = _threads;
    final active = threads?.where((t) => !t.archived).toList() ?? const [];
    final archived = threads?.where((t) => t.archived).toList() ?? const [];
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: const Text('알림장'),
        actions: [
          TextButton.icon(
            onPressed: _createThread,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('새 알림장'),
          ),
        ],
      ),
      body: SafeArea(
        child: threads == null
            ? const Center(child: CircularProgressIndicator())
            : threads.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '아직 알림장이 없어요',
                      style: TextStyle(color: context.colors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _createThread,
                      child: const Text('첫 알림장 만들기'),
                    ),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                  children: [
                    for (final t in active) _card(t),
                    if (archived.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () =>
                            setState(() => _archivedOpen = !_archivedOpen),
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              Icon(
                                _archivedOpen
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                size: 18,
                                color: context.colors.textTertiary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '보관됨 ${archived.length} — 새 기록을 쓰면 다시 올라와요',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: context.colors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_archivedOpen)
                        for (final t in archived)
                          Opacity(opacity: 0.7, child: _card(t)),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _card(CareThread t) {
    final claimed = t.claimedNickname != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.border, width: 0.5),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: t.lastPhoto == null
            ? CircleAvatar(
                backgroundColor: context.colors.primarySoft,
                child: Text(
                  t.petLabel.characters.first,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: context.colors.primaryDark,
                  ),
                ),
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  t.lastPhoto!,
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      ColoredBox(color: context.colors.surfaceMuted),
                ),
              ),
        title: Text(
          t.petLabel,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: context.colors.textPrimary,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            '기록 ${t.reportCount} · ${_ago(t.lastReportAt)}'
            ' · ${claimed ? '@${t.claimedNickname} 연결됨' : '미연결'}',
            style: TextStyle(
              fontSize: 12,
              color: claimed
                  ? context.colors.primaryDark
                  : context.colors.textSecondary,
            ),
          ),
        ),
        trailing: Icon(Icons.chevron_right, color: context.colors.textTertiary),
        onTap: () => _openThread(t),
      ),
    );
  }
}
