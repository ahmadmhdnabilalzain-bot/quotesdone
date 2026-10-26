#!/bin/bash
# one monitoring cycle: report merges since $1, release-failed PRs, and feed up to 3 stale labelled PRs
R=ahmadmhdnabilalzain-bot/quotesdone; SINCE=$1
echo "merged since $SINCE: $(gh pr list -R $R --state merged --search "merged:>=$SINCE" --json number --jq '[.[].number]|join(" ")')"
echo "open: $(gh pr list -R $R --state open --json number --jq length)"
echo "release-failed: $(gh pr list -R $R --state open --label release-failed --json number --jq '[.[].number]|join(" ")')"
running=0; fed=""
for p in $(gh pr list -R $R --state open --label review-approved --json number,createdAt --jq 'sort_by(.createdAt)|.[].number'); do
  st=$(gh pr checks $p -R $R 2>/dev/null | awk -F'\t' '{print $2}' | sort | uniq -c | tr '\n' ' ')
  if echo "$st" | grep -q pending; then running=$((running+1)); continue; fi
  if echo "$st" | grep -q fail && [ $running -lt 4 ]; then gh pr update-branch $p -R $R >/dev/null 2>&1 && { fed="$fed $p"; running=$((running+1)); }; fi
done
echo "in CI: $running  fed:$fed"
