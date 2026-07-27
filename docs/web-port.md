# 웹 이식 계획 (Flutter Web)

## 목적

웹은 **앱 유입 퍼널**이다. 독립된 제품이 아니다.

- 웹이 하는 일 — 커뮤니티 게시글·후기를 **읽게** 하고, 회원가입까지 받는다
- 웹이 하지 않는 일 — 지도, 동네 인증, 글쓰기, 채팅, 펫 신원 인증
  → 전부 "앱에서 계속하기"로 유도한다

따라서 웹의 성공 지표는 체류가 아니라 **앱 설치 전환**이다. 기능을 웹으로
끌어오고 싶은 요구가 생기면 이 문서의 목적을 먼저 다시 본다.

## 결정 1 — 단일 코드베이스, 포크 금지

디자인을 앱과 100% 동일하게 유지하는 유일한 방법이다. 같은 `lib/` 를 web
타깃으로 빌드하면 같은 위젯 트리·같은 `theme/app_theme.dart`·같은 `motion/`
스프링이 그대로 돌아간다.

규칙:

- 웹 전용 화면을 새로 만들지 않는다. 분기는 `kIsWeb` 과 조건부 import 만
- 렌더러는 **CanvasKit 고정**. HTML 렌더러는 `ImageFiltered` 블러(11개 파일)·
  그림자·폰트 메트릭이 앱과 달라진다
- 지도·지역 인증 코드는 **삭제하지 않는다**. 진입점만 웹에서 차단하고 코드는
  앱 빌드와 계속 공유한다
- 데스크톱에서 바뀌는 것은 **크롬(내비게이션)뿐**이다 — 결정 5 참고. 본문의
  반응형 재배치(다단 피드 등)는 곧 디자인이 갈라진다는 뜻이므로 하지 않는다

## 결정 2 — 웹 탭 구성 (5탭 노출, 2개는 앱 유도)

| 탭 | 웹 |
|---|---|
| 커뮤니티 | ✅ |
| 유저 검색 | ✅ |
| 마이 | ✅ |
| 지도 | 🔒 아이콘은 보이고, 누르면 설치 안내 |
| 채팅 | 🔒 아이콘은 보이고, 누르면 설치 안내 |

처음엔 지도·채팅을 **숨겨서** 3탭으로 갔는데 뒤집었다 — 숨기면 앱에서 뭘 더 할
수 있는지 알 길이 없어 유입으로 이어지지 않는다. **보여주고 누르면 권한다.**

구현(`main_screen.dart`):

- `visibleTabs` = 아이콘으로 노출할 탭(5개, 플랫폼 무관)
- `appOnlyTabs` = 웹에서 `{지도, 채팅}` — 누르면 `AppInviteDialog`, 화면 전환
  없음(알약도 안 움직인다). 내용 위젯도 만들지 않는다(웹 구현 없는 지도
  플랫폼뷰가 붙는 것 방지)
- `contentTabs` = 실제 화면이 있는 탭. `IndexedStack` 은 이쪽 인덱스를 쓴다
- 딥링크(`tabRequest`)가 앱 전용 탭을 가리키면 조용히 무시한다 — 사용자가 누른
  것이 아니므로 안내를 띄우지 않는다

`AppInviteDialog` 는 `AuthWallDialog` 와 같은 시각 언어다. 스토어 주소
(`Env.storeUrlIos`/`storeUrlAndroid`, `--dart-define`)가 **비어 있으면 — 출시 전
기본값 — 설치 버튼 대신 "출시 준비 중" 안내만** 보여준다(죽은 링크 방지).
share-view Edge Function 의 `STORE_URL_*` 와 같은 값을 넣으면 된다.

## 결정 3 — 게스트 경계

앱에 이미 있는 게스트 모드(`MainScreen(isGuest: true)` + `AuthWallDialog`)를
그대로 쓴다. 경계도 앱과 동일하다.

