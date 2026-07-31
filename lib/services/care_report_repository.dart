import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'error_reporter.dart';
import 'session.dart';

/// 케어 리포트(0028 P1 — 미용 전후 사진) 데이터 접근.
/// 발행은 has_license('grooming') 게이트가 서버에서 재검증한다.
class CareReportRepository {
  CareReportRepository._();
  static final CareReportRepository instance = CareReportRepository._();

  SupabaseClient get _c => Supabase.instance.client;

  /// 발행 — 성공 시 공유 토큰, 실패 시 에러 코드
  /// (license_required / invalid_pet_label / invalid_photos / invalid_phone / network).
  /// [recipientPhone] 은 선택 — 넣으면 손님 가입 시 자동 연결(0028 §4.2).
  Future<({String? token, String? error})> create({
    required String petLabel,
    required List<String> photoUrls,
    String? note,
    String? recipientPhone,
  }) async {
    if (SessionManager.instance.user == null) {
      return (token: null, error: 'auth');
    }
    try {
      final res = await _c.rpc(
        'create_care_report',
        params: {
          'p_pet_label': petLabel.trim(),
          'p_photos': photoUrls,
          'p_note': (note ?? '').trim().isEmpty ? null : note!.trim(),
          'p_recipient_phone': (recipientPhone ?? '').trim().isEmpty
              ? null
              : recipientPhone!.trim(),
        },
      );
      final token = (res as Map<String, dynamic>)['token'] as String?;
      return (token: token, error: token == null ? 'network' : null);
    } on PostgrestException catch (e) {
      const codes = [
        'license_required',
        'invalid_pet_label',
        'invalid_photos',
        'invalid_phone',
      ];
      for (final c in codes) {
        if (e.message.contains(c)) return (token: null, error: c);
      }
      return (token: null, error: 'network');
    } catch (e, st) {
      ErrorReporter.userFacing(e, where: 'careReport.create', stackTrace: st);
      return (token: null, error: 'network');
    }
  }

