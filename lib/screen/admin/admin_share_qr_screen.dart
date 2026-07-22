import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/admin_repository.dart';
import '../../services/facility_repository.dart';
import '../../theme/app_palette.dart';
import '../../utils/share_links.dart';
import 'admin_theme.dart';

/// 매장 QR 발급 (0028 §3) — 시설 검색 → 미리보기 공유 링크 발급 → QR 표시.
/// QR 은 share-view 공개 뷰어(설치·가입 없이 열람)로 연결되고, 열람·스토어
/// 클릭이 funnel_events 에 매장별로 계측된다. 같은 시설은 유효 토큰을
/// 재사용하므로(서버) 재발급해도 기존 인쇄 QR 이 무효화되지 않는다.
class AdminShareQrScreen extends StatefulWidget {
  const AdminShareQrScreen({super.key});

  @override
  State<AdminShareQrScreen> createState() => _AdminShareQrScreenState();
}

class _AdminShareQrScreenState extends State<AdminShareQrScreen> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<Facility> _results = const [];
  bool _searching = false;
  String? _issuingId; // 발급 중인 시설(중복 탭 방지)

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final query = q.trim();
      if (query.isEmpty) {
        if (mounted) setState(() => _results = const []);
        return;
      }
      setState(() => _searching = true);
      final rows = await FacilityRepository.instance.searchByName(query);
      if (!mounted) return;
      setState(() {
        _results = rows;
        _searching = false;
      });
    });
  }

  Future<void> _issue(Facility f) async {
    if (_issuingId != null) return;
    setState(() => _issuingId = f.id);
    try {
      final link = await AdminRepository.instance.createFacilityShareLink(f.id);
      if (!mounted) return;
      setState(() => _issuingId = null);
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: context.colors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) =>
            _QrSheet(facility: f, token: link.token, expiresAt: link.expiresAt),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _issuingId = null);
      _toast('링크 발급에 실패했어요');
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: adminAppBar(context, '매장 QR 발급'),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: TextField(
                controller: _searchCtrl,
                onChanged: _onQuery,
                decoration: InputDecoration(
                  hintText: '매장 이름 검색',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : null,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: Text(
                '발급된 QR 은 설치 없이 열리는 매장 미리보기(share-view)로 연결돼요. '
                '같은 매장은 항상 같은 토큰이 재사용돼 재발급해도 기존 인쇄물이 유효해요.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: context.colors.textTertiary,
                ),
              ),
            ),
            Expanded(
              child: _results.isEmpty
                  ? Center(
                      child: Text(
                        _searchCtrl.text.trim().isEmpty
                            ? '매장 이름으로 검색해 주세요'
                            : (_searching ? '' : '검색 결과가 없어요'),
                        style: TextStyle(color: context.colors.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                      itemCount: _results.length,
                      itemBuilder: (context, i) => _card(_results[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(Facility f) {
    final issuing = _issuingId == f.id;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.border, width: 0.5),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(
          f.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: context.colors.textPrimary,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            [
              kFacilityLabels[f.category] ?? f.category,
              if ((f.address ?? '').isNotEmpty) f.address!,
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: context.colors.textSecondary),
          ),
        ),
        trailing: issuing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(Icons.qr_code_2, color: context.colors.primaryDark),
        onTap: issuing ? null : () => _issue(f),
      ),
    );
  }
}

/// 발급 결과 시트 — QR + 링크 복사 + 회수. QR 은 밝은 배경 고정(스캐너 대비).
class _QrSheet extends StatefulWidget {
  final Facility facility;
  final String token;
  final DateTime? expiresAt;
  const _QrSheet({
    required this.facility,
    required this.token,
    required this.expiresAt,
  });

  @override
  State<_QrSheet> createState() => _QrSheetState();
}

class _QrSheetState extends State<_QrSheet> {
  bool _busy = false;

  String get _url => shareViewUrl(widget.token);

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _url));
    _toast('링크를 복사했어요');
  }

  Future<void> _revoke() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('링크를 회수할까요?'),
        content: const Text('회수하면 배포된 QR·링크가 즉시 열리지 않게 돼요. 되돌릴 수 없어요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: Text('회수', style: TextStyle(color: dCtx.colors.danger)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final done = await AdminRepository.instance.revokeShareLink(widget.token);
    if (!mounted) return;
    if (done) {
      Navigator.pop(context);
      _toast('링크를 회수했어요 — 다음 발급 시 새 토큰이 생성돼요');
    } else {
      setState(() => _busy = false);
      _toast('회수에 실패했어요');
    }
  }

  @override
  Widget build(BuildContext context) {
    final exp = widget.expiresAt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.facility.name,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: _url,
                size: 220,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Color(0xFF3A3428),
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Color(0xFF3A3428),
                ),
              ),
            ),
          ),
          if (exp != null) ...[
            const SizedBox(height: 10),
            Text(
              '만료: ${exp.year}.${exp.month.toString().padLeft(2, '0')}.${exp.day.toString().padLeft(2, '0')}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: context.colors.textTertiary,
              ),
            ),
          ],
          const SizedBox(height: 12),
          SelectableText(
            _url,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: context.colors.textSecondary),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _copy,
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('링크 복사'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : _revoke,
            style: OutlinedButton.styleFrom(
              foregroundColor: context.colors.danger,
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('링크 회수'),
          ),
        ],
      ),
    );
  }
}