| 게스트 허용 | 앱 유도 |
|---|---|
| 커뮤니티 피드 | 댓글 작성 |
| 게시글 상세 본문·사진 | 하트 / pawing |
| 댓글 읽기 | 채팅 시작 |
| 후기 목록·상세 | 글쓰기 |
| 회원가입 · 로그인 | |

상세 열람까지 자유롭게 두는 이유: 공유 링크로 들어온 사람이 내용을 다 보고
설득되는 구조라야 전환이 난다. 목록에서 막으면 그냥 이탈한다.

웹에서 `AuthWallDialog` 는 **`AppInviteDialog` 로 대체**한다 — "로그인 할래요 /
나중에 할래요" 대신 "앱에서 열기(스토어) / 로그인 / 나중에". 로그인은 웹에서도
되므로 선택지에서 빼지 않는다.

로그인한 사용자는 웹에서도 정상 동작한다. 단 위 표의 '앱 전용' 기능(채팅·
글쓰기·지도·동네 인증)은 로그인 여부와 무관하게 앱으로 유도한다.

## 결정 4 — 커뮤니티 피드 폴백 (C-a) — **서버 작업 불필요**

계획 단계에서는 "웹 사용자는 `region_code` 가 없어 피드가 빈다"고 보고 pmdb 에
`feed_public` RPC 신설을 잡았다. **실제로 확인해보니 이미 폴백이 동작한다.**

`public.feed_region_codes()` 는 아래 중 하나라도 해당하면 `NULL` 을 반환한다:

- `activity_radius_m` 이 null
- `is_location_verified` 이 false
- `latitude` 가 null

게스트와 웹 신규 가입자는 전부 여기 걸려 `NULL` 이고,
`community_repository.dart` 의 `fetchFeed` 는 `codes == null` 이면 지역 필터를
아예 걸지 않는다(빈 배열 `[]` 일 때만 빈 목록을 반환한다). 결과는 전국 피드다.

즉 C-a 는 **클라이언트·서버 모두 무변경**으로 이미 만족한다. 실제 브라우저에서
게스트로 진입해 전국 게시글이 나오는 것을 확인했다.

남은 선택지는 정렬뿐이다 — 현재는 `created_at desc`(최신순 전국)이다. 인기·최근
혼합이 첫인상에 낫지만, 이건 웹 전용이 아니라 앱의 미인증 사용자에게도 똑같이
적용되는 기존 동작이므로 별도 과제로 둔다.

## 결정 5 — 데스크톱은 "크롬만" 분리 ✅ 구현됨

넓은 화면에서 모바일 레이아웃을 그대로 늘리면 게시글 카드가 1300px 로 퍼져
앱과 완전히 다른 비율이 된다. 그렇다고 데스크톱 전용 반응형(다단 피드·우측
상세 패널)으로 가면 화면마다 두 벌을 영구히 유지해야 한다.

**중간을 택한다 — 본문은 그대로, 내비게이션 위치만 바꾼다.**

| | < 900px (모바일 브라우저) | ≥ 900px (데스크톱) |
|---|---|---|
| 내비게이션 | 하단 플로팅 바 | 좌측 플로팅 레일 |
| 본문 컬럼 | 화면 폭 (460 초과 시 460) | 460 중앙 정렬 |
| 카드·타이포·모션 | 앱과 동일 | 앱과 동일 |

구현 지점:

- `lib/utils/layout.dart` — `kContentMaxWidth`(460), `useSideNav`,
  `useContentColumn`, `bottomNavClearance`. **전부 웹에서만 참이다** — 네이티브
  앱(아이패드 포함)의 현재 레이아웃은 이 작업 범위가 아니라 건드리지 않는다
- `lib/motion/springy_nav_bar.dart` — `axis` 추가. 세로 레일은 **별도 위젯이
  아니라 같은 위젯**이다. 스프링·스쿼시·근접 보간이 전부 같은 코드를 타므로
  두 형태가 영원히 같은 모션 언어를 유지한다(알약만 90° 돌아 진행 축을 따른다)
