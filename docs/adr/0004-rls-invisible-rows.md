# ADR-0004: RLS 로 안 보이게 되는 행의 쓰기는 DEFINER RPC 로

- 상태: 채택 (2026-07)
- 관련: 소프트 삭제 계열 RPC, `app.uid()`

## 맥락

RLS 는 "읽을 수 있는 행" 만 정의하는 게 아니라 **쓰기 결과에도 적용**된다.
`UPDATE ... USING/WITH CHECK` 는 갱신 **후** 행이 정책을 만족하는지도 본다.

## 결정

- **갱신 결과가 SELECT 비가시가 되는 쓰기**는 INVOKER 경로로 만들지 않고
  `SECURITY DEFINER` RPC 안에서 처리한다(소프트 삭제, 상태 전이 등)
- RPC 안에서 권한 판정은 **직접 다시 한다**. 정의자 권한으로 도는 순간 RLS 는
  더 이상 안전망이 아니다

## 결과

- 소프트 삭제 같은 흔한 동작에도 RPC 가 하나씩 생긴다
- 대신 실패가 런타임 42501 이 아니라 **설계 시점에** 드러난다

### 실제로 밟은 함정 ①: 소프트 삭제가 42501

`visibility_status` 를 `deleted_*` 로 바꾸는 UPDATE 가 `42501 permission denied` 로 실패했다.
권한 설정이 잘못된 줄 알고 GRANT 를 뒤졌지만 원인은 다른 데 있었다 —
**갱신된 행이 SELECT 정책에 걸려 안 보이게 되면 그 UPDATE 자체가 거부된다.**
"삭제 표시하면 목록에서 사라진다" 는 정책이 곧 "삭제 표시를 못 한다" 가 된 것이다.

`GRANT` 로는 풀 수 없고, 정의자 RPC 안에서 처리하는 게 정답이었다.

### 실제로 밟은 함정 ②: INVOKER RPC 안의 조용한 NULL

`SECURITY INVOKER` RPC 안의 서브쿼리도 **호출자의 RLS** 를 탄다. 비가시 행은 에러가
아니라 **NULL** 로 돌아온다. 그래서 함수는 조용히 잘못된 결과를 내고, 로컬에서 `postgres`
롤로 테스트하면 멀쩡히 통과한다.

이후 DB 함수 검증은 **반드시 `authenticated` 롤 + JWT 시뮬레이션**으로 한다:

```sql
set local role authenticated;
select set_config('request.jwt.claims',
  json_build_object('sub', '<uuid>', 'tv', 0)::text, true);
```

`postgres` 로 돌린 테스트는 RLS 를 통과한 게 아니라 **RLS 를 안 거친 것**이다.
