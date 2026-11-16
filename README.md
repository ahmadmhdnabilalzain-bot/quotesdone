# QuotesDone

A UAE B2B **anonymous quotation marketplace**. A buyer describes a job or a product; verified UAE suppliers quote
it; the quotes reach the buyer with each supplier's identity hidden. The buyer pays a **3% reveal fee** to unlock
and contact one supplier. Pre-launch: everything is proven on synthetic `ZZ DEMO` data, never on a real customer.

The company is run by software. Six **seats** (AI staff roles) own every deployed function and every scheduled
job between them; a person (the founder) holds the decisions only he can make. This file is the front door: what
the product is, how the repository is laid out, and how to run, test and release it.
`ARCHITECTURE.md` is the 15-minute tour of how it works. `CONTRIBUTING.md` is how to change it.

**Reading this for a review?** Start with `docs/reports/2026-11-11-technical-due-diligence.md`: the architecture in one
page, a scored assessment with evidence, and the ranked plan for what is not yet good enough.

---

## The stack

Versions read from `package.json` and `.nvmrc`, 11 Nov 2026.

| piece | what it is |
|---|---|
| web | **Next.js 16** (`next` 16.4.3, React 19.3, App Router, `next-intl` for English at `/` and Arabic at `/ar`, Tailwind 4) in `src/`, on **Vercel**, serving quotesdone.com and quotesdone.ae. Node 24 |
| backend | **79 Supabase edge functions** (Deno, TypeScript; 79 folders with an `index.ts`, counted 16 Nov 2026) in `supabase/functions/<name>/`, plus shared code in `supabase/functions/_shared/`. The browser calls them directly; the Next app has two API routes of its own (`/api/health`, `/api/resilience-ping`) |
| database | **one** Supabase Postgres project, `htdblwldjkcgjvmqkbeh`: 872 tables, 2,667 routines and 89 views in the `public` schema (extension objects excluded), and 154 `pg_cron` jobs, all active (SELECT on production, 16 Nov 2026; mapped by area in `docs/architecture/database/`). Business rules are SQL routines and constraints; there is no staging project |
| scheduling | `pg_cron` inside the database for most recurring work, and one Vercel cron (every 15 minutes) into the `resilience_ping` function, which runs the seats' duties by staleness within a time budget |
| messages | email through Resend, SMS and WhatsApp through Twilio; one outbox table (`public.notifications`) for all of them |
| money | Stripe (checkout, refunds, invoices) |
| models | every model call goes through the `ai_gateway` function; OpenRouter is held on the founder's standing instruction, so the product runs deterministic code first |
| secrets | rows in `public.app_secrets`, read at call time by the function that needs them; none in the repository |

## The repository

| path | what is in it |
|---|---|
| `src/` | the website and the two portals (customer at `/me`, supplier at `/portal`): `src/app` routes, `src/components`, `src/lib`, `src/content` |
| `supabase/functions/` | the backend, one directory per function; how to change and deploy one is in `supabase/README.md` |
| `scripts/sql/` | every database change, one file per subject, named as a sentence; `scripts/sql/MANIFEST.txt` is the apply order |
| `scripts/checks/` | the repository's checks: ~580 `node --test` files, some reading production read-only. `scripts/checks/run.mjs` runs them all plus the Deno tests |
| `scripts/ci/local_gate.mjs` | the release gate (`npm run gate`); GitHub Actions is switched off, so this is CI |
| `scripts/lib/` | modules other scripts import (the production guard `qd_guard.mjs`, the demo factory, the token reader) |
| `scripts/` (other folders) | tools a person runs: `e2e/` browser walks, `kb/` knowledge tools, `eval/`, `staging/` sandbox fixtures, `archive/` scripts that already did their job |
| `supabase/schema/full_schema/` | the schema mirror: the whole production `public` schema as text, regenerated after every apply |
| `knowledge/` | the company and trade knowledge the seats answer from |
| `docs/` | narrative: architecture maps, engineering standards and debt, runbooks, reports and evidence. Never the source of truth for behaviour |
| `.claude/` | the rules a Claude Code session works by (`skills/`) and its memory of the founder's rulings (`memory/MEMORY.md`) |
| `ai-organization/`, `knowledge-import/`, `messages/`, `tests/` | tier-3 SQL definitions still canonical for a few routines, the corpus importer, the `next-intl` message files, generated test fixtures |

