# Keys a Claude Code session needs

Owner: it_engineer. Measured 26 Oct 2026. This page records names only. A value never goes in this
repository, and never in a chat message.

The founder's ruling of 26 Oct 2026 is that every key lives in GitHub and nothing lives on the
laptop. The founder copies each value from its dashboard and pastes it into the two places in the
table. Nobody else sets a secret. Setup steps are in [cloud-sessions.md](cloud-sessions.md).

## The keys

| Key | Purpose | Copy it from | GitHub repo secret | claude.ai/code environment |
|---|---|---|---|---|
| `SUPABASE_ACCESS_TOKEN` | Management API for project `htdblwldjkcgjvmqkbeh`: reads, applies, function deploys, checks. Scripts also use it to fetch the service-role and anon keys and the internal credentials, so those need no variable of their own. | https://supabase.com/dashboard/account/tokens (Generate new token) | **present** | **to add** |
| `GH_TOKEN` | `gh`: CI runs, PRs, release reads. | https://github.com/settings/personal-access-tokens/new. Make it fine-grained, for repository `quotesdone` only, with these permissions: Contents read/write, Pull requests read/write, Actions read, Metadata read. | not needed: Actions gets its own `github.token` on every run | **to add** |
| `QD_AI_GATEWAY_SECRET` | Optional. Only `scripts/eval/reasoning_eval.mjs --live` uses it. It is an internal credential the `ai_gateway` function accepts. | No dashboard. Internal credentials live in `public.app_secrets` (the `cred_fn_*` keys), and a session reads them with `SUPABASE_ACCESS_TOKEN`. Which key carries the `ai_gateway` scope was not measured. | absent; optional | absent; optional |

Where to paste:
- **GitHub repo secrets:** https://github.com/ahmadmhdnabilalzain-bot/quotesdone/settings/secrets/actions
- **The cloud environment:** claude.ai/code, then the environment selector, then the settings icon on `quotesdone`, then **Environment variables**.

## Everything else already lives in the cloud

A session does not need these keys, because the deployed functions read them where they are:
- **`public.app_secrets`:** 278 keys, including:
  - `openrouter_api_key`
  - `stripe_*`, `resend_*`, `twilio_*`, `dropbox_*`, `meta_*`
  - `vercel_token`, `github_token`
  - every `cred_fn_*` / `cred_cron_*`
- **Supabase edge secrets:** 12 names. `MS_CLIENT_ID`, `MS_CLIENT_SECRET`, `MS_TENANT_ID`,
  `SERPER_API_KEY` and `SITE_ERROR_INGEST_SECRET`, plus the 7 `SUPABASE_*` names Supabase sets itself.
  Dashboard: https://supabase.com/dashboard/project/htdblwldjkcgjvmqkbeh/settings/functions

## Where the laptop holds them today

These are the copies that stop mattering once the two rows above are filled in. Measured 26 Oct 2026:

- **Windows user and system environment variables:** no keys.
- **`~/.supabase/access-token`:** the Supabase token. `supabase login` writes it there.
  `scripts/lib/supabase_token.mjs` still accepts this file, but only when `SUPABASE_ACCESS_TOKEN` is unset.
- **Windows Credential Manager:** `Supabase CLI:supabase` (the Supabase login),
  `gh:github.com:ahmadmhdnabilalzain-bot` (the `gh` login) and `git:https://github.com` (git's login).
- **The repository:** no `.env` file.
