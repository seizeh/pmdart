# ADR-0003: SECURITY DEFINER 객체에는 쓰기 경로를 만들지 않는다

- 상태: 채택 (2026-06-30)
- 관련: `pmdb/supabase/migrations/20260630160000_security_revoke_view_write_grants.sql`,
  `20260713201500_create_post_region_gate_overload12.sql`

## 맥락

`public_profiles`·`v_post_feed` 같은 공개 읽기 뷰는 정의자(postgres) 권한으로 동작한다.
"큐레이트된 공개 읽기 뷰니까 안전하다" 고 판단해 Supabase advisor 의
`security_definer_view` 경고를 한 번 보류한 적이 있다.

## 결정

정의자 권한으로 도는 객체(뷰·`SECURITY DEFINER` 함수)는 **읽기 경로만 노출한다.**

- 노출 뷰: `anon`/`authenticated` 에 **SELECT 만** 부여. INSERT/UPDATE/DELETE/TRUNCATE/
  REFERENCES/TRIGGER 는 회수
- `SECURITY DEFINER` RPC: 필요한 롤에만 EXECUTE. 시그니처를 바꿀 때는 **구버전을 반드시 drop**

## 결과

- 뷰를 통한 쓰기가 필요하면 명시적인 RPC 를 만들어야 한다(귀찮지만 의도가 드러난다)
- 정의자 객체의 GRANT 는 리뷰 대상이 된다

### 실제로 밟은 함정 ①: 무인증 관리자 승격

보류했던 그 경고가 실제 취약점이었다. 세 조건이 겹쳤다.

1. `public_profiles` 가 단일 테이블 기반이라 **자동 업데이트 가능한 뷰**였다
2. 소유자가 `postgres`(BYPASSRLS) → 뷰를 거치면 `users` 의 RLS·컬럼 권한이 **전부 우회**된다
3. `anon`/`authenticated` 에 뷰 INSERT/UPDATE/DELETE 권한이 부여돼 있었다

결과적으로 **공개 anon 키만으로, 로그인 없이** 다음이 가능했다.

```http
PATCH /rest/v1/public_profiles?id=eq.<victim>
{ "user_type": "admin" }
```

임의 계정 관리자 승격(`app.is_admin()` 통과), `is_location_verified` 셀프 설정으로
동네 인증·`verify-location` 무력화, 닉네임·주소 변조, DELETE 로 계정 삭제까지.
`role=anon` 으로 **실증 확인**했고, 수정 후 `permission denied for view public_profiles`
를 확인했다.

조치는 뷰 정의를 바꾸는 게 아니라 **쓰기 권한 회수**였다. 익스플로잇의 핵심은
"정의자 뷰" 가 아니라 **"정의자 뷰에 쓰기 경로가 있었다"** 였기 때문이다.

### 실제로 밟은 함정 ②: 버려진 오버로드가 게이트를 우회

`create_post_verified` 를 확장하면서 9-파라미터를 drop 하지 않고 12-파라미터 오버로드를
추가해 **둘이 공존**했다. 앱은 9-파라미터만 호출하니 문제없어 보였지만, 12-파라미터에도
`authenticated` EXECUTE 가 남아 있어 **직접 호출하면 동네 인증 게이트를 우회**할 수 있었다.

같은 게이트를 오버로드에도 넣어 막았다. 그 뒤로 RPC 시그니처를 바꿀 때는 구버전 drop 을
같은 마이그레이션에 넣는다 — **"아무도 안 부르는 함수" 는 "아무도 못 부르는 함수" 가 아니다.**