- `lib/widgets/app_shell.dart` — `MaterialApp.builder` 에 꽂히는 셸. 레일이
  본문 컬럼 **바깥**에 있어야 하고 상세 라우트가 얹혀도 유지돼야 해서
  Navigator 바깥에 둔다. `MainScreen` 은 탭 상태만 `navRail` 로 공개한다
- `bottomNavClearance` — 레일을 쓰면 0. 데스크톱에서 목록 끝에 하단 바용
  빈 공간이 남던 것을 막는다

미구현 — 레일 하단의 "앱으로 보기" CTA. 스토어 등록 전이라 링크가 없어
Phase C 로 미룬다.

### 셸이 Navigator 바깥에 있어서 생기는 함정 두 가지 (배포 후 발견)

컬럼이 Navigator를 **옮기고 좁히기** 때문에, 라우트 안에서 보는 좌표와 크기가
창의 그것과 달라진다. 둘 다 데스크톱에서만, **창이 넓을수록 더 크게** 어긋난다.

1. **좌표** — 모프의 `originRect` 는 `localToGlobal`(창 좌표)로 잡는데 라우트는
   컬럼 좌표계다. 보정 없이 쓰면 상세가 엉뚱한 자리(거의 화면 밖)에서 펼쳐진다.
   → 규약을 "`originRect` 는 언제나 창 좌표"로 못박고, 소비 지점
   (`CollapsibleView`·`ExpandRoute`)에서 `toRouteRect()` 로 변환한다. 캡처 지점이
   18곳이라 소비 쪽 3곳에서 잡는 편이 안전하다. `riseOriginRect` 는 MediaQuery
   기준이라 반대로 `shellOrigin()` 을 더해 규약에 맞춘다.

2. **크기** — `ConstrainedBox` 는 MediaQuery 를 바꾸지 않아 컬럼 안에서도
   `MediaQuery.size` 가 창 크기로 보고된다. 모프의 도착 사각형이 창 폭으로
   잡혀 어긋난다. → 컬럼 안에서 MediaQuery 를 컬럼 크기로 덮어쓴다.

   ⚠️ 그런데 이걸 덮으면 **크롬 구성 판단까지 오염된다** — `useSideNav` 가
   컬럼 폭(460)을 보고 "좁은 화면"으로 오판해 **좌측 레일과 하단 바가 동시에**
   나온다. 그래서 창 크기는 `ShellMetrics`(InheritedWidget)로 따로 내려보내고,
   `useSideNav`/`useContentColumn` 은 그 값을 우선 본다.

## 결정 6 — 공유 링크는 share-view 유지 + 웹앱 CTA 추가 ✅ 구현됨

`go.pawmate.kr/s?t=<token>` 을 웹앱으로 **대체하지 않는다**. 지금 페이지는
빈 껍데기가 아니라 서버 렌더링 퍼널 페이지이고, 대체하면 잃는 게 크다:

| 잃는 것 | 이유 |
|---|---|
| 카톡 링크 미리보기 | Flutter 웹은 클라이언트 렌더링 — 크롤러는 빈 셸만 받는다. 공유 기반 유입에서 가장 치명적 |
| 즉시 페인트 | 서버 HTML(JS·외부 리소스 0) → CanvasKit 약 2MB 선다운로드 |
| 퍼널 계측 | `share_view`/`store_click` 을 RPC 가 원자적으로 기록 중 |

대신 **동선만 잇는다** — 게시글 공유 페이지에 "웹에서 계속 보기" 2차 CTA 를
추가해 `app.pawmate.kr/p/<postId>` 로 보낸다. 1차 CTA(스토어)는 그대로다.

게시글 공유에만 붙인다. 케어리포트·업체 미리보기는 웹앱에 대응 화면이 없다
(시설 상세는 지도에 딸려 있고 지도는 웹 범위 밖 — 결정 2).

**토큰이 아니라 게시글 id 로 넘기는 이유**: `share_view_load` 는 service_role
전용이라(`revoke execute … from anon, authenticated`) 웹앱(anon)이 토큰을 못
읽는다. 새 anon RPC 를 파는 대신 이미 서버가 아는 post id 를 응답에 실었다.
노출 확대가 아니다 — 게시글은 `v_post_feed` 로 이미 anon 열람 가능하다
(비로그인 둘러보기와 같은 경로).

