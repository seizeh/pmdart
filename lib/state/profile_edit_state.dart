import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

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
    String? initialImageUrl,
  }) : _mode = initialMode,
       _address = initialAddress,
       _verified = initialVerified,
       _originalImageUrl = initialImageUrl;

  /// 진입 시점의 프로필 사진 — 교체 저장 성공 시 구 파일 정리에 쓴다(#233).
  /// null 이면(집계 미전달) 정리를 건너뛴다.
  final String? _originalImageUrl;

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

  // 현재 모드 — 화면 안에서 계정 전환하면 즉시 반영되도록 로컬 상태로 든다
  // (진입 시점 스냅샷이 전환 후 낡은 값이 되는 문제 방지).
  String _mode;
  String? _imageUrl;
  bool _uploading = false;
  bool _saving = false;

  // 활동 지역(동네 인증) — GPS 인증 결과를 화면에 즉시 반영하기 위한 로컬 상태.
  String? _address;
  bool _verified;

  // 닉네임 실시간 중복확인 — 디바운스는 화면(입력)이, RPC 호출·결과만 홀더가.
  // null = 표시 없음(빈 값·원래 닉네임 그대로·확인 실패), true/false = 가능/중복.
  bool? _nickAvailable;
  int _nickCheckSeq = 0; // 늦게 도착한 이전 응답이 최신 입력 결과를 덮지 않게

  // 저장 실패 사유(스낵바용) — 닉네임 중복(23505)만 구분, 그 외는 null.
  String? _saveError;

  String get mode => _mode;
  bool get isBizMode => _mode == 'business';
  String? get imageUrl => _imageUrl;
  bool get uploading => _uploading;
  bool get saving => _saving;
  bool? get nickAvailable => _nickAvailable;
  String? get saveError => _saveError;
  String? get address => _address;
  bool get verified => _verified;
  String? get regionName =>
      ProfileData.regionNameFromAddress(_address, verified: _verified);

  /// 계정 전환 패널이 모드를 바꿨을 때(화면 전체가 개인 편집 ↔ 업체 관리로 전환).
  void setMode(String mode) {
    _mode = mode;
    _notify();
  }

  /// 선택된 사진 업로드(선택은 화면의 피커가 선행). 실패 시 false.
  Future<bool> uploadImage(XFile file) async {
    _uploading = true;
    _notify();
    try {
      final prev = _imageUrl;
      final up = await StorageService.instance.upload(
        file,
        category: 'profile',
      );
      _imageUrl = up.url;
      // 같은 세션에서 다시 고른 경우 — 직전 업로드는 저장 전이라 고아가 된다(#233).
      if (prev != null && prev != up.url) {
        unawaited(StorageService.instance.discardByUrl(prev));
      }
      return true;
    } catch (e) {
      debugPrint('내정보 수정: 사진 업로드 실패: $e');
      return false;
    } finally {
      _uploading = false;
      _notify();
    }
  }

  /// 닉네임 중복확인(화면이 디바운스 후 호출). [original] 은 진입 시점 닉네임 —
  /// 그대로면(또는 빈 값) 확인 없이 표시를 지운다.
  Future<void> checkNickname(
    String nickname, {
    required String original,
  }) async {
    final nick = nickname.trim();
    final seq = ++_nickCheckSeq;
    if (nick.isEmpty || nick == original.trim()) {
      _nickAvailable = null;
      _notify();
      return;
    }
    try {
      final ok = await ProfileRepository.instance.checkNicknameAvailable(nick);
      if (seq != _nickCheckSeq) return;
      _nickAvailable = ok;
    } catch (e) {
      if (seq != _nickCheckSeq) return;
      _nickAvailable = null; // 확인 실패로 저장을 막지 않는다 — 최종 판정은 제약
      debugPrint('내정보 수정: 닉네임 확인 실패: $e');
    }
    _notify();
  }

  /// 프로필 저장(성공 시 화면이 pop). 실패 시 false — 닉네임 중복(23505)이면
  /// [saveError] 에 사유를 담는다(선체크를 지나친 경합도 여기서 잡힌다).
  Future<bool> save(String nickname) async {
    _saving = true;
    _saveError = null;
    _notify();
    try {
      await ProfileRepository.instance.updateProfile(
        nickname: nickname,
        profileImageUrl: _imageUrl,
      );
      // 사진 교체 저장 성공 — 이전 사진 파일은 더 이상 참조되지 않는다(#233).
      if (_imageUrl != null &&
          _originalImageUrl != null &&
          _originalImageUrl != _imageUrl) {
        unawaited(StorageService.instance.discardByUrl(_originalImageUrl));
      }
      return true;
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        _saveError = '이미 사용 중인 닉네임이에요';
        _nickAvailable = false; // 폼 표시도 중복으로 동기화
      }
      debugPrint('내정보 수정: 저장 실패: $e');
      return false;
    } catch (e) {
      debugPrint('내정보 수정: 저장 실패: $e');
      return false;
    } finally {
      _saving = false;
      _notify();
    }
  }

  /// GPS 인증 성공 후 서버 값 재조회(인증 화면 이동은 화면이 담당).
  /// 조회 실패해도 인증 자체는 반영됨(내정보 탭이 새로고침으로 따라잡는다).
  Future<void> refreshRegion() async {
    try {
      final r = await ProfileRepository.instance.fetchRegion();
      _address = r.address;
      _verified = r.verified;
      _notify();
    } catch (e) {
      debugPrint('내정보 수정: 활동 지역 재조회 실패(인증은 반영됨): $e');
    }
  }
}
