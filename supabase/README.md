# Edge functions — deploying and keeping them in git

## The problem this solves

QuotesDone runs on **195 Supabase edge functions**. Until now none of them were in
git. The repo held only the Next.js frontend.

That meant the only way to change backend code was to read a function out of the
Supabase API and write it back by hand. Every change risked silent transcription
drift — a mangled regex or a dropped line — landing straight in production with
nothing to diff against.

On 21 Jul 2026 that constraint stopped two already-verified fixes from shipping,
because the function in question (`customer_api`) is 64 KB and hand-copying it was
a worse risk than leaving the fixes unshipped.

## One-time setup (~60 seconds)

1. Go to **https://supabase.com/dashboard/account/tokens**
2. **Generate new token**, name it `quotesdone-cli`, copy it (shown once)
3. Set it in your environment:

```powershell
# Windows — then open a NEW terminal
setx SUPABASE_ACCESS_TOKEN "sbp_xxxxxxxxxxxxxxxx"
```

```bash
# bash / WSL
export SUPABASE_ACCESS_TOKEN=sbp_xxxxxxxxxxxxxxxx
```

The token is a personal access token for your own Supabase account. Treat it like
a password: never commit it, never paste it into a chat.

## Then

```bash
# Mirror all 195 functions into the repo — do this first
./scripts/edge-functions.sh pull
git add supabase/functions && git commit -m "Put edge functions under source control"

# Ship the pending customer_api fixes (source is already staged in the repo)
./scripts/edge-functions.sh deploy customer_api

# See whether local differs from what is live
./scripts/edge-functions.sh diff customer_api
```

## What is staged and waiting

`supabase/functions/customer_api/index.ts` is **v33** — verified, not yet deployed.
Production is still on v32. Two changes, 67 lines, diffed line by line:

1. **`brief_pdf` action** — renders "What suppliers see" through `pdf_native`, so
   the download carries the QuotesDone header band, logo, licence letterhead and
   footer, exactly like a quotation and the comparison report. Today that button
   still uses browser print.
2. **Verification error copy** — used to say *"Check your inbox for the confirmation
   link."* No such link exists anywhere in the product; verification is a 6-digit
   code in the Account tab. Anyone who hit it had no way to act on it.

Verified before staging:
- `diff` against live v32 shows exactly those two changes and nothing else
- `deno check` reports **8 type errors on v33 and the same 8 on live v32** — the
  patch introduces zero new ones (these are pre-existing; Deno Deploy strips types)

After deploying, wire the portal button: in `src/components/me/CustomerPortal.tsx`,
`SupplierBrief` still calls `printSection(ref.current)`. Swap it for a
`compare_pdf`-style call to `brief_pdf` — the `Comparison` component right below it
is the working pattern to copy.

## The one trap that will bite you

**Deploying without `--no-verify-jwt` breaks any function that does its own auth.**

Supabase defaults `verify_jwt` to ON. Functions like `pdf_native`, `login_otp`,
`customer_api` and `kyc` authenticate internally (inbound `__secret` or an
admin-email JWT). If the gateway starts enforcing JWT, it returns 401 to every
internal caller *before* the function body runs — and the function looks fine in
the dashboard.

This happened to `pdf_native` on 21 Jul 2026; it 401'd for about three minutes
until the flag was restored.

`scripts/edge-functions.sh` keeps a `NO_JWT` allowlist and passes the flag
automatically. **Add any new self-authenticating function to that list.**

## Safety built into the script

- `deploy` snapshots the live version into `.edge-backups/<slug>_<timestamp>/`
  before overwriting, so rollback is a file copy
- `deploy` refuses to run if there is no local source (prevents deploying an
  empty directory over a working function)
- `diff` shows drift between local and production without touching anything
