#!/bin/bash
# usage: qd-rel-release.sh PR SEAT file1.sql [file2.sql ...]   (apply order; probes named probe:xxx.sql)
set -u
P=$1; SEAT=$2; shift 2
cd /c/Users/Opera/qd-rel || exit 1
st=$(gh pr view $P --json state --jq .state)
if [ "$st" = OPEN ]; then gh pr merge $P --squash || { echo "MERGE FAILED #$P"; exit 1; }; fi
git fetch -q origin main && git checkout -q -B release/pr-$P origin/main || exit 1
for f in "$@"; do
  if [[ $f == probe:* ]]; then f=${f#probe:}
    out=$(node scripts/qsql.mjs scripts/sql/$f --ref=htdblwldjkcgjvmqkbeh 2>&1); echo "$out" | tail -3
    echo "$out" | grep -q "PROBE OK" && ! echo "$out" | grep -q "PROBE FAILED" || { echo "PROBE FAILED $f"; exit 2; }
    continue; fi
  out=$(node scripts/apply_sql.mjs scripts/sql/$f --apply --ddl --seat $SEAT 2>&1); echo "$out" | tail -2
  echo "$out" | grep -q "^APPLIED" || { echo "APPLY FAILED $f"; exit 3; }
  rm -f scripts/sql/pending/${f%.sql}.txt
  grep -qx "scripts/sql/$f" scripts/sql/MANIFEST.txt || echo "scripts/sql/$f" >> scripts/sql/MANIFEST.txt
done
node scripts/checks/export_from_either_source_is_identical.mjs --write 2>&1 | tail -1
git add -- scripts/sql/MANIFEST.txt scripts/sql/pending supabase/schema
git -c core.autocrlf=false commit -qm "$SEAT: #$P applied - pending notes out, MANIFEST and schema mirror recorded

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" && { git push -q origin HEAD:main || { git pull -q --rebase origin main && git push -q origin HEAD:main; }; } && echo "BOOKKEEPING PUSHED #$P"
node scripts/checks/canonical_routine_manifest.mjs 2>&1 | grep -E "countable|DRIFTED|gaps  |uncommitted"
git checkout -q --detach origin/main
