import 'package:flutter/foundation.dart';

import '../models/community.dart';
import '../services/business/mode_repository.dart';
import '../services/community_repository.dart';
import '../services/session.dart';
import '../services/social_repository.dart';

/// 게시글 상세 화면 상태 홀더 — 게시글/댓글 데이터와 하트·팔로우·지원·댓글의
/// 서버 호출 및 낙관적 갱신. (#155 두 번째 전환 — 패턴은 docs/architecture-state.md)
///
/// 로그인 가드(AuthWall)·다이얼로그·토스트·내비게이션은 화면이 담당하고,
/// 여기는 BuildContext 를 모른다. 실패는 반환값(bool)로 알려 화면이 표시한다.
class PostDetailState extends ChangeNotifier {
  PostDetailState({
    required Post post,
    required this.isGuest,
    CommunityRepository? community,
    SocialRepository? social,
    AccountModeRepository? business,
    // ignore: prefer_initializing_formals  (private 필드 + named 파라미터)
  }) : _post = post,
       _repo = community ?? CommunityRepository.instance,
       _social = social ?? SocialRepository.instance,
       _business = business ?? AccountModeRepository.instance {
    _canManage = isMyPost;
    _managerChecked = isMyPost || isGuest || isFreePost;
  }

  final bool isGuest;

  /// 의존은 **선택적 생성자 주입** — 인자를 안 주면 종전대로 싱글턴을 쓴다.
  /// 기존 호출부는 그대로 두고 테스트만 대역을 넣을 수 있게 하는 점진적 전환이며,
  /// NotificationsState 가 먼저 쓰던 방식을 넓힌 것이다.
  final CommunityRepository _repo;
  final SocialRepository _social;
  final AccountModeRepository _business;

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

  Post _post;
  List<Comment> _comments = const [];
  bool _loadingComments = true;
  bool _sending = false;
  bool _applying = false;
  bool _following = false;
  bool _canManage = false;
  bool _managerChecked = false;
  bool _businessMode = false;

  Post get post => _post;
  List<Comment> get comments => _comments;
  bool get loadingComments => _loadingComments;
  bool get sending => _sending;
  bool get applying => _applying;
  bool get following => _following;

  /// 지원자 목록을 관리(조회·수락)할 수 있는지 — 작성자 또는 공동보호자.
  bool get canManage => _canManage;

  /// 공동보호자 권한 확인이 끝났는지 (확인 전엔 지원하기 버튼을 숨긴다).
  bool get managerChecked => _managerChecked;

  /// 현재 업체 모드인가 — 업체 모드에선 지원(개인 매칭)이 불가.
  bool get businessMode => _businessMode;

  /// 매칭(지원→약속) 없는 게시글 — 자유글·업체 소식. 지원 UI 를 띄우지 않는다.
  bool get isFreePost => _post.category == 'free' || _post.category == 'news';
  bool get isMyPost => _post.userId == SessionManager.instance.user?.id;

  /// 초기 로드 오케스트레이션 — 화면 initState 에서 1회.
  /// 작성자 본인 조회는 조회수·팔로우·권한 확인을 생략한다(원래 규칙 유지).
  void init() {
    loadComments();
    if (!isGuest && !isMyPost) {
      _recordView();
      _loadFollowing();
      if (!isFreePost) {
        _loadManager();
        _loadMode();
      }
    }
  }

  Future<void> loadComments() async {
    try {
      _comments = await _repo.fetchComments(_post.id);
      _loadingComments = false;
    } catch (e) {
      debugPrint('게시글 상세: 댓글 조회 실패(기존 목록 유지): $e');
      _loadingComments = false;
    }
    _notify();
  }

  /// 조회수 기록 (같은 시간대 재조회는 집계 안 됨). 집계됐으면 화면 수치도 +1.
  Future<void> _recordView() async {
    final counted = await _repo.recordView(_post.id);
    if (counted) {
      _post = _post.copyWith(viewCount: _post.viewCount + 1);
      _notify();
    }
  }

