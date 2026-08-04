/// 푸시·알림 탭 라우팅 — main.dart 에서 떼어냈다(부트스트랩과 라우팅은 서로 다른 일이다).
library;

import 'dart:async';
import 'package:flutter/material.dart';
import '../motion/motion.dart';
import '../screen/activity_screens.dart' show MyReviewsScreen;
import '../screen/chat_room_screen.dart';
import '../screen/guardian_invites_screen.dart';
import '../screen/main_screen.dart';
import '../screen/notifications_screen.dart';
import '../screen/post_detail_screen.dart';
import '../screen/review_detail_screen.dart';
import '../screen/user_profile_screen.dart';
import '../screen/vaccination_schedule_screen.dart';
import '../services/chat_repository.dart';
import '../services/community_repository.dart';
import '../services/facility_review_repository.dart';
import '../services/local_notice_service.dart';
import '../services/pet_repository.dart';
import '../services/session.dart';
import '../widgets/review_cards.dart';
import 'app_keys.dart';

/// 포그라운드 알림(Android) — 새 알림(realtime)이 오면 백그라운드 푸시와 동일한
/// 형태의 OS 시스템 알림으로 보여주고, 탭하면 해당 화면으로 이동한다.
/// iOS 는 FCM 의 네이티브 포그라운드 배너가 담당(LocalNoticeService 는 no-op).
void showNotificationBanner(Map<String, dynamic> row) {
  final type = (row['notification_type'] ?? '') as String;
  final resourceType = row['resource_type'] as String?;
  final resourceId = row['resource_id'] as String?;
  // 동기화용 타입은 사용자 대면 알림이 아님.
  if (type == 'chat_read_receipt' || type == 'unread_sync') return;
  // 포그라운드에서만 — 백그라운드 전환 직후 realtime 이 잠시 살아 있으면
  // FCM 푸시(OS 표시)와 이중 알림이 되므로 그쪽에 맡긴다.
  if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
    return;
  }
  // 지금 보고 있는 채팅방의 메시지면 생략 — 이미 화면에 실시간으로 뜬다.
  if (type == 'chat_message' &&
      resourceId != null &&
      ChatRepository.instance.activeRoomId == resourceId) {
    return;
  }
  unawaited(
    LocalNoticeService.instance.show(
      title: row['title'] as String?,
      body: row['body'] as String?,
      type: type,
      resourceType: resourceType,
      resourceId: resourceId,
    ),
  );
}

