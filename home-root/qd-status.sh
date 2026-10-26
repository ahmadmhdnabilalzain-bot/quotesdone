R=ahmadmhdnabilalzain-bot/quotesdone
for p in "$@"; do echo "$p $(gh pr view $p -R $R --json state --jq .state): $(gh pr checks $p -R $R 2>/dev/null | awk -F'\t' '$2!="pass" && $2!="skipping"{print $1":"$2}' | tr '\n' ';')"; done
