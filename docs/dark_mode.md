# 다크모드 (2026-07)

앱 전체 다크모드 구조 정리. 관련 PR: `feat/dark-mode` 브랜치(팔레트 도입 → 전면 이행 → 지도 → 테마 토글).

---

## 1. 구조 개요

색은 전부 **시맨틱 토큰**으로만 쓴다. 위젯에서 하드코딩 `Color(0xFF...)` 나
`AppColors`(삭제됨) 를 쓰지 않고, `ThemeExtension` 기반 팔레트를 컨텍스트로 읽는다.

```dart
import '../theme/app_palette.dart';

Container(color: context.colors.surface);      // 팔레트 토큰
if (context.isDark) { ... }                     // 현재 모드 분기
```

- `lib/theme/app_palette.dart` — `AppPalette` (`ThemeExtension<AppPalette>`).
  `AppPalette.light` / `AppPalette.dark` 두 세트 + `copyWith`/`lerp`(테마 전환 시 보간).
- `lib/theme/app_theme.dart` — `AppTheme.light()` / `AppTheme.dark()`.
  하나의 `_build(palette, brightness)` 가 컴포넌트 테마(AppBar·버튼·입력창·칩·스낵바·카드)를
  팔레트로 파라미터화해 생성. 라이트/다크 로직 분기가 한곳에만 있다.
- `lib/main.dart` — `MaterialApp(theme: light, darkTheme: dark, themeMode: ...)`.
  상태바 아이콘 밝기는 builder 의 `AnnotatedRegion` 이 테마 밝기 기준으로 기본값을 깔고,
  사진 히어로 등 개별 화면의 `AnnotatedRegion` 이 필요한 곳만 덮어쓴다.

## 2. 토큰 (AppPalette)

| 토큰 | 라이트 | 다크 | 용도 |
|---|---|---|---|
| `background` | `FFFFFF` | `121212` | 페이지 배경(라이트는 순백 유지 — 크림 아님) |
| `cream` | `F5EFE3` | `121212` | 웰컴/인증 화면 배경, 블롭 |
| `surface` | `FFFFFF` | `1E1E1E` | 카드·시트·바텀시트 |
| `surfaceMuted` | — | `191919` | 살짝 가라앉은 면(빈 상태 박스 등) |
| `frostFilm` | 흰 반투명 | `EB1B1B1B` | 상단 헤더/하단 메뉴바 셀로판 필름 |
| `photoVeil` | 흰 베일 | `B3161616` | 사진 블러 배경 위 가독 스크림 |
| `primary` / `primaryDark` | 골드 / 진브라운 | 골드 / 밝은 샌드 `D8C7A9` | 액센트. 다크에선 primaryDark 가 밝은 색으로 반전 |
| `textOnPrimary` | 흰색 | `1E1B15` | primaryDark 면 위 텍스트(다크에선 어두운 글자) |
| `textPrimary/Secondary/Tertiary` | 브라운 계열 | 밝은 회백 계열 | 본문 위계 |
| `border` / `borderStrong` | 밝은 회색 | `2E2E2E` / `454545` | 윤곽선 |
| `success/warning/danger/info`, `admin*`, `cat*` | 고정 계열 | 동일/약간 조정 | 상태·카테고리 색(`categoryColor(String)`) |

원칙:
- **다크 = 중립 무채색 회색** 기반(웜 브라운 배경 아님 — 사용자 확정 사항).
  골드/샌드는 액센트로만.
- **라이트의 흰 배경은 순백 유지**(크림으로 바꾸지 않음 — 사용자 확정 사항).

## 3. 테마 토글 (4단계)

- `lib/services/theme_controller.dart` — `ThemeController`.
  `ValueNotifier<ThemeMode> mode` + SharedPreferences(`theme_mode` 키) 저장/복원.
  `main()` 에서 `await ThemeController.load()` 후 `MaterialApp` 이
  `ValueListenableBuilder` 로 구독 → 선택 즉시 전체 반영.
- UI 진입점: **내정보 수정 > 설정 > 화면 테마** — 바텀시트에서
  시스템 설정 / 라이트 / 다크 선택. 기본값은 시스템.

## 4. 지도(네이버) 다크 대응

`lib/screen/tabs/map_tab.dart`:

- **라이트**: `customStyleId`(콘솔 스타일 편집기에서 만든 커스텀 스타일 —
  아파트명·공원·지하철/기차역 외 POI 숨김) 적용.
- **다크**: `mapType: NMapType.navi` + `nightModeEnable: true`.
  ⚠️ `nightModeEnable` 은 **navi 타입에서만 공식 지원**. 이 조합이어야
  SDK `isDark` 판정이 참이 되어 **네이버 로고가 다크용으로 자동 교체**되고
  (로고는 앱에서 직접 바꾸는 API 없음), 내비 지도라 상업 POI 대부분이 숨겨져
  라이트 커스텀 스타일과 비슷한 정보 밀도가 된다.
  - 완전한 표시 규칙 일치가 필요하면: 콘솔에서 라이트 스타일을 복제한
    다크 스타일을 만들어 `customStyleId` 를 모드별로 스위치(단, 이 경우
    로고는 SDK 판정 밖이라 기본(초록)으로 돌아옴).
- **마커 아이콘**: 비트맵으로 직접 렌더(`_renderMarkerIcon`). 단색 통일 —
  라이트 `#5A4E38`(진브라운), 다크 `#AC9466`(골드). 외곽선 대신 부드러운
  그림자로 지도와 대비. 분양 마커(IMG_4)는 같은 색으로 틴트.
- **캡션**: 라이트 `#5A4E3A`+흰 halo, 다크 `#E8E2D5`+`#1E1E1E` halo.
- **테마 전환 감지**: `didChangeDependencies` 에서 brightness 변화 시
  **마커 아이콘 캐시(`_catIcons`)를 비우고** `_loadFacilities` 재호출.
  (마커는 지도 위 비트맵이라 테마가 바뀌어도 스스로 다시 안 그려짐.)

## 5. 작업 시 주의(함정 모음)

- **`const` 금지 구역**: `context.colors.x` 는 런타임 값이라 이를 포함하는
  위젯 서브트리는 `const` 를 못 쓴다. 팔레트 이행 때 const 제거를 일괄 수행했음.
- **컨텍스트 없는 헬퍼**: 톱레벨/스태틱 헬퍼가 색을 쓰면 `BuildContext` 를
  파라미터로 받는다(팔레트 이행 때 `_card`, `adminAppBar` 등 다수 수정).
- **await 뒤 컨텍스트**: 비동기 작업(마커 렌더 등) 전에 색을 **미리 캡처**한다.
- **상태바**: 전역 기본은 main.dart 의 `AnnotatedRegion`(테마 밝기 따름).
  사진 위 흰 아이콘이 필요한 화면만 개별 `AnnotatedRegion` 으로 덮는다.
- **사진 배경 스크림**: 흰 반투명 하드코딩 대신 `photoVeil` 토큰 사용
  (다크에서 어두운 베일로 바뀜).
- **새 색이 필요하면**: 위젯에 hex 를 넣지 말고 `AppPalette` 에 토큰을 추가하고
  light/dark 값을 함께 정의한다(`copyWith`/`lerp` 도 갱신).
