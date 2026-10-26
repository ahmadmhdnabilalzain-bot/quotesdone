#!/bin/bash
# merge the given no-SQL PRs when every check is green; rerun infra-failed DB checks once
cd /c/Users/Opera/qd-rel
left="$*"; declare -A rr
for i in $(seq 1 60); do
  next=""
  for p in $left; do
    st=$(gh pr view $p --json state --jq .state)
    [ "$st" != OPEN ] && { echo "$(date +%H:%M) #$p $st"; continue; }
    bad=$(gh pr checks $p 2>/dev/null | awk -F'\t' '$2!="pass" && $2!="skipping"{print $1":"$2}')
    if [ -z "$bad" ]; then gh pr merge $p --squash >/dev/null 2>&1 && echo "$(date +%H:%M) MERGED #$p" || { echo "$(date +%H:%M) merge failed #$p"; next="$next $p"; }; continue; fi
    if echo "$bad" | grep -q "^the database.*:fail" && [ -z "${rr[$p]}" ]; then
      r=$(gh pr checks $p | grep "^the database" | grep -oE "runs/[0-9]+" | cut -d/ -f2)
      if gh run view $r --log-failed 2>/dev/null | grep -q INFRASTRUCTURE; then gh run rerun $r --failed && rr[$p]=1 && echo "$(date +%H:%M) rerun db #$p"; fi
    fi
    if echo "$bad" | grep -q ":fail" && [ -z "${rr[$p]}" -o "$(echo "$bad"|grep -c :fail)" -gt 0 ] && ! echo "$bad" | grep -q pending; then echo "$(date +%H:%M) RED #$p: $(echo $bad)"; continue; fi
    next="$next $p"
  done
  left="$next"; [ -z "$(echo $left)" ] && break
  sleep 60
done
echo "left: $left"
