import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:share_plus/share_plus.dart';

import '../services/care_report_repository.dart';
import '../services/storage_service.dart';
import '../theme/app_palette.dart';
import '../utils/share_links.dart';

/// 케어 리포트(전후 사진) 발행 (0028 P1) — 미용 완료 사진을 보호자에게 링크로.
/// 사진 1~4장 + 아이 이름 + 메모(선택) + 전화번호(선택 — 넣으면 손님 가입 시
/// 자동 연결). 발행 성공 시 공유 시트(카톡 등 시스템 공유 + 링크 복사).
class CareReportSendScreen extends StatefulWidget {
  const CareReportSendScreen({super.key});

  @override
  State<CareReportSendScreen> createState() => _CareReportSendScreenState();
}

class _CareReportSendScreenState extends State<CareReportSendScreen> {
  final _petCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final List<String> _photos = [];
  bool _uploading = false;
  bool _submitting = false;

  static const _maxPhotos = 4;

  @override
  void dispose() {
    _petCtrl.dispose();
    _noteCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), behavior: SnackBarBehavior.floating),
    );
  }

  bool get _canSubmit =>
      !_submitting &&
      !_uploading &&
      _photos.isNotEmpty &&
      _petCtrl.text.trim().isNotEmpty;

  Future<void> _addPhotos() async {
    if (_photos.length >= _maxPhotos || _uploading) return;
    final files = await StorageService.instance.pickImages();
    if (files.isEmpty) return;
    if (!mounted) return; // 픽커 대기 중 라우트 제거 가능(#238)
    setState(() => _uploading = true);
    try {
      for (final f in files) {
        if (_photos.length >= _maxPhotos) break;
        final up = await StorageService.instance.upload(
          f,
          category: 'care_report',
        );
        _photos.add(up.url);
      }
      if (mounted) setState(() {});
    } catch (_) {
      _toast('사진 업로드에 실패했어요');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    final res = await CareReportRepository.instance.create(
      petLabel: _petCtrl.text,
      photoUrls: _photos,
      note: _noteCtrl.text,
      recipientPhone: _phoneCtrl.text,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    final token = res.token;
    if (token == null) {
      _toast(switch (res.error) {
        'license_required' => '동물미용업 인증 후 사용할 수 있어요',
        'invalid_phone' => '전화번호 형식을 확인해 주세요',
        'invalid_pet_label' => '아이 이름을 확인해 주세요',
        _ => '발행에 실패했어요. 잠시 후 다시 시도해주세요',
      });
      return;
    }
    // 발행 성공 — 공유 시트를 띄우고, 닫히면 화면도 닫는다(목록 갱신은 pop true).
    // 시트를 공유 없이 닫아도 "발행은 됐다"가 명확하도록 토스트로 한 번 더 확인
    // (피드백이 없으면 사장님이 불안해서 재발행 → 중복 링크 사고, 실기기 확인).
    await showCareReportShareSheet(
      context,
      petLabel: _petCtrl.text.trim(),
      token: token,
      justIssued: true,
    );
    _toast('발행되었어요 — 보낸 기록에서 언제든 다시 공유할 수 있어요');
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('전후 사진 보내기')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '미용 완료 사진을 보호자에게 링크로 보내드려요. '
              '보호자는 앱 설치 없이 바로 볼 수 있어요.',
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '사진 (${_photos.length}/$_maxPhotos) — 전/후 순서로 담아주세요',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _photos.length; i++)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          _photos[i],
                          width: 92,
                          height: 92,
                          fit: BoxFit.cover,
                        ),
                      ),
                      if (_photos.length >= 2 && i < 2)
                        Positioned(
                          left: 6,
                          top: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              i == 0 ? '전' : '후',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
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
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                if (_photos.length < _maxPhotos)
                  GestureDetector(
                    onTap: _addPhotos,
                    child: Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        color: context.colors.surfaceMuted,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.colors.border),
                      ),
                      child: _uploading
                          ? const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : Icon(
                              Icons.add_a_photo_outlined,
                              color: context.colors.textTertiary,
                            ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _petCtrl,
              onChanged: (_) => setState(() {}),
              maxLength: 50,
              decoration: const InputDecoration(
                labelText: '아이 이름',
                hintText: '예: 초코',
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteCtrl,
              maxLines: 3,
              maxLength: 300,
              decoration: const InputDecoration(
                labelText: '메모 (선택)',
                hintText: '예: 오늘 컷 예쁘게 잘 됐어요!',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: '보호자 전화번호 (선택)',
                hintText: '010-0000-0000',
                helperText: '번호를 넣으면 보호자가 가입할 때 이 기록이 자동으로 연결돼요.',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _canSubmit ? _submit : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: context.colors.primaryDark,
                foregroundColor: context.colors.textOnPrimary,
                minimumSize: const Size.fromHeight(50),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      '발행하고 공유하기',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 공유 시트 — 발행 직후([justIssued])·보낸 기록 재전송 공용.
/// 전송 주체는 업체 폰(카톡·문자 등 시스템 공유), 앱은 링크만 만든다(0028 §4.1).
Future<void> showCareReportShareSheet(
  BuildContext context, {
  required String petLabel,
  required String token,
  bool justIssued = false,
}) {
  final url = shareViewUrl(token);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetCtx) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            // 발행 직후엔 '완료' 상태를 명시 — 시트를 그냥 닫아도 재발행하지 않게.
            justIssued
                ? '✓ 발행 완료 — $petLabel 사진을 보내주세요'
                : '$petLabel 사진 링크가 준비됐어요',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: sheetCtx.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '카톡이나 문자로 보호자에게 보내주세요. 링크는 30일간 유효해요.',
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: sheetCtx.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          SelectableText(
            url,
            style: TextStyle(fontSize: 12, color: sheetCtx.colors.textTertiary),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => SharePlus.instance.share(
              ShareParams(text: '$petLabel의 오늘 미용 사진이에요 🐾\n$url'),
            ),
            icon: const Icon(Icons.ios_share, size: 18),
            label: const Text('카톡·문자로 공유하기'),
            style: ElevatedButton.styleFrom(
              backgroundColor: sheetCtx.colors.primaryDark,
              foregroundColor: sheetCtx.colors.textOnPrimary,
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (sheetCtx.mounted) {
                ScaffoldMessenger.of(sheetCtx).showSnackBar(
                  const SnackBar(
                    content: Text('링크를 복사했어요'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('링크 복사'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ],
      ),
    ),
  );
}
