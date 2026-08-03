import 'package:flutter/foundation.dart';

import '../models/community.dart';
import '../models/profile.dart';
import '../services/app_events.dart';
import '../services/business_repository.dart';
import '../services/community_repository.dart';
import '../services/pet_repository.dart';
import '../services/profile_repository.dart';
import '../services/session.dart';

/// 내정보 탭 상태 홀더 — 프로필/초대 수/내 게시글/업체 후기 요약 로드와
/// AppEvents(소셜·프로필 변경) 자동 새로고침 구독. (#155 네 번째 전환)
///
/// 탭은 IndexedStack 으로 살아 있어 재진입만으로는 갱신되지 않으므로,
/// 다른 화면의 변경 이벤트를 여기서 구독해 silent 새로고침한다.
class MyInfoState extends ChangeNotifier {
  MyInfoState({required this.isGuest});

  final bool isGuest;

  ProfileData? _profile;
  int _pendingInvites = 0;
  bool _loading = true;
  String? _error;
  List<Post> _myPosts = [];

  // 업체 모드 히어로용 후기 요약(일반 모드면 null).
  int? _bizReviewCount;
  double? _bizReviewAvg;

  ProfileData? get profile => _profile;
  int get pendingInvites => _pendingInvites;
  bool get loading => _loading;
  String? get error => _error;
  List<Post> get myPosts => _myPosts;
  int? get bizReviewCount => _bizReviewCount;
  double? get bizReviewAvg => _bizReviewAvg;

  void init() {
    if (isGuest) return;
    load();
    AppEvents.instance.social.addListener(_onChanged);
    AppEvents.instance.profile.addListener(_onChanged);
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    AppEvents.instance.social.removeListener(_onChanged);
    AppEvents.instance.profile.removeListener(_onChanged);
    super.dispose();
  }

  /// dispose 뒤 도착한 비동기 완료가 assert 를 밟지 않게 하는 안전 notify(#239).
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _onChanged() => load(silent: true);

  /// 프로필 일괄 로드. [silent] 면 로딩 표시 없이 갱신하고,
  /// 실패해도 기존 데이터를 유지한다(첫 로드 실패만 에러 표시).
  Future<void> load({bool silent = false}) async {
    if (!silent) {
      _loading = true;
      _error = null;
      _notify();
    }
    try {
      final p = await ProfileRepository.instance.fetchProfile();
      var invites = 0;
      try {
        invites = await PetRepository.instance.pendingInviteCount();
      } catch (e) {
        debugPrint('내정보: 초대 수 조회 실패(0으로 표시): $e');
      }
      var posts = _myPosts;
      try {
        final uid = SessionManager.instance.user?.id;
        if (uid != null) {
          // 같은 계정이지만 분리된 프로필 — 현재 모드로 작성한 글만 (0025 후속)
          posts = await CommunityRepository.instance.fetchUserPosts(
            uid,
            authoredAs: p.activeMode,
          );
        }
      } catch (e) {
        // 게시글 조회 실패 시 기존 목록 유지
        debugPrint('내정보: 게시글 조회 실패 — 기존 목록 유지: $e');
      }
      // 업체 모드 히어로의 후기 요약(후기 수·평점)
      int? bizCount;
      double? bizAvg;
      if (p.activeMode == 'business') {
        try {
          final rs = await BusinessRepository.instance.fetchMyFacilityReviews();
          bizCount = rs.length;
          bizAvg = rs.isEmpty
              ? null
              : rs.map((r) => r.rating).reduce((a, b) => a + b) / rs.length;
        } catch (e) {
          debugPrint('내정보: 업체 후기 요약 조회 실패(0으로 표시): $e');
          bizCount = 0;
        }
      }
      _profile = p;
      _pendingInvites = invites;
      _myPosts = posts;
      _bizReviewCount = bizCount;
      _bizReviewAvg = bizAvg;
      _loading = false;
      _error = null;
    } catch (e) {
      debugPrint('내정보: 프로필 로드 실패: $e');
      _loading = false;
      // 조용한 새로고침 실패 시 기존 데이터 유지
      if (_profile == null) _error = '프로필을 불러오지 못했어요';
    }
    _notify();
  }
}
