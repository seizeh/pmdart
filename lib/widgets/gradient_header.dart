import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// 메인(커뮤니티) 상단과 동일한 **흰색 셀로판지** 헤더.
///
/// 블러 없이 균일한 흰색 반투명 필름([AppColors.frostFilm])만 덮어, 뒤로 스크롤되는
/// 리스트가 **선명하게** 비치며 흰 베일이 얹힌다. [child] 는 제목(및 검색창 등) 헤더
/// 콘텐츠, [topInset] 은 상태바 안전영역 높이. 리스트에는 헤더 높이만큼 상단 패딩을 줘
/// 헤더 아래에서 시작하게 한다(스크롤 시 그 위로 흘러 들어가며 비친다).
class GradientHeader extends StatelessWidget {
  const GradientHeader({
    super.key,
    required this.topInset,
    required this.child,
  });

  final double topInset;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      // 상태바 아래에 떠 있는 둥근 직사각형 패널 — 네 모서리 모두 동일 곡률(24,
      // 하단 메뉴바와 통일).
      child: Padding(
        padding: EdgeInsets.fromLTRB(12, topInset + 8, 12, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: ColoredBox(
            color: AppColors.frostFilm,
            child: child,
          ),
        ),
      ),
    );
  }
}
