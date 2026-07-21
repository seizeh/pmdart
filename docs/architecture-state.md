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