/// 푸시 탭 라우팅 — 대상 화면(채팅방/게시글/후기/초대함)으로 **바로** 이동한다.
/// 종료 상태에서 탭해 콜드 스타트해도 동일(네비게이터·세션 준비를 기다린 뒤 이동).
/// 대상을 못 찾으면(삭제·네트워크 실패 등) 알림함으로 폴백.
/// 알림함(벨 패널·알림 화면)도 이 라우팅을 그대로 쓴다 — 채팅방은 채팅 탭 위에
/// rise 전환으로 열려, 닫으면(쓸어내리기/뒤로가기) 채팅 목록이 나온다.
Future<void> openFromPush(
  String type,
  String? resourceType,
  String? resourceId, {
  // 알림함(목록/패널)에서의 탭은 false — 라우팅할 곳이 없으면 아무것도 하지
  // 않는다(알림함 안에서 알림함을 또 여는 재귀 방지). 푸시 탭은 기본 true.
  bool fallbackToInbox = true,
}) async {
  debugPrint('deeplink: type=$type resource=$resourceType/$resourceId');
  // 콜드 스타트 — 첫 프레임(네비게이터)이 붙을 때까지 잠깐 대기(최대 5초).
  NavigatorState? nav = navigatorKey.currentState;
  for (var i = 0; i < 50 && nav == null; i++) {
    await Future.delayed(const Duration(milliseconds: 100));
    nav = navigatorKey.currentState;
  }
  if (nav == null) return;
  // 알림은 로그인 사용자에게만 온다 — 세션이 없으면(만료 등) 라우팅하지 않는다.
  if (!SessionManager.instance.isLoggedIn) return;

  // 딥링크는 항상 "루트(메인 탭) 위에 상세 1장" 스택으로 만든다 — 상세를 닫으면
  // (뒤로가기/쓸어내리기) 관련 탭(채팅 목록·커뮤니티 등)이 바로 나온다.
  void popToRoot() => nav!.popUntil((r) => r.isFirst);

  // 백그라운드 복귀 직후엔 끊긴 소켓 탓에 첫 요청이 일시 실패하곤 한다 —
  // 대상 조회는 짧게 재시도해 '탭했는데 알림함 폴백'으로 새지 않게 한다.
  Future<T?> fetchRetry<T>(Future<T?> Function() f) async {
    for (var i = 0; i < 3; i++) {
      try {
        final r = await f();
        if (r != null) return r;
      } catch (e) {
        debugPrint('push route: 대상 조회 실패(${i + 1}/3) — $e');
      }
      await Future.delayed(const Duration(milliseconds: 400));
    }
    return null;
  }

  try {
    if (type == 'guardian_invite') {
      // 초대 알림은 리소스 없이 초대함으로.
      popToRoot();
      nav.push(AppPageRoute(builder: (_) => const GuardianInvitesScreen()));
      return;
    }
    if (type == 'review_received') {
      // 후기 알림 — 내가 받은 후기 화면으로.
      popToRoot();
      nav.push(AppPageRoute(builder: (_) => const MyReviewsScreen()));
      return;
    }
    if (resourceId != null && resourceId.isNotEmpty) {
      switch (resourceType) {
        case 'post':
          final post = await fetchRetry(
            () => CommunityRepository.instance.fetchPost(resourceId),
          );
          if (post != null) {
            popToRoot();
            MainScreen.tabRequest.value = MainScreen.tabCommunity;
            // 앱 공통 상세 언어 — 아래에서 떠오르고, 쓸어내리면 닫힌다.
            final pctx = navigatorKey.currentContext;
            nav.push(
              CollapseRoute(
                builder: (_) => PostDetailScreen(
                  post: post,
                  originRect: pctx == null ? null : riseOriginRect(pctx),
                ),
              ),
            );
            return;
          }
        case 'user':
          // 포잉 알림 — 팔로우한 상대의 프로필로(개인 활동이라 개인 얼굴).
          popToRoot();
          final uctx = navigatorKey.currentContext;
          nav.push(
            CollapseRoute(
              builder: (_) => UserProfileScreen(
                userId: resourceId,
                forcePersonalFace: true,
                originRect: uctx == null ? null : riseOriginRect(uctx),
                cardRadius: 24,
              ),
            ),
          );
          return;
        case 'chat_room':
          final room = await fetchRetry(
            () => ChatRepository.instance.fetchRoom(resourceId),
          );
          if (room != null) {
            popToRoot();
            MainScreen.tabRequest.value = MainScreen.tabChat;
            // 채팅 목록에서 열 때와 동일한 언어 — 아래에서 떠오르고,
            // 헤더를 잡아 쓸어내리면 채팅 목록으로 닫힌다.
            final ctx = navigatorKey.currentContext;
            nav.push(
              CollapseRoute(
                builder: (_) => ChatRoomScreen(
                  room: room,
                  originRect: ctx == null ? null : riseOriginRect(ctx),
                ),
              ),
            );
            return;
          }
        case 'pet':
          // 접종 알림(vaccine_reminder) 등 펫 리소스 — 접종 일정 화면으로.
          // 펫 조회 실패(삭제·보호자 아님 등)면 아래 알림함 폴백.
          final pet = await fetchRetry(
            () => PetRepository.instance.fetchPet(resourceId),
          );
          if (pet != null) {
            popToRoot();
            nav.push(
              AppPageRoute(
                builder: (_) => VaccinationScheduleScreen(
                  petId: pet.id,
                  petName: pet.name,
                  birthDate: pet.birthDate,
                  speciesKind: pet.speciesKind,
                  source: 'manage',
                ),
              ),
            );
            return;
          }
        case 'facility_review':
          final review = await fetchRetry(
            () => FacilityReviewRepository.instance.fetchReviewById(resourceId),
          );
          if (review != null) {
            popToRoot();
            final rctx = navigatorKey.currentContext;
            nav.push(
              CollapseRoute(
                builder: (_) => ReviewDetailScreen(
                  review: ReviewCardData.fromFacilityReview(review),
                  originRect: rctx == null ? null : riseOriginRect(rctx),
                  fromDeepLink: true,
                ),
              ),
            );
            return;
          }
      }
    }
  } catch (_) {
    // 대상 조회 실패 — 아래 폴백으로.
  }
  // 대상 화면으로 못 갔으면 알림함으로(푸시 탭 한정 — 알림함 내 탭은 제자리 유지).
  if (fallbackToInbox) {
    popToRoot();
    nav.push(AppPageRoute(builder: (_) => const NotificationsScreen()));
  }
}
