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

| 등급 | 링 버퍼(`recent`) | 서버(`app.client_errors`) |
|---|---|---|
| 무시 | ✅ | ❌ |
| 사용자 알림 | ✅ | ❌ |
| 리포팅 | ✅ | ✅ |

**리포팅만 서버로 보낸다.** 셋 다 보내면 게스트 한 명이 테이블을 채운다. 무시·사용자알림은
링 버퍼(최근 50건)에만 남아 앱 안에서 진단할 때 쓴다.

### 왜 외부 서비스가 아니라 우리 DB 인가

Sentry 를 붙였다가 되돌렸다. 판단 근거:

- **개인정보처리방침** — Supabase 는 **이미 처리위탁 수탁자**다. 외부 리포팅 서비스를
  쓰면 수탁자를 추가하고 국외이전을 고지해야 한다(`pmlegal`). 베타 전에 치러야 할 비용이었다.
- **CSP** — `sentry_flutter` 는 웹에서 `browser.sentry-cdn.com` 의 JS SDK 를 `<script>` 로
  끼워 넣는다. `script-src` 를 열어야 했다. 우리 DB 는 `connect-src` 에 이미 있다.
- **관리자 화면** — 이미 있는 관리자 대시보드에 그대로 붙는다.

**잃은 것은 그룹핑·중복제거·릴리스 비교다.** 같은 오류 1,000건이 1,000행이 된다.
베타 규모(5~10명)에서는 값이 작다고 봤고, 대신 **발생 지점별 집계**로 "어디가 자주
터지나" 를 본다(`admin_client_error_summary`). 사용자가 늘어 그룹핑이 필요해지면
`ErrorReporter.sink` 만 갈아끼우면 된다 — 앱 코드는 한 줄도 안 바뀐다.

### 수집 경로

```
ErrorReporter.report(...)
  → SupabaseErrorSink
  → public.record_client_error RPC   (SECURITY DEFINER)
  → app.client_errors                (30일 보존, cleanup_retention 이 파기)
```

RPC 는 **`anon` 에게도 열려 있다** — 웹은 비로그인 방문자가 주 진입로라 그들의 오류를
못 받으면 목적의 절반이 사라진다. 공개 쓰기 엔드포인트가 되므로 넷을 전제로 깔았다.

1. **레이트리밋** — 2단. 개별 30/분(로그인=계정, 익명=IP) + 익명 전역 300/분.
   처음엔 익명을 단일 버킷 300/분으로 뒀는데, 그러면 **방문자 한 명의 오류 루프가
   전역 예산을 태워 다른 모두의 오류를 조용히 버린다** — 제일 알고 싶은 순간에
   눈이 먼다. IP 는 서버가 `cf-connecting-ip` 에서 뽑고(위조하면 Cloudflare 가 요청을 거부한다 — 실측)
   60초 버킷 키로만 쓰고 저장하지 않는다([ADR-0011](adr/0011-self-hosted-error-collection.md))
2. **서버측 길이 절단** — `message` 500자 · `stack` 8,000자 · 과대 `extra` 는 표식+앞부분만 남김
3. **예외 삼킴** — 서버도 클라이언트도. 오류 보고가 또 오류를 만들면 안 된다
4. **등급 제한** — `reported` 만

전송 실패는 **조용히 버린다.** 여기서 `ErrorReporter` 를 부르면 무한 재귀다
(디버그 빌드에서만 콘솔로 알린다).

### 보는 곳

관리자 앱 → **클라이언트 오류**. 상단에 최근 24시간 발생 지점 집계가 뜨고, 칩을 누르면
그 지점만 걸러 본다. 항목을 누르면 스택을 편다.

SQL 로 직접 볼 수도 있다:

```sql
select * from public.admin_client_error_summary(24);   -- 발생 지점별
select * from public.admin_client_errors(null, 100, 0); -- 최근 100건
```

## `where` 짓는 법

