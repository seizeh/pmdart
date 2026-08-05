"""PR 커버리지 코멘트 본문 생성 — lcov + 변경 파일 목록 → 마크다운.
사용: python3 cov_report.py <lcov.info> <changed_files.txt>"""
import sys

lcov_path, changed_path = sys.argv[1], sys.argv[2]
per = {}  # file -> [hit, total]
cur = None
for line in open(lcov_path):
    line = line.strip()
    if line.startswith('SF:'):
        cur = line[3:]
        per[cur] = [0, 0]
    elif line.startswith('DA:') and cur:
        n = per[cur]
        n[1] += 1
        if int(line.split(',')[1]) > 0:
            n[0] += 1
    elif line == 'end_of_record':
        cur = None

tot_h = sum(h for h, _ in per.values())
tot_t = sum(t for _, t in per.values())
pct = tot_h * 100 / tot_t if tot_t else 0.0

changed = [f.strip() for f in open(changed_path) if f.strip()]
rows = []
for f in changed:
    if f in per:
        h, t = per[f]
        p = h * 100 / t if t else 0.0
        mark = '🟢' if p >= 80 else ('🟡' if p >= 40 else '🔴')
        rows.append(f'| `{f}` | {mark} {p:.0f}% ({h}/{t}) |')
    else:
        # 테스트가 한 번도 import 하지 않은 파일 — lcov 에 아예 안 나온다.
        rows.append(f'| `{f}` | ⚪ 커버 없음 |')

print('<!-- coverage-report -->')
print(f'**전체 라인 커버리지: {pct:.1f}%** ({tot_h}/{tot_t})')
if rows:
    print()
    print('이 PR 의 변경 파일:')
    print()
    print('| 파일 | 커버리지 |')
    print('|---|---|')
    print('\n'.join(rows))
