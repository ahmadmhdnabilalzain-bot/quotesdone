#!/bin/bash
S=/c/Users/Opera/AppData/Local/Temp/claude/C--Users-Opera-quotesdone/8c4972a3-8a16-4cb0-a308-31a4f45e00bb/scratchpad/int3
mkdir -p $S
for b in "$@"; do
  if [ "$b" = every_test_and_every_run_reaches_the_model_and_openrouter_stays_on ]; then
    cp scripts/sql/$b.sql $S/orig.sql
    { echo "set local app.change_reason = 'founder:1260';"; cat $S/orig.sql; } > scripts/sql/$b.sql
  fi
  node scripts/apply_sql.mjs scripts/sql/$b.sql --apply --ddl --seat it_engineer > $S/$b.log 2>&1; rc=$?
  [ "$b" = every_test_and_every_run_reaches_the_model_and_openrouter_stays_on ] && cp $S/orig.sql scripts/sql/$b.sql
  echo "=== $b rc=$rc $(grep -E '^PROBE|APPLIED' $S/$b.log | tr '\n' ' ' | cut -c1-160)"
  [ $rc = 0 ] || { tail -6 $S/$b.log; exit 1; }
  echo $b >> $S/applied.txt
done
