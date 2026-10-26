# approve action_required runs on the current head of each given PR
R=ahmadmhdnabilalzain-bot/quotesdone
for p in "$@"; do
  read b h <<<"$(gh pr view $p -R $R --json headRefName,headRefOid --jq '.headRefName+" "+.headRefOid')"
  for id in $(gh run list -R $R --branch "$b" --limit 10 --json databaseId,conclusion,headSha --jq ".[]|select(.conclusion==\"action_required\" and .headSha==\"$h\")|.databaseId"); do
    gh api -X POST repos/$R/actions/runs/$id/approve >/dev/null && echo -n "$p:$id "
  done
done; echo
