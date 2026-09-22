# QuotesDone

A UAE B2B **anonymous quotation marketplace**. A buyer posts a request describing a job or a
product; verified UAE suppliers quote it; the quotes reach the buyer with the supplier's identity
hidden. The buyer pays a **3% reveal fee** to unlock and contact one supplier.

The company is run by software: six seats (`sales_engineer`, `customer_support`, `accountant`,
`it_engineer`, `marketing`, `ceo`) own all 73 deployed functions between them, and a
15-minute tick does the work. `ARCHITECTURE.md` says where each kind of thing lives and how the
money moves. This file says how to run it.

---

## The stack

| piece | what it is |
|---|---|
| web | **Next.js 16** (`next@16.3.5`, React 19, App Router, `next-intl` for EN/AR) in `src/`, deployed on **Vercel**, serving **quotesdone.com** and **quotesdone.ae** |
| backend | **73 Supabase edge functions** (Deno, TypeScript) in `supabase/functions/<name>/index.ts` — the browser calls these directly; the Next app has exactly one API route of its own |
| database | **ONE Supabase project, `htdblwldjkcgjvmqkbeh`.** Postgres holds the data, the business rules as SQL routines, and the secrets. There is no second production project |
| scheduler | one Vercel cron, every 15 minutes, into `resilience_ping` |
| models | routed through the single `ai_gateway` function; OpenRouter is deliberately held (see `ARCHITECTURE.md`) |

Counted 23 Sep 2026: `ls supabase/functions/*/index.ts | wc -l` = **73**. It was 72 until
`sms_inbound` landed, and this line is re-measured on any commit that quotes it — a document that
hands the reader a command *and* an answer that disagree with each other is exactly the failure this
repository is trying to stop.

## Run it

```bash
npm ci
# configure the environment — see "Configuration" below
npm run dev          # http://localhost:3000
```

The dev server talks to the **live** Supabase project, because there is only one. Read freely;
anything that writes goes through an edge function that authenticates itself.

## Configuration

Put these in `.env.local` (git-ignored). Measured 22 Sep 2026 with
`grep -rhoE "process\.env\.[A-Z0-9_]+" src scripts` — names only, never a value in the repository.

| variable | read by | what it is |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | `src/lib/supaEnv.ts` | the project URL |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | `src/lib/supaEnv.ts` | the anon key; RLS is what protects the data |
| `NEXT_PUBLIC_VERCEL_ENV` | `src/lib/supaEnv.ts` | set by Vercel; only needed locally to reproduce preview behaviour |
| `CRON_SECRET` | `src/app/api/resilience-ping/route.ts:35` | the bearer Vercel Cron presents. Unset = the route accepts the call unauthenticated |
| `SUPABASE_ACCESS_TOKEN` | every script in `scripts/` | a Supabase personal access token (`sbp_…`). `scripts/lib/qd_guard.mjs` falls back to `~/.supabase/access-token` |

Optional per-run switches exist for the harnesses (`QD_SITE`, `QD_HEADED`, `QD_E2E_REPORTS`,
`QD_FIXTURES`, `QD_TARGET_REF`, `QD_STAGING_REF`, `QD_AED_PER_USD`); leave them unset unless you
are running that thing.

**The edge functions are not configured from here.** Supabase injects `SUPABASE_URL`,
`SUPABASE_SERVICE_ROLE_KEY` and `SUPABASE_ANON_KEY`; every third-party credential — Resend,
Twilio, Stripe, Dropbox, Vercel, OpenRouter — is a row in the `public.app_secrets` table, read at
call time. There is no `.env` to leak, which is the point.

## Test

```bash
npm test                 # scripts/checks/run.mjs — every *.test.mjs plus the Deno suite
npm run typecheck        # tsc --noEmit over the Next app
deno check --no-lock --node-modules-dir=auto supabase/functions/*/index.ts
```

`npm test` needs `deno` on PATH and fails hard without it: a suite that could not run must not be
reported as one that passed. Checks that read production need `SUPABASE_ACCESS_TOKEN`.

CI (`.github/workflows/checks.yml`) runs the same three, plus `npm audit --omit=dev
--audit-level=high` and a Squawk lint of any hand-written migration.

## Change the database

One project, and every change is a file.

```bash
node scripts/qsql.mjs <file.sql>           # READ production. SELECT only
node scripts/apply_sql.mjs <file.sql>      # dry run: parse, plan, change nothing
node scripts/apply_sql.mjs <file.sql> --apply
```

1. Write **one file per subject** in `scripts/sql/`, named as a lowercase sentence saying what it
   does — `the_customer_asks_and_the_chain_actually_starts.sql`. Its first 40 lines say what was
   measured, what was wrong, what this changes and what it deliberately does not.
2. Add its path as a line at the **end** of `scripts/sql/MANIFEST.txt`. The manifest is the apply
   order, and its order is what decides which file is canonical for a routine.
3. A `SECURITY DEFINER` routine created here revokes `EXECUTE` from `PUBLIC`, `anon` and
   `authenticated`, and pins `search_path`. A new table gets RLS **and** a policy.
4. Apply, commit the file and the manifest line in the same commit, then
   `node scripts/checks/canonical_routine_manifest.mjs` — it must report 0 findings. Applying
   without committing makes the repository and the database disagree, and CI says so.

## Deploy

| what | how |
|---|---|
| the site | push to `main` — Vercel builds and deploys it |
| an edge function | the `deploy-functions` workflow (`.github/workflows/deploy-functions.yml`), or `node scripts/deploy_functions.mjs <slug>` |
| proof it landed | `node scripts/verify_deploy_parity.mjs --all` — compares every deployed bundle against the repository |

## Where the rules live

The code is not the whole company. Three places hold decisions, and none of them is a comment:

| what | where |
|---|---|
| the founder's instructions, verbatim, the moment he gives them | `public.founder_instruction` (`select * from public.fn_founder_open_instructions();` shows what is still owed) |
| a settled policy, and the guard that enforces it | `public.company_policy_decision` + the trigger, constraint or check that makes it true |
| how a session must work | `.claude/skills/*/SKILL.md`, registered in `.claude/CLAUDE.md` |
| narrative, history, audits | `docs/` — never the source of truth for behaviour. Things the company has left are in `docs/archive/` |

Where a document and the code disagree, the code is right and the document is stale.
