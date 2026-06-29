import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_colors.dart';
import '../models/facility_review.dart';
import '../services/facility_repository.dart';
import '../services/facility_review_repository.dart';
import '../services/session.dart';
import '../screen/facility_review_screen.dart';

/// 시설 상세 화면을 연다(정보 + 후기/사진 + 후기 작성 + 네이버 지도 링크).
/// 모달이 아니라 전용 라우트로 띄운다 — 네이버 지도 플랫폼뷰 위에 스크롤 모달을
/// 겹치면 hit-test 레이아웃 충돌이 나기 때문.
Future<void> showFacilitySheet(
  BuildContext context,
  Facility facility, {
  required Color color,
  required String label,
}) {
  return Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) =>
          FacilityDetailScreen(facility: facility, color: color, label: label),
    ),
  );
}

class FacilityDetailScreen extends StatefulWidget {
  final Facility facility;
  final Color color;
  final String label;
  const FacilityDetailScreen(
      {super.key,
      required this.facility,
      required this.color,
      required this.label});

  @override
  State<FacilityDetailScreen> createState() => _FacilityDetailScreenState();
}

class _FacilityDetailScreenState extends State<FacilityDetailScreen> {
  List<FacilityReview>? _reviews;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await FacilityReviewRepository.instance
          .fetchReviews(widget.facility.id);
      if (mounted) setState(() => _reviews = r);
    } catch (_) {
      if (mounted) setState(() => _reviews = const []);
    }
  }

  double get _avg {
    final r = _reviews;
    if (r == null || r.isEmpty) return 0;
    return r.fold<int>(0, (s, e) => s + e.rating) / r.length;
  }

  Future<void> _writeReview() async {
    if (!SessionManager.instance.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('후기는 로그인 후 남길 수 있어요')),
      );
      return;
    }
    FacilityReview? mine;
    for (final r in _reviews ?? const <FacilityReview>[]) {
      if (r.isMine) mine = r;
    }
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => FacilityReviewScreen(
          facilityId: widget.facility.id,
          facilityName: widget.facility.name,
          existing: mine,
        ),
      ),
    );
    if (ok == true) _load();
  }

  Future<void> _openInNaverMap() async {
    final f = widget.facility;
    final name = Uri.encodeComponent(f.name);
    final app = Uri.parse(
        'nmap://place?lat=${f.lat}&lng=${f.lng}&name=$name&appname=com.example.pawmate');
    final web =
        Uri.parse('https://map.naver.com/p/?c=${f.lng},${f.lat},17,0,0,0,dh');
    try {
      if (await canLaunchUrl(app) &&
          await launchUrl(app, mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {/* 앱 없음 */}
    await launchUrl(web, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.facility;
    final dist = f.distanceM < 1000
        ? '${f.distanceM.round()}m'
        : '${(f.distanceM / 1000).toStringAsFixed(1)}km';
    final reviews = _reviews;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: Text(f.name, overflow: TextOverflow.ellipsis)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(widget.label,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: widget.color)),
                ),
                const Spacer(),
                Text(dist,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textTertiary)),
              ],
            ),
            const SizedBox(height: 10),
            Text(f.name,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            if (reviews != null && reviews.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.star, size: 16, color: Color(0xFFFFB300)),
                const SizedBox(width: 3),
                Text(_avg.toStringAsFixed(1),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const SizedBox(width: 4),
                Text('· 후기 ${reviews.length}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textTertiary)),
              ]),
            ],
            if (f.address != null && f.address!.isNotEmpty) ...[
              const SizedBox(height: 12),
              _row(Icons.place_outlined, f.address!),
            ],
            if (f.phone != null && f.phone!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _row(Icons.call_outlined, f.phone!),
            ],
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _writeReview,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryDark,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.rate_review_outlined, size: 18),
                  label: const Text('후기 쓰기',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _openInNaverMap,
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  side: const BorderSide(color: AppColors.border),
                ),
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text('네이버'),
              ),
            ]),
            const SizedBox(height: 18),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 14),
            const Text('후기',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 10),
            if (reviews == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child:
                    Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
              )
            else if (reviews.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text('아직 후기가 없어요. 첫 후기를 남겨보세요!',
                      style: TextStyle(color: AppColors.textTertiary)),
                ),
              )
            else
              for (final r in reviews) _ReviewItem(review: r),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String text) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textSecondary, height: 1.4)),
          ),
        ],
      );
}

class _ReviewItem extends StatelessWidget {
  final FacilityReview review;
  const _ReviewItem({required this.review});

  @override
  Widget build(BuildContext context) {
    final d = review.createdAt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(review.authorNickname,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              if (review.isMine) ...[
                const SizedBox(width: 4),
                const Text('(내 후기)',
                    style:
                        TextStyle(fontSize: 11, color: AppColors.primaryDark)),
              ],
              const Spacer(),
              Text('${d.year}.${d.month}.${d.day}',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textTertiary)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              for (var i = 1; i <= 5; i++)
                Icon(i <= review.rating ? Icons.star : Icons.star_border,
                    size: 14,
                    color: i <= review.rating
                        ? const Color(0xFFFFB300)
                        : AppColors.border),
            ],
          ),
          if (review.content != null && review.content!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(review.content!,
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textSecondary, height: 1.45)),
          ],
          if (review.photoUrls.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final url in review.photoUrls)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(url,
                        width: 84, height: 84, fit: BoxFit.cover),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
