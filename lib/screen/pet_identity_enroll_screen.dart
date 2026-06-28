import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:video_thumbnail/video_thumbnail.dart';

import '../theme/app_colors.dart';
import '../services/pet_enroll_repository.dart';
import '../services/storage_service.dart';

/// 펫 신원 인증(0020) — 무작위 동작 임무 영상 촬영 → 프레임 추출 → 서버 AI 검증.
///
/// 원본 영상은 검증용으로만 전송되고 저장되지 않는다(프레임 N장만 기준으로 저장).
/// 성공 시 Navigator.pop(context, true).
class PetIdentityEnrollScreen extends StatefulWidget {
  final String petId;
  final String petName;
  const PetIdentityEnrollScreen({
    super.key,
    required this.petId,
    required this.petName,
  });

  @override
  State<PetIdentityEnrollScreen> createState() =>
      _PetIdentityEnrollScreenState();
}

class _PetIdentityEnrollScreenState extends State<PetIdentityEnrollScreen> {
  // 11초 전 구간 분산 샘플링(앞 몰림 방지). 영상이 짧으면 마지막 프레임으로 클램프됨.
  static const _frameTimesMs = [1500, 4500, 7500, 10000];

  List<PetChallenge> _challenges = pickRandomChallenges();
  bool _busy = false;
  String? _status;

  void _reshuffle() => setState(() => _challenges = pickRandomChallenges());

  Future<void> _captureAndEnroll() async {
    XFile? video;
    try {
      video = await StorageService.instance.capturePetVideo();
    } catch (_) {
      _toast('카메라를 열 수 없어요. 카메라/마이크 권한을 확인하거나 실기기에서 시도해주세요');
      return;
    }
    if (video == null) return; // 취소
    setState(() {
      _busy = true;
      _status = '프레임 추출 중…';
    });
    try {
      final frames = <Uint8List>[];
      for (final t in _frameTimesMs) {
        final data = await VideoThumbnail.thumbnailData(
          video: video.path,
          imageFormat: ImageFormat.JPEG,
          timeMs: t,
          maxWidth: 1024,
          quality: 85,
        );
        if (data != null) frames.add(data);
      }
      if (frames.length < 3) {
        setState(() {
          _busy = false;
          _status = null;
        });
        _toast('영상이 너무 짧아요. 임무를 천천히 수행하며 다시 촬영해주세요');
        return;
      }

      if (!mounted) return;
      setState(() => _status = '신원 인증 중… (영상 분석)');
      final videoBytes = await File(video.path).readAsBytes();
      final res = await PetEnrollRepository.instance.enroll(
        petId: widget.petId,
        challenge: [for (final c in _challenges) c.code],
        videoBytes: videoBytes,
        videoMime: video.mimeType ?? 'video/mp4',
        frames: frames,
      );
      // 로컬 임시 영상 삭제(잔존 방지).
      try {
        await File(video.path).delete();
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = null;
      });

      if (res.enrolled) {
        if (res.warnings.isNotEmpty) {
          await _showWarningDialog(res.warnings);
        }
        if (!mounted) return;
        Navigator.pop(context, true);
        return;
      }
      // 실패 — 임무 미수행이면 임무를 새로 뽑아 재시도 유도
      if (res.errorCode == 'challenge_failed') _reshuffle();
      _toast(res.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = null;
      });
      _toast('영상 처리에 실패했어요. 다시 시도해주세요');
    }
  }

  Future<void> _showWarningDialog(List<String> warnings) async {
    final labels = warnings
        .map((w) => w == 'species_kind' ? '종류(강아지/고양이)' : w == 'breed' ? '품종' : w)
        .join(', ');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('등록정보 확인'),
        content: Text('등록한 $labels 이(가) 영상과 달라 보여요.\n'
            '인증은 완료됐지만, 펫 정보가 정확한지 확인해 주세요.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('확인')),
        ],
      ),
    );
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('신원 인증')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${widget.petName}의 신원을 인증할게요',
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              const Text(
                '아래 동작을 하며 약 11초 영상을 촬영해주세요. 무작위로 주어지는 동작이라 '
                '미리 찍어둔 영상으로는 인증되지 않아요. 영상은 저장되지 않고 인증에만 사용돼요.',
                style: TextStyle(
                    fontSize: 13, color: AppColors.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('오늘의 동작 임무',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primaryDark)),
                    const SizedBox(height: 12),
                    for (var i = 0; i < _challenges.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 12,
                              backgroundColor: AppColors.primary,
                              child: Text('${i + 1}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white)),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(_challenges[i].label,
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary)),
                            ),
                          ],
                        ),
                      ),
                    if (!_busy)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _reshuffle,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('다른 동작'),
                        ),
                      ),
                  ],
                ),
              ),
              const Spacer(),
              if (_busy) ...[
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 12),
                Center(
                  child: Text(_status ?? '처리 중…',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                ),
                const SizedBox(height: 12),
              ] else
                FilledButton.icon(
                  onPressed: _captureAndEnroll,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryDark,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: const Icon(Icons.videocam),
                  label: const Text('영상 촬영하기',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
