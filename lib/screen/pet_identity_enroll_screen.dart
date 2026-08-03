import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:video_thumbnail/video_thumbnail.dart';

import '../services/pet_enroll_repository.dart';
import '../services/storage_service.dart';
import '../theme/app_palette.dart';
import '../utils/temp_file.dart';

/// 펫 신원 인증(0020) — 반려동물 영상 촬영 → 프레임 추출 → 서버 AI 검증(실물·동일개체).
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
  // 전 구간 분산 샘플링(앞 몰림 방지). 영상이 짧으면 마지막 프레임으로 클램프됨.
  // 정수 초 격자 고정 — Gemini 는 영상을 1fps 로 샘플링하므로, 어중간한 시각
  // (예: 800ms)의 프레임은 서버 frames_from_video 판정에서 "영상에 없는 장면"
  // 오탐을 만들 수 있다. 베타 측정(pmdb #135) 중에는 변경 금지(측정 오염).
  static const _frameTimesMs = [1000, 2000, 3000, 4000];

  bool _busy = false;
  String? _status;

  Future<void> _captureAndEnroll() async {
    XFile? video;
    try {
      video = await StorageService.instance.capturePetVideo();
    } catch (_) {
      _toast('카메라를 열 수 없어요. 카메라/마이크 권한을 확인하거나 실기기에서 시도해주세요');
      return;
    }
    if (video == null) return; // 취소
    if (!mounted) return; // 픽커 대기 중 라우트 제거 가능(#238)
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
        // 프레임 추출은 await 루프라 그 사이 라우트가 걷힐 수 있다. 바로 아래
        // 75행은 이미 가드하고 있는데 이 분기만 빠져 있었다(#238).
        if (!mounted) return;
        setState(() {
          _busy = false;
          _status = null;
        });
        _toast('영상이 너무 짧아요. 조금 더 길게(약 5초) 다시 촬영해주세요');
        return;
      }

      if (!mounted) return;
      setState(() => _status = '신원 인증 중… (영상 분석)');
      final videoBytes = await video.readAsBytes();
      final res = await PetEnrollRepository.instance.enroll(
        petId: widget.petId,
        videoBytes: videoBytes,
        videoMime: video.mimeType ?? 'video/mp4',
        frames: frames,
      );
      // 로컬 임시 영상 삭제(잔존 방지).
      await deleteTempFile(video.path);

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
        .map(
          (w) => w == 'species_kind'
              ? '종류(강아지/고양이)'
              : w == 'breed'
              ? '품종'
              : w,
        )
        .join(', ');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('등록정보 확인'),
        content: Text(
          '등록한 $labels 이(가) 영상과 달라 보여요.\n'
          '인증은 완료됐지만, 펫 정보가 정확한지 확인해 주세요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('확인'),
          ),
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
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('신원 인증')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${widget.petName}의 신원을 인증할게요',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: context.colors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '반려동물이 또렷이 보이게 약 5초 영상을 촬영해주세요. '
                '영상은 저장되지 않고 인증에만 사용돼요.',
                style: TextStyle(
                  fontSize: 13,
                  color: context.colors.textSecondary,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: context.colors.primarySoft.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '촬영 팁',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.colors.primaryDark,
                      ),
                    ),
                    SizedBox(height: 12),
                    _Tip('밝은 곳에서 얼굴과 몸이 잘 보이게'),
                    _Tip('한 마리만 화면에 담기'),
                    _Tip('천천히 각도를 조금씩 바꿔가며 촬영'),
                  ],
                ),
              ),
              const Spacer(),
              if (_busy) ...[
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    _status ?? '처리 중…',
                    style: TextStyle(
                      fontSize: 13,
                      color: context.colors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ] else
                FilledButton.icon(
                  onPressed: _captureAndEnroll,
                  style: FilledButton.styleFrom(
                    backgroundColor: context.colors.primaryDark,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: const Icon(Icons.videocam),
                  label: const Text(
                    '영상 촬영하기',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// 촬영 팁 한 줄(체크 아이콘 + 문구).
class _Tip extends StatelessWidget {
  final String text;
  const _Tip(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 16,
            color: context.colors.primaryDark,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: context.colors.textPrimary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
