import 'package:flutter/material.dart';
import '../theme/app_palette.dart';
import '../data/review_categories.dart';
import '../services/activity_repository.dart';

/// 평가 작성 — 완료된 약속의 상대에게 8개 카테고리 중 최대 4개 선택해 평가.
/// 상반되는 카테고리(예: 친절해요 ↔ 불친절해요)는 동시 선택 불가.
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
          content: Text('평가를 남겼어요'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('이미 평가했거나 평가할 수 없는 약속이에요'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('평가하기')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '${widget.revieweeNickname} 님은 어떠셨나요?',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '최대 ${ReviewCategories.maxSelectable}개까지 선택할 수 있어요 (${_selected.length}/${ReviewCategories.maxSelectable})',
              style: TextStyle(
                fontSize: 13,
                color: context.colors.textSecondary,
              ),
            ),
            const SizedBox(height: 24),
            _group(
              '이런 점이 좋았어요',
              ReviewCategories.positive,
              context.colors.success,
            ),
            const SizedBox(height: 24),
            _group(
              '이런 점이 아쉬웠어요',
              ReviewCategories.negative,
              context.colors.danger,
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: _selected.isEmpty || _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: context.colors.primaryDark,
              disabledBackgroundColor: context.colors.borderStrong,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
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
                : const Text(
                    '평가 남기기',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _group(String title, List<String> cats, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: context.colors.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: cats.map((c) {
            final selected = _selected.contains(c);
            final disabled = _isDisabled(c);
            return GestureDetector(
              onTap: disabled ? null : () => _toggle(c),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
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
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
