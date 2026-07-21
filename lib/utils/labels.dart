/// 표시용 라벨/시간 헬퍼.
library;

/// 상대 시간 표시 ("방금 전", "3시간 전" 등).
String timeAgo(DateTime time, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  final diff = ref.difference(time);
  if (diff.inMinutes < 1) return '방금 전';
  if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
  if (diff.inHours < 24) return '${diff.inHours}시간 전';
  if (diff.inDays < 7) return '${diff.inDays}일 전';
  return '${time.month}월 ${time.day}일';
}

/// 게시글 카테고리 라벨.
String categoryLabel(String category) => switch (category) {
  'walk_together' => '동반산책',
  'walk_proxy' => '대리산책',
  'care' => '돌봄',
  'give_away' => '분양',
  'adoption' => '입양',
  'free' => '자유',
  'news' => '소식',
  _ => category,
};
