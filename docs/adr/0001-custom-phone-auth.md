# ADR-0001: Supabase Auth 대신 전화번호 OTP 커스텀 인증

- 상태: 채택 (2026-06)
- 관련: `pmdb/supabase/functions/{send-phone-code,verify-phone-code,signup,login,refresh}`,
  `app.uid()`, `pmdb/docs/refresh-token-flow-design.md`

## 맥락

동네 기반 서비스라 **전화번호가 곧 신원**이다. 중복 계정과 유령 계정이 매칭 신뢰도를
직접 깎기 때문에 가입 시점에 전화 인증을 반드시 통과해야 한다.

Supabase Auth 의 phone provider 를 쓸 수도 있었지만 두 가지가 걸렸다.

- 국내 SMS 사업자(Solapi) 연동, 발신번호 사전등록, 문구 규제 등 국내 사정에 맞춰야 하는데
  provider 규격에 끼워 맞추는 비용이 직접 구현보다 크지 않았다
- `auth.users` 와 서비스 `users` 를 잇는 이중 테이블 구조가 생긴다. RLS 를
  `auth.uid()` 기준으로 쓰면 서비스 도메인 규칙(정지·탈퇴·업체 승인 상태)을 매번
  조인해서 확인해야 한다

## 결정

전화 OTP 발급/검증과 로그인을 Edge Function 으로 직접 구현하고, **HS256 커스텀 JWT** 를
발급한다. 모든 RLS 는 `auth.uid()` 가 아니라 `app.uid()`(JWT `sub`)를 기준으로 쓴다.
비밀번호는 `extensions.crypt`(bcrypt) 로 해싱하고, refresh 토큰은 원문을 저장하지 않고
sha256 해시만 `app.refresh_tokens` 에 둔다(PostgREST 비노출 스키마 — [ADR-0005](0005-db-change-management.md)).

## 검토한 대안

| 대안 | 기각 사유 |
|---|---|
| Supabase Auth phone provider | 국내 SMS 규제 대응이 provider 규격 밖, `auth.users`/`users` 이중 구조 |
| 세션 테이블 기반(무JWT) | 매 요청 DB 조회. PostgREST 를 그대로 쓰려면 JWT 가 자연스러움 |

## 결과

- RLS 가 서비스 도메인 하나만 보면 된다 — `app.uid()` 가 곧 `public.users.id`
- SMS 비용·발송 실패·레이트리밋을 직접 통제한다
- **대가: 토큰 수명 동안의 권한 변화를 직접 처리해야 한다** (아래)

### 실제로 밟은 함정

**정지시킨 사용자가 계속 접근됐다.** `login_user` 는 `status='active'` 만 토큰을 발급하지만,
로그인 **후** 관리자가 정지시켜도 이미 발급된 토큰(exp 30일)은 그대로 살아 있었다.
무상태 JWT 라 서버가 "이 토큰 무효" 를 알 방법이 없다.

토큰 수명을 줄이는 대신, **`app.uid()` 자체에 상태 게이트**를 넣었다
(`20260630180000_security_active_uid_enforce_status.sql`):

```sql
create or replace function app.uid() returns uuid
language sql stable security definer set search_path to '' as $$
  select u.id from public.users u
   where u.id = nullif((nullif(current_setting('request.jwt.claims', true),'')::jsonb)->>'sub','')::uuid
     and u.status = 'active'
$$;
```

`app.uid()` 를 쓰는 **모든 RLS·RPC 에 정지/차단이 즉시 반영된다.** `SECURITY DEFINER` 인
이유는 `users` 를 RLS 우회로 읽어야 정책 재귀가 안 생기기 때문이다(`is_admin()` 과 같은 패턴).

남은 위험은 "활성 사용자의 토큰이 유출되면 30일" 이고, 이건 짧은 access + refresh 흐름으로
후속 대응했다(`20260701090000_refresh_tokens_phase1.sql`). 토큰 수명을 30일로 유지한 건
UX 판단이며, **위험을 없앤 게 아니라 어디로 옮겼는지 알고 선택한 것**이다.
