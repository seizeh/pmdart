import 'package:flutter/material.dart';

import '../services/care_report_repository.dart';
import '../services/storage_service.dart';
import '../theme/app_palette.dart';
import 'care_report_send_screen.dart' show showCareReportShareSheet;

/// 알림장 스레드 타임라인 (0028 §4.4) — 기록을 날짜로 그룹핑해 표시.
/// '위탁 건'의 경계는 이 화면의 날짜 구분선일 뿐이다(엔티티 아님).
/// [canPost] true = 업체(발행 가능), false = 연결 보호자(열람만).
class BoardingThreadScreen extends StatefulWidget {
  final String threadId;
  final String petLabel;
  final bool canPost;

  const BoardingThreadScreen({
    super.key,
    required this.threadId,
    required this.petLabel,
    this.canPost = false,
  });

  @override
  State<BoardingThreadScreen> createState() => _BoardingThreadScreenState();
}

class _BoardingThreadScreenState extends State<BoardingThreadScreen> {
  List<ThreadReport>? _reports; // null = 로딩

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await CareReportRepository.instance.fetchThreadReports(
      widget.threadId,
    );
    if (!mounted) return;
    setState(() => _reports = rows);
  }

  Future<void> _openCompose() async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) =>
          _ComposeSheet(threadId: widget.threadId, petLabel: widget.petLabel),
    );
    if (sent == true) await _load();
  }

  String _dateKey(DateTime? d) => d == null
      ? ''
      : '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  String _time(DateTime? d) => d == null
      ? ''
      : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final reports = _reports;
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: Text('${widget.petLabel} 알림장')),
      floatingActionButton: widget.canPost
          ? FloatingActionButton.extended(
              onPressed: _openCompose,
              backgroundColor: context.colors.primaryDark,
              foregroundColor: context.colors.textOnPrimary,
              icon: const Icon(Icons.edit_note),
              label: const Text('오늘 기록'),
            )
          : null,
      body: SafeArea(
        child: reports == null
            ? const Center(child: CircularProgressIndicator())
            : reports.isEmpty
            ? Center(
                child: Text(
                  widget.canPost
                      ? '첫 기록을 남겨보세요 — 보호자에게 큰 안심이 돼요'
                      : '아직 기록이 없어요',
                  style: TextStyle(color: context.colors.textSecondary),
                ),
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
                  children: [
                    // 날짜 구분선 그룹핑 — 최신순 목록에서 날짜가 바뀌는 지점마다 헤더.
                    for (var i = 0; i < reports.length; i++) ...[
                      if (i == 0 ||
                          _dateKey(reports[i].createdAt) !=
                              _dateKey(reports[i - 1].createdAt))
                        _dateDivider(_dateKey(reports[i].createdAt)),
                      _reportCard(reports[i]),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _dateDivider(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 14, 0, 8),
    child: Row(
      children: [
        Expanded(child: Divider(color: context.colors.border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: context.colors.textTertiary,
            ),
          ),
        ),
        Expanded(child: Divider(color: context.colors.border)),
      ],
    ),
  );

  Widget _reportCard(ThreadReport r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
                  _time(r.createdAt),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textTertiary,
                  ),
                ),
              ),
              // 미연결 보호자에게 링크 재전송(업체 화면에서만 의미).
              if (widget.canPost && r.token != null)
                InkWell(
                  onTap: () => showCareReportShareSheet(
                    context,
                    petLabel: widget.petLabel,
                    token: r.token!,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.ios_share,
                      size: 18,
                      color: context.colors.primaryDark,
                    ),
                  ),
                ),
            ],
          ),
          if (r.photos.isNotEmpty) ...[
            const SizedBox(height: 8),
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
          if ((r.note ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                r.note!,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: context.colors.textPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 오늘 기록 작성 시트 — 사진(선택) + 식사·배변·컨디션·산책 + 메모.
class _ComposeSheet extends StatefulWidget {
  final String threadId;
  final String petLabel;
  const _ComposeSheet({required this.threadId, required this.petLabel});

  @override
  State<_ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends State<_ComposeSheet> {
  final List<String> _photos = [];
  final Map<String, TextEditingController> _fieldCtrls = {
    for (final (key, _, _) in kBoardingBodyFields) key: TextEditingController(),
  };
  final _noteCtrl = TextEditingController();
  bool _uploading = false;
  bool _submitting = false;

  @override
  void dispose() {
    for (final c in _fieldCtrls.values) {
      c.dispose();
    }
    _noteCtrl.dispose();
    super.dispose();
  }

  bool get _hasContent =>
      _photos.isNotEmpty ||
      _noteCtrl.text.trim().isNotEmpty ||
      _fieldCtrls.values.any((c) => c.text.trim().isNotEmpty);

  Future<void> _addPhotos() async {
    if (_photos.length >= 4 || _uploading) return;
    final files = await StorageService.instance.pickImages();
    if (files.isEmpty) return;
    if (!mounted) return; // 픽커 대기 중 라우트 제거 가능(#238)
    setState(() => _uploading = true);
    try {
      for (final f in files) {
        if (_photos.length >= 4) break;
        final up = await StorageService.instance.upload(
          f,
          category: 'care_report',
        );
        _photos.add(up.url);
      }
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('사진 업로드에 실패했어요')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    final res = await CareReportRepository.instance.createBoardingReport(
      threadId: widget.threadId,
      photoUrls: _photos,
      body: {for (final e in _fieldCtrls.entries) e.key: e.value.text},
      note: _noteCtrl.text,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (res.token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(switch (res.error) {
            'license_required' => '동물위탁관리업 인증 후 사용할 수 있어요',
            'empty_report' => '사진이나 내용을 하나 이상 담아주세요',
            _ => '기록 저장에 실패했어요',
          }),
        ),
      );
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.petLabel} 오늘 기록',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _photos.length; i++)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          _photos[i],
                          width: 72,
                          height: 72,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: GestureDetector(
                          onTap: () => setState(() => _photos.removeAt(i)),
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                if (_photos.length < 4)
                  GestureDetector(
                    onTap: _addPhotos,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: context.colors.surfaceMuted,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: context.colors.border),
                      ),
                      child: _uploading
                          ? const Center(
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : Icon(
                              Icons.add_a_photo_outlined,
                              size: 20,
                              color: context.colors.textTertiary,
                            ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            for (final (key, label, hint) in kBoardingBodyFields)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TextField(
                  controller: _fieldCtrls[key],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: label,
                    hintText: hint,
                    isDense: true,
                  ),
                ),
              ),
            TextField(
              controller: _noteCtrl,
              onChanged: (_) => setState(() {}),
              maxLines: 2,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: '한 줄 메모 (선택)',
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _hasContent && !_submitting && !_uploading
                  ? _submit
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: context.colors.primaryDark,
                foregroundColor: context.colors.textOnPrimary,
                minimumSize: const Size.fromHeight(48),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      '기록 보내기',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
            const SizedBox(height: 4),
            Text(
              '연결된 보호자에겐 바로 알림이 가요. 아직 연결 전이면 기록 옆 공유 버튼으로 링크를 보내주세요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: context.colors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