`'session.refresh'` 처럼 **점으로 구분한 기능 경로**를 쓴다. 파일 경로가 아니다 —
리팩터로 파일이 옮겨져도 같은 지점을 가리켜야 대시보드의 추이가 이어진다.

## 켜는 법 — 이미 켜져 있다

시크릿도 DSN 도 필요 없다. `SupabaseErrorSink` 가 기본 sink 라 앱을 띄우면 그때부터
`reported` 등급이 서버로 올라간다.

`APP_RELEASE` 만 빌드에서 주입하면 "어느 배포부터 생긴 오류인지" 를 볼 수 있다.
웹은 `deploy-web.yml` 이 `pubspec.yaml` 버전에서 뽑아 자동으로 넣는다. 앱은 수동이다:

```bash
flutter build ipa --release --dart-define=APP_RELEASE=pawmate@2.0.0+10
```

### 전역 훅

`FlutterError.onError` 와 `PlatformDispatcher.onError` 를 `report` 로 흘려보낸다.
이 훅이 없으면 위젯 빌드 예외와 처리되지 않은 비동기 예외가 **어디에도 남지 않는다**.

### 보내지 않는 것

- 개인정보를 payload 에 담지 않는다. 이 앱의 식별자는 **전화번호**라 특히 위험하다.
  사용자 식별은 서버가 `app.uid()` 로 붙이는 `user_id` 하나뿐이다.
- `ignored`·`userFacing` 등급 — 링 버퍼에만.

## 래칫 — 남은 것을 어떻게 줄이나

162곳을 한 번에 고치지 않는다. **늘어나지 않게 못 박고 줄여 간다** — 커버리지 래칫과
같은 방식이다([ADR-0007](adr/0007-coverage-ratchet.md)).

CI 가 `lib/` 의 `catch (_)` 개수를 세어 상한을 넘으면 실패한다. 지금 상한은 **110**.
줄일 때마다 상한도 함께 내린다.

| 단계 | 남은 `catch (_)` |
|---|---:|
| 시작 | 162 |
| 세션·인증·업로드 등 위험 경로 18곳 | 144 |
| 네트워크를 타는 리포지토리 3개 22곳 | 122 |
| `map_tab.dart` 12곳 | **110** |

**순서는 "많은 곳" 이 아니라 "모르면 곤란한 곳" 으로 잡는다.** 리포지토리를 먼저 한
이유가 그것이고, 다음이 `map_tab.dart` 였던 이유도 같다 — 지도는 네이버 SDK ·
위치 권한 · 네트워크가 한꺼번에 얽혀 베타에서 가장 깨지기 쉬운 화면인데,
"지도가 안 떠요" 라는 신고를 받고도 이유를 알 방법이 없었다.

12곳을 4:8 로 갈랐다. 지도가 비거나 결과가 사라지는 4곳만 `report`(서버로 보낸다):

| 지점 | 등급 | 이유 |
|---|---|---|
| `map.loadFacilities` | report | 지도가 비는 경로. "지도가 안 떠요" 가 여기로 수렴한다 |
| `map.loadClusters` | report | 빈 배열을 돌려주면 호출부가 성공으로 본다 — 게시글이 조용히 사라진다 |
| `map.search` | report | 삼키면 '검색 결과가 없어요' 가 뜬다. 실패를 없음으로 바꿔 보여주는 셈 |
| `map.addSearchMarker` | report | 찾긴 찾았는데 표시가 없는 상태가 된다 |
| 아이콘 렌더 5곳 · 마커 정리 3곳 | ignored | 전부 폴백이 있다(기본 마커로 뜨거나 다음 로드가 다시 그린다) |

새 코드에는 `catch (_)` 를 쓰지 않는다. 셋 중 하나를 고르면 된다.

## 남은 일

- 나머지 110곳 등급화 — 화면 계층(`lib/screen/`)이 대부분이다.
  UI 방어성 `catch` 가 많아 실사용 실패와는 거리가 있어 후순위다
- 브레드크럼을 화면 전환·주요 동작에 심어 리포트를 읽을 수 있게 만들기
