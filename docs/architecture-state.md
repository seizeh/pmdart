# 화면 상태 분리 패턴 (#155 · #156)

## 결정

상태관리는 **프레임워크 없이 `ChangeNotifier` 상태 홀더**로 간다.

근거:
- 코드베이스의 기존 관용구와 일치 — `SessionManager`·`ThemeController` 가 이미
  `ChangeNotifier`, 화면 간 이벤트는 `AppEvents`(`ValueNotifier`) 사용 중
- 의존성 0, 화면 단위 점진 전환이 가능(전면 마이그레이션 강제 없음)
- Riverpod 등 프레임워크 도입은 화면 분해가 진행돼 상태 경계가 드러난 뒤
  재평가한다(#156) — 지금 도입하면 God Widget 구조 위에 레이어만 얹게 된다

## 패턴 (파일럿: 알림함)

- `lib/state/<화면>_state.dart` — `ChangeNotifier` 상태 홀더
  - 로딩/에러/목록 등 화면 상태와 리포지토리 호출, 낙관적 갱신을 전부 보유
  - 위젯 트리·`BuildContext` 참조 금지 (테스트 가능성의 핵심)
  - 협력자는 생성자 주입 가능하게(`{Repo? repo}`) — 기본값은 기존 싱글턴
- 화면은 홀더를 `ListenableBuilder` 로 구독해 **그리기만** 한다
  - 내비게이션·다이얼로그 등 `BuildContext` 가 필요한 일만 화면에 남긴다
- 홀더 테스트는 `test/state/` 에 — FakeSupabase(http 목킹)로 리포지토리까지
  실코드로 관통 (`test/state/notifications_state_test.dart` 참고)

파일럿 구현: `lib/state/notifications_state.dart` + `lib/screen/notifications_screen.dart`

## 적용 규칙

- **새 화면은 이 구조로 작성한다**
- 기존 화면은 수정할 일이 생길 때 그 화면부터 전환한다 — 우선순위는 #155
  (1,000줄+ 화면 8개: user_profile, business_register, map_tab, my_info_tab,
  post_create, post_detail, signup_phone, chat_room)
- 홀더가 커지면 화면 하위 영역별로 쪼갠다(홀더도 God 이 되지 않게)

## 리포지토리 분리 기준 (2026-08-05)

**나누는 기준은 줄 수가 아니라 역할 수다.** 한 클래스가 서로 무관한 일을 여럿
하고 있으면 나누고, 하나를 깊게 하고 있으면 길어도 두는 게 맞다.

분리한 것과 그 근거:

| 원본 | → | 근거 |
|---|---|---|
| `AdminRepository` 913줄 | 5개 | 메서드 26개가 관리자 화면과 거의 1:1로 갈렸다. **631줄은 모델**이라 `lib/models/admin.dart` 로 뺀 게 절반이다 |
| `BusinessRepository` 527줄 | 4개 | 화면 5곳이 "지금 개인인가 업체인가" 하나를 묻자고 국세청 조회·허가 심사까지 딸려 오는 클래스를 잡고 있었다 |
| `CommunityRepository` 538줄 | 4개 | 조회는 `_postsFromRows` 를 공유하는 한 덩어리, 반응은 전부 로그인 필수+낙관적 갱신 — 실패 시 사용자에게 보여 줄 것부터 다르다 |

**나누지 않기로 한 것**: `profile_repository`(398) · `pet_repository`(386) ·
`care_report_repository`(370). 셋 다 길지만 **역할이 이미 하나**다. 지금 나누면
파일 수만 늘고 응집도는 떨어진다 — 줄 수를 기준으로 삼으면 이렇게 된다.

> 나눌 때 지킨 것
> - **파사드를 남기지 않는다.** 델리게이트만 하는 옛 이름을 남기면 "이거 하나만
>   부르면 된다" 가 유지돼 나눈 의미가 없다. 호출부를 고친다.
> - **역할 간 협력은 숨기지 않는다.** `BusinessReviewsRepository` 가
>   `BusinessProfileRepository.fetchMine()` 을 부르는 것처럼, 복사하지 말고
>   명시적으로 부른다.
> - **모델은 역할에 딸리지 않는다.** 여러 역할이 함께 쓰므로 `lib/models/` 로.
> - **주입 타입도 같이 좁힌다.** 홀더가 넓은 타입을 받으면 그 홀더가 무엇까지
>   건드리는지 읽는 사람이 알 수 없다.

## 의존 주입 — 상태 홀더 전부 적용 (2026-08-05)

위 '패턴' 의 `{Repo? repo}` 규칙은 오래 적혀 있었지만 **파일럿 하나에만** 적용돼
있었다. 나머지 홀더 5개에도 넓혔다(chat_room · my_info · post_detail ·
profile_edit · user_profile).

전면 DI(컨테이너·프레임워크)로 가지 않은 이유는 호출부가 200곳이 넘고
(`SessionManager.instance` 79 · `StorageService` 47 · `AppEvents` 45 …) 지금 필요한
것이 '조립기' 가 아니라 **'갈아끼울 수 있는 자리'** 이기 때문이다. 기본값이 종전
싱글턴이라 기존 호출부는 한 줄도 바뀌지 않는다.

⚠️ 그 주입 자리는 **아무 테스트도 쓰지 않고 있었다.** 안 쓰는 주입 자리는 있으나
마나고, 다음 사람이 쓰려는 순간에야 안 된다는 걸 알게 된다. 그래서
`test/state/injection_seam_test.dart` 가 주입이 실제로 도는 것과 **대역 만드는 법**을
함께 고정한다 — 리포지토리 생성자가 private 이라 `extends` 가 막히므로
`implements` + `noSuchMethod` 로 부분 구현해야 한다.