구현 지점:

- **pmdb** `migrations/20260726120000_share_view_post_id.sql` — `share_view_load`
  의 post 분기에 `'id', p.id` 추가. 권한 변경 없음
- **pmdb** `functions/share-view/index.ts` — `WEB_APP_URL` 환경변수. **미설정이면
  CTA 를 아예 그리지 않는다**(웹앱 배포 전 죽은 링크 방지 스위치)
- **pmdart** `lib/utils/web_link.dart` — 진입 URL `/p/<uuid>` 파싱
- **pmdart** `lib/main.dart` `_openInitialWebLink()` — 게시글을 열되, 비로그인이면
  웰컴 대신 **게스트 메인을 깔고 그 위에** 상세를 얹는다(닫으면 커뮤니티 피드가
  나와야 둘러보기로 이어진다. 웰컴으로 되돌아가면 거기서 끊긴다).
  `openFromPush` 를 안 쓰는 이유는 그쪽이 로그인 전용이기 때문
- **pmdart** `web/_redirects` — SPA 폴백(`/* /index.html 200`). 없으면 `/p/<id>`
  직접 진입·새로고침이 404

배포 순서 (전부 웹앱 배포 이후):

1. 마이그레이션 적용 → `./scripts/dump_schema.sh` 로 스냅샷 갱신·커밋
2. `supabase functions deploy share-view`
3. Edge Function 시크릿에 `WEB_APP_URL=https://app.pawmate.kr` 설정 → 이 시점에
   CTA 가 나타난다

## 결정 7 — 웹 세션은 탭 단위·8시간 상한 ✅ 구현됨

### 먼저, 실제 토큰 모델 (계획 단계의 서술이 틀렸다)

계획에는 "무상태 JWT exp 30일"이라고 적었는데 **옛날 얘기**였다. refresh-token
phase 2 이후 실제 모델은:

| | 값 |
|---|---|
| access TTL | **8시간** (`ACCESS_TTL_CAPABLE`) |
| access TTL (레거시) | 30일 — `x-client-refresh:1` 헤더를 **안 보낼 때만** |
| refresh | 슬라이딩 30일 / 절대 90일, 회전형 |
| 탈취 감지 | `rt_rotate` 재사용 감지 시 family 전체 회수(`reuse_revoked`) |

⚠️ **로그인 요청의 `x-client-refresh:1` 헤더를 빼면 안 된다** — 서버가 레거시
클라로 보고 30일짜리 access 를 발급해 오히려 나빠진다(`login/index.ts`).

### 정책

httpOnly 쿠키 이관(원래 계획)은 하지 않는다. 로그인 경로 자체를 바꾸는 작업이라
검증 부담이 큰 데 비해, XSS 가 페이지 안에서 그대로 요청하는 건 어차피 못 막는다.
웹은 **앱 유입 퍼널**이므로 세션을 짧게 끊는 쪽이 맞는 교환이다.

| | 앱(네이티브) | 웹 |
|---|---|---|
| access | secure storage | **sessionStorage**(탭 닫으면 소멸) |
| user | SharedPreferences | sessionStorage |
| refresh | secure storage, 회전 | **영속화 안 함**, 갱신에도 안 씀 |
| 세션 상한 | 30일(회전) | **8시간** |

refresh 를 메모리에는 들고 있는다 — 로그아웃 시 서버 family 회수(`logout` 엣지)에
필요하기 때문이다. 갱신에는 쓰지 않는다(`isAccessExpiringSoon` 이 웹에서 항상
false, `_doRefresh` 도 즉시 반환).

구현: `lib/services/session_store.dart`(조건부 export) + `_io`/`_web`,
`session.dart` 는 `_store` 를 통해서만 접근. 서버 변경 없음.

`flutter_secure_storage` 를 웹에서 안 쓰는 이유: 웹 구현이 localStorage + AES 인데
복호화 키도 같은 localStorage 에 있어 사실상 난독화다.

