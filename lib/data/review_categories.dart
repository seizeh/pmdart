/// 평가(리뷰) 카테고리 정의 — DB CHECK 제약과 1:1 로 일치해야 한다.
///
/// 8개 카테고리(긍정 4 / 부정 4), 상반쌍 4개. 한 평가에서 최대 4개 선택,
/// 상반되는 두 카테고리는 동시에 선택 불가(DB reviews_excl_* CHECK 와 동일).
class ReviewCategories {
  ReviewCategories._();

  /// 한 평가에서 선택 가능한 최대 개수 (DB reviews_len_chk = 1..4)
  static const int maxSelectable = 4;

  /// 긍정 카테고리 (표시 순서대로)
  static const List<String> positive = [
    '친절해요',
    '약속을잘지켜요',
    '반려동물이순해요',
    '준비성이좋아요',
  ];

  /// 부정 카테고리 (positive 와 같은 인덱스끼리 상반)
  static const List<String> negative = [
    '불친절해요',
    '약속을잘안지켜요',
    '반려동물이사나워요',
    '준비성이아쉬워요',
  ];

  /// 전체 8개 (긍정 → 부정 순)
  static const List<String> all = [...positive, ...negative];

  /// 상반쌍: 한쪽을 고르면 반대쪽은 선택 불가
  static const Map<String, String> opposite = {
    '친절해요': '불친절해요',
    '불친절해요': '친절해요',
    '약속을잘지켜요': '약속을잘안지켜요',
    '약속을잘안지켜요': '약속을잘지켜요',
    '반려동물이순해요': '반려동물이사나워요',
    '반려동물이사나워요': '반려동물이순해요',
    '준비성이좋아요': '준비성이아쉬워요',
    '준비성이아쉬워요': '준비성이좋아요',
  };

  static bool isPositive(String c) => positive.contains(c);
}
