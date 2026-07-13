import 'package:flutter/material.dart';
import '../motion/motion.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_palette.dart';
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
  const FacilityDetailContent({
    super.key,
    required this.facility,
    required this.color,
    required this.label,
  });

  @override
  State<FacilityDetailContent> createState() => _FacilityDetailContentState();
}

class _FacilityDetailContentState extends State<FacilityDetailContent> {
  List<FacilityReview>? _reviews;
  List<String>? _categories; // 같은 업체의 겹치는 카테고리 전부(로드되면 헤더에 모두 표기)

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 겹치는 업종(병원+위탁 등)을 전부 표기하도록, 자기 카테고리 우선 + 나머지.
  List<String> get _displayCategories {
    final own = widget.facility.category;
    final loaded = _categories;
    if (loaded == null || loaded.isEmpty) return [own];
    return [own, ...loaded.where((c) => c != own)];
  }

  Future<void> _load() async {
    final fac = widget.facility;
    // 같은 업체의 전체 카테고리(DB 시설만; Naver 카페는 단일). 리뷰와 병렬로.
    if (!fac.isNaver) {
      FacilityRepository.instance.allCategories(fac.id).then((cats) {
        if (mounted && cats.isNotEmpty) setState(() => _categories = cats);
      });
    }
    try {
      final f = widget.facility;
      // 카페는 마커 id 가 가짜라, 승격된 실제 facility_id 를 해석(없으면 후기 0).
      final fid = f.isNaver
          ? await FacilityReviewRepository.instance.naverFacilityId(
              f.name,
              f.address,
            )
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('후기는 로그인 후 남길 수 있어요')));
      return;
    }
    FacilityReview? mine;
    for (final r in _reviews ?? const <FacilityReview>[]) {
      if (r.isMine) mine = r;
    }
    final ok = await Navigator.push<bool>(
      context,
      AppPageRoute(
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
      'nmap://place?lat=${f.lat}&lng=${f.lng}&name=$name&appname=com.seizeh.pawmate',
    );
    final web = Uri.parse(
      'https://map.naver.com/p/?c=${f.lng},${f.lat},17,0,0,0,dh',
    );
    try {
      if (await canLaunchUrl(app) &&
          await launchUrl(app, mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {
      /* 앱 없음 */
    }
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
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // 겹치는 업종 전부(예: 동물병원 · 위탁·호텔 · 미용) 칩으로 표기.
            for (final cat in _displayCategories)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  kFacilityLabels[cat] ?? cat,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: widget.color,
                  ),
                ),
              ),
            Text(
              dist,
              style: TextStyle(
                fontSize: 12,
                color: context.colors.textTertiary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          f.name,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: context.colors.textPrimary,
          ),
        ),
        if (evaluatePetSales(f) case final s?) ...[
          const SizedBox(height: 12),
          _PetSalesTrustCard(score: s),
        ],
        if (reviews != null && reviews.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.star, size: 16, color: Color(0xFFFFB300)),
              const SizedBox(width: 3),
              Text(
                _avg.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textPrimary,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '· 후기 ${reviews.length}',
                style: TextStyle(
                  fontSize: 12,
                  color: context.colors.textTertiary,
                ),
              ),
            ],
          ),
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
                  horizontal: 18,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: context.colors.primaryDark,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.rate_review_outlined,
                      size: 18,
                      color: Colors.white,
                    ),
                    SizedBox(width: 6),
                    Text(
                      '후기 쓰기',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _openInNaverMap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.colors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.map_outlined,
                      size: 18,
                      color: context.colors.textSecondary,
                    ),
                    SizedBox(width: 6),
                    Text(
                      '네이버',
                      style: TextStyle(color: context.colors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Divider(height: 1, color: context.colors.border),
        const SizedBox(height: 14),
        Text(
          '후기',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: context.colors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        if (reviews == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
          )
        else if (reviews.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text(
                '아직 후기가 없어요. 첫 후기를 남겨보세요!',
                style: TextStyle(color: context.colors.textTertiary),
              ),
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
      Icon(icon, size: 16, color: context.colors.textSecondary),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: TextStyle(
            fontSize: 14,
            color: context.colors.textSecondary,
            height: 1.4,
          ),
        ),
      ),
    ],
  );
}

/// 분양(반려동물판매업) 신뢰도 안내 카드.
/// 사업자 업종만 판매업으로 등록하고 실제론 분양과 무관한 업장이 섞여 있어,
/// 상호명 키워드 점수로 추정해 사용자에게 경고/안내한다(확정 아님).
class _PetSalesTrustCard extends StatelessWidget {
  final PetSalesScore score;
  const _PetSalesTrustCard({required this.score});

  @override
  Widget build(BuildContext context) {
    final (bg, fg, icon, title) = switch (score.level) {
      PetSalesTrust.likely => (
        const Color(0xFFE8F5E9),
        const Color(0xFF2E7D32),
        Icons.verified_outlined,
        '분양 전문점으로 보여요',
      ),
      PetSalesTrust.unclear => (
        const Color(0xFFFFF8E1),
        const Color(0xFFF57F17),
        Icons.help_outline,
        '분양 전문 여부가 불분명해요',
      ),
      PetSalesTrust.caution => (
        const Color(0xFFFFEBEE),
        const Color(0xFFC62828),
        Icons.warning_amber_rounded,
        '분양 전문점이 아닐 수 있어요',
      ),
    };
    final pts = score.score > 0 ? '+${score.score}' : '${score.score}';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: fg.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  '신뢰도 $pts',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            "사업자 업종은 '반려동물판매업'이지만, 상호명으로 추정한 점수예요. 실제 분양 여부는 직접 확인하세요.",
            style: TextStyle(
              fontSize: 12,
              color: context.colors.textSecondary,
              height: 1.4,
            ),
          ),
          if (score.positives.isNotEmpty || score.negatives.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final w in score.positives)
                  _kwChip('+$w', const Color(0xFF2E7D32)),
                for (final w in score.negatives)
                  _kwChip('-$w', const Color(0xFFC62828)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _kwChip(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
    ),
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
                child: Text(
                  review.authorNickname,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textPrimary,
                  ),
                ),
              ),
              if (review.isMine) ...[
                const SizedBox(width: 4),
                Text(
                  '(내 후기)',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.colors.primaryDark,
                  ),
                ),
              ],
              const Spacer(),
              Text(
                '${d.year}.${d.month}.${d.day}',
                style: TextStyle(
                  fontSize: 11,
                  color: context.colors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 1; i <= 5; i++)
                Icon(
                  i <= review.rating ? Icons.star : Icons.star_border,
                  size: 14,
                  color: i <= review.rating
                      ? const Color(0xFFFFB300)
                      : context.colors.border,
                ),
            ],
          ),
          if (review.content != null && review.content!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              review.content!,
              style: TextStyle(
                fontSize: 14,
                color: context.colors.textSecondary,
                height: 1.45,
              ),
            ),
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
                    child: Image.network(
                      url,
                      width: 84,
                      height: 84,
                      fit: BoxFit.cover,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
