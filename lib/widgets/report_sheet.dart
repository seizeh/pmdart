import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../services/report_repository.dart';

/// 신고 바텀시트를 띄운다. 접수 성공 시 true 를 반환한다.
///
/// [targetType] 은 ReportRepository.target* 상수 중 하나,
/// [targetTitle] 은 헤더에 보여줄 대상 이름(예: 게시글 제목, 닉네임).
Future<bool> showReportSheet(
  BuildContext context, {
  required String targetType,
  required String targetId,
  required String targetLabel,
  required String targetTitle,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _ReportSheet(
      targetType: targetType,
      targetId: targetId,
      targetLabel: targetLabel,
      targetTitle: targetTitle,
    ),
  );
  return ok ?? false;
}

class _ReportSheet extends StatefulWidget {
  final String targetType;
  final String targetId;
  final String targetLabel;
  final String targetTitle;
  const _ReportSheet({
    required this.targetType,
    required this.targetId,
    required this.targetLabel,
    required this.targetTitle,
  });

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final _selected = <String>{};
  final _descCtrl = TextEditingController();
  bool _submitting = false;

  bool get _etcSelected =>
      _selected.contains(ReportRepository.categoryEtc);
  bool get _canSubmit =>
      !_submitting &&
      _selected.isNotEmpty &&
      (!_etcSelected || _descCtrl.text.trim().isNotEmpty);

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      await ReportRepository.instance.submit(
        targetType: widget.targetType,
        targetId: widget.targetId,
        selectedCategories: _selected.toList(),
        extraDescription: _descCtrl.text,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      // 중복 신고 등 안내 가능한 사유는 그 메시지를, 그 외엔 일반 안내를 보여준다.
      final msg = (e is StateError)
          ? e.message
          : (e is ArgumentError)
              ? e.message.toString()
              : '신고 접수에 실패했어요. 잠시 후 다시 시도해주세요';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '${widget.targetLabel} 신고',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.targetTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textTertiary,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '신고 사유 (중복 선택 가능)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ReportRepository.categories.map((c) {
                  final on = _selected.contains(c);
                  return GestureDetector(
                    onTap: () => setState(() {
                      if (on) {
                        _selected.remove(c);
                      } else {
                        _selected.add(c);
                      }
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: on ? AppColors.primaryDark : AppColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(
                          color: on ? AppColors.primaryDark : AppColors.border,
                        ),
                      ),
                      child: Text(
                        c,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: on
                              ? AppColors.textOnPrimary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _descCtrl,
                onChanged: (_) => setState(() {}),
                minLines: 2,
                maxLines: 5,
                maxLength: 500,
                decoration: InputDecoration(
                  hintText: _etcSelected
                      ? "'기타' 사유를 자세히 적어주세요 (필수)"
                      : '상세 내용을 적어주세요 (선택)',
                  filled: true,
                  fillColor: AppColors.surfaceMuted,
                  contentPadding: const EdgeInsets.all(14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:
                        const BorderSide(color: AppColors.primary, width: 1.2),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              ElevatedButton(
                onPressed: _canSubmit ? _submit : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  foregroundColor: AppColors.textOnPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('신고하기',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