## 작업 단계

### Phase A — 웹에서 정상 기동 ✅ 완료

계획 단계의 전제("`flutter build web` 이 컴파일에서 깨진다")는 **틀렸다**.
빌드는 손대기 전에도 통과했다. `dart:io` 는 웹에서 컴파일되는 스텁이고,
`flutter_naver_map`·`flutter_local_notifications` 등도 Dart 코드는 멀쩡히
컴파일된다. **문제는 전부 런타임이었다.**

실제 증상 — 브라우저에서 흰 화면:

```
DartError: MissingPluginException(No implementation found for
method initializeNcp on channel flutter_naver_map_sdk)
```

`main()` 의 네이버 지도 초기화가 `runApp` **이전에** 던져서 앱이 아예 뜨지 않았다.
빌드 게이트로는 절대 못 잡는 종류다.

**A1. `dart:io` 제거 (3파일)** — `lib/utils/platform_info.dart` 신설

- `services/push_service.dart` — `Platform.isIOS` → `isIOS`
- `services/local_notice_service.dart` — `Platform.isAndroid` → `isAndroid`
- `screen/pet_identity_enroll_screen.dart` — `File(video.path).readAsBytes()`
  → `XFile.readAsBytes()`, 임시파일 삭제는 `utils/temp_file.dart` 조건부 import

**A2. 네이티브 전용 플러그인** — 파사드는 필요 없었다. 컴파일은 되므로
`kIsWeb` 가드로 **호출만** 막으면 된다.

| 플러그인 | 처리 |
|---|---|
| `flutter_naver_map` | `main.dart` 초기화를 `if (!kIsWeb)` 로 감쌈. 지도 탭은 웹에서 생성 자체를 안 함 |
| `firebase_messaging` | `main.dart` 에서 웹이면 `_setupPush()` 를 건너뜀 |
| `flutter_local_notifications` | `isAndroid` 가 false → `init()` 이 즉시 반환 |
| `video_thumbnail` | `storage_service` 포스터 생성을 `kIsWeb` 이면 생략 |

⚠️ **A2 에서 놓쳤던 것 — 네이티브 싱글턴의 필드 초기화**

`main()` 에서 `_setupPush()` 만 건너뛰면 충분하다고 봤는데 아니었다.
`PushService` 는 `final FirebaseMessaging _fm = FirebaseMessaging.instance;` 를
**인스턴스 필드**로 갖고 있어서, `PushService.instance` 를 처음 참조하는 순간
Firebase 가 없다며 `[core/no-app]` 로 던진다. 그 참조가 로그인 성공 직후
(`auth_service.dart` 의 `registerToken()`)와 로그아웃(`clearToken()`)에 있었다.

증상이 고약했다 — 세션은 이미 저장된 뒤라 **"로그인 버튼은 눌리는데 로그인이
안 된다"**(에러 토스트만 뜨고, 새로고침하면 로그인돼 있음). 게스트 둘러보기만
확인해서는 절대 안 잡힌다.

교훈: `kIsWeb` 가드는 **초기화 지점이 아니라 공개 진입점마다** 걸어야 하고,
네이티브 플러그인 핸들은 필드가 아니라 **게터**로 둬야 한다(참조 시점 지연).

**A3. 웹 진입점 차단**

- `main_screen.dart` — `visibleTabs` 도입. 탭 상수는 정체성으로 고정하고 표시
  순서만 플랫폼별로. 딥링크(`tabRequest`)는 상수로 요청 → 없는 탭이면 무시
- `community_tab.dart` 글쓰기 FAB — 웹 미노출
- `profile_edit_screen.dart` 지역 재인증 진입 — 웹에서 `onTap: null`

**A4. CI 게이트** — `.github/workflows/ci.yml` 에 둘 다 추가:

- `flutter build web --release` — 번들이 깨지는 것 방지
- **`dart:io` 직접 import 금지 grep** — 빌드로는 못 잡는 런타임 회귀를 막는
  실질적인 게이트. `lib/utils/temp_file_io.dart` 만 예외

