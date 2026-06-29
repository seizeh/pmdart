import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_colors.dart';
import '../models/facility_review.dart';
import '../services/facility_repository.dart';
import '../services/facility_review_repository.dart';
import '../services/session.dart';
import '../screen/facility_review_screen.dart';

/// 시설 상세 콘텐츠(정보 + 후기/사진 + 후기 작성 + 네이버 지도 링크).
///
/// `MapTab.showSheetOverMap` 이 지도를 스냅샷으로 얼린 뒤 [MapBottomSheet] 안에 이
/// 콘텐츠를 올린다(살아있는 PlatformView 위에 모달을 겹치지 않으려고, pmdart #28).
/// 시트가 프레임(손잡이·스크림·드래그 닫기·폭 고정 Align>SizedBox)을 제공하므로 여기선
/// 본문 ListView 만 반환한다. ⚠️ 무한 너비에서 죽는 위젯 금지(머티리얼 버튼/Spacer/Expanded
/// 대신 Container 탭/Text).
class FacilityDetailContent extends StatefulWidget {
  final Facility facility;
  final Color color;
  final String label;
  const FacilityDetailContent(
      {super.key,
      required this.facility,
      required this.color,
      required this.label});

  @override
  State<FacilityDetailContent> createState() => _FacilityDetailContentState();
}

class _FacilityDetailContentState extends State<FacilityDetailContent> {
  List<FacilityReview>? _reviews;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final f = widget.facility;
      // 카페는 마커 id 가 가짜라, 승격된 실제 facility_id 를 해석(없으면 후기 0).
      final fid = f.isNaver
          ? await FacilityReviewRepository.instance
              .naverFacilityId(f.name, f.address)
          : f.id;
      final r = fid == null
          ? const <FacilityReview>[]
          : await FacilityReviewRepository.instance.fetchReviews(fid);
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
        builder: (_) =>
            FacilityReviewScreen(facility: widget.facility, existing: mine),
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
    // 폭은 MapBottomSheet 가 Align>SizedBox 로 고정해 준다. 여기선 본문 ListView 만.
    // 무한 너비에서 죽는 위젯 금지(Container 탭/Text 만).
    return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
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
                    const SizedBox(width: 8),
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
                // 머티리얼 버튼은 무한 너비에서 maximumSize(∞)로 채우려다 터진다(이
                // 화면 본문은 너비 제약이 깨져 무한이 들어옴, #28). Container 는 intrinsic
                // 크기라 무한에서도 안전 → GestureDetector+Container 로 버튼을 구성.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: _writeReview,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.primaryDark,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.rate_review_outlined,
                              size: 18, color: Colors.white),
                          SizedBox(width: 6),
                          Text('후기 쓰기',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _openInNaverMap,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.map_outlined,
                              size: 18, color: AppColors.textSecondary),
                          SizedBox(width: 6),
                          Text('네이버',
                              style: TextStyle(color: AppColors.textSecondary)),
                        ]),
                      ),
                    ),
                  ],
                ),
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
                    child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2.4)),
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
    );
  }

  // 시트 본문은 폭이 유한(스냅샷 위)이라 Expanded 로 긴 주소를 줄바꿈해도 안전.
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
              // 긴 닉네임이 가로로 넘치지 않게 Flexible + ellipsis(폭 유한이라 안전).
              Flexible(
                child: Text(review.authorNickname,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ),
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
            mainAxisSize: MainAxisSize.min,
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
