# Running Claude Code on QuotesDone from claude.ai/code

Owner: it_engineer. Written 26 Oct 2026, on the founder's order: he must be able to run Claude Code
cloud sessions on this repository from his phone, with nothing depending on his Windows laptop.

The keys themselves, one row each with where to copy them, are in [keys.md](keys.md).

## What a session needs

| Variable | Required | What it is for |
|---|---|---|
| `SUPABASE_ACCESS_TOKEN` | yes | Every read and change of production. That includes `scripts/qsql.mjs`, `scripts/apply_sql.mjs`, `scripts/deploy_functions.mjs`, the checks and the sandbox rehearsals. Scripts also use it to fetch the service-role and anon keys (management API `api-keys`) and the internal credentials (`public.app_secrets`), so neither needs its own variable. |
| `GH_TOKEN` | yes | `gh`: reading CI runs and opening PRs. |
| `QD_AI_GATEWAY_SECRET` | no | Only `scripts/eval/reasoning_eval.mjs --live`. Its own error names it. |

A session needs no other key. OpenRouter, Stripe, Resend, Twilio, Dropbox and the rest are already
in Supabase. The deployed functions read them from there, and a session never handles them.

Optional settings, none of them secret:
- `QD_SANDBOX_OUT` is where rehearsal reports go. The default is a temp folder.
- `QD_OPS_PACK` is the folder of the operations knowledge pack used by `scripts/import_ops_knowledge.mjs`.

## One-time setup (about five minutes, from the phone)

1. Open **claude.ai/code** and start a new session.
2. Tap the **environment selector**, the first control under the message box, then choose **New environment**.
   To change an existing environment, find it under **Cloud**, then tap the settings icon beside it.
3. **Name:** `quotesdone`.
4. **Network access:** choose **Full**.
   Sessions call `api.supabase.com`, `htdblwldjkcgjvmqkbeh.supabase.co` and `www.quotesdone.com`, and
   the default **Trusted** list does not include them.
   If you would rather keep a list, choose **Custom** and tick *also include the default list*.
   Then add these domains:
   - `api.supabase.com`
   - `*.supabase.co`
   - `quotesdone.com`
   - `*.quotesdone.com`
   - `quotesdone.ae`
   - `*.quotesdone.ae`
5. **Environment variables:** enter one per line, in `NAME=value` form:
   ```
   SUPABASE_ACCESS_TOKEN=<paste>
   GH_TOKEN=<paste>
   ```
   Type the values in that box yourself. Never put a value in a chat message, a file or this repository.
   Anyone who can use this environment can read its variables, so keep the environment for your own use.
6. Leave **Setup script** empty. The repository installs its own tools (next section).
7. Tap **Add environment**, then pick this repository: `ahmadmhdnabilalzain-bot/quotesdone`.

## What happens when a session starts

`.claude/settings.json` has a SessionStart hook. It runs `scripts/cloud/setup.sh` only when
`CLAUDE_CODE_REMOTE=true`, which means a cloud session. It never runs on the laptop. The script does three things:

- **It installs what the cloud image lacks**, at the versions CI uses:
  - Node 24 (the image ships Node 22)
  - Deno 2.9.4
  - Supabase CLI 2.110.0
  - gh 2.96.0
  - the repository's npm packages

  Every download comes from `nodejs.org` or a GitHub release. A tool already at the right version
  is skipped, so after the first run this takes seconds.
- **It checks that `SUPABASE_ACCESS_TOKEN` and `GH_TOKEN` are present.** It prints names only, never a value.
  If either is missing, the session's first message says `MISSING: …`, naming each variable.
- **It puts the tools on `PATH`** for the rest of the session.

To run the same check by hand, in any session: `bash scripts/cloud/setup.sh --check`

## Supabase is already in the cloud

The project is `htdblwldjkcgjvmqkbeh`, and nothing about it lives on the laptop. A session reaches
it in two ways:

- **`SUPABASE_ACCESS_TOKEN` plus the project ref.**
  - The ref is written in the scripts. It is not a secret.
  - All reads, every apply (`apply_sql.mjs`, with its read-back) and every function deploy go this way.
  - `scripts/lib/supabase_token.mjs` is the one place a script reads the token. If the variable is
    missing, the error says `SUPABASE_ACCESS_TOKEN is not set`.
  - On the laptop the same helper also accepts the file that `supabase login` writes in the home
    folder. A cloud session never has that file.
- **The Supabase MCP connector (optional).** Connectors enabled on claude.ai work in cloud sessions.
  Their traffic goes through Anthropic's servers, so they need no network allowlist entry.
  - It is good for quick reads (`execute_sql`, logs, advisors).
  - Do not use it to change production. `apply_sql.mjs` and `deploy_functions.mjs` carry the
    guards, the MANIFEST discipline and the read-back that a raw connector call skips.
  - The scripts never depend on it. They need only the token.

## Known limits in cloud sessions

- **`gh pr …` and `gh issue …` return 403.** The cloud GitHub proxy refuses GraphQL, and these
  commands use it. Setting `GH_TOKEN` does not get around this. REST calls work, for example:
  ```
  gh api repos/ahmadmhdnabilalzain-bot/quotesdone/pulls -f title=… -f head=… -f base=main -f body=…
  ```
  `scripts/it/release_train.mjs` uses `gh pr`, so the release train keeps running in GitHub
  Actions, where it already runs. It does not run from a cloud session.
- **The browser rehearsals (`scripts/e2e/*walk*.mjs`) need Playwright's Chromium.** The setup
  skips that download because it is about 150 MB. Run `npx playwright install chromium` in the
  session that needs it.
- **`scripts/import_ops_knowledge.mjs` reads a knowledge pack that is not in the repository.**
  Point `QD_OPS_PACK` at a copy, or run it on the laptop.