  Future<void> _loadManager() async {
    try {
      _canManage = await _repo.canManageApplicants(_post.id);
    } catch (e) {
      debugPrint('게시글 상세: 지원자 관리 권한 확인 실패(숨김 유지): $e');
    }
    _managerChecked = true;
    _notify();
  }

  Future<void> _loadFollowing() async {
    try {
      // 글의 얼굴(개인/업체) 단위로 팔로우 상태 확인 — 업체 글은 업체 팔로우 여부.
      _following = await _social.isFollowing(
        _post.userId,
        business: _post.authoredAs == 'business',
      );
      _notify();
    } catch (e) {
      debugPrint('게시글 상세: 팔로우 상태 조회 실패(미표시): $e');
    }
  }

  Future<void> _loadMode() async {
    try {
      final mode = await _business.fetchActiveMode();
      _businessMode = mode == 'business';
      _notify();
    } catch (e) {
      debugPrint('게시글 상세: 활성 모드 조회 실패(개인 모드로 표시): $e');
    }
  }

  // 실수 이중 탭(팔로우→즉시 언팔) 방지 쿨다운 — 프로필 화면과 동일 규칙.
  DateTime? _lastFollowToggle;

  /// 팔로우 낙관적 토글 — 쿨다운(700ms) 내 재탭은 무시, 실패 시 롤백.
  Future<void> toggleFollow() async {
    final now = DateTime.now();
    if (_lastFollowToggle != null &&
        now.difference(_lastFollowToggle!) <
            const Duration(milliseconds: 700)) {
      return;
    }
    _lastFollowToggle = now;
    final was = _following;
    _following = !was;
    _notify();
    try {
      // 팔로우/해제 모두 글의 얼굴 단위 — 업체 글(소식)은 업체 팔로우로.
      final biz = _post.authoredAs == 'business';
      if (was) {
        await _social.unfollow(_post.userId, business: biz);
      } else {
        await _social.follow(_post.userId, business: biz);
      }
    } catch (e) {
      debugPrint('게시글 상세: 팔로우 토글 실패(롤백): $e');
      _following = was;
      _notify();
    }
  }

  /// 하트 낙관적 토글. 실패하면 롤백 후 false(화면이 안내).
  Future<bool> toggleHeart() async {
    final wasHearted = _post.hearted;
    _post = _post.copyWith(
      hearted: !wasHearted,
      heartCount: _post.heartCount + (wasHearted ? -1 : 1),
    );
    _notify();
    try {
      await _repo.toggleHeart(_post.id, wasHearted);
      return true;
    } catch (e) {
      debugPrint('게시글 상세: 하트 토글 실패(롤백): $e');
      _post = _post.copyWith(
        hearted: wasHearted,
        heartCount: _post.heartCount + (wasHearted ? 1 : -1),
      );
      _notify();
      return false;
    }
  }

  /// 댓글 등록만 수행(성공 여부 반환) — 입력창 정리·재조회 순서는 화면이 제어.
  Future<bool> submitComment(String text) async {
    _sending = true;
    _notify();
    try {
      await _repo.addComment(_post.id, text);
      return true;
    } catch (e) {
      debugPrint('게시글 상세: 댓글 작성 실패: $e');
      return false;
    } finally {
      _sending = false;
      _notify();
    }
  }

  /// 지원 제출(성공 여부 반환) — 업체 모드 확인·전환 다이얼로그는 화면이 선행.
  Future<bool> submitApply() async {
    _applying = true;
    _notify();
    try {
      await _repo.apply(_post.id);
      return true;
    } catch (e) {
      debugPrint('게시글 상세: 지원 실패(중복 등): $e');
      return false;
    } finally {
      _applying = false;
      _notify();
    }
  }

  /// 수정 후 최신 내용 재조회. 삭제됐으면 false(화면이 닫는다).
  Future<bool> reloadPost() async {
    final fresh = await _repo.fetchPost(_post.id);
    if (fresh == null) return false;
    _post = fresh;
    _notify();
    return true;
  }
}