## Run it

```bash
npm ci
cp .env.example .env.local     # every variable the code reads, with what it is; fill only what you need
npm run dev                    # http://localhost:3000
```

There is one Supabase project, so the dev server talks to **production**. Reading is safe; anything that writes goes
through an edge function that authenticates the caller. A local copy of the whole schema can be built from the mirror
with `npm run db:local` (Docker; `docs/runbooks/local-database.md`), and `docker compose up app` runs the site in a
container (`docs/runbooks/docker.md`).

## Test

```bash
npm run lint             # oxlint over src/ (errors fail; warnings are counted debt, docs/engineering/linting.md)
npm run typecheck        # tsc --noEmit over the Next app (TypeScript 7)
npm test                 # every scripts/checks test plus the Deno suite; needs deno on PATH
npm run gate -- --offline        # the release gate without production credentials
```

`npm test` fails hard when `deno` is missing: a suite that could not run is not a suite that passed. Checks that read
production need `SUPABASE_ACCESS_TOKEN`. Without it `npm test` skips them with the reason printed, and the gate fails
them unless it is run with `--offline`, which lists them SKIPPED; neither ever reports them as passed. What the tests
cover, and what they do not, is measured in the due-diligence report.

## Change the database

One project, and every change is a file.

```bash
node scripts/qsql.mjs <file.sql>                 # READ production. SELECT only
node scripts/apply_sql.mjs <file.sql>            # dry run: guards only, changes nothing
node scripts/apply_sql.mjs <file.sql> --apply --ddl   # apply, then read the definition back
```

1. Write **one file per subject** in `scripts/sql/`, named as a lowercase sentence saying what it does. Its first
   40 lines say what was measured, what was wrong, what it changes and what it deliberately does not.
2. Add its path as the **last** line of `scripts/sql/MANIFEST.txt`. The manifest's order decides which file is
   canonical for a routine. A file committed but not yet applied gets a note in `scripts/sql/pending/` instead.
3. A `SECURITY DEFINER` routine revokes `EXECUTE` from `PUBLIC`, `anon` and `authenticated` and pins `search_path`.
   A new table gets RLS **and** a policy.
4. Apply, commit the file and its manifest line together, regenerate the mirror, and run
   `node scripts/checks/canonical_routine_manifest.mjs` (0 findings).

## Release

GitHub Actions is **off** (founder ruling, ledger 1564: the Actions budget is spent). Every workflow is
`workflow_dispatch` only and must not be dispatched. A release is:

1. a branch and a pull request;
2. `npm run gate` green on the PR's own head, its table posted on the PR;
3. merge;
4. the same session applies any SQL, deploys the changed functions with
   `node scripts/deploy_functions.mjs --ref=htdblwldjkcgjvmqkbeh --production <slugs>`, regenerates the schema mirror
   and checks parity. Vercel builds the site from `main` by itself.

The full procedure, including how to merge from a cloud session, is `docs/runbooks/release-without-ci.md`.

## Where the rules live

The code is not the whole company. Four places hold decisions, and none of them is a comment:

| what | where |
|---|---|
| the founder's instructions, verbatim, the moment he gives them | `public.founder_instruction` (`select * from public.fn_founder_open_instructions();` shows what is still owed) |
| a settled policy, and the guard that enforces it | `public.company_policy_decision` + the trigger, constraint or check that makes it true |
| how a session must work | `.claude/skills/*/SKILL.md`, registered in `.claude/CLAUDE.md` |
| narrative, history, audits | `docs/`, with what the company has left in `docs/archive/` |

Where a document and the code disagree, the code is right and the document is stale; fix the document.

## Documentation index

| need | page |
|---|---|
| how it works, end to end | `ARCHITECTURE.md` |
| the database by business area (generated) | `docs/architecture/database/README.md` |
| engineering standards, lint and typing policy, the debt register | `docs/engineering/README.md` |
| operating it: incidents, restore, release, keys, Docker | `docs/runbooks/README.md` |
| changing it | `CONTRIBUTING.md` |
| reports and evidence | `docs/reports/README.md` |
