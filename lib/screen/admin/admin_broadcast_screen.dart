import 'package:flutter/material.dart';
import '../../theme/app_palette.dart';
import '../../services/admin_repository.dart';
import 'admin_theme.dart';

/// 전체 공지 발송 — 탈퇴자를 제외한 전 회원에게 system_notice 알림(인앱+푸시)을 보낸다.
/// 약관·처리방침 개정 고지(개정 7일 전, 불리 변경 30일 전) 채널로 사용.
class AdminBroadcastScreen extends StatefulWidget {
  const AdminBroadcastScreen({super.key});

  @override
  State<AdminBroadcastScreen> createState() => _AdminBroadcastScreenState();
}

class _AdminBroadcastScreenState extends State<AdminBroadcastScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  bool get _canSend =>
      !_sending &&
      _title.text.trim().isNotEmpty &&
      _body.text.trim().isNotEmpty;

  Future<void> _send() async {
    final title = _title.text.trim();
    final body = _body.text.trim();

    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: const Text('전체 공지 발송'),
        content: Text(
          '탈퇴자를 제외한 모든 회원에게 인앱 알림과 푸시가 발송됩니다. 발송 후 취소할 수 없어요.\n\n[$title]\n$body',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: const Text('발송'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _sending = true);
    try {
      final count = await AdminRepository.instance.broadcastSystemNotice(
        title,
        body,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('회원 $count명에게 공지를 발송했어요')));
      Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('발송에 실패했어요. 다시 시도해주세요')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: adminAppBar(context, '전체 공지 발송'),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.colors.adminAccentSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                '약관·개인정보 처리방침 개정은 시행 7일 전(이용자에게 불리하거나 중대한 '
                '변경은 30일 전)까지 고지해야 해요. 발송 내역은 감사 로그에 기록됩니다.',
                style: TextStyle(
                  fontSize: 13,
                  color: context.colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _title,
              maxLength: 80,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: '제목',
                hintText: '예: 개인정보 처리방침 개정 안내 (7/19 시행)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _body,
              maxLength: 1000,
              minLines: 6,
              maxLines: 12,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: '내용',
                hintText: '개정 사유·주요 변경 사항·시행일을 안내해주세요',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: context.colors.adminAccent,
                  foregroundColor: context.colors.adminOnAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _canSend ? _send : null,
                child: _sending
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Text(
                        '전체 회원에게 발송',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
