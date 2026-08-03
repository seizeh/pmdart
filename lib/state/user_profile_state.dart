import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/community.dart';
import '../models/profile.dart';
import '../services/business_repository.dart';
import '../services/community_repository.dart';
import '../services/profile_repository.dart';
import '../services/session.dart';
import '../services/social_repository.dart';

/// 타 사용자 공개 프로필 화면 상태 홀더 — 프로필/게시글/방문 후기 로드와
/// 얼굴(개인/업체) 판별, 팔로우 토글. (#155 여섯 번째 전환)
///
/// 두 얼굴 규칙(0025): 진입 맥락이 개인(forcePersonalFace)이면 상대가 업체
/// 모드여도 개인 얼굴만 보여준다 — 게시글 필터·후기 종류·팔로우 대상이
/// 전부 얼굴 단위로 갈리므로 판별(bizFace)을 여기서 한 번만 한다.
class UserProfileState extends ChangeNotifier {
  UserProfileState({required this.userId, required this.forcePersonalFace});

  final String userId;
  final bool forcePersonalFace;

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// dispose 뒤 도착한 비동기 완료가 assert 를 밟지 않게 하는 안전 notify(#239).
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  PublicProfileData? _profile;
  List<Post> _posts = [];

  // 업체 모드 프로필의 방문 후기(매칭 시설, 0025 분리) — 일반 프로필이면 빈 목록.
  List<BizFacilityReview> _bizReviews = const [];

  bool _loading = true;
  bool _error = false;
  bool _following = false;
  bool _followBusy = false;

  PublicProfileData? get profile => _profile;
  List<Post> get posts => _posts;
  List<BizFacilityReview> get bizReviews => _bizReviews;
  bool get loading => _loading;
  bool get error => _error;
  bool get following => _following;

  /// 이 화면이 '업체 얼굴'을 보여주는가 — 상대가 업체 모드이면서 진입 맥락도
  /// 업체일 때만. 개인 맥락 진입은 항상 개인 얼굴(정체성 연결 차단).
  bool get bizFace => !forcePersonalFace && (_profile?.isBusinessMode ?? false);

  bool get isMe => userId == SessionManager.instance.user?.id;

  String displayName(PublicProfileData p) =>
      bizFace ? (p.businessName ?? p.nickname) : p.nickname;

  Future<void> load({bool silent = false}) async {
    if (!silent) {
      _loading = true;
      _error = false;
      _notify();
    }
    try {
      // 프로필 먼저 — 업체 모드 여부에 따라 게시글 필터·방문 후기 로드가 갈린다(0025 분리).
      final p = await ProfileRepository.instance.fetchPublicProfile(
        userId,
        // 업체 맥락 진입이면 Pawmate 카운트도 업체 얼굴 팔로워 기준(얼굴 분리).
        businessFace: !forcePersonalFace,
      );
      final biz = p.isBusinessMode && !forcePersonalFace;
      final posts = await CommunityRepository.instance
          .fetchUserPosts(userId, authoredAs: biz ? 'business' : 'personal')
          .catchError((_) => const <Post>[]);
      final bizReviews = (biz && p.businessFacilityId != null)
          ? await BusinessRepository.instance.fetchFacilityReviews(
              p.businessFacilityId!,
            )
          : const <BizFacilityReview>[];
      _profile = p;
      _posts = posts;
      _bizReviews = bizReviews;
      _loading = false;
      _notify();
      if (!isMe) unawaited(_loadFollowing());
    } catch (e) {
      debugPrint('프로필: 로드 실패: $e');
      _loading = false;
      if (!silent) _error = true;
      _notify();
    }
  }

  Future<void> _loadFollowing() async {
    try {
      _following = await SocialRepository.instance.isFollowing(
        userId,
        business: bizFace,
      );
      _notify();
    } catch (e) {
      debugPrint('프로필: 팔로우 상태 조회 실패(미표시): $e');
    }
  }

  // 마지막 토글 시각 — 실수 이중 탭(팔로우→즉시 언팔) 방지 쿨다운.
  DateTime? _lastFollowToggle;

  Future<void> toggleFollow() async {
    if (_followBusy) return;
    // 연속 탭 쿨다운(700ms): 손떨림·이중 탭이 팔로우/언팔 왕복이 되지 않게.
    // (알림 자체는 서버가 90초 유예 후 발송하므로 그 안의 취소는 조용하다.)
    final now = DateTime.now();
    if (_lastFollowToggle != null &&
        now.difference(_lastFollowToggle!) <
            const Duration(milliseconds: 700)) {
      return;
    }
    _lastFollowToggle = now;
    final was = _following;
    _followBusy = true;
    _following = !was;
    _notify();
    try {
      // 팔로우/해제 모두 지금 보고 있는 얼굴 단위 — 다른 얼굴 팔로우엔 영향 없음.
      if (was) {
        await SocialRepository.instance.unfollow(userId, business: bizFace);
      } else {
        await SocialRepository.instance.follow(userId, business: bizFace);
      }
    } catch (e) {
      debugPrint('프로필: 팔로우 토글 실패(롤백): $e');
      _following = was;
    } finally {
      _followBusy = false;
      _notify();
    }
  }
}
