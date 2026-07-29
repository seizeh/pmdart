import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../env.dart';
import 'error_reporter.dart';

/// 오류 보고 부트스트랩 — `main()` 이 `runApp` 대신 [bootstrap] 을 부른다.
///
/// `Env.sentryDsn` 이 비어 있으면 **Sentry 를 통째로 건너뛴다**. 그때 동작은
/// 종전과 완전히 같고([ErrorReporter] 기본 sink 만 동작), DSN 을 주입한 빌드에서만
/// 원격 전송이 켜진다 — `webPushVapidKey`·`jusoApiKey` 와 같은 관용구다.
abstract final class Observability {
  static Future<void> bootstrap(Widget app) async {
    if (Env.sentryDsn.isEmpty) {
      // Sentry 가 없을 때만 우리가 전역 훅을 건다. Sentry 를 켜면 그쪽 통합이
      // 같은 훅을 잡으므로, 둘 다 걸면 한 오류가 두 번 보고된다.
      ErrorReporter.installGlobalHandlers();
      runApp(app);
      return;
    }

    ErrorReporter.sink = kDebugMode
        ? const FanOutErrorSink([DebugErrorSink(), SentryErrorSink()])
        : const SentryErrorSink();

    await SentryFlutter.init((options) {
      options.dsn = Env.sentryDsn;
      options.environment = Env.sentryEnvironment;
      options.release = Env.appRelease.isEmpty ? null : Env.appRelease;

      // 성능 추적은 켜지 않는다 — 지금 필요한 건 '장애가 났는지' 이지 지연 분포가
      // 아니고, 무료 쿼터를 오류 이벤트에 쓰는 편이 낫다. 필요해지면 켠다.
      options.tracesSampleRate = 0.0;

      // 개인정보는 보내지 않는다. 이 앱의 식별자는 전화번호라 특히 위험하다
      // (개인정보처리방침 — pmlegal). 사용자 식별이 필요하면 users.id 만 태그로.
      options.sendDefaultPii = false;

      options.beforeSend = (event, hint) {
        // 오프라인·일시 네트워크 오류는 리포팅 가치가 없고 쿼터만 먹는다.
        final type = event.throwable?.runtimeType.toString() ?? '';
        if (type.contains('SocketException') ||
            type.contains('ClientException') ||
            type.contains('TimeoutException')) {
          return null;
        }
        return event;
      };
    }, appRunner: () => runApp(app));
  }
}

/// [ErrorReporter] 등급을 Sentry 개념으로 옮긴다.
///
/// 등급별로 보내는 방식이 다르다 — 전부 이벤트로 올리면 오프라인 사용자 한 명이
/// 쿼터를 다 쓴다.
///
/// | 등급 | Sentry |
/// |---|---|
/// | 무시 | 브레드크럼(info) — 이벤트 아님 |
/// | 사용자 알림 | 브레드크럼(warning) — 이벤트 아님. 리포트에 맥락으로 붙는다 |
/// | 리포팅 | `captureException` — 이벤트 |
class SentryErrorSink implements ErrorSink {
  const SentryErrorSink();

  @override
  void add(ErrorRecord record) {
    switch (record.tier) {
      case ErrorTier.ignored:
        Sentry.addBreadcrumb(
          Breadcrumb(
            message: '${record.where}: ${record.error}',
            category: 'ignored',
            level: SentryLevel.info,
            data: {'why': record.why ?? ''},
          ),
        );
      case ErrorTier.userFacing:
        Sentry.addBreadcrumb(
          Breadcrumb(
            message: '${record.where}: ${record.error}',
            category: 'user-facing',
            level: SentryLevel.warning,
          ),
        );
      case ErrorTier.reported:
        Sentry.captureException(
          record.error,
          stackTrace: record.stackTrace,
          withScope: (scope) {
            scope.setTag('where', record.where);
            final extra = record.extra;
            if (extra != null) {
              for (final e in extra.entries) {
                scope.setContexts(e.key, e.value);
              }
            }
          },
        );
    }
  }

  @override
  void breadcrumb(
    String message, {
    String? category,
    Map<String, Object?>? data,
  }) {
    Sentry.addBreadcrumb(
      Breadcrumb(message: message, category: category ?? 'app', data: data),
    );
  }
}
