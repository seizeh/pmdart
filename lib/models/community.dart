/// 커뮤니티 도메인 모델 (Supabase 실데이터).
library;

/// 게시글 이미지 표시 비율 (가로:세로 = 4284:5712, 최신 카메라 기본 비율 = 3:4).
const double kPostImageAspectRatio = 4284 / 5712;

DateTime _parseDate(dynamic v) =>
    v == null ? DateTime.fromMillisecondsSinceEpoch(0) : DateTime.parse(v as String).toLocal();

DateTime? _parseDateNullable(dynamic v) =>
    v == null ? null : DateTime.parse(v as String).toLocal();

int _parseInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : 0);

/// 게시글 (v_post_feed 뷰 기준).
class Post {
  final String id;
  final String category;
  final String title;
  final String content;
  final String userId;
  final String authorNickname;
  final String authorUserType;
  final DateTime createdAt;
  final DateTime? scheduledAt;
  final String? location;
  final int heartCount;
  final int commentCount;
  final int viewCount;
  final String progressStatus;
  final bool hearted;
  final String? imageUrl;

  const Post({
    required this.id,
    required this.category,
    required this.title,
    required this.content,
    required this.userId,
    required this.authorNickname,
    required this.authorUserType,
    required this.createdAt,
    required this.scheduledAt,
    required this.location,
    required this.heartCount,
    required this.commentCount,
    required this.viewCount,
    required this.progressStatus,
    required this.hearted,
    this.imageUrl,
  });

  factory Post.fromJson(Map<String, dynamic> j) => Post(
        id: j['id'] as String,
        category: (j['category'] ?? 'free') as String,
        title: (j['title'] ?? '') as String,
        content: (j['content'] ?? '') as String,
        userId: (j['user_id'] ?? '') as String,
        authorNickname: (j['author_nickname'] ?? '알 수 없음') as String,
        authorUserType: (j['author_user_type'] ?? '') as String,
        createdAt: _parseDate(j['created_at']),
        scheduledAt: _parseDateNullable(j['scheduled_at']),
        location: j['location'] as String?,
        heartCount: _parseInt(j['heart_count']),
        commentCount: _parseInt(j['comment_count']),
        viewCount: _parseInt(j['view_count']),
        progressStatus: (j['progress_status'] ?? 'recruiting') as String,
        hearted: j['hearted'] == true,
        imageUrl: j['image_url'] as String?,
      );

  /// 하트 토글 등 낙관적 업데이트용.
  Post copyWith({bool? hearted, int? heartCount}) => Post(
        id: id,
        category: category,
        title: title,
        content: content,
        userId: userId,
        authorNickname: authorNickname,
        authorUserType: authorUserType,
        createdAt: createdAt,
        scheduledAt: scheduledAt,
        location: location,
        heartCount: heartCount ?? this.heartCount,
        commentCount: commentCount,
        viewCount: viewCount,
        progressStatus: progressStatus,
        hearted: hearted ?? this.hearted,
        imageUrl: imageUrl,
      );
}

/// 댓글 (v_comment_feed 뷰 기준).
class Comment {
  final String id;
  final String postId;
  final String userId;
  final String content;
  final DateTime createdAt;
  final String authorNickname;

  const Comment({
    required this.id,
    required this.postId,
    required this.userId,
    required this.content,
    required this.createdAt,
    required this.authorNickname,
  });

  factory Comment.fromJson(Map<String, dynamic> j) => Comment(
        id: j['id'] as String,
        postId: (j['post_id'] ?? '') as String,
        userId: (j['user_id'] ?? '') as String,
        content: (j['content'] ?? '') as String,
        createdAt: _parseDate(j['created_at']),
        authorNickname: (j['author_nickname'] ?? '알 수 없음') as String,
      );
}

/// 내 반려동물 (게시글 작성 시 연결용).
class MyPet {
  final String id;
  final String name;
  final String species;
  final String role; // owner / co_guardian

  const MyPet({
    required this.id,
    required this.name,
    required this.species,
    required this.role,
  });
}
