/// 게시글 히어로 에디터의 공용 조각 — 작성(post_create_screen)과 수정
/// (post_edit_screen)이 **같은 코드**를 쓴다.
///
/// 원래 이 위젯들은 작성 화면 안의 private 메서드였고, 수정 화면은 별개의
/// `Scaffold + AppBar + 폼`이었다. 그래서 같은 게시글을 쓰는 화면과 고치는 화면의
/// 생김새가 달랐다. 복제하지 않고 추출한 이유: 복사본은 갈라진다(비밀번호 복잡도
/// 규칙이 가입·재설정·변경 세 곳에서 갈라져 '변경만 6자'였던 사고와 같은 종류).
///
/// 여기 있는 것은 **표현만** 담는다. 무엇을 편집할 수 있는지·저장이 가능한지 같은
/// 판단은 각 화면이 갖는다(작성은 카테고리·펫·촬영 인증, 수정은 잠금·고정 필드).
library;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../motion/motion.dart';
import '../theme/app_palette.dart';

/// 본문 입력 — [hero] 면 사진 없는 글의 히어로 중앙(큰 글씨·가운데 정렬),
/// 아니면 하단 오버레이 패널 안(작은 흰 글씨).
class EditorContentField extends StatelessWidget {
  final TextEditingController controller;
  final bool hero;
  final ValueChanged<String>? onChanged;
  final String hintText;

  const EditorContentField({
    super.key,
    required this.controller,
    required this.hero,
    this.onChanged,
    this.hintText = '내용을 입력하세요',
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      minLines: 1,
      maxLines: hero ? 9 : 3,
      textAlign: hero ? TextAlign.center : TextAlign.start,
      cursorColor: hero ? context.colors.textPrimary : Colors.white,
      style: hero
          ? TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.colors.textPrimary,
              height: 1.6,
            )
          : const TextStyle(
              fontSize: 13,
              color: Color(0xE0FFFFFF),
              height: 1.5,
            ),
      decoration: InputDecoration(
        isDense: true,
        isCollapsed: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        hintText: hintText,
        hintStyle: hero
            ? TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: context.colors.textTertiary,
                height: 1.6,
              )
            : const TextStyle(
                fontSize: 13,
                color: Color(0x99FFFFFF),
                height: 1.5,
              ),
      ),
    );
  }
}

/// 히어로 좌상단의 원형 버튼(사진 추가·교체·제거) — 사진 위에 얹히므로 반투명 검정.
class EditorCardIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool busy;

  /// 첨부 진행률(0.0~1.0). 값이 `null` 이면 종전처럼 무한 회전한다 —
  /// picker 가 떠 있는 동안처럼 아직 잴 게 없는 구간이 그렇다.
  final ValueListenable<double?>? progress;

  const EditorCardIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.busy = false,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: busy ? null : onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: Color(0x66000000),
            shape: BoxShape.circle,
          ),
          child: busy ? _ring() : Icon(icon, size: 20, color: Colors.white),
        ),
      ),
    );
  }

  /// 진행률 고리. 결정 상태에서는 남은 몫을 옅게 깔아 두어 "얼마나 남았는지" 가
  /// 한눈에 보이게 한다(무한 회전에는 트랙이 없다 — 끝을 모르니까).
  Widget _ring() {
    if (progress == null) {
      return const Padding(
        padding: EdgeInsets.all(10),
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      );
    }
    return ValueListenableBuilder<double?>(
      valueListenable: progress!,
      builder: (_, value, _) => Padding(
        padding: const EdgeInsets.all(10),
        child: TweenAnimationBuilder<double>(
          // 콜백이 띄엄띄엄 와도 고리가 끊겨 보이지 않게 값 사이를 잇는다.
          tween: Tween(begin: 0, end: value ?? 0),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          builder: (_, shown, _) => CircularProgressIndicator(
            value: value == null ? null : shown,
            strokeWidth: 2,
            color: Colors.white,
            backgroundColor: value == null ? null : const Color(0x33FFFFFF),
          ),
        ),
      ),
    );
  }
}

/// 카테고리 태그(흰 필름 알약) — 피드 카드와 동일 문법.
/// [trailing] 에 `Icons.expand_more` 를 주면 편집 가능 힌트가 된다(수정 화면은
/// 카테고리를 바꿀 수 없으므로 힌트 없이 쓴다).
/// [selected] 는 작성 화면의 인라인 카테고리 목록에서 현재 값 강조용.
class EditorCategoryPill extends StatelessWidget {
  final String text;
  final Color textColor;
  final IconData? trailing;
  final bool selected;

  const EditorCategoryPill({
    super.key,
    required this.text,
    required this.textColor,
    this.trailing,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: selected ? textColor : Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : textColor,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 2),
            Icon(trailing, size: 13, color: textColor),
          ],
        ],
      ),
    );
  }
}

/// 메타 알약(일정 등) — 피드 카드의 메타 알약과 동일. [editable] 이면 ▾ 힌트.
class EditorMetaPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool editable;

  const EditorMetaPill({
    super.key,
    required this.icon,
    required this.label,
    this.editable = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: context.colors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: context.colors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (editable) ...[
            const SizedBox(width: 2),
            Icon(
              Icons.expand_more,
              size: 13,
              color: context.colors.textSecondary,
            ),
          ],
        ],
      ),
    );
  }
}

/// 히어로 우상단의 확정 버튼 — 작성은 '등록', 수정은 '저장'.
/// 앱바가 아니라 히어로에 직접 얹는다(확장 전환이 안착한 뒤 나타나야 모프 중간에
/// 불쑥 뜨지 않는다 — 호출부에서 `CollapseSettledFade` 로 감싼다).
class EditorSubmitPill extends StatelessWidget {
  final String label;
  final bool enabled;
  final bool busy;
  final VoidCallback? onTap;

  const EditorSubmitPill({
    super.key,
    required this.label,
    required this.enabled,
    required this.busy,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressable(
      scaleTo: 0.92,
      borderRadius: BorderRadius.circular(100),
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: enabled ? context.colors.primaryDark : const Color(0x59000000),
          borderRadius: BorderRadius.circular(100),
        ),
        child: busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: enabled ? Colors.white : const Color(0x99FFFFFF),
                ),
              ),
      ),
    );
  }
}
