import 'package:flutter/material.dart';

import '../services/report_repository.dart';
import '../theme/app_palette.dart';

/// 신고 바텀시트를 띄운다. 접수 성공 시 true 를 반환한다.
///
/// [targetType] 은 ReportRepository.target* 상수 중 하나,
/// [targetTitle] 은 헤더에 보여줄 대상 이름(예: 게시글 제목, 닉네임).
///
/// [authorId] 를 주면 '이 사용자도 차단' 체크박스가 함께 나온다. 신고만 하면
/// 상대 글이 계속 보여 "신고했는데 왜 그대로지?" 가 되기 때문 — 다만 신고가
/// **자동 차단이 되지는 않는다**(오신고로 관계가 끊기면 되돌리기 번거롭다).
/// [targetType] 이 user 면 targetId 가 곧 작성자라 따로 줄 필요가 없다.
Future<bool> showReportSheet(
  BuildContext context, {
  required String targetType,
  required String targetId,
  required String targetLabel,
  required String targetTitle,
  String? authorId,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _ReportSheet(
      targetType: targetType,
      targetId: targetId,
      targetLabel: targetLabel,
      targetTitle: targetTitle,
      authorId:
          authorId ??
          (targetType == ReportRepository.targetUser ? targetId : null),
    ),
  );
  return ok ?? false;
}

class _ReportSheet extends StatefulWidget {
  final String targetType;
  final String targetId;
  final String targetLabel;
  final String targetTitle;

  /// 차단 대상(작성자). null 이면 체크박스를 아예 노출하지 않는다.
  final String? authorId;
  const _ReportSheet({
    required this.targetType,
    required this.targetId,
    required this.targetLabel,
    required this.targetTitle,
    this.authorId,
  });

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final _selected = <String>{};
  final _descCtrl = TextEditingController();
  bool _submitting = false;

  /// 기본 해제 — 차단은 되돌리는 데 손이 가므로 사용자가 직접 고르게 한다.
  bool _alsoBlock = false;

  bool get _etcSelected => _selected.any(ReportRepository.isEtc);
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
      // 차단은 신고가 접수된 뒤에만. 실패해도 신고는 이미 접수됐으므로
      // 시트는 성공으로 닫고(중복 신고 오류 방지) 안내만 남긴다.
      var blocked = false;
      if (_alsoBlock && widget.authorId != null) {
        try {
          await ReportRepository.instance.block(widget.authorId!);
          blocked = true;
        } catch (e) {
          debugPrint('report+block: 차단 실패 — $e');
        }
      }
      if (!mounted) return;
      Navigator.pop(context, true);
      if (_alsoBlock && !blocked) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('신고는 접수됐지만 차단에 실패했어요. 프로필에서 다시 시도해주세요'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
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
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
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
                    color: context.colors.border,
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '${widget.targetLabel} 신고',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.targetTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: context.colors.textTertiary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '신고 사유 (중복 선택 가능)',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ReportRepository.categoriesFor(widget.targetType).map(
                  (c) {
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
                          horizontal: 14,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: on
                              ? context.colors.primaryDark
                              : context.colors.surfaceMuted,
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(
                            color: on
                                ? context.colors.primaryDark
                                : context.colors.border,
                          ),
                        ),
                        child: Text(
                          c,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: on
                                ? context.colors.textOnPrimary
                                : context.colors.textSecondary,
                          ),
                        ),
                      ),
                    );
                  },
                ).toList(),
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
                  fillColor: context.colors.surfaceMuted,
                  contentPadding: const EdgeInsets.all(14),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: context.colors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: context.colors.primary,
                      width: 1.2,
                    ),
                  ),
                ),
              ),
              // 차단 동시 선택 — 작성자를 알 때만. 신고는 운영자에게 알리는 것이고
              // 차단은 내 화면에서 치우는 것이라 역할이 다르므로 기본은 해제다.
              if (widget.authorId != null) ...[
                const SizedBox(height: 4),
                InkWell(
                  onTap: _submitting
                      ? null
                      : () => setState(() => _alsoBlock = !_alsoBlock),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Checkbox(
                          value: _alsoBlock,
                          onChanged: _submitting
                              ? null
                              : (v) => setState(() => _alsoBlock = v ?? false),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '이 사용자도 차단하기',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: context.colors.textPrimary,
                                ),
                              ),
                              Text(
                                '이 사용자의 게시글이 목록에서 바로 사라져요. '
                                '내정보 > 차단 사용자 관리에서 해제할 수 있어요.',
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.4,
                                  color: context.colors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 4),
              ElevatedButton(
                onPressed: _canSubmit ? _submit : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.danger,
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
                    : const Text(
                        '신고하기',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
