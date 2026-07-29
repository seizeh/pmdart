# ADR-0005: DB 변경 관리 — 스냅샷 복원에서 마이그레이션 리플레이로

- 상태: 채택 (2026-07-29) — 종전의 스냅샷 전용 방식을 대체
- 관련: `pmdb` PR #138, `scripts/build_baseline.py`, `scripts/replay_check.sh`,
  `.github/workflows/db-tests.yml`

## 맥락

이 프로젝트의 기반 스키마는 2026-06-08 이전에 Supabase 프로젝트에 **직접 적용**됐고
마이그레이션 파일이 없다. 그래서 빈 DB 를 마이그레이션만으로 채울 수 없었고, CI 는
스냅샷(`schema/schema.sql`) 복원으로 테스트 DB 를 만들었다.

이 우회에는 두 가지 대가가 있었다.

- **재현 불가** — 저장소만 받아서 올려볼 수 없다
- **드리프트 무감지** — 마이그레이션 없이 운영 DB 에 직접 친 DDL 을 아무도 모른다

## 결정

빠진 조각을 스냅샷에서 **역산**해 `schema/baseline.sql` 로 복원하고, 등식이 성립하는지
CI 가 매번 검증한다.

```
빈 DB ─ prelude → replay-stubs → baseline → 기본권한 → migrations/* ─┐
                                                                     ├→ diff
빈 DB ─ prelude → schema.sql ───────────────────────────────────────┘
```

`baseline.sql` 은 손으로 쓴 게 아니라 `build_baseline.py` 의 자동 생성물이다
(마이그레이션을 순서대로 흘려 보며 "다시 만들어 주는 것" 을 빼낸다). 역산이 불가능한
조각만 `baseline-manual.sql` 에 수기로 둔다(현재 2건).

또한 PostgREST 는 `public` 스키마만 노출하므로, **`.rpc()` 로 부를 함수는 `public` 에**,
내부 전용(트리거 함수·refresh 토큰 저장 등)은 `app` 스키마에 둔다.

## 검토한 대안

| 대안 | 기각 사유 |
|---|---|
| 현재 스냅샷을 그대로 baseline 으로 승격 | 리플레이가 곧 스냅샷 복원 — 아무것도 검증 못 함 |
| 기반 스키마를 손으로 재작성 | 27개 테이블 + 함수·트리거·RLS. 검증 수단도 없음 |

## 결과

- 스냅샷을 갱신하면(`dump_schema.sh`) 베이스라인도 함께 재생성된다
- 리플레이 결과 DB 에서 pgTAP 을 한 번 더 돌려 "형태만 맞고 의미가 틀린" 경우를 막는다
- **운영 DB 에 직접 친 DDL 이 즉시 빨간불이 된다**

### 실제로 밟은 함정 ①: 만들자마자 진짜 드리프트가 나왔다

CI 를 켜자 운영 DB 에만 있고 마이그레이션에는 없는 정의가 무더기로 나왔다. 그중 하나는
동작 차이였다 — `app.dispatch_engagement_notifications` 의 `pawings` 조인에서

```sql
and w.context = p.authored_as   -- 같은 얼굴 팔로워만
```

이 빠져 있었다. `20260718160000` 이 넣은 조건을 `20260720090000` 의 `create or replace` 가
**조용히 지운 것**이다. 운영에는 살아 있어서 아무도 몰랐지만, 저장소만 보고 재생하면
**업체 소식이 개인 팔로워에게도 나간다.**

공유 함수를 각자 `create or replace` 하면 나중 것이 앞 것의 변경을 통째로 덮는다.
함수 재정의는 **반드시 운영의 현재 정의를 기준으로** 해야 한다.

### 실제로 밟은 함정 ②: `add column if not exists` 가 FK 를 삼킨다

베이스라인에 컬럼이 이미 있으면 `alter table … add column if not exists` 는 통째로
no-op 이 된다. 그러면 **같은 문장에 달린 `references`·`check` 까지 함께 사라진다.**
`posts.photo_verification_id` 의 FK 가 리플레이 결과에서 통째로 빠져 있었다.

무엇이 진짜 마이그레이션 소관 컬럼인지는 **운영 스키마의 컬럼 순서**로 판별한다 —
`ADD COLUMN` 은 항상 맨 뒤에 붙으므로 마이그레이션 소관 컬럼은 꼬리를 이룬다.
방어적으로 써 둔 `if not exists` 와 진짜 추가를 구분하는 유일한 단서였다.

### 실제로 밟은 함정 ③: `pg_dump` 출력은 되먹여도 그대로 안 나온다

varchar 컬럼에 `check (status in ('a','b'))` 를 걸면 pg_dump 가

```
(status)::text = ANY ((ARRAY['a'::character varying, …])::text[])   -- 배열 통째 캐스트
```

로 뱉는데, 이 텍스트를 **다시 파싱하면** 파서가 캐스트를 원소별로 접어

```
(status)::text = ANY (ARRAY[('a'::character varying)::text, …])
```

가 된다. 의미는 같은데 글자가 다르다. 그래서 스냅샷 파일과 직접 비교하지 않고
**스냅샷도 한 번 복원했다 다시 덤프**해 양쪽을 같은 처리에 태운다. 그래도 남는 것은
`normalize_schema.py` 가 맞춘다(DEFAULT ACL 껍데기 제거, ACL 나열 순서 정렬, 빈 줄 제거).
