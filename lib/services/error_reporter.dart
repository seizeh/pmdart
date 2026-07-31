import 'dart:collection';

import 'package:flutter/foundation.dart';

/// 예외 처리 등급과 보고 경로 — 정책은 `docs/error-policy.md`.
///
/// 이 앱의 `catch` 에 판단이 없었던 건 아니다. 대부분
/// `// 네트워크 오류: 세션 유지(다음 요청에서 재시도)` 처럼 근거가 주석으로 적혀
/// 있었다. 진짜 문제는 그 판단이 **런타임에 아무 흔적도 남기지 않는다**는 것이었다
/// — 무엇이 얼마나 자주 실패하는지 아무도 모른다.
///
/// 그래서 등급을 주석이 아니라 **호출**로 표현한다. 셋 중 하나를 반드시 고른다.
///
/// | 등급 | 호출 | 언제 |
/// |---|---|---|
/// | 무시 | [ignored] | 실패해도 사용자 경험에 영향 없음. `why` 로 근거를 남긴다 |
/// | 사용자 알림 | [userFacing] | 사용자가 다시 시도하면 되는 실패. 호출부가 UI 로 알린다 |
/// | 리포팅 | [report] | 코드나 서버가 잘못됐다. 사용자는 몰라도 우리는 알아야 한다 |
///
/// 어느 등급이든 [recent] 링 버퍼에는 남는다. 원격 전송 여부만 등급에 따라 다르다.
enum ErrorTier {
  /// 무시해도 되는 실패 — 원격 전송하지 않고 브레드크럼으로만 남긴다.
  ignored,

  /// 사용자에게 알린 실패 — 빈도를 보기 위해 남기되 이슈로 올리지는 않는다.
  userFacing,

  /// 리포팅 대상 — 원격으로 보낸다.
  reported,
}

/// 남겨진 한 건.
@immutable
class ErrorRecord {
  const ErrorRecord({
    required this.tier,
    required this.where,
    required this.error,
    this.why,
    this.stackTrace,
    this.extra,
  });

  final ErrorTier tier;

  /// 발생 지점. `'session.refresh'` 처럼 점으로 구분한 짧은 이름을 쓴다
  /// (파일 경로가 아니라 **기능 경로** — 리팩터해도 안 바뀌게).
  final String where;
  final Object error;

  /// [ErrorTier.ignored] 일 때 왜 무시해도 되는지.
  final String? why;
  final StackTrace? stackTrace;
  final Map<String, Object?>? extra;

  @override
  String toString() {
    final b = StringBuffer('[${tier.name}] $where: $error');
    if (why != null) b.write(' (무시 근거: $why)');
    if (extra != null && extra!.isNotEmpty) b.write(' $extra');
    return b.toString();
  }
}

/// 실제 전송을 맡는 곳. 앱 코드는 이 인터페이스를 모른다 — [ErrorReporter] 만 쓴다.
abstract class ErrorSink {
  void add(ErrorRecord record);

  /// 오류 직전 맥락(화면 이동·네트워크 호출 등).
  void breadcrumb(
    String message, {
    String? category,
    Map<String, Object?>? data,
  });
}

/// 아무 데도 보내지 않는다. DSN 미설정 릴리스의 기본값 —
/// 그래도 [ErrorReporter.recent] 링 버퍼에는 남으므로 앱 내 진단은 가능하다.
class SilentErrorSink implements ErrorSink {
  const SilentErrorSink();

  @override
  void add(ErrorRecord record) {}

  @override
  void breadcrumb(
    String message, {
    String? category,
    Map<String, Object?>? data,
  }) {}
}

/// 콘솔로 찍는다. 디버그 빌드 기본값.
class DebugErrorSink implements ErrorSink {
  const DebugErrorSink();

  @override
  void add(ErrorRecord record) {
    debugPrint('⚠️ $record');
    // 무시 등급의 스택까지 찍으면 콘솔이 못 쓰게 된다 — 리포팅만 붙인다.
    if (record.tier == ErrorTier.reported && record.stackTrace != null) {
      debugPrintStack(stackTrace: record.stackTrace, maxFrames: 12);
    }
  }

  @override
  void breadcrumb(
    String message, {
    String? category,
    Map<String, Object?>? data,
  }) {
    debugPrint(
      '· ${category ?? 'app'}: $message${data == null ? '' : ' $data'}',
    );
  }
}

/// 여러 곳으로 동시에 보낸다(예: 디버그 콘솔 + 원격).
class FanOutErrorSink implements ErrorSink {
  const FanOutErrorSink(this._sinks);

  final List<ErrorSink> _sinks;

  @override
  void add(ErrorRecord record) {
    for (final s in _sinks) {
      s.add(record);
    }
  }

