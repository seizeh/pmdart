import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../models/profile.dart';
import '../services/profile_repository.dart';
import '../services/storage_service.dart';

/// 내정보 수정 화면 상태 홀더 — 모드/사진 업로드/저장/활동 지역 갱신.
/// (#155 다섯 번째 전환 — 패턴은 docs/architecture-state.md)
///
/// 사진 선택(피커)·인증 화면 이동·토스트·pop 은 화면이 담당한다.
class ProfileEditState extends ChangeNotifier {
  ProfileEditState({
    required String initialMode,
    required String? initialAddress,
    required bool initialVerified,
  }) : _mode = initialMode,
       _address = initialAddress,
       _verified = initialVerified;

  // 현재 모드 — 화면 안에서 계정 전환하면 즉시 반영되도록 로컬 상태로 든다
  // (진입 시점 스냅샷이 전환 후 낡은 값이 되는 문제 방지).
  String _mode;
  String? _imageUrl;
  bool _uploading = false;
  bool _saving = false;

  // 활동 지역(동네 인증) — GPS 인증 결과를 화면에 즉시 반영하기 위한 로컬 상태.
  String? _address;
  bool _verified;

  String get mode => _mode;
  bool get isBizMode => _mode == 'business';
  String? get imageUrl => _imageUrl;
  bool get uploading => _uploading;
  bool get saving => _saving;
  String? get address => _address;
  bool get verified => _verified;
  String? get regionName =>
      ProfileData.regionNameFromAddress(_address, verified: _verified);

  /// 계정 전환 패널이 모드를 바꿨을 때(화면 전체가 개인 편집 ↔ 업체 관리로 전환).
  void setMode(String mode) {
    _mode = mode;
    notifyListeners();
  }

  /// 선택된 사진 업로드(선택은 화면의 피커가 선행). 실패 시 false.
  Future<bool> uploadImage(XFile file) async {
    _uploading = true;
    notifyListeners();
    try {
      final up = await StorageService.instance.upload(
        file,
        category: 'profile',
      );
      _imageUrl = up.url;
      return true;
    } catch (e) {
      debugPrint('내정보 수정: 사진 업로드 실패: $e');
      return false;
    } finally {
      _uploading = false;
      notifyListeners();
    }
  }

  /// 프로필 저장(성공 시 화면이 pop). 실패 시 false.
  Future<bool> save(String nickname) async {
    _saving = true;
    notifyListeners();
    try {
      await ProfileRepository.instance.updateProfile(
        nickname: nickname,
        profileImageUrl: _imageUrl,
      );
      return true;
    } catch (e) {
      debugPrint('내정보 수정: 저장 실패: $e');
      return false;
    } finally {
      _saving = false;
      notifyListeners();
    }
  }

  /// GPS 인증 성공 후 서버 값 재조회(인증 화면 이동은 화면이 담당).
  /// 조회 실패해도 인증 자체는 반영됨(내정보 탭이 새로고침으로 따라잡는다).
  Future<void> refreshRegion() async {
    try {
      final r = await ProfileRepository.instance.fetchRegion();
      _address = r.address;
      _verified = r.verified;
      notifyListeners();
    } catch (e) {
      debugPrint('내정보 수정: 활동 지역 재조회 실패(인증은 반영됨): $e');
    }
  }
}
