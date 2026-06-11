import 'package:flutter/material.dart';

/// 앱 알림 1건 (notifications 테이블). Flutter 의 Notification 과 이름 충돌 피해 AppNotification.
class AppNotification {
  final String id;
  final String type;
  final String? title;
  final String? body;
  final bool isRead;
  final DateTime createdAt;
  final String? resourceType; // post / comment / chat_room / appointment
  final String? resourceId;
  final int aggregatedCount;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.isRead,
    required this.createdAt,
    required this.resourceType,
    required this.resourceId,
    required this.aggregatedCount,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as String,
        type: (j['notification_type'] ?? 'system_notice') as String,
        title: j['title'] as String?,
        body: j['body'] as String?,
        isRead: j['is_read'] == true,
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
        resourceType: j['resource_type'] as String?,
        resourceId: j['resource_id'] as String?,
        aggregatedCount: (j['aggregated_count'] as num?)?.toInt() ?? 1,
      );

  /// title 이 없을 때 타입으로 기본 문구.
  String get displayTitle => title ?? _defaultTitle(type);

  static String _defaultTitle(String type) => switch (type) {
        'chat_message' => '새 메시지',
        'post_application' => '내 게시글에 지원이 왔어요',
        'post_comment' => '새 댓글',
        'pawing_new_post' => 'Pawing 한 사람의 새 글',
        'application_accepted' => '지원이 수락됐어요',
        'application_accepted_by_co' => '공동보호자가 지원을 수락했어요',
        'review_received' => '새 평가를 받았어요',
        'system_notice' => '공지',
        'location_expired' => '지역 인증이 만료됐어요',
        _ => '알림',
      };

  IconData get icon => switch (type) {
        'chat_message' => Icons.chat_bubble_outline,
        'post_application' => Icons.send_outlined,
        'post_comment' => Icons.mode_comment_outlined,
        'pawing_new_post' => Icons.article_outlined,
        'application_accepted' => Icons.check_circle_outline,
        'application_accepted_by_co' => Icons.check_circle_outline,
        'review_received' => Icons.star_border,
        'location_expired' => Icons.location_off_outlined,
        _ => Icons.notifications_outlined,
      };
}
