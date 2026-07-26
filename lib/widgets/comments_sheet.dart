import 'package:flutter/material.dart';

import '../services/keyboard_barrier.dart';
import '../theme/app_palette.dart';

/// 댓글 바텀시트 열기 — 전역 키보드 배리어를 시트가 열려 있는 동안 끈다.
/// 배리어가 켜져 있으면 키보드가 뜬 상태의 첫 탭(전송 버튼 포함)을 흡수해
/// "한 번 닫혀야 눌리는" 문제가 생긴다. 리스트 탭으로 키보드 닫기는
/// [CommentsSheetShell] 내부에서 처리하고, 닫힐 때 배리어 복구 + 포커스 해제.
Future<T?> showCommentsSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  keyboardBarrierEnabled.value = false;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: builder,
  ).whenComplete(() {
    keyboardBarrierEnabled.value = true;
    FocusManager.instance.primaryFocus?.unfocus();
  });
}

/// 댓글 바텀시트 공용 셸 — 그랩바·카운트 헤더 + 댓글 리스트(드래그 확장) +
/// 하단 입력바. 게시글 상세와 시설 후기 상세가 공유한다.
///
/// - [listenable] 이 갱신되면 헤더 카운트·리스트·전송 스피너를 다시 그린다.
/// - 입력 포커스 중에는 시트 확장/축소 드래그를 잠근다(작성 중 오작동 방지).
/// - 리스트 빈 곳 탭 → 키보드 닫기(전역 배리어는 [showCommentsSheet] 가 끔).
class CommentsSheetShell extends StatefulWidget {
  /// 카운트·리스트·전송 상태의 소스(예: PostDetailState, 후기 갱신 노티파이어).
  final Listenable? listenable;

  /// 헤더 제목(예: '댓글 3') — 리빌드 시점마다 재평가.
  final String Function() title;

  /// 댓글 리스트 본문(비스크롤 — 스크롤은 시트가 담당).
  final WidgetBuilder listBuilder;

  final TextEditingController inputController;
  final bool Function() sending;
  final VoidCallback onSend;

  /// 입력바 표시 여부 — 비로그인 열람(후기) 등에서 숨긴다.
  final bool showInput;

  const CommentsSheetShell({
    super.key,
    this.listenable,
    required this.title,
    required this.listBuilder,
    required this.inputController,
    required this.sending,
    required this.onSend,
    this.showInput = true,
  });

  @override
  State<CommentsSheetShell> createState() => _CommentsSheetShellState();
}

class _CommentsSheetShellState extends State<CommentsSheetShell> {
  /// 입력 포커스 추적 — 작성 중에는 시트 드래그(확장/축소)를 잠근다.
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  void _onFocus() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final composing = _focus.hasFocus;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, scroll) {
        Widget body(BuildContext context) => Column(
          children: [
            const SizedBox(height: 10),
            // 그랩바.
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.colors.border,
                borderRadius: BorderRadius.circular(100),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              widget.title(),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              // 리스트 빈 곳 탭 → 키보드 닫기(전역 배리어는 시트 동안 꺼짐).
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                child: ListView(
                  controller: scroll,
                  // 작성 중엔 시트 확장/축소 드래그 잠금(스크롤 물리 차단 —
                  // DraggableScrollableSheet 는 이 스크롤러블로만 움직인다).
                  physics: composing
                      ? const NeverScrollableScrollPhysics()
                      : null,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  children: [widget.listBuilder(context)],
                ),
              ),
            ),
            if (widget.showInput) _inputBar(context),
          ],
        );
        final listenable = widget.listenable;
        if (listenable == null) return body(context);
        return ListenableBuilder(
          listenable: listenable,
          builder: (context, _) => body(context),
        );
      },
    );
  }

  /// 입력바 — 키보드가 올라오면 그 위로 붙는다.
  Widget _inputBar(BuildContext context) {
    final sending = widget.sending();
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(
          top: BorderSide(color: context.colors.border, width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            12,
            8,
            12,
            8 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.inputController,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: '댓글을 입력하세요',
                    filled: true,
                    fillColor: context.colors.surfaceMuted,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(100),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(100),
                      borderSide: BorderSide(
                        color: context.colors.primary,
                        width: 1.2,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                decoration: BoxDecoration(
                  color: context.colors.primaryDark,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: sending
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.colors.textOnPrimary,
                          ),
                        )
                      : Icon(
                          Icons.arrow_upward,
                          color: context.colors.textOnPrimary,
                        ),
                  onPressed: sending ? null : widget.onSend,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