  @override
  void breadcrumb(
    String message, {
    String? category,
    Map<String, Object?>? data,
  }) {
    for (final s in _sinks) {
      s.breadcrumb(message, category: category, data: data);
    }
  }
}

/// 앱 전체의 오류 기록 진입점.
abstract final class ErrorReporter {
  /// 부팅 시 한 번 교체한다(예: Sentry 연결). 테스트에서도 이걸로 갈아끼운다.
  static ErrorSink sink = kDebugMode
      ? const DebugErrorSink()
      : const SilentErrorSink();

  static const _maxRecent = 50;
  static final Queue<ErrorRecord> _recent = Queue<ErrorRecord>();

  /// 최근 기록(최신이 뒤). 원격 전송과 무관하게 항상 쌓이므로
  /// 사용자 문의 대응·수동 진단에 쓸 수 있다.
  static List<ErrorRecord> get recent => List.unmodifiable(_recent);

  static void _push(ErrorRecord r) {
    _recent.addLast(r);
    while (_recent.length > _maxRecent) {
      _recent.removeFirst();
    }
    sink.add(r);
  }

  /// 등급 1 — 실패해도 사용자 경험에 영향이 없다.
  ///
  /// [why] 는 선택이 아니다. "왜 무시해도 되는지" 를 못 적겠으면 그건 무시 대상이
  /// 아니라는 신호다.
  static void ignored(
    Object error, {
    required String where,
    required String why,
  }) {
    _push(
      ErrorRecord(
        tier: ErrorTier.ignored,
        where: where,
        error: error,
        why: why,
      ),
    );
  }

  /// 등급 2 — 사용자에게 알린(또는 알릴) 실패. UI 표시는 호출부 책임이고,
  /// 여기서는 빈도를 보기 위해 기록만 한다.
  static void userFacing(
    Object error, {
    required String where,
    StackTrace? stackTrace,
    Map<String, Object?>? extra,
  }) {
    _push(
      ErrorRecord(
        tier: ErrorTier.userFacing,
        where: where,
        error: error,
        stackTrace: stackTrace,
        extra: extra,
      ),
    );
  }

  /// 등급 3 — 코드나 서버가 잘못됐다. 원격으로 보낸다.
  static void report(
    Object error, {
    required String where,
    StackTrace? stackTrace,
    Map<String, Object?>? extra,
  }) {
    _push(
      ErrorRecord(
        tier: ErrorTier.reported,
        where: where,
        error: error,
        stackTrace: stackTrace,
        extra: extra,
      ),
    );
  }

  /// 오류 직전 맥락. 화면 이동·주요 동작에 남겨 두면 리포트를 읽을 수 있게 된다.
  static void breadcrumb(
    String message, {
    String? category,
    Map<String, Object?>? data,
  }) {
    sink.breadcrumb(message, category: category, data: data);
  }

  /// 프레임워크가 잡는 오류를 [report] 로 흘려보낸다.
  ///
  /// 이 훅이 없으면 위젯 빌드 예외와 처리되지 않은 비동기 예외가 **어디에도 남지 않는다**
  /// (릴리스에서는 콘솔조차 없다). `main()` 초입에서 한 번 부른다.
  static void installGlobalHandlers() {
    final priorOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      report(
        details.exception,
        where: 'flutter.${details.library ?? 'widgets'}',
        stackTrace: details.stack,
        extra: {'context': details.context?.toStringDeep().trim()},
      );
      priorOnError?.call(details);
    };

    // 위젯 트리 밖(비동기 콜백 등)에서 새어 나오는 오류.
    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, where: 'platform.uncaught', stackTrace: stack);
      return true; // 앱을 죽이지 않는다 — 기록은 남았다.
    };
  }

  /// 부팅 중 쌓인 리포팅 등급을 지금 sink 로 흘려보낸다.
  ///
  /// `main()` 은 `Supabase.initialize` 보다 **먼저** 세션을 복원한다. 그때 나는
  /// 오류(`session.restoreUser` 등)는 sink 가 붙기 전이라 서버로 갈 수 없다 —
  /// 정작 '반드시 알아야 하는' 축에 드는 것들인데 조용히 사라진다.
  ///
  /// 링 버퍼에는 남아 있으므로 sink 를 붙인 직후 한 번 다시 흘린다.
  /// 그 전에는 아무것도 전송되지 않았으므로 중복이 생기지 않는다
  /// (부팅당 한 번만 부를 것 — [Observability.bootstrap]).
  static void flushPending() {
    for (final r in _recent.where((r) => r.tier == ErrorTier.reported)) {
      sink.add(r);
    }
  }

  /// 테스트 전용 — 링 버퍼를 비운다.
  @visibleForTesting
  static void resetForTest() {
    _recent.clear();
    sink = const SilentErrorSink();
  }
}
