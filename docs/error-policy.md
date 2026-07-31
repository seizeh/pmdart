# 예외 처리 정책 (#157)

## 무엇이 문제였나

`catch (_)` 가 162곳이었고 오류 리포팅이 없었다. 흔한 진단은 "판단 없이 예외를 삼킨다"
지만, 실제로 읽어 보면 **판단은 대부분 있었다.**

```dart
} catch (_) {
  // 네트워크 오류: 세션 유지(다음 요청에서 재시도). 기존 access 로 계속 시도.
}
} catch (_) {
  /* 회수 실패해도 로컬은 정리 */
}
```

진짜 문제는 그 판단이 **런타임에 아무 흔적도 남기지 않는다**는 것이었다.
무엇이 얼마나 자주 실패하는지 알 수 없고, 릴리스에서는 콘솔조차 없다.
전역 오류 훅도 없어서 **위젯 빌드 예외와 처리되지 않은 비동기 예외가 어디에도 안 남았다.**

그래서 이 정책의 목표는 "catch 를 없애기" 가 아니라 **판단을 주석이 아니라 코드로
표현하고 흔적을 남기기** 다.

## 세 등급

모든 `catch` 는 [`ErrorReporter`](../lib/services/error_reporter.dart) 의 셋 중 하나를
부른다.

### 1. 무시 — `ErrorReporter.ignored(e, where:, why:)`

실패해도 사용자 경험에 영향이 없다. 폴백이 이미 있거나, 그 기능이 없어도 되는 경우.

```dart
} catch (e) {
  ErrorReporter.ignored(e, where: 'storage.videoPoster',
      why: '포스터 생성 실패 — 표시 쪽이 기본 썸네일로 폴백한다');
}
```

**`why` 는 선택이 아니다.** 왜 무시해도 되는지 한 줄로 못 적겠으면, 그건 무시 대상이
아니라는 신호다. 이 강제가 이 정책의 핵심이다.

### 2. 사용자 알림 — `ErrorReporter.userFacing(e, where:, stackTrace:)`

사용자가 다시 시도하면 되는 실패. **UI 표시는 호출부 책임**이고, 이 호출은 빈도를
보기 위한 기록이다.

```dart
} catch (e, st) {
  ErrorReporter.userFacing(e, where: 'auth.login', stackTrace: st);
  return const AuthResult(ok: false, errorCode: 'network_error');
}
```

### 3. 리포팅 — `ErrorReporter.report(e, where:, stackTrace:)`

코드나 서버가 잘못됐다. **사용자는 몰라도 우리는 알아야 한다.**

```dart
} catch (e, st) {
  // 저장된 사용자 JSON 이 깨졌다 = 모델 변경과 저장본이 어긋났다는 뜻.
  ErrorReporter.report(e, where: 'session.restoreUser', stackTrace: st);
  _user = null;
}
```

## 어디로 가나

| 등급 | 링 버퍼(`recent`) | Sentry |
|---|---|---|
| 무시 | ✅ | 브레드크럼(info) — 이벤트 아님 |
| 사용자 알림 | ✅ | 브레드크럼(warning) — 이벤트 아님 |
| 리포팅 | ✅ | `captureException` — **이벤트** |

등급을 나눈 이유는 비용이다. 전부 이벤트로 올리면 **지하철에 있는 사용자 한 명이
무료 쿼터를 다 쓴다.** 무시·사용자알림은 리포트에 **맥락으로** 붙을 때 의미가 있지,
그 자체가 알림이 될 이유는 없다.

`recent` 링 버퍼(최근 50건)는 전송 여부와 무관하게 항상 쌓인다 — DSN 이 없어도
앱 안에서 진단할 수 있다.

## `where` 짓는 법

`'session.refresh'` 처럼 **점으로 구분한 기능 경로**를 쓴다. 파일 경로가 아니다 —
리팩터로 파일이 옮겨져도 같은 지점을 가리켜야 대시보드의 추이가 이어진다.

## 켜는 법

DSN 은 **기본값이 없다.** 개발·테스트 실행이 운영 프로젝트로 이벤트를 흘리면 신호가
잡음에 묻히기 때문이다(`jusoApiKey` 와 같은 관용구).

```bash
flutter build web --release \
  --dart-define=SENTRY_DSN=https://…@…ingest.sentry.io/… \
  --dart-define=SENTRY_ENVIRONMENT=production \
  --dart-define=APP_RELEASE=pawmate@2.0.0+6
```

비어 있으면 [`Observability.bootstrap`](../lib/services/observability.dart) 이
Sentry 초기화를 통째로 건너뛴다 — 동작은 종전과 완전히 같다.

### 전역 훅

Sentry 가 꺼져 있을 때만 `ErrorReporter.installGlobalHandlers()` 가
`FlutterError.onError` 와 `PlatformDispatcher.onError` 를 잡는다. Sentry 를 켜면
그쪽 통합이 같은 훅을 쓰므로, 둘 다 걸면 **한 오류가 두 번 보고된다.**

### 보내지 않는 것

- `sendDefaultPii = false` — 이 앱의 식별자는 **전화번호**라 특히 위험하다
  (개인정보처리방침 — `pmlegal`). 사용자 식별이 필요하면 `users.id` 만 태그로 붙인다.
- `SocketException` · `ClientException` · `TimeoutException` 은 `beforeSend` 에서
  버린다 — 오프라인은 장애가 아니다.

## 래칫 — 남은 것을 어떻게 줄이나

162곳을 한 번에 고치지 않는다. **늘어나지 않게 못 박고 줄여 간다** — 커버리지 래칫과
같은 방식이다([ADR-0007](adr/0007-coverage-ratchet.md)).

CI 가 `lib/` 의 `catch (_)` 개수를 세어 상한을 넘으면 실패한다. 지금 상한은 **122**.
줄일 때마다 상한도 함께 내린다.

| 단계 | 남은 `catch (_)` |
|---|---:|
| 시작 | 162 |
| 세션·인증·업로드 등 위험 경로 18곳 | 144 |
| 네트워크를 타는 리포지토리 3개 22곳 | **122** |

새 코드에는 `catch (_)` 를 쓰지 않는다. 셋 중 하나를 고르면 된다.

## 남은 일

- 나머지 122곳 등급화 — 화면 계층(`lib/screen/`)이 대부분이다(`map_tab.dart` 12곳 등).
  UI 방어성 `catch` 가 많아 실사용 실패와는 거리가 있어 후순위다
- 브레드크럼을 화면 전환·주요 동작에 심어 리포트를 읽을 수 있게 만들기
- Sentry 프로젝트 개설 후 DSN 주입(현재는 코드만 준비된 상태)
