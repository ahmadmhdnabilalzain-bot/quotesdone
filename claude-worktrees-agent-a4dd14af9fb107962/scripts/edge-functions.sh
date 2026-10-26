#!/usr/bin/env bash
# QuotesDone — edge function deploy + source-control tooling.
#
# WHY THIS EXISTS
# ---------------
# The 195 Supabase edge functions that run this business have never been in git.
# The only way to change one was to read it out of the API and write it back by
# hand, which risks silent transcription drift in production code. On 21 Jul 2026
# that constraint blocked two verified fixes from shipping. This removes it.
#
# SETUP (once, ~60 seconds)
#   1. https://supabase.com/dashboard/account/tokens -> "Generate new token"
#      Name it "quotesdone-cli". Copy it (shown once).
#   2. setx SUPABASE_ACCESS_TOKEN "sbp_xxxxxxxx"        (Windows, new shell after)
#      export SUPABASE_ACCESS_TOKEN=sbp_xxxxxxxx        (bash/WSL)
#
# USAGE
#   ./scripts/edge-functions.sh pull            # mirror ALL functions into git
#   ./scripts/edge-functions.sh deploy <slug>   # deploy one function from disk
#   ./scripts/edge-functions.sh diff <slug>     # show local vs production drift
#
set -euo pipefail

REF=htdblwldjkcgjvmqkbeh
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FNDIR="$ROOT/supabase/functions"
SB="npx --yes supabase@latest"

# Functions that MUST keep verify_jwt OFF. Each implements its own auth (inbound
# __secret, admin-email JWT, or a public page route). Deploying one of these
# without --no-verify-jwt makes the gateway 401 every internal caller before the
# function body ever runs. This exact mistake took pdf_native down for ~3 minutes
# on 21 Jul 2026 — the list is here so it cannot happen again.
NO_JWT="pdf_native login_otp customer_api customer_portal supplier_api kyc quote_compare quote_ai home app portal os2 os3 admin crm site_deploy send_sms send_whatsapp send_outbox email_cron"

need_token() {
  if [ -z "${SUPABASE_ACCESS_TOKEN:-}" ]; then
    echo "SUPABASE_ACCESS_TOKEN is not set." >&2
    echo "Create one at https://supabase.com/dashboard/account/tokens then:" >&2
    echo "  export SUPABASE_ACCESS_TOKEN=sbp_..." >&2
    exit 1
  fi
}

wants_no_jwt() { case " $NO_JWT " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

cmd_pull() {
  need_token
  mkdir -p "$FNDIR"
  echo "Listing functions on $REF ..."
  $SB functions list --project-ref "$REF" -o json > /tmp/qd_fns.json
  local slugs ok=0 fail=0
  slugs=$(node -e 'const f=require("/tmp/qd_fns.json");console.log(f.map(x=>x.slug).join("\n"))')
  for s in $slugs; do
    printf "  %-38s " "$s"
    if (cd "$ROOT" && $SB functions download "$s" --project-ref "$REF" >/dev/null 2>&1); then
      echo "ok"; ok=$((ok+1))
    else
      echo "SKIP"; fail=$((fail+1))
    fi
  done
  echo
  echo "Mirrored $ok functions ($fail skipped) into supabase/functions/"
  echo "Next:  git add supabase/functions && git commit -m 'Put edge functions under source control'"
}

cmd_deploy() {
  need_token
  local slug="${1:?usage: deploy <slug>}"
  [ -d "$FNDIR/$slug" ] || { echo "No local source at supabase/functions/$slug — run 'pull' first." >&2; exit 1; }

  # Always snapshot what is live before overwriting it.
  local stamp; stamp=$(date -u +%Y%m%dT%H%M%SZ)
  local bak="$ROOT/.edge-backups/${slug}_$stamp"
  mkdir -p "$bak"
  local tmp; tmp=$(mktemp -d)
  if (cd "$tmp" && $SB functions download "$slug" --project-ref "$REF" >/dev/null 2>&1); then
    cp -r "$tmp/supabase/functions/$slug/." "$bak/" && echo "Backed up live $slug -> .edge-backups/${slug}_$stamp"
  else
    echo "WARNING: could not snapshot live $slug before deploy" >&2
  fi
  rm -rf "$tmp"

  if wants_no_jwt "$slug"; then
    echo "Deploying $slug WITH --no-verify-jwt (it implements its own auth)"
    (cd "$ROOT" && $SB functions deploy "$slug" --project-ref "$REF" --no-verify-jwt)
  else
    echo "Deploying $slug with JWT verification ON"
    (cd "$ROOT" && $SB functions deploy "$slug" --project-ref "$REF")
  fi

  echo
  echo "Deployed. Verify before walking away:"
  echo "  curl -s -o /dev/null -w '%{http_code}\\n' https://$REF.supabase.co/functions/v1/$slug"
}

cmd_diff() {
  need_token
  local slug="${1:?usage: diff <slug>}"
  local tmp; tmp=$(mktemp -d)
  (cd "$tmp" && $SB functions download "$slug" --project-ref "$REF" >/dev/null 2>&1) \
    || { echo "could not download $slug" >&2; rm -rf "$tmp"; exit 1; }
  if diff -u "$tmp/supabase/functions/$slug/index.ts" "$FNDIR/$slug/index.ts"; then
    echo "$slug: local matches production"
  fi
  rm -rf "$tmp"
}

case "${1:-}" in
  pull)   cmd_pull ;;
  deploy) shift; cmd_deploy "$@" ;;
  diff)   shift; cmd_diff "$@" ;;
  *) sed -n '1,20p' "${BASH_SOURCE[0]}"; exit 1 ;;
esac
