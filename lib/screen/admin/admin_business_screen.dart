import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/admin_repository.dart';
import '../../services/business_repository.dart' show businessCategoryLabel;
import '../../services/storage_service.dart';
import '../../theme/app_palette.dart';
import 'admin_theme.dart';

/// 업체 인증 심사 (0025 §6) — 신청 목록 · 매칭 근거 · 서류 열람 · 승인/반려.
/// 승인: track=auto 대기 건은 일반 승인, 그 외(review/new_business)는
/// 자동승인 조건 미달의 override 라 사유 필수(서버 검증과 동일 규칙).
class AdminBusinessScreen extends StatefulWidget {
  const AdminBusinessScreen({super.key});

  @override
  State<AdminBusinessScreen> createState() => _AdminBusinessScreenState();
}

class _AdminBusinessScreenState extends State<AdminBusinessScreen> {
  String? _status = 'pending';
  List<AdminBusinessApplication> _items = const [];
  bool _loading = true;

  static const _statusTabs = <(String?, String)>[
    ('pending', '대기'),
    ('approved', '승인'),
    ('rejected', '반려'),
    (null, '전체'),
  ];

  static const _trackLabels = {
    'auto': '자동승인 조건 충족',
    'review': '검토 필요',
    'new_business': '신규개업 (서류 심사)',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await AdminRepository.instance.listBusinessApplications(
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
      appBar: adminAppBar(context, '업체 인증 심사'),
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

  Widget _card(AdminBusinessApplication a) {
    final statusColor = switch (a.status) {
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
                a.businessName,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textPrimary,
                ),
              ),
            ),
            Text(
              switch (a.status) {
                'approved' => a.autoApproved ? '자동승인' : '승인',
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
            '${businessCategoryLabel(a.declaredCategory)} · ${_trackLabels[a.reviewTrack] ?? a.reviewTrack}'
            '${a.matchScore != null ? ' · ${a.matchScore}점' : ''} · @${a.nickname}',
            style: TextStyle(fontSize: 12, color: context.colors.textSecondary),
          ),
        ),
        trailing: Icon(Icons.chevron_right, color: context.colors.textTertiary),
        onTap: () => _openDetail(a),
      ),
    );
  }

  // ── 상세 + 심사 ──

  Future<void> _openDetail(AdminBusinessApplication a) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _DetailSheet(app: a),
    );
    if (changed == true) unawaited(_load());
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }
}

class _DetailSheet extends StatefulWidget {
  final AdminBusinessApplication app;
  const _DetailSheet({required this.app});

  @override
  State<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends State<_DetailSheet> {
  bool _busy = false;

  AdminBusinessApplication get a => widget.app;

  @override
  Widget build(BuildContext context) {
    final d = a.matchDetail;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        children: [
          Text(
            a.businessName,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          _row('신청자', '@${a.nickname}'),
          _row('사업자번호', a.businessRegNo),
          _row('업종(신고)', businessCategoryLabel(a.declaredCategory)),
          if ((a.storefrontName ?? '').isNotEmpty)
            _row('사업장명', a.storefrontName!),
          if ((a.prevBusinessName ?? '').isNotEmpty)
            _row('이전 상호', a.prevBusinessName!),
          _row('주소(도로명)', a.businessAddress),
          if ((a.businessAddressJibun ?? '').isNotEmpty)
            _row('주소(지번)', a.businessAddressJibun!),
          if ((a.businessPhone ?? '').isNotEmpty)
            _row('업장 전화', a.businessPhone!),
          if ((a.representativeName ?? '').isNotEmpty)
            _row('대표자', a.representativeName!),
          _row('이메일', a.contactEmail),
          const Divider(height: 28),
          Text(
            '공공데이터 대조',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: context.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          _row(
            '트랙 · 점수',
            '${a.reviewTrack}${a.matchScore != null ? ' · ${a.matchScore}점' : ''}',
          ),
          if (a.matchedFacilityName != null)
            _row('매칭 업소', a.matchedFacilityName!),
          if (d.isNotEmpty)
            _row(
              '신호',
              [
                '상호 ${((d['name_sim'] as num?) ?? 0).toStringAsFixed(2)}',
                if (d['phone_ok'] == true) '전화 일치',
                if (d['category_ok'] == true) '업종 일치',
                if (d['region_ok'] == true) '지역 일치',
                '후보 ${d['group_count'] ?? 0}곳',
              ].join(' · '),
            ),
          if (a.status == 'rejected' && (a.rejectedReason ?? '').isNotEmpty)
            _row('반려 사유', a.rejectedReason!),
          if ((a.reviewNote ?? '').isNotEmpty) _row('심사 메모', a.reviewNote!),
          const Divider(height: 28),
          OutlinedButton.icon(
            onPressed: () => _openDoc(a.licenseImagePath),
            icon: const Icon(Icons.description_outlined),
            label: const Text('사업자등록증 열람'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
            ),
          ),
          if (a.extraDocPath != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => _openDoc(a.extraDocPath!),
              icon: const Icon(Icons.attach_file),
              label: const Text('추가 서류 열람 (영업 등록증 등)'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
              ),
            ),
          ],
          const SizedBox(height: 20),
          // 상태 전이: pending → 승인/반려, approved → 승인 취소(반려), rejected → 승인
          Row(
            children: [
              if (a.status != 'rejected')
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => _decide('rejected'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.colors.danger,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: Text(a.status == 'approved' ? '승인 취소(반려)' : '반려'),
                  ),
                ),
              if (a.status == 'pending') const SizedBox(width: 10),
              if (a.status != 'approved')
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
          if (a.status == 'pending' && a.approveNeedsReason)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '이 건은 자동승인 조건 미달이라 승인 시 사유(override)가 기록돼요.',
                style: TextStyle(
                  fontSize: 12,
                  color: context.colors.textSecondary,
                ),
              ),
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
          width: 86,
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
    // 반려는 항상, 승인은 override(비 auto 트랙)일 때 사유 필수 — 서버 규칙과 동일.
    final needReason = status == 'rejected' || a.approveNeedsReason;
    String? reason;
    if (needReason) {
      reason = await _askReason(
        status == 'rejected' ? '반려 사유' : '승인 사유 (override 기록)',
      );
      if (reason == null || reason.trim().isEmpty) return;
    }
    if (!mounted) return; // 다이얼로그 대기 중 라우트 제거 가능(#239)
    setState(() => _busy = true);
    try {
      await AdminRepository.instance.setBusinessStatus(
        a.userId,
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

  Future<String?> _askReason(String title) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
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
    // 다이얼로그 전환이 끝난 뒤 컨트롤러 해제(#239 — 반복 열기 누수).
    Future.delayed(const Duration(seconds: 1), ctrl.dispose);
    return reason;
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }
}
