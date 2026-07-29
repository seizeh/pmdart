# ADR-0002: 불변식은 Edge Function 이 아니라 DB 에서 강제한다

- 상태: 채택 (2026-07)
- 관련: `pmdb/supabase/migrations/20260714000000_block_self_guardian_invite.sql`,
  `pmdb/supabase/tests/t02_guardian_invite_test.sql`

## 맥락

클라이언트는 PostgREST 로 테이블에 직접 접근한다. 검증 로직을 Edge Function 에 두면
"함수를 거쳐 온 요청" 만 검증되고, **테이블로 직접 오는 요청은 그대로 통과**한다.

## 결정

도메인 불변식은 세 층 중 **가장 안쪽**에 둔다.

| 층 | 역할 |
|---|---|
| 클라이언트 검증 | UX 전용 — 즉각 피드백. 보안 근거로 삼지 않는다 |
| Edge Function | 외부 연동(SMS·AI·국세청)과 시크릿이 필요한 일 |
| **DB 트리거 / CHECK / RLS** | **불변식의 최종 강제. 어떤 경로로 와도 뚫리지 않는다** |

쓰기 검증이 필요한 작업은 테이블 권한을 회수하고 `SECURITY DEFINER` RPC 로만 열어 둔다.
불변식은 그 RPC 안이 아니라 **트리거**에 둔다 — RPC 를 우회해도 걸리도록.

## 검토한 대안

Edge Function 에서만 검증(구현이 가장 쉽고 로직이 한곳에 모임) → 아래 사고로 기각.

## 결과

- 검증 로직이 SQL 로 내려가 읽기 어려워진다 → pgTAP 으로 불변식마다 테스트를 붙였다
  ([ADR-0007](0007-coverage-ratchet.md))
- 대신 **불변식이 실제로 불변**이 된다. "이 규칙이 어디서 깨질 수 있나" 에 답할 수 있다

### 실제로 밟은 함정

**자기 자신을 공동보호자로 초대한 pending 행이 운영 DB 에 실제로 생겼다.**

`invite-guardian` Edge Function 은 `self_invite` 를 이미 거르고 있었다. 그런데
`pet_guardian_invites` 의 RLS `pgi_insert` 정책에는 자기 초대 조건이 없었고, 함수 배포 전
구버전 앱이 **PostgREST 로 테이블에 직접 INSERT** 하는 경로가 열려 있었다.
"함수가 막고 있다" 는 말이 사실이 아니었던 것이다.

조치는 함수 수정이 아니라 **BEFORE INSERT 트리거**였다
(`20260714000000_block_self_guardian_invite.sql`). 전화번호로 온 초대는 트리거 안에서
`invitee_user_id` 를 확정한 뒤 검사하므로, 초대 시점에 상대가 가입돼 있든 아니든
`inviter = invitee` 면 예외를 던진다 — PostgREST 직접 INSERT 도, `service_role` 도 막힌다.

이 불변식은 `t02_guardian_invite_test.sql` 로 CI 에서 매번 검증한다.

**교훈:** "함수가 검증한다" 는 **함수를 거쳤을 때만** 참이다. 불변식을 어디에 두느냐는
편의 문제가 아니라 **공격면(攻擊面)이 어디까지인가** 의 문제다.
