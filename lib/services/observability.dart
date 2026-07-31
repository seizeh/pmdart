import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../env.dart';
import '../utils/platform_info.dart' as platform;
import 'error_reporter.dart';

/// 오류 보고 부트스트랩 — `main()` 이 `runApp` 대신 [bootstrap] 을 부른다.
///
/// 리포팅은 **우리 DB 로** 받는다(`app.client_errors`). 외부 서비스를 쓰지 않는
/// 이유는 Supabase 가 이미 처리위탁 수탁자라 개인정보처리방침을 고칠 필요가 없고,
/// 관리자 화면에 그대로 붙기 때문이다. 대신 그룹핑·중복제거는 없다 —
/// 발생 지점별 집계(`admin_client_error_summary`)로 대신한다.
abstract final class Observability {
  /// 이 빌드가 쓸 sink. 어느 갈래를 타는지가 "운영 오류 테이블에 개발 노이즈가
  /// 섞이느냐" 를 가르므로 [bootstrap] 에서 떼어내 테스트로 고정한다.
  ///
  /// 디버그에서는 기본적으로 콘솔로만 흘린다 — 개발 중 오류는 리빌드마다 다시
  /// 보고돼(위젯 어서션 하나가 수십 건이 된다) 실사용자 오류를 묻어 버린다.
  /// 전송 경로 자체를 확인할 때만 `REPORT_ERRORS_IN_DEBUG=true` 로 켠다.
  @visibleForTesting
  static ErrorSink resolveSink({
    required bool debugMode,
    required bool reportInDebug,
  }) {
    if (!debugMode) return const SupabaseErrorSink();
    return reportInDebug
        ? const FanOutErrorSink([DebugErrorSink(), SupabaseErrorSink()])
        : const DebugErrorSink();
  }

  static Future<void> bootstrap(Widget app) async {
    ErrorReporter.sink = resolveSink(
      debugMode: kDebugMode,
      reportInDebug: Env.reportErrorsInDebug,
    );

    // 프레임워크가 잡는 오류(위젯 빌드·비동기 누수)를 report 로 흘려보낸다.
    // 이 훅이 없으면 릴리스에서는 어디에도 남지 않는다.
    ErrorReporter.installGlobalHandlers();

    // main() 은 Supabase.initialize 보다 먼저 세션을 복원한다 — 그때 난 오류는
    // sink 가 붙기 전이라 서버로 못 갔다. 링 버퍼에 남은 것을 지금 흘려보낸다.
    ErrorReporter.flushPending();

    runApp(app);
  }
}

/// [ErrorTier.reported] 만 서버로 보낸다.
///
/// 무시·사용자알림까지 보내면 게스트 한 명이 테이블을 채운다. 그 둘은
/// [ErrorReporter.recent] 링 버퍼에만 남아 앱 안에서 진단할 때 쓴다.
///
/// 전송은 **실패해도 되는 일**이다 — 실패를 알리려다 또 실패하면 안 되므로
/// 여기서는 [ErrorReporter] 를 부르지 않는다(무한 재귀).
class SupabaseErrorSink implements ErrorSink {
  const SupabaseErrorSink();

  @override
  void add(ErrorRecord record) {
    if (record.tier != ErrorTier.reported) return;
    unawaited(_send(record));
  }

  static Future<void> _send(ErrorRecord r) async {
    try {
      await Supabase.instance.client.rpc(
        'record_client_error',
        params: {
          'p_where': r.where,
          'p_message': r.error.toString(),
          // 서버가 8,000자로 자르지만 그 전에 네트워크로 나가는 양을 줄인다.
          'p_stack': r.stackTrace?.toString().substring(
            0,
            _min(r.stackTrace.toString().length, 8000),
          ),
          'p_platform': _platform,
          'p_release': Env.appRelease.isEmpty ? null : Env.appRelease,
          'p_extra': r.extra,
        },
      );
    } catch (e) {
      // ErrorReporter 를 부르면 무한 재귀다. 디버그에서만 콘솔로 알린다.
      if (kDebugMode) debugPrint('오류 보고 전송 실패(무시): $e');
    }
  }

  static int _min(int a, int b) => a < b ? a : b;

  /// `dart:io` 를 쓰지 않는다 — 웹에서 런타임에 죽는다(platform_info 주석 참고).
  static String get _platform {
    if (kIsWeb) return 'web';
    if (platform.isIOS) return 'ios';
    if (platform.isAndroid) return 'android';
    return 'other';
  }

  /// 브레드크럼은 서버로 보내지 않는다 — 링 버퍼가 그 역할을 한다.
  @override
  void breadcrumb(
    String message, {
    String? category,
    Map<String, Object?>? data,
  }) {}
}