**검증** — `flutter analyze` 무결점, `flutter test` 154개 통과,
릴리스 웹 번들을 실제 Chrome 에서 기동해 웰컴 화면 → 게스트 진입 →
커뮤니티 피드(실데이터)·3탭 내비까지 확인.

### Phase B — 웹 고유 문제

- **B1. 토큰 저장** ✅ 완료 — 결정 7 참고. `flutter_secure_storage` 를 웹에서
  쓰지 않게 되면서, `dart:html`·`package:js` 때문에 **wasm 빌드를 막던 유일한
  의존성**도 웹 경로에서 빠졌다(wasm 전환 여지가 열렸다 — 별도 과제)
- **B2. juso CORS** — `juso_service.dart` 의 직접 호출은 브라우저에서 막힌다.
  Worker `/api/juso` 프록시 경유. (업체등록은 웹 범위 밖이라 우선순위 낮음)
- **B3. URL 라우팅** — 최소 `/post/:id`, `/u/:id`. 기존 `AppPageRoute` 모션을
  깨지 않으려면 `Router` 전면 도입 대신 `onGenerateRoute` 로 간다
- ~~**B4. 데스크톱 셸**~~ ✅ 완료 — 결정 5 참고
- **B5. 스크롤 동작** ✅ 완료 — `widgets/app_scroll_behavior.dart`(웹 전용):
  데스크톱 스크롤바 제거(앱에 없는 요소) + `dragDevices` 에 마우스·트랙패드 추가.
  후자가 중요하다 — 기본값은 터치·스타일러스뿐이라 **가로 목록(커뮤니티 카테고리
  칩)이 마우스만 있는 PC 에서 도달 불가**였다(뒤쪽 '입양'·'자유'를 못 씀).
  오버스크롤 물리는 건드리지 않았다(관측된 문제 없음)
- ~~**B6. 초기 로딩**~~ ✅ 부분 완료 — `web/index.html` 정비(제목·OG·theme-color),
  앱 배경색 스플래시 + `flutter-first-frame` 에 제거, 아이콘 5종을 앱 아이콘으로
  재생성(전부 Flutter 기본 로고였다), `manifest.json` 정비
- **B7. 한글 두부(tofu)** ✅ 완화 완료 — **폰트 번들은 하지 않는다**

  증상: 첫 로드에서 몇 초간 모든 한글이 □로 보였다. CanvasKit 은 CJK 글리프를
  번들하지 않고, **첫 프레임을 그린 뒤에야** 빠진 글자를 발견해 Noto Sans KR 을
  받는다. localhost 에서는 빨라 안 보였고 실제 도메인에서 드러났다.

  처음엔 한글 폰트 번들로 잡으려 했는데, **실측해보니 처방이 틀렸다**:

  | 항목 | 실측 |
  |---|---|
  | 폴백으로 받는 Noto Sans KR | **32KB** (unicode-range 조각 4개) |
  | 번들할 경우(전체 한글 음절 서브셋) | **1.15MB × 굵기 수** (앱은 w400~w800 사용) |
  | `canvaskit.wasm` (gstatic, 자체호스팅 전) | **5.3MB** |

  32KB 를 없애자고 2~4MB 를 첫 프레임 앞에 세우는 꼴이라 오히려 손해다. 진짜
  원인은 용량이 아니라 **순서와 연결 비용**이었다. 그래서:

  - `web/index.html` 에 `<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>`
    — 폰트를 받을 시점에 DNS+TLS 부터 시작하던 것을 미리 끝내 둔다
  - **CanvasKit 자체 호스팅** — 빌드에 `--no-web-resources-cdn`. 같은 오리진에서
    Cloudflare 가 brotli 로 **2.0MB** 만 보낸다(gstatic 원본 5.4MB). 서드파티
    의존도 사라진다. **이 플래그는 배포 때마다 필요하다**

  콜드 로드 실측(적용 후): `main.dart.js` 0.74→2.6s, `canvaskit.wasm` 0.74→2.4s,
  폰트 요청 3.7s 시작·**7ms 만에 완료**. 두부 구간이 수 초 → 100ms 대로 줄어
  사실상 보이지 않는다.

  남은 여지(필요해지면): 완전 제거를 원하면 스플래시를 첫 프레임 후 ~250ms 더
  유지해 폰트 도착을 덮으면 된다. 다만 재방문(폰트 캐시됨)에는 순수 지연이라
  지금은 넣지 않았다. `google_fonts` 의 Baloo2(웰컴 로고)도 런타임 다운로드지만
  같은 preconnect 로 덮인다

