import 'package:flutter/material.dart';

import '../data/review_categories.dart';
import '../models/community.dart' show kPostImageAspectRatio;
import '../motion/motion.dart';
import '../services/activity_repository.dart';
import '../services/session.dart';
import '../theme/app_palette.dart';
import '../widgets/blob_background.dart';

/// 평가 작성 — 완료된 약속의 상대에게 8개 카테고리 중 최대 4개 선택해 평가.
/// 상반되는 카테고리(예: 친절해요 ↔ 불친절해요)는 동시 선택 불가.
///
/// UI 문법은 게시글 작성(post_create_screen)과 동일하다: 상단의 편집형
/// 미리보기 카드(블롭 배경 + 하단 정보)가 결과를 그대로 보여주고, 아래
/// 섹션에서 값을 고른다. 제출은 앱바 우측 '등록'.
class ReviewWriteScreen extends StatefulWidget {
  final String appointmentId;
  final String revieweeId;
  final String revieweeNickname;
  const ReviewWriteScreen({
    super.key,
    required this.appointmentId,
    required this.revieweeId,
    required this.revieweeNickname,
  });

  @override
  State<ReviewWriteScreen> createState() => _ReviewWriteScreenState();
}

class _ReviewWriteScreenState extends State<ReviewWriteScreen> {
  final _selected = <String>{};
  bool _submitting = false;

  /// 상반 카테고리가 이미 선택돼 있으면 비활성(선택 불가).
  bool _isDisabled(String c) {
    if (_selected.contains(c)) return false;
    final opp = ReviewCategories.opposite[c];
    if (opp != null && _selected.contains(opp)) return true;
    // 최대 개수 도달 시 미선택 항목 비활성
    return _selected.length >= ReviewCategories.maxSelectable;
  }

  void _toggle(String c) {
    setState(() {
      if (_selected.contains(c)) {
        _selected.remove(c);
      } else if (!_isDisabled(c)) {
        _selected.add(c);
      }
    });
  }

  bool get _canSubmit => _selected.isNotEmpty && !_submitting;

