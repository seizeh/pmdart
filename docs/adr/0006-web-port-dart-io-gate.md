# ADR-0006: 웹 이식 — `dart:io` 직접 사용을 CI 로 금지

- 상태: 채택 (2026-07)
- 관련: `.github/workflows/ci.yml`(dart:io 게이트·웹 빌드), `lib/utils/platform_info.dart`,
  `lib/utils/temp_file_io.dart`, `docs/web-port.md`

## 맥락

iOS/Android 로 먼저 만든 앱을 웹으로 이식했다. Flutter Web 에서 `dart:io` 는
**컴파일이 된다.** 대신 `Platform.isIOS`, `File(...)` 같은 게 **런타임에
`UnsupportedError` 를 던진다.**

즉 이 부류의 회귀는

- `flutter analyze` 로 안 잡힌다
- `flutter build web` 으로도 안 잡힌다
- 화면이 흰 채로 뜨는 것으로만 드러난다

이식 중 실제로 여기에 당했고, 원인을 찾는 데 시간이 오래 걸렸다.

## 결정

플랫폼 분기와 파일 조작을 **파사드로 모으고, `dart:io` 직접 import 를 CI 가 막는다.**

- 플랫폼 판별 → `lib/utils/platform_info.dart`
- 파일 조작 → 조건부 import 파사드. `lib/utils/temp_file_io.dart` 하나만 게이트에서 예외
- CI 게이트:

```bash
git ls-files | grep -E '^lib/.*\.dart$' \
  | grep -v '^lib/utils/temp_file_io\.dart$' \
  | xargs grep -ln "^import 'dart:io'" || true
# 결과가 있으면 실패
```

- 추가로 `flutter build web --release` 를 CI 에 넣어 번들이 조용히 깨지는 것을 막는다

## 검토한 대안

| 대안 | 기각 사유 |
|---|---|
| 코드 리뷰로 관리 | 리뷰어가 나 혼자다. 사람이 기억할 규칙이 아니다 |
| 린트 규칙(custom_lint) | 도입 비용 대비 이득이 적다. grep 한 줄로 같은 효과 |
| 웹 E2E 테스트 | 유지 비용이 크고, 흰 화면은 특정 경로를 밟아야 재현된다 |

## 결과

- 파일 조작이 필요하면 파사드에 함수를 추가해야 한다(한 겹 늘어난다)
- 대신 **한 번 당한 버그가 같은 방식으로 두 번 나지 않는다**
- 웹 빌드 게이트는 **컴파일 회귀만** 잡는다. 런타임 회귀는 위 게이트가 일부를 담당하고,
  나머지는 여전히 수동 확인 영역이다 — 이 한계를 CI 주석에 적어 뒀다

### 남은 한계

`dart:io` 를 안 써도 웹에서만 깨지는 것들이 있다(예: 포그라운드 푸시 표시 경로).
게이트는 **알려진 한 부류**를 막을 뿐 웹 동작을 보증하지 않는다.
