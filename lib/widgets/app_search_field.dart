import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// 공용 검색창 — 사용자 검색 탭 디자인 기준(테마 InputDecoration: surfaceMuted
/// 채움, 곡률 16, 얇은 테두리, search 프리픽스, 입력 중 X 클리어)으로
/// 지도·사용자·게시글 검색이 공유한다. 세로 폭은 일반 폼 필드(≈56)보다 낮은 ≈44.
class AppSearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;

  const AppSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    this.focusNode,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText: hintText,
        // 세로 폭 축소 — 테마 기본(vertical 18, ≈56)보다 낮게(≈44).
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        prefixIcon: const Icon(
          Icons.search,
          color: AppColors.textSecondary,
          size: 22,
        ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 44,
          minHeight: 44,
        ),
        suffixIconConstraints: const BoxConstraints(
          minWidth: 44,
          minHeight: 44,
        ),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (_, value, _) => value.text.isEmpty
              ? const SizedBox(width: 4)
              : IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  icon: const Icon(
                    Icons.close,
                    size: 20,
                    color: AppColors.textTertiary,
                  ),
                  onPressed: onClear,
                ),
        ),
      ),
    );
  }
}