  Future<void> _submit() async {
    if (_selected.isEmpty) return;
    setState(() => _submitting = true);
    try {
      await ActivityRepository.instance.submitReview(
        appointmentId: widget.appointmentId,
        revieweeId: widget.revieweeId,
        categories: _selected.toList(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('후기를 남겼어요'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('이미 후기를 남겼거나 남길 수 없는 약속이에요'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() => _submitting = false);
    }
  }

  /// 카테고리 색 — 긍정/부정 두 갈래(선택 알약·미리보기 공용).
  Color _catColor(String c) => ReviewCategories.isPositive(c)
      ? context.colors.success
      : context.colors.danger;

  /// 미리보기 배경 톤 — 고른 후기의 성격을 색으로 요약(빈 상태는 브랜드 색).
  Color get _moodColor {
    if (_selected.isEmpty) return context.colors.primary;
    final hasPositive = _selected.any(ReviewCategories.isPositive);
    final hasNegative = _selected.any((c) => !ReviewCategories.isPositive(c));
    if (hasPositive && !hasNegative) return context.colors.success;
    if (hasNegative && !hasPositive) return context.colors.danger;
    return context.colors.primary;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: const Text('후기 남기기'),
        actions: [
          TextButton(
            onPressed: _canSubmit ? _submit : null,
            child: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    '등록',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 미리보기 = 편집 캔버스. 고른 후기가 카드 위에 바로 얹히고,
              // 카드 위 알약을 탭하면 그 자리에서 해제된다.
              const _SectionLabel('미리보기'),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  '상대에게 이렇게 전달돼요 — 카드의 알약을 탭하면 빼요',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
              _editableCard(),
              const SizedBox(height: 24),
              _group('이런 점이 좋았어요', ReviewCategories.positive),
              const SizedBox(height: 20),
              _group('이런 점이 아쉬웠어요', ReviewCategories.negative),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // ── 편집형 미리보기 카드 — 게시글 작성 카드와 같은 시각 문법
  //    (블롭 배경 + 하단 스크림 + 흰 필름 알약 + 하단 정보 줄).
  Widget _editableCard() {
    final me = SessionManager.instance.user;
    final selected = _selected.toList();

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.colors.border, width: 0.5),
      ),
      child: AspectRatio(
        aspectRatio: kPostImageAspectRatio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 배경 — 고른 후기의 성격을 담은 블롭(상대마다 고정 패턴).
            BlobBackground(
              seed: 'review/${widget.revieweeId}',
              color: _moodColor,
            ),
            // 히어로 — 고른 후기 알약들(비었으면 안내 문구).
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 150),
                child: Center(
                  child: selected.isEmpty
                      ? Text(
                          '아래에서 어떠셨는지 골라주세요',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: context.colors.textTertiary,
                            height: 1.6,
                          ),
                        )
                      : SingleChildScrollView(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: [
                              for (final (i, c) in selected.indexed)
                                Entrance(
                                  index: i,
                                  offsetY: 12,
                                  fromScale: 0.85,
                                  child: Pressable(
                                    scaleTo: 0.9,
                                    borderRadius: BorderRadius.circular(100),
                                    onTap: () => _toggle(c),
                                    child: _previewPill(
                                      text: c,
                                      textColor: _catColor(c),
                                      trailing: Icons.close,
                                      large: true,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
            // 가독용 스크림(피드·게시글 작성과 동일).
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 210,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0x73000000)],
                  ),
                ),
              ),
            ),
            // 하단 정보 — 선택 개수 알약 / 대상 / 작성자.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        // 개수가 바뀔 때마다 알약이 살짝 튀며 안착 — 선택 피드백.
                        KeyedSubtree(
                          key: ValueKey('count-${_selected.length}'),
                          child: Entrance(
                            index: 0,
                            offsetY: 6,
                            fromScale: 0.8,
                            child: _previewPill(
                              text:
                                  '${_selected.length}/${ReviewCategories.maxSelectable} 선택',
                              textColor: _moodColor,
                            ),
                          ),
                        ),
                        const Spacer(),
                        const Text(
                          '방금 전',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xCCFFFFFF),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${widget.revieweeNickname} 님과의 만남',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      selected.isEmpty
                          ? '고른 후기가 여기에 표시돼요'
                          : selected.join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: selected.isEmpty
                            ? const Color(0x99FFFFFF)
                            : const Color(0xE0FFFFFF),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          me?.nickname ?? '',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xE6FFFFFF),
                          ),
                        ),
                        const Spacer(),
                        const Icon(
                          Icons.star_rounded,
                          size: 16,
                          color: Color(0xCCFFFFFF),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 흰 필름 알약 — 게시글 작성 카드의 카테고리 태그와 동일 문법.
  Widget _previewPill({
    required String text,
    required Color textColor,
    IconData? trailing,
    bool large = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 14 : 10,
        vertical: large ? 8 : 4,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: large ? 14 : 11,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
          if (trailing != null) ...[
            SizedBox(width: large ? 4 : 2),
            Icon(trailing, size: large ? 15 : 13, color: textColor),
          ],
        ],
      ),
    );
  }

  /// 선택 섹션 — 게시글 작성의 아래 섹션과 같은 라벨/알약 문법.
  Widget _group(String title, List<String> cats) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(title),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final (i, c) in cats.indexed)
              Entrance(
                index: i,
                offsetY: 10,
                fromScale: 0.9,
                child: Pressable(
                  scaleTo: 0.92,
                  borderRadius: BorderRadius.circular(100),
                  onTap: _isDisabled(c) ? null : () => _toggle(c),
                  child: _optionPill(c),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _optionPill(String c) {
    final selected = _selected.contains(c);
    final disabled = _isDisabled(c);
    final accent = _catColor(c);
    return AnimatedContainer(
      duration: MotionDurations.base,
      curve: SpringCurve.standard,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? accent : context.colors.surface,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: selected
              ? accent
              : (disabled
                    ? context.colors.border
                    : context.colors.borderStrong),
        ),
      ),
      child: Text(
        c,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: selected
              ? Colors.white
              : (disabled
                    ? context.colors.textTertiary
                    : context.colors.textPrimary),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: context.colors.textPrimary,
        ),
      ),
    );
  }
}
