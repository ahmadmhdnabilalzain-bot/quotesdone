#!/bin/bash
# usage: qd-rel-kb.sh PR SEAT  - wait green, merge, load packs, run the seat's live exam
P=$1; SEAT=$2; cd /c/Users/Opera/qd-rel
for i in $(seq 1 90); do
  bad=$(gh pr checks $P 2>/dev/null | awk -F'\t' '$2!="pass" && $2!="skipping"{print $1":"$2}')
  [ -z "$bad" ] && break
  if echo "$bad" | grep -q ":fail" && ! echo "$bad" | grep -q pending; then echo "RED #$P: $(echo $bad)"; exit 1; fi
  sleep 60
done
[ -n "$bad" ] && { echo "TIMEOUT #$P: $(echo $bad)"; exit 1; }
gh pr merge $P --squash || exit 1
git fetch -q origin main; git checkout -q --detach origin/main
node scripts/kb/load_verified_packs.mjs --apply 2>&1 | tail -1
[ -n "$SEAT" ] && node scripts/eval/seat_qualification_exam.mjs --mode live --seat $SEAT 2>&1 | grep -E "pass [0-9]"
echo "MERGED #$P"
