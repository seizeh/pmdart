import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import '../models/facility_review.dart';
import '../services/facility_repository.dart';
import '../services/facility_review_repository.dart';
import '../services/storage_service.dart';

/// 시설 후기 작성/수정 (0022). 갤러리 다중 사진 허용. 카페는 작성 시 승격.
/// 저장 성공 시 true 를 pop.
class FacilityReviewScreen extends StatefulWidget {
  final Facility facility;
  final FacilityReview? existing; // 있으면 수정
  const FacilityReviewScreen({
    super.key,
    required this.facility,
    this.existing,
  });

  @override
  State<FacilityReviewScreen> createState() => _FacilityReviewScreenState();
}

class _FacilityReviewScreenState extends State<FacilityReviewScreen> {
  late int _rating = widget.existing?.rating ?? 5;
  late final _contentCtrl = TextEditingController(
    text: widget.existing?.content ?? '',
  );
  late final List<String> _photos = [...?widget.existing?.photoUrls];
  bool _uploading = false;
  bool _submitting = false;

  static const _maxPhotos = 5;
  final _repo = FacilityReviewRepository.instance;

  @override
  void dispose() {
    _contentCtrl.dispose();
    super.dispose();
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(m), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _addPhotos() async {
    if (_photos.length >= _maxPhotos || _uploading) return;
    final files = await StorageService.instance.pickImages();
    if (files.isEmpty) return;
    setState(() => _uploading = true);
    try {
      for (final f in files) {
        if (_photos.length >= _maxPhotos) break;
        final up = await StorageService.instance.upload(
          f,
          category: 'facility_review',
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

  /// 후기를 매달 facility_id (카페는 승격해서 확보).
  Future<String> _resolveFacilityId() async {
    final f = widget.facility;
    if (!f.isNaver) return f.id;
    return _repo.ensureNaverFacility(
      name: f.name,
      address: f.address,
      phone: f.phone,
      lng: f.lng,
      lat: f.lat,
    );
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      final fid = await _resolveFacilityId();
      await _repo.addReview(
        facilityId: fid,
        rating: _rating,
        body: _contentCtrl.text,
        photoUrls: _photos,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      // 자기 업체 후기는 서버가 차단(own_facility) — 안내를 구분한다.
      _toast(
        e.toString().contains('own_facility')
            ? '내 업체에는 후기를 남길 수 없어요'
            : '후기 저장에 실패했어요',
      );
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('후기 삭제'),
        content: const Text('이 후기를 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _submitting = true);
    try {
      final fid = await _resolveFacilityId();
      await _repo.deleteMine(fid);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _toast('삭제에 실패했어요');
    }
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: Text(editing ? '후기 수정' : '후기 작성'),
        actions: [
          if (editing)
            IconButton(
              icon: Icon(Icons.delete_outline, color: context.colors.danger),
              onPressed: _submitting ? null : _delete,
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              widget.facility.name,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '별점',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (var i = 1; i <= 5; i++)
                  GestureDetector(
                    onTap: () => setState(() => _rating = i),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(
                        i <= _rating ? Icons.star : Icons.star_border,
                        size: 34,
                        color: i <= _rating
                            ? const Color(0xFFFFB300)
                            : context.colors.border,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              '후기',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _contentCtrl,
              minLines: 3,
              maxLines: 8,
              maxLength: 1000,
              decoration: InputDecoration(
                hintText: '시설에 대한 후기를 남겨주세요',
                filled: true,
                fillColor: context.colors.surfaceMuted,
                contentPadding: const EdgeInsets.all(14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: context.colors.border),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '사진 (${_photos.length}/$_maxPhotos)',
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
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: context.colors.primaryDark,
                foregroundColor: context.colors.textOnPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      editing ? '수정하기' : '등록하기',
                      style: const TextStyle(
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