### Phase C — 앱 유도 UI

- `AppInviteDialog` — 스토어 링크(iOS/Android 분기) + 로그인 + 나중에
- 채팅 탭 자리·글쓰기 FAB 등 앱 전용 기능 진입 시 동일 다이얼로그
- 상단 스마트 배너(선택) — 모바일 브라우저에서만

### Phase D — 선택

- FCM 웹 푸시(서비스워커 + VAPID). iOS Safari 는 PWA 설치 상태에서만 수신
- PWA `manifest.json` 정비

### Phase E — 배포 ✅ 완료 (2026-07-26)

**https://app.pawmate.kr** (= `pawmate-web.pages.dev`)

- Cloudflare Pages 프로젝트 `pawmate-web`. 배포:

  ```
  flutter build web --release --no-web-resources-cdn
  find build/web/canvaskit -name '*.symbols' -delete   # 런타임 미사용, 8MB 절감
  npx wrangler pages deploy build/web --project-name pawmate-web --branch main
  ```

  `--no-web-resources-cdn` 는 선택이 아니다 — 빼면 CanvasKit 이 gstatic 에서
  오면서 한글 두부 구간이 다시 길어진다(B7)
- `go.pawmate.kr/s` 의 share-proxy Worker 는 건드리지 않았다(경로 충돌 없음)
- 커스텀 도메인 함정: **wrangler CLI 에는 Pages 커스텀 도메인 명령이 없고**,
  wrangler OAuth 토큰은 `zone(read)` 뿐이라 **DNS 레코드를 만들 수 없다**.
  도메인 등록은 API(`POST /pages/projects/<p>/domains`)로 되지만 DNS 는 대시보드에서
  사람이 넣어야 한다 — `CNAME app → pawmate-web.pages.dev`, **Proxied(주황)**.
  API 로 등록하면 대시보드 마법사의 DNS 자동 생성 단계가 건너뛰어져 행에 버튼이
  안 생긴다. 전파 중 몇 분간 522 가 나는 것은 정상.
- 검증: `/`·`/p/<postId>`·임의 경로 전부 200(SPA 폴백 동작),
  `app.pawmate.kr` 전용 인증서 발급(Google Trust Services), OG 메타 서빙 확인

남은 것:

- GitHub Actions 자동 배포(현재는 수동) + `--dart-define` 주입
- CSP — CanvasKit 이 wasm 을 쓰므로 `script-src 'wasm-unsafe-eval'` 필요.
  Pages 는 기본 CSP 가 없어 지금도 동작하지만 하드닝 대상(`web/_headers`)

## 웹에서 재현되지 않는 것

디자인은 동일하지만 플랫폼상 불가능한 것들이다. 버그로 신고하지 않는다.

- 상태바가 없다 → `SystemChrome.setSystemUIOverlayStyle`(`main.dart`)과 상태바
  스크림 페이드는 웹에서 무의미. 상단 세이프에어리어 계산이 다르다
- 햅틱 피드백 no-op
- iOS Safari 에서 `ImageFiltered` 블러가 긴 리스트에서 프레임을 떨어뜨릴 수
  있다 → 필요 시 웹 한정 블러 시그마 하향 스위치
- 카메라 촬영 인증은 모바일 브라우저만. 데스크톱은 파일 선택 폴백
  (단 촬영 인증이 필요한 글쓰기 자체가 웹 범위 밖이라 실질 영향 없음)
