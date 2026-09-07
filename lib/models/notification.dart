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

  AppNotification copyWith({bool? isRead}) => AppNotification(
    id: id,
    type: type,
    title: title,
    body: body,
    isRead: isRead ?? this.isRead,
    createdAt: createdAt,
    resourceType: resourceType,
    resourceId: resourceId,
    aggregatedCount: aggregatedCount,
  );

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

  /// 탭했을 때 이동할 화면이 있는가 — push_routing.openFromPush 의 분기와
  /// 거울이어야 한다(거기서 라우팅을 추가하면 여기도 함께).
  ///
  /// 없으면(공지 등) 알림함이 탭을 "이동" 이 아니라 "본문 제자리 펼침" 으로
  /// 처리한다 — 이동할 곳도 없는데 본문이 2줄에서 잘리면 긴 공지는 영영 못
  /// 읽는다(관리자 운영 알람 실사고).
  bool get hasDestination {
    if (type == 'guardian_invite' || type == 'review_received') return true;
    if (resourceId == null || resourceId!.isEmpty) return false;
    return const {
      'post',
      'user',
      'chat_room',
      'pet',
      'facility_review',
    }.contains(resourceType);
  }

  static String _defaultTitle(String type) => switch (type) {
    'chat_message' => '새 메시지',
    'post_application' => '내 게시글에 지원이 왔어요',
    'post_comment' => '새 댓글',
    'review_comment' => '내 후기에 새 댓글이 달렸어요',
    'pawing_new_post' => 'Pawing 한 사람의 새 글',
    'post_heart' => '회원님의 게시글을 좋아해요',
    'pawing_follow' => '새로운 Pawing',
    'facility_review_received' => '내 업체에 방문 후기가 달렸어요',
    'pet_in_post' => '공동보호 반려동물이 게시글에 등록됐어요',
    'application_accepted' => '지원이 수락됐어요',
    'application_accepted_by_co' => '공동보호자가 지원을 수락했어요',
    'guardian_invite' => '공동보호자 초대가 왔어요',
    'review_received' => '새 후기를 받았어요',
    'system_notice' => '공지',
    'location_expired' => '지역 인증이 만료됐어요',
    'security_login' => '새 기기에서 로그인되었어요',
    'schedule_changed' => '약속 일정이 변경됐어요',
    'vaccine_reminder' => '접종 알림',
    _ => '알림',
  };

  IconData get icon => switch (type) {
    'chat_message' => Icons.chat_bubble_outline,
    'post_application' => Icons.send_outlined,
    'post_comment' => Icons.mode_comment_outlined,
    'review_comment' => Icons.mode_comment_outlined,
    'pawing_new_post' => Icons.article_outlined,
    'post_heart' => Icons.favorite_border,
    'pawing_follow' => Icons.person_add_alt,
    'facility_review_received' => Icons.star_border,
    'pet_in_post' => Icons.pets_outlined,
    'application_accepted' => Icons.check_circle_outline,
    'application_accepted_by_co' => Icons.check_circle_outline,
    'guardian_invite' => Icons.mail_outline,
    'review_received' => Icons.star_border,
    'location_expired' => Icons.location_off_outlined,
    'security_login' => Icons.phonelink_lock_outlined,
    'schedule_changed' => Icons.event_repeat_outlined,
    'vaccine_reminder' => Icons.vaccines_outlined,
    _ => Icons.notifications_outlined,
  };
}
