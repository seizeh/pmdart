import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/admin_repository.dart';
import '../../services/business_repository.dart' show bizLicenseLabel;
import '../../services/storage_service.dart';
import '../../theme/app_palette.dart';
import 'admin_theme.dart';

/// 업종 인증 심사 (0028 §1) — 등록·허가증 확인 후 승인/반려.
/// 업체 인증 심사(0025)와 같은 문법: 상태 탭 · 목록 · 상세 시트 · 서류 열람.
/// 자동승인 트랙 없음 — 전건 수동 검토, 반려는 사유 필수(서버 검증과 동일).
class AdminLicensesScreen extends StatefulWidget {
  const AdminLicensesScreen({super.key});

  @override
  State<AdminLicensesScreen> createState() => _AdminLicensesScreenState();
}

class _AdminLicensesScreenState extends State<AdminLicensesScreen> {
  String? _status = 'pending';
  List<AdminBizLicense> _items = const [];
  bool _loading = true;

  static const _statusTabs = <(String?, String)>[
    ('pending', '대기'),
    ('approved', '승인'),
    ('rejected', '반려'),
    (null, '전체'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await AdminRepository.instance.listBusinessLicenses(
        status: _status,
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _loading = false;
      });
      _toast('목록을 불러오지 못했어요');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: adminAppBar(context, '업종 인증 심사'),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(
                children: [
                  for (final (value, label) in _statusTabs)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: _status == value,
                        onSelected: (_) {
                          setState(() => _status = value);
                          _load();
                        },
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                  ? Center(
                      child: Text(
                        '신청이 없어요',
                        style: TextStyle(color: context.colors.textSecondary),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        itemCount: _items.length,
                        itemBuilder: (context, i) => _card(_items[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(AdminBizLicense l) {
    final statusColor = switch (l.status) {
      'approved' => context.colors.primary,
      'rejected' => context.colors.danger,
      _ => context.colors.textSecondary,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.border, width: 0.5),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        title: Row(
          children: [
            Expanded(
              child: Text(
                '${l.businessName ?? '@${l.nickname}'} · ${bizLicenseLabel(l.type)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textPrimary,
                ),
              ),
            ),
            Text(
              switch (l.status) {
                'approved' => '승인',
                'rejected' => '반려',
                _ => '대기',
              },
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: statusColor,
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            '${l.licenseNo} · @${l.nickname}',
            style: TextStyle(fontSize: 12, color: context.colors.textSecondary),
          ),
        ),
        trailing: Icon(Icons.chevron_right, color: context.colors.textTertiary),
        onTap: () => _openDetail(l),
      ),
    );
  }

  Future<void> _openDetail(AdminBizLicense l) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _LicenseDetailSheet(license: l),
    );
    if (changed == true) unawaited(_load());
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }
}

class _LicenseDetailSheet extends StatefulWidget {
  final AdminBizLicense license;
  const _LicenseDetailSheet({required this.license});

  @override
  State<_LicenseDetailSheet> createState() => _LicenseDetailSheetState();
}

class _LicenseDetailSheetState extends State<_LicenseDetailSheet> {
  bool _busy = false;

  AdminBizLicense get l => widget.license;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            bizLicenseLabel(l.type),
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          _row('신청자', '@${l.nickname}'),
          if ((l.businessName ?? '').isNotEmpty) _row('상호', l.businessName!),
          _row('등록·허가번호', l.licenseNo),
          if (l.status == 'rejected' && (l.rejectReason ?? '').isNotEmpty)
            _row('반려 사유', l.rejectReason!),
          const Divider(height: 28),
          OutlinedButton.icon(
            onPressed: () => _openDoc(l.documentPath),
            icon: const Icon(Icons.description_outlined),
            label: const Text('등록·허가증 열람'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
            ),
          ),
          const SizedBox(height: 20),
          // 상태 전이: pending → 승인/반려, approved → 승인 취소(반려), rejected → 승인
          Row(
            children: [
              if (l.status != 'rejected')
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => _decide('rejected'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.colors.danger,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: Text(l.status == 'approved' ? '승인 취소(반려)' : '반려'),
                  ),
                ),
              if (l.status == 'pending') const SizedBox(width: 10),
              if (l.status != 'approved')
                Expanded(
                  child: ElevatedButton(
                    onPressed: _busy ? null : () => _decide('approved'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: const Text('승인'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            k,
            style: TextStyle(fontSize: 13, color: context.colors.textTertiary),
          ),
        ),
        Expanded(
          child: SelectableText(
            v,
            style: TextStyle(fontSize: 13.5, color: context.colors.textPrimary),
          ),
        ),
      ],
    ),
  );

  /// 비공개 버킷 서류 → signed URL 발급 후 외부 뷰어로 열람.
  Future<void> _openDoc(String path) async {
    final url = await StorageService.instance.businessDocSignedUrl(
      path,
      expiresIn: 300,
    );
    if (url == null) {
      _toast('서류 열람 링크 발급에 실패했어요');
      return;
    }
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _decide(String status) async {
    String? reason;
    if (status == 'rejected') {
      reason = await _askReason('반려 사유');
      if (reason == null || reason.trim().isEmpty) return;
    }
    setState(() => _busy = true);
    try {
      await AdminRepository.instance.reviewBusinessLicense(
        l.id,
        status,
        reason: reason,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast('처리에 실패했어요. 잠시 후 다시 시도해주세요');
    }
  }

  Future<String?> _askReason(String title) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(hintText: '신청자에게 전달·기록될 내용'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dCtx, ctrl.text),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }
}