  /// 내가 발행한 리포트(업체) — 수령자 연결 상태 표시용.
  Future<List<IssuedCareReport>> fetchMine() async {
    try {
      final rows = await _c.rpc('my_care_reports', params: {'p_limit': 50});
      return (rows as List)
          .map((r) => IssuedCareReport.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      // 빈 목록은 '보낸 리포트 없음' 으로 보인다 — 발행 기록이 통째로 사라진다.
      ErrorReporter.report(e, where: 'careReport.fetchMine', stackTrace: st);
      return const [];
    }
  }

  /// 내가 받은 리포트(보호자).
  Future<List<ReceivedCareReport>> fetchReceived() async {
    try {
      final rows = await _c.rpc(
        'my_received_care_reports',
        params: {'p_limit': 50},
      );
      return (rows as List)
          .map((r) => ReceivedCareReport.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      // 빈 목록은 '받은 기록 없음' 으로 보인다 — 업체가 보낸 알림장이 안 보인다.
      ErrorReporter.report(
        e,
        where: 'careReport.fetchReceived',
        stackTrace: st,
      );
      return const [];
    }
  }

  // ── 위탁 알림장(0028 P2 §4.4) — 스레드 = 펫×업체 상시 1개 ──

  /// 스레드 생성 — 성공 시 id, 실패 시 에러 코드.
  Future<({String? id, String? error})> createThread({
    required String petLabel,
    String? recipientPhone,
  }) async {
    try {
      final res = await _c.rpc(
        'create_care_thread',
        params: {
          'p_pet_label': petLabel.trim(),
          'p_recipient_phone': (recipientPhone ?? '').trim().isEmpty
              ? null
              : recipientPhone!.trim(),
        },
      );
      return (id: res as String?, error: null);
    } on PostgrestException catch (e) {
      const codes = ['license_required', 'invalid_pet_label', 'invalid_phone'];
      for (final c in codes) {
        if (e.message.contains(c)) return (id: null, error: c);
      }
      return (id: null, error: 'network');
    } catch (e, st) {
      ErrorReporter.userFacing(
        e,
        where: 'careReport.createThread',
        stackTrace: st,
      );
      return (id: null, error: 'network');
    }
  }

  /// 알림장 발행 — 성공 시 공유 토큰(미연결 보호자 재전송용).
  Future<({String? token, String? error})> createBoardingReport({
    required String threadId,
    List<String> photoUrls = const [],
    Map<String, String> body = const {},
    String? note,
  }) async {
    try {
      final res = await _c.rpc(
        'create_boarding_report',
        params: {
          'p_thread': threadId,
          'p_photos': photoUrls,
          'p_body': {
            for (final e in body.entries)
              if (e.value.trim().isNotEmpty) e.key: e.value.trim(),
          },
          'p_note': (note ?? '').trim().isEmpty ? null : note!.trim(),
        },
      );
      final token = (res as Map<String, dynamic>)['token'] as String?;
      return (token: token, error: token == null ? 'network' : null);
    } on PostgrestException catch (e) {
      const codes = [
        'license_required',
        'thread_not_found',
        'invalid_photos',
        'empty_report',
      ];
      for (final c in codes) {
        if (e.message.contains(c)) return (token: null, error: c);
      }
      return (token: null, error: 'network');
    } catch (e, st) {
      ErrorReporter.userFacing(
        e,
        where: 'careReport.createBoardingReport',
        stackTrace: st,
      );
      return (token: null, error: 'network');
    }
  }

  /// 업체 스레드 목록(보관은 서버 파생값).
  Future<List<CareThread>> fetchThreads() async {
    try {
      final rows = await _c.rpc('my_care_threads', params: {'p_limit': 100});
      return (rows as List)
          .map((r) => CareThread.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      // 빈 목록은 '진행 중 돌봄 없음' 으로 보인다.
      ErrorReporter.report(e, where: 'careReport.fetchThreads', stackTrace: st);
      return const [];
    }
  }

  /// 스레드 기록(최신순) — 업체 소유 또는 연결 보호자만(서버 검증).
  Future<List<ThreadReport>> fetchThreadReports(String threadId) async {
    try {
      final rows = await _c.rpc(
        'care_thread_reports',
        params: {'p_thread': threadId, 'p_limit': 200},
      );
      return (rows as List)
          .map((r) => ThreadReport.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (e, st) {
      // 빈 목록은 '알림장 없음' 으로 보인다.
      ErrorReporter.report(
        e,
        where: 'careReport.fetchThreadReports',
        stackTrace: st,
      );
      return const [];
    }
  }

  /// 전화번호 대조 자동 연결(0028 §4.2) — 앱 시작·가입 직후 호출.
  /// 연결 건수 반환(알림은 서버가 발송). 실패는 조용히 0(다음 시작 때 재시도).
  Future<int> claim() async {
    if (SessionManager.instance.user == null) return 0;
    try {
      final n = await _c.rpc('claim_care_reports');
      return (n as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('케어 리포트 claim 실패(무해 — 다음 시작 때 재시도): $e');
      return 0;
    }
  }
}

/// 발행한 리포트 1건 (my_care_reports RPC 기준).
class IssuedCareReport {
  final String id;
  final String petLabel;
  final List<String> photos;
  final String? note;
  final DateTime? createdAt;
  final String? claimedNickname; // null = 미연결
  final String? token;
  final DateTime? expiresAt;
  final int viewCount;

  const IssuedCareReport({
    required this.id,
    required this.petLabel,
    required this.photos,
    this.note,
    this.createdAt,
    this.claimedNickname,
    this.token,
    this.expiresAt,
    this.viewCount = 0,
  });

  factory IssuedCareReport.fromJson(Map<String, dynamic> j) => IssuedCareReport(
    id: (j['id'] ?? '') as String,
    petLabel: (j['pet_label'] ?? '') as String,
    photos: [for (final u in (j['photos'] as List? ?? const [])) u.toString()],
    note: j['note'] as String?,
    createdAt: DateTime.tryParse((j['created_at'] ?? '') as String)?.toLocal(),
    claimedNickname: j['claimed_nickname'] as String?,
    token: j['token'] as String?,
    expiresAt: DateTime.tryParse((j['expires_at'] ?? '') as String)?.toLocal(),
    viewCount: (j['view_count'] as num?)?.toInt() ?? 0,
  );
}

/// 받은 리포트 1건 (my_received_care_reports RPC 기준).
class ReceivedCareReport {
  final String id;
  final String kind; // grooming | boarding
  final String petLabel;
  final List<String> photos;
  final Map<String, dynamic> body; // 알림장 구조 필드(식사·배변 등)
  final String? note;
  final DateTime? createdAt;
  final String? businessName;
  final String? threadId; // boarding — 스레드 뷰 진입용

  const ReceivedCareReport({
    required this.id,
    required this.kind,
    required this.petLabel,
    required this.photos,
    this.body = const {},
    this.note,
    this.createdAt,
    this.businessName,
    this.threadId,
  });

  factory ReceivedCareReport.fromJson(
    Map<String, dynamic> j,
  ) => ReceivedCareReport(
    id: (j['id'] ?? '') as String,
    kind: (j['kind'] ?? 'grooming') as String,
    petLabel: (j['pet_label'] ?? '') as String,
    photos: [for (final u in (j['photos'] as List? ?? const [])) u.toString()],
    body: (j['body'] as Map?)?.cast<String, dynamic>() ?? const {},
    note: j['note'] as String?,
    createdAt: DateTime.tryParse((j['created_at'] ?? '') as String)?.toLocal(),
    businessName: j['business_name'] as String?,
    threadId: j['thread_id'] as String?,
  );
}

/// 알림장 스레드 1개 (my_care_threads RPC 기준) — 보관(archived)은 서버 파생값.
class CareThread {
  final String id;
  final String petLabel;
  final String? claimedNickname; // null = 미연결
  final DateTime? lastReportAt;
  final int reportCount;
  final String? lastPhoto;
  final bool archived;

  const CareThread({
    required this.id,
    required this.petLabel,
    this.claimedNickname,
    this.lastReportAt,
    this.reportCount = 0,
    this.lastPhoto,
    this.archived = false,
  });

  factory CareThread.fromJson(Map<String, dynamic> j) => CareThread(
    id: (j['id'] ?? '') as String,
    petLabel: (j['pet_label'] ?? '') as String,
    claimedNickname: j['claimed_nickname'] as String?,
    lastReportAt: DateTime.tryParse(
      (j['last_report_at'] ?? '') as String,
    )?.toLocal(),
    reportCount: (j['report_count'] as num?)?.toInt() ?? 0,
    lastPhoto: j['last_photo'] as String?,
    archived: j['archived'] == true,
  );
}

/// 스레드 기록 1건 (care_thread_reports RPC 기준).
class ThreadReport {
  final String id;
  final List<String> photos;
  final Map<String, dynamic> body;
  final String? note;
  final DateTime? createdAt;
  final String? token; // 미연결 보호자 링크 재전송용

  const ThreadReport({
    required this.id,
    required this.photos,
    this.body = const {},
    this.note,
    this.createdAt,
    this.token,
  });

  factory ThreadReport.fromJson(Map<String, dynamic> j) => ThreadReport(
    id: (j['id'] ?? '') as String,
    photos: [for (final u in (j['photos'] as List? ?? const [])) u.toString()],
    body: (j['body'] as Map?)?.cast<String, dynamic>() ?? const {},
    note: j['note'] as String?,
    createdAt: DateTime.tryParse((j['created_at'] ?? '') as String)?.toLocal(),
    token: j['token'] as String?,
  );
}

/// 알림장 구조 필드 라벨 — 뷰어(share-view)·앱 공통 키.
const kBoardingBodyFields = <(String, String, String)>[
  ('meal', '🍚 식사', '예: 사료 완식'),
  ('potty', '🚽 배변', '예: 정상 2회'),
  ('mood', '😊 컨디션', '예: 활발해요'),
  ('walk', '🐾 산책', '예: 30분 산책'),
];

String boardingBodyLabel(String key) => switch (key) {
  'meal' => '🍚 식사',
  'potty' => '🚽 배변',
  'mood' => '😊 컨디션',
  'walk' => '🐾 산책',
  _ => key,
};
