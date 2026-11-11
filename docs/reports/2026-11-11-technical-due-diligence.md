# Technical due diligence, 11 Nov 2026

**Seat:** it_engineer. **Asked for by:** the founder, ruling 1622 (10 Nov 2026, standing): *"the code must stand up to
an investor's developer reviewing it under NDA: not random garbage, not messy, not needing a lot of work to operate,
and scalable."* Ruling 1621 ties supplier invitations to IT saying the code is good to go.
**Branch:** `it_engineer-due-diligence`, cut from `origin/main` 5d20a57eb. Nothing was applied or deployed and no PR
was opened. Production was read with SELECT statements only (function ownership and the active seats).

**How to read this.** It is written the way an outside reviewer would write it for an investor: what the system is,
then a score per area with the evidence behind it, then what a reviewer would call messy, what was fixed on this
branch, and the ranked plan for the rest. Every number names what was counted and how. Where a number is a
heuristic it says so.

---

## Verdict in one paragraph

QuotesDone is a serious, unusually well-documented pre-launch system: a Next.js site and two portals, 78 Supabase
edge functions, and a Postgres database that carries most of the business rules. The security posture is good (no
secrets in the repository, a fail-closed paid-provider gate, RLS and revokes enforced by checks), and the habit of
writing down *why* with a measurement is a real asset. What a reviewer would mark down is **scale of surface rather
than quality of any one file**: 2,125 SQL routines and 805 tables for a marketplace with no customers yet, most of
them for the AI seats' own management; database changes that are hand-applied files rather than a replayable
migration chain; one human and a stream of AI sessions as the whole team; and a release gate that, on the day of this
review, let `main` go red on 8 offline checks and does not build the site. None of these is hidden; most are already
in the debt register. **IT does not yet say "good to go" for ruling 1621**: the conditions are in
[What "good to go" needs](#what-good-to-go-needs), and they are days of work, not weeks.

---

## 1. The architecture in 15 minutes

### What it does

A buyer in the UAE describes a job or a product. The platform asks the questions an expert in that trade would ask,
matches verified suppliers by capability, and collects their quotes. The buyer sees the quotes with every supplier's
identity hidden and pays a **3% reveal fee** (Stripe) to unlock one. Suppliers are invited, verified against six
mandatory registration facts, and quote from their own portal. The company is pre-launch: every flow is proven on
synthetic `ZZ DEMO` data.

### The stack

| layer | technology | where |
|---|---|---|
| site and portals | Next.js 16.4.3, React 19.3, TypeScript 7.0.2 (`strict: true`), `next-intl` (English, Arabic), Tailwind 4, on Vercel | `src/` |
| backend | 78 Supabase edge functions, Deno, TypeScript | `supabase/functions/` |
| database | one Supabase Postgres project (`htdblwldjkcgjvmqkbeh`, region ap-southeast-1): 805 tables, 2,125 routines, 88 views, 105 cron jobs | changes in `scripts/sql/`, mirror in `supabase/schema/full_schema/` |
| providers | Stripe (money), Resend (email), Twilio (SMS, WhatsApp), Dropbox (backups), OpenRouter (models, held) | credentials are rows in `public.app_secrets` |

### The edge functions, by the seat that owns them

Read from `public.function_owner` on 10 Nov 2026 at 23:59 UTC. A seat is an AI staff role; there are six, all active
(`public.org_role`).

| seat | n | functions |
|---|---:|---|
| `sales_engineer` | 29 | the customer and supplier backends (`customer_api`, `supplier_api`, `customer_portal`, `supplier_portal`, `procurement_api`, `project_api`, `messages_api`), intake (`inquiry_intake`), matching and the seat itself (`sales_engineer`), documents and drawings (`doc_extract`, `extract_text`, `quote_extract`, `license_extract`, `drawing_boq`, `drawing_redact`, `cad_convert`, `pdf_native`, `supplier_catalog_ingest`), and the rest of the funnel (`quote_compare`, `kyc`, `rfq_flag`, `supplier_ack`, `supplier_onboard`, `customer_documents`, `customer_followup`, `customer_intelligence`, `claim_lookup`, `compliance_archive`, `conversation_archive`) |
| `customer_support` | 19 | every channel: the outbox (`send_outbox`, `send_sms`, `send_whatsapp`, `email_cron`), inbound (`inbound_email`, `resend_inbound`, `resend_webhook`, `email_triage`, `sms_inbound`, `wa_inbound`, `wa_status`, `transcribe`), WhatsApp templates (`wa_template_setup`, `wa_templates_watch`), the site's public doors (`public_site`, `site_assistant`, `contact_submit`, `complaint_status`, `unsubscribe`) |
| `it_engineer` | 13 | the estate: the tick (`resilience_ping`), the model gateway (`ai_gateway`), sign-in (`login_otp`, `mobile_otp`, `voice_otp`, `voice_otp_capture`, `role_guard`, `oauth_connect`), backups (`backup`, `dropbox_backup`), `embed_ml`, `site_error_ingest`, the seat (`it_engineer`) |
| `accountant` | 11 | money: `stripe_checkout`, `stripe_confirm`, `stripe_webhook`, `stripe_setup`, `stripe_setup_page`, `supplier_pay`, `refund_flow`, `refunds_api`, `reveal_invoice`, `sanctions_screen`, the seat (`accountant`) |
| `marketing` | 5 | `marketing`, `marketing_channels`, `marketing_outreach`, `marketing_social_connect`, `marketing_social_inbox` |
| `ceo` | 1 | `ceo_agent`: the daily plan, the weekly report, the decisions |

### The database, by area

Generated and drift-checked: [docs/architecture/database/README.md](../architecture/database/README.md). Every
routine, table, view and cron job is filed under one of ten areas with its canonical SQL file.

| area | routines | tables |
|---|---:|---:|
| Quotes, reveal and payments | 78 | 35 |
| Matching | 40 | 14 |
| Customers and inquiries | 192 | 87 |
| Suppliers and registration | 261 | 78 |
| Messaging, outbox and WhatsApp | 127 | 48 |
| Accounting | 175 | 51 |
| Marketing | 173 | 75 |
| Knowledge | 127 | 69 |
| IT, operations and monitoring | 370 | 116 |
| Seats, agents and duties | 582 | 232 |

### How work happens

- **The customer's money**, end to end: `ARCHITECTURE.md` section 3 (intake, the inquiry, readiness, matching, the
  supplier inbox, the quote, the reveal, the 3% computed in one module and cross-checked at checkout, Stripe, the
  idempotent webhook, the invoice, the audit against what Stripe took).
- **Scheduling.** `pg_cron` runs most recurring work (99 of 99 active, 26,698 runs and 0 failures in the 24 h measured
  on 10 Nov, reliability audit). A Vercel cron calls `/api/resilience-ping` every 15 minutes; the `resilience_ping`
  function runs the seats' duties by staleness within a 70 s budget (`fn_resilience_tick_plan`).
- **Channels.** One outbox table, `public.notifications`, for email (Resend), SMS and WhatsApp (Twilio), with
  attempts, dead-lettering, suppression and caps. The founder is mailed exceptions only, through
  `public.founder_mail_policy`.
- **Models.** Every call goes through `ai_gateway`: rate limit, a no-model answer first, routing, budget, cache, then the
  call. Permission to reach a paid provider is one function whose default is refusal (`_shared/paid_gate.ts`).
  OpenRouter is held on the founder's instruction, so the product runs deterministic code first.

### How a release happens without CI

GitHub Actions is off (ledger 1564: the budget is spent). All 29 workflows are `workflow_dispatch` only, and a check
(`the_schedules_moved_off_github_stay_on_pg_cron`) keeps them that way. A release is: a branch, the local gate
(`npm run gate`, `scripts/ci/local_gate.mjs`, which runs what the PR workflows ran) with its table posted on the PR, a
merge, and then the same session applies SQL with read-back (`scripts/apply_sql.mjs --apply --ddl`), deploys the
changed functions (`scripts/deploy_functions.mjs`, which refuses without an explicit target and reads `verify_jwt`
only from `supabase/config.toml`), regenerates the schema mirror and checks parity. Vercel builds the site from `main`
on its own. Full procedure: [docs/runbooks/release-without-ci.md](../runbooks/release-without-ci.md).

---

## 2. Scored assessment

Scale: **5** would pass an investor's review without comment; **4** good, with named gaps; **3** acceptable, a
reviewer would raise it; **2** a reviewer would call it a risk; **1** a blocker.

| # | area | score | one line |
|---|---|:---:|---|
| 1 | Code organisation | 3 | clear homes for everything, but a very large, flat surface |
| 2 | Readability | 3 | comments explain why with measurements; files and comments are long |
| 3 | Duplication | 2 | four helpers copied 43 to 81 times across functions, measured and registered |
| 4 | Typing | 3 | 0 compile errors everywhere, but 44 portal files unchecked and 989 `any` in functions |
| 5 | Tests | 3 | many tests, real behavioural ones on the money doors; a third are source-text checks; `main` red on 8 |
| 6 | Dead code | 4 | none found in `src/`; history archived rather than left on paths |
| 7 | Migrations and SQL discipline | 2 | disciplined by checks, but hand-applied and not replayable |
| 8 | Secrets handling | 4 | nothing in the repository; all credentials in one table read at call time |
| 9 | Observability | 2 | in-house signals only; no external uptime, APM or point-in-time recovery |
| 10 | Documentation | 3 | abundant and measured, and therefore often stale |
| 11 | Onboarding time | 3 | the site in under an hour; the database in one to two weeks |
| 12 | Bus factor | 1 | one human and AI sessions |
| 13 | Operability | 3 | one project, few moving parts, but every release is manual |
| 14 | Scalability | 3 | the shape scales; the region placement and the database's own workload need work |

### 2.1 Code organisation — 3

**Good.** Every kind of thing has one home and the root says where (`ARCHITECTURE.md` section 1): one directory per
edge function; one SQL file per subject named as a sentence; checks in `scripts/checks/`; tooling split into what is
imported (`scripts/lib/`, 42 files) and what is run. The database map is generated and fails a check when it drifts.
Large functions have been split into `actions/`, `lib/` and `handle.ts` (e.g. `customer_api/actions/`,
`supplier_api/lib/fields.ts`). `src/components` is grouped by surface (`me/` customer portal, `portal/` supplier
portal and modules, `home/`).

**What a reviewer would call messy.**
- **Flat, very large directories.** `scripts/sql/` holds 2,089 files in one folder (414k lines);
  `supabase/functions/_shared/` 476 files (249 modules, the rest tests and fixtures); `scripts/checks/` 615 files.
  The sentence names make each findable by search, not by browsing.
- **Where the code is.** 177k lines in `supabase/functions` and 414k in `scripts/sql`, against 39k in `src`. The
  largest database area is "Seats, agents and duties": 582 routines and 232 tables, more than quotes, payments and
  matching together (118 routines, 49 tables). A reviewer will ask how much of the system is the marketplace and how
  much is the machinery that runs the AI seats.
- **Four SQL apply tiers** decide which file defines a routine (`scripts/lib/canonical_routines.mjs`):
  `supabase/migrations_history` (739 files), `supabase/migrations` (10), `ai-organization/db-functions` (8),
  `scripts/sql` in manifest order. It is explicit and checked, and it is still four places.
- **Generated and vendored code inside source folders**: `_shared/brand_facts.generated.ts` (1,767 lines),
  `_shared/vendor/` (imagescript, sheetjs).

### 2.2 Readability — 3

**Good.** Comments state what was measured, what was wrong and the date, so a reader learns why a line exists:
`deploy_functions.mjs` lines 13-27 give each of its four rules the incident that produced it. Names are plain English.
Arabic copy is reviewed and hash-pinned per file.

**Messy.** File headers are often long narratives (the first 40 lines of a SQL file are its story, by rule), which is
excellent for an auditor of one change and heavy for a reader of the whole. The two largest handlers are single
functions: `inquiry_intake/handle.ts` 1,187 lines and `ai_gateway/handle.ts` 898 (TD-18). Several portal files pass
650 lines (`me/NewRequest.tsx` 718, `portal/supplier/ServicesTab.tsx` 694). Line-number citations in documents go
stale (`ARCHITECTURE.md` cited lines that moved when functions were split; corrected on this branch with a banner).

### 2.3 Duplication — 2

Measured with `git grep` over `supabase/functions` (non-test, vendor excluded), 11 Nov 2026:

| helper | copies | register |
|---|---:|---|
| JSON response helper `J` | 50 top-level definitions (66 incl. nested, 12 distinct bodies on 10 Nov) | TD-04 |
| CORS constant | 44 top-level, 10 distinct values | TD-05 |
| `createClient(` | 81 call sites | TD-06 |
| secret reader `sec` | 43 definitions | TD-07 |

Some of this has started moving into `_shared` (`json_response.ts`, `internal_auth.ts` `secretOk`). The order of the
remaining work is right in the register: settle CORS per policy first, then one factory, each with a deploy.

### 2.4 Typing — 3

- `tsc --noEmit` (TypeScript 7.0.2, `strict: true`): **0 errors**. `deno check` of all 78 functions: **0 errors**.
- **44 files in `src/` carry `@ts-nocheck`** (all in the two portals), hiding 1,185 errors when last measured
  (`docs/engineering/ts-nocheck.md`, TD-01). 0 in `supabase/functions`.
- **`any`**: 62 annotations or casts in `src/` (non-test) and **989** in `supabase/functions` (non-test, vendor
  excluded), `git grep ':\s*any\b|as any\b'`. Most are PostgREST rows with no declared type. The type checks pass
  partly because so much is `any`.

### 2.5 Tests — 3

What exists, measured 11 Nov 2026:

| kind | count | what it really covers |
|---|---:|---|
| Deno tests beside the functions | 451 files, 3,087 `Deno.test` blocks | unit and handler-level tests; the money doors are driven through their real handlers over a stubbed PostgREST/Stripe (`accountant/actions_contract.test.ts` pins every action and `execute_refunds`' guard order) |
| `scripts/checks/*.test.mjs` | 578 files | by a heuristic over the file text: **203** read production (read-only), **40** read the schema mirror, **152** execute code (import a module or spawn Deno), **165** match patterns in source text, 18 other |
| `src` tests | 35 files | portal models and helpers (`node --test`) |
| browser walks | 93 files in `scripts/e2e/` | Playwright walks run by hand or by a session; not in the gate |

**What a reviewer would raise.**
- **`main` was red on 8 offline checks** at 5d20a57eb (every `scripts/checks/*.test.mjs`, no token: 570 pass, 8 fail).
  The gate is routinely run as `npm run gate -- --offline --skip=npm-test`, and `npm-test` is exactly where these
  live. Two were it_engineer's and are fixed on this branch; six remain (section 4, TD-26).
- **29 of 78 functions have no `*.test.ts` in their directory**, three of them money paths: `refund_flow`,
  `stripe_confirm`, `supplier_pay` (18 check or test files elsewhere name the latter two). TD-08.
- **A third of the checks are source-text checks.** They prove a pattern is present in a file, not that the code
  does the right thing. Useful for structure, weak as behavioural evidence. TD-29.
- **No coverage measurement** and no browser end-to-end step in the gate.

### 2.6 Dead code — 4

- `src/`: of 277 non-route modules (non-test), **0** are named by no other `src` file. The 7 the first pass flagged
  are `instrumentation.ts` and `middleware.ts` (framework conventions) and five module barrels loaded through
  `dynamic(() => import(...))` from `me/dashboard/lazyModules.tsx`.
- `scripts/` root: 20 files; 3 were superseded and are archived on this branch (section 4). The other 17 are each run
  by a workflow, a check, a SQL header or a runbook.
- History is kept, not left on paths: `scripts/archive/` (76 files, with an index of what each did), 67 retired
  checks as `*.RETIRED.mjs`, `scripts/sql/DROPPED.txt` for routines removed on purpose.

### 2.7 Migrations and SQL discipline — 2

**How it works, honestly.** There is no replayable migration chain. A database change is a hand-written file in
`scripts/sql/`, applied to production through the Supabase Management API by `scripts/apply_sql.mjs`, which runs guards,
applies, and **reads each routine's definition back** to compare it with the file. `scripts/sql/MANIFEST.txt` is the
apply order and decides which file is canonical when several define the same routine. Today: **2,089 files**, **1,910**
listed in the manifest, **179** not applied, each with its own note in `scripts/sql/pending/` (173 of them probes that
are never applied by design, 6 changes waiting). After every apply the whole schema is exported to
`supabase/schema/full_schema/` (11 files) and a check fails if the export and production differ.

**What keeps it honest** (each is a check, not a habit): `canonical_routine_manifest.mjs` (one canonical file per
routine; no file unlisted and unnoted; no drift repo to production), `export_from_either_source_is_identical.mjs`,
`anon_cannot_execute_security_definer`, the advisors baseline, `each_pending_sql_file_has_its_own_note`, and Squawk on
hand-written migrations. `npm run db:local` rebuilds the whole public schema in a local Postgres from the mirror
(784/784 tables when measured on 9 Nov).

**What a reviewer would say.** You cannot create a fresh database from the repository by running migrations:
`supabase/migrations` replays only 414 tables of 805 (TD-10). Ordering lives in a text file, and the definition of a
routine may be in any of four tiers. Every change is applied by a person-equivalent session. It works because the
checks are strict, and it does not scale to a second team.

**The plan** (ranked item 3 in section 5): take a baseline dump of production as one migration, mark it applied
(`supabase migration repair`), and from then on write each change as a timestamped migration named with the same
sentence (`<timestamp>_<sentence>.sql`), applied by `supabase db push` from the gate. `scripts/sql/` and the manifest
become read-only history; the canonical-routine check gains the new tier first so nothing is ambiguous during the move.

### 2.8 Secrets handling — 4

- Scanned every tracked file (except lockfiles) for 10 credential shapes (Supabase PAT, Stripe live keys, Resend,
  Twilio SID, GitHub token, Dropbox, OpenRouter, private keys, service-role JWTs): every hit is a fixture or a
  placeholder (`sk_live_ZZDEMOlive`, `sbp_` + 40 zeros, a test string in `_shared/error_text.test.ts`). No JWT appears.
- Provider credentials are rows in `public.app_secrets` (278 keys), read at call time by the function that needs them
  with a fail-closed reader; 12 names are Supabase edge secrets (`docs/runbooks/keys.md`). Functions read only the
  three Supabase-injected variables and a few switches from the environment.
- Internal calls carry per-caller credentials (`_shared/internal_auth.ts`), and admin sign-in now has a second factor
  (authenticator app).
- **Gap:** every credential lives in one table in the production database, so anyone with service-role SQL reads all
  of them, and any copy of the database carries them. A vault (Supabase Vault or a KMS) with per-function grants is the
  long-term answer.

### 2.9 Observability — 2

- **What exists.** The site reports its own server errors (`src/instrumentation.ts` to `site_error_ingest`, with a
  heartbeat so silence is not read as health); each run writes `agent_runs`; the IT tick turns failures into findings;
  `fn_cron_liveness` pages the founder if the scheduler stops; 137 `console.*` calls in functions land in Supabase logs.
- **What is missing.** No external uptime monitor (TD-13); no APM, tracing or structured log schema; no error tracker
  outside the estate itself; point-in-time recovery is **off** and a whole-database restore has never been run
  (TD-21). A system that watches itself is blind when it is down.

### 2.10 Documentation — 3

386 Markdown files under `docs/`, plus `ARCHITECTURE.md`, a generated database map, runbooks for incidents, restore,
release, keys, Docker and a local database, and a debt register with measurements. That is far more than most
companies of this size have. The cost is staleness: in one pass this review found wrong numbers in the README (Next
version, function count, API routes, CI), `ARCHITECTURE.md` (five statements), `supabase/README.md` (72 functions, a
retired script), `.env.example`, the MANIFEST header (852 files when it holds 1,910) and the lint and debt counts (255
versus 268 versus 272). `docs/reports/` is 25 MB of evidence. The generated pages do not have this problem; the
hand-written ones do.

### 2.11 Onboarding time — 3

- Run the site: under an hour (`npm ci`, copy `.env.example`, `npm run dev`). Note the dev server talks to
  **production**, because there is one project; `npm run db:local` gives a local schema copy with Docker.
- Productive on the web app: one to two days. The portals are ordinary React; the `@ts-nocheck` files slow it.
- Productive on the backend and database: one to two weeks, to learn the four apply tiers, the manifest, the seat
  model, `app_secrets`, the outbox and the conventions in `.claude/skills/` (18 skills) and `.claude/memory/` (437
  notes).
- `CONTRIBUTING.md` (added on this branch) is the entry point; before it the rules were spread over five places.

### 2.12 Bus factor — 1

The team is one person, the founder, plus Claude Code sessions acting as the seats. The cloud clone is shallow (TD-30),
so authorship can only be counted for the visible window, 2 to 11 Nov 2026: 457 commits, 324 authored as Claude, 122
by the founder's account (mostly merges). The operating knowledge is written down (skills, memory, runbooks, the
founder-instruction ledger), which is better than most single-founder codebases, but there is no second engineer who
has run a release, and releases depend on a session running the gate because CI is off.

### 2.13 Operability — 3

One Supabase project and one Vercel project, no servers, no staging to keep in sync. Vercel builds the site on its own.
Against that: every database change and every function deploy is a manual step after the merge; 105 cron jobs and
the tick run the seats; there is no staging, so the only full rehearsal environment is production with `ZZ DEMO`
data.

### 2.14 Scalability — 3

- Edge functions are stateless and scale with the platform; Postgres scales vertically a long way, and the data is
  small (about 20,300 leads, 0 customers, pre-launch).
- **The site's server functions run in Washington (iad1), the database is in Singapore, and the customers are in the
  UAE** (TD-22): every server render pays two long round trips.
- The database does a great deal of its own work: business rules in plpgsql, 26,698 cron runs a day with no
  customers. Under real load the database is the one shared bottleneck and the hardest part to test.
- 175 indexes with no recorded scans (202 MB, TD-20); some duties scan whole tables to find nothing (TD-19).
- No load test exists (the rules forbid one on production and there is nowhere else).

---

## 3. What a reviewer would call messy, in one list

1. `main` red on offline checks, and a gate that skips the step they live in and does not build the site (TD-25, TD-26).
2. The gate's `node_modules` is Deno's layout, not the lockfile: 13 of 215 top-level packages differ from
   `package-lock.json`, and `sharp` is 0.34.5 although `overrides` pins `^0.35.5` for GHSA-wq5f-xc86-pv6w (high,
   commit 0d0f7929d). Production is not affected (Vercel installs from the lockfile); the gate certifies a tree that
   is not the one shipped (TD-24).
3. Hand-applied SQL, 2,089 files, four apply tiers, no replayable migrations (TD-10).
4. 582 routines and 232 tables of AI-seat machinery around a marketplace core a fifth that size.
5. Helpers copied 43 to 81 times (TD-04 to TD-07); 44 unchecked portal files; 989 `any` in functions.
6. Documents that disagree with the code, and with each other, within a day of being written.
7. No external monitoring, PITR off, no whole-database restore drill.
8. Mixed GitHub Actions pins: the same actions by SHA in some workflows and by bare tag in others; one pin comment
   names the wrong version (TD-28).

---

## 4. Fixed on this branch

One commit each, in order. Each was proven by the checks that read what it touched, and the whole branch by the gate
and by the offline check diff in section 7.

| commit | what | proved by |
|---|---|---|
| archive the second deploy path | `scripts/edge-functions.sh` and `qd-pull-functions.ps1` (pulled production over git; deployed with their own `--no-verify-jwt` list, which `deploy_functions.mjs` rule 3 forbids) and `promote_rows_to_production.mjs` (staging to production; staging was deleted on 15 Aug) moved to `scripts/archive/` with index rows and repaired paths; the 27 Jul "production was the source of truth" note moved out of `supabase/functions/` to `docs/archive/`; `supabase/README.md` rewritten for today | `a_session_needs_no_laptop`, `schema_dump_not_replayable`, root allowlist, `every_test_file_is_run` |
| `main` red on two of it_engineer's own checks | `no_module_level_supabase_client` flagged a type-only import and a test file; the detector now skips type-only imports, a value import beside them is still caught, and only `*.test.*` files are exempt (self-tests added, broken once to prove it bites). `every_external_host_and_secret_is_registered`: the two test hosts of `admin_two_step_harness.ts` registered in `not_integrations`, the route the check's own header names. **`resilience_ping` should be redeployed after the merge** (the registry is bundled into it; runtime behaviour is unchanged) | both checks pass; `deno check` of `resilience_ping` |
| README | rewritten as the front door: the product, the stack with current versions, every top-level folder, run, test, the database, release without CI, the documentation index | no check reads its text |
| CONTRIBUTING.md | the one page on how a change gets in; root allowlist updated, and the dead `eslint.config.mjs` entry removed | root allowlist check |
| ARCHITECTURE.md | five false statements corrected (function count, API routes, the seat table, the backup second scheduler now on `pg_cron`, the deleted staging project), plus a banner on stale line citations | review against the cited files |
| two misleading config comments | `dependabot.yml` (the Tailwind 3 to 4 migration it described is done) and `.env.example` (provider keys are `app_secrets` rows) | `dependabot_watches_npm_and_actions`; YAML parses |
| a mangled pending note | shell residue `-strue-e0` removed; the other 178 notes scanned for the same shapes: none | `each_pending_sql_file_has_its_own_note` |
| debt register and lint counts | TD-02, 08, 09 and 15 re-measured (TD-15 paid: the MANIFEST header names the command, not a number); TD-24 to TD-30 added from this review | the three MANIFEST integrity counts (0 missing, 0 duplicates, unlisted = pending) |
| a folder named for what it no longer holds | `src/components/portal/approvals/` held only the Orders module after the founder removed Approvals on 14 Sep; it kept the name then only to avoid conflicts with in-flight branches. Renamed `orders/`, with every reader repointed (including a relative `../approvals/strings` import a path grep missed) | tsc 0, oxlint 0 errors / 272 warnings, `next build` 524/524 on a lockfile-exact tree; the Arabic-strings, approval-chain and nocheck checks |
| Dependabot keeps `@types/node` on the runtime's major | an ignore rule for `@types/node` majors while `.nvmrc` is 24 (the #1872 verdict) | YAML parses; `dependabot_watches_npm_and_actions` |
| a lockfile-exact `node_modules` by hard links | `scripts/ci/node_modules_from_lockfile.mjs`, the method section 6 used, kept so the next Dependabot PR can be tested the same way; memory note `.claude/memory/the-gate-tree-is-not-the-lockfile.md` | run twice from the committed file: 217 of 217 top-level packages match the lockfile |

**Not changed, and why.** The six other `main` failures belong to the ceo seat's in-flight work and regenerate files
that ship (the compiled brief, a seed SQL file that must be applied): `every_seat_card_comes_from_its_pack` and
`the_agent_brief_is_compiled_and_traced` (stale output of `scripts/kb/compile_brief.mjs`),
`the_senior_verdict_is_measured_against_the_standard_in_the_repository` (stale
`scripts/eval/seat_senior_standard_seed.mjs` output), `every_seat_is_held_to_a_senior_standard` (`ceo-exam-120` to
`122` have no checklist id), `seat_duties_run_on_their_clock` (`fn_ceo_launch_readiness_now` is registered by
`a_trade_opens_to_customers_as_soon_as_it_has_enough_verified_suppliers.sql`, which does not define it), and
`every_table_is_exported_or_explicitly_excluded` (11 new tables, starting `break_even_basis`, with no
`table_export_registry` row; that needs an applied SQL change).

---

## 5. The ranked plan for the rest

Ranked by what a reviewer would weigh most against the effort. Effort is one engineer-equivalent session-day = 1 d.

| rank | item | why first | effort | register |
|---:|---|---|---|---|
| 1 | Make `main` green and keep it green: fix the six ceo-seat failures; the merge rule becomes "no `--skip=npm-test` without the offline subset run and diffed against `main`" | a red `main` is the first thing a reviewer runs into | 0.5 d | TD-26 |
| 2 | The gate builds what ships: add a `next build` step; build the gate's tree with `npm ci` only and run the Deno steps with `--node-modules-dir=none` (all 78 functions type-check that way, measured on this branch); a check that the tree matches the lockfile | the gate must certify the shipped tree | 1 d | TD-24, TD-25 |
| 3 | Replayable migrations: baseline dump, `migration repair`, forward migrations named with the same sentences, `db push` from the gate, `scripts/sql` frozen as history | a fresh database from the repository is the standard a reviewer expects | 1-2 weeks | TD-10 |
| 4 | Point-in-time recovery on, and one whole-database restore drill on a branch database | data loss is the risk an investor cannot accept; PITR has a monthly cost, so the founder decides it | 1 d + cost | TD-21 |
| 5 | External uptime monitor on `/api/health` for both domains, and an error tracker for the site and functions | today a total outage is seen only by the system that is down | 0.5 d | TD-13 |
| 6 | Behavioural tests for the three money functions with none (`refund_flow`, `stripe_confirm`, `supplier_pay`), in the `actions_contract` style | money paths | 2-3 d | TD-08, TD-09 |
| 7 | Remove `@ts-nocheck` from the 44 portal files by declaring the `customer_api` and `supplier_api` response types once; then start on `any` in functions with generated database types | typing is where reviewers look next | 1-2 weeks | TD-01 |
| 8 | Shared CORS policy, one `J(cors)`, one client factory, one secret reader, each with its deploy | duplication | 1 week | TD-04 to TD-07 |
| 9 | Put the site's functions near the database (`regions` in `vercel.json`), measured before and after; a firewall rate-limit rule | latency and abuse | 0.5 d | TD-22, TD-23 |
| 10 | Split the two largest handlers, behaviour pinned first | readability | 2-3 d each | TD-18 |
| 11 | Replace source-text checks that guard behaviour with tests that run the code | test quality | ongoing | TD-29 |
| 12 | Secrets in a vault with per-function grants instead of one table | blast radius | 1 week | new |
| 13 | Measure and say plainly how much of the database serves the marketplace and how much the seats; retire what no seat uses | surface area | 1 week to measure | new |
| 14 | Pin every action by SHA with correct comments; run the `middleware-to-proxy` codemod | hygiene | 0.5 d | TD-27, TD-28 |

### What "good to go" needs

For ruling 1621, IT will say the code is good to go when: (a) items 1 and 2 are done and the full offline suite is green
on `main`; (b) this branch and the six safe Dependabot PRs below are merged, #1872 is closed, and zero PRs are open;
(c) `resilience_ping` has been redeployed and `verify_deploy_parity.mjs --all` reports every function carries the
repository's code. Items 3 onward are for the investor review, not for the invitations.

---

## 6. Dependabot and dependency security

### The seven open pull requests

Measured 11 Nov 2026 against `origin/main` 5d20a57eb. Every PR merges cleanly (`git merge-tree`). The two npm PRs
touch only `package.json` and `package-lock.json`, so main's source plus each PR's lockfile is the merge result.

**Method for the npm PRs.** Disk allowed no second 2 GB `npm ci`, and the shared gate tree is Deno's layout, not the
lockfile (TD-24). So for each lockfile an npm-layout `node_modules` was built inside the worktree by hard-linking each
locked package out of the existing Deno store, and downloading the 35 to 44 packages the store lacked (each checked
against its lockfile `sha512` integrity). That is exactly the tree `npm ci` would produce for linux-x64-glibc, at
almost no disk cost. Then `tsc --noEmit`, `oxlint`, `next build` (output on tmpfs), and `deno check` of all 78
functions (`--node-modules-dir=none`, in a tmpfs copy with that PR's `package.json`), and `npm audit` on each lockfile.

| | main | #1875 | #1872 |
|---|---|---|---|
| `tsc --noEmit` | 0 errors | 0 errors | 0 errors |
| `oxlint` | 0 errors, 272 warnings | 0 errors, 272 warnings (oxlint 1.92.0) | 0 errors, 272 warnings |
| `next build` | exit 0, 524/524 pages (16.4.3) | exit 0, 524/524 pages (16.4.5) | exit 0, 524/524 pages |
| `deno check`, 78 functions | exit 0 | exit 0 | exit 0 |
| `npm audit` (all and `--omit=dev`) | 0 | 0 | 0 |

| PR | what | verdict |
|---|---|---|
| **#1875** npm minor/patch group, 13 updates (next 16.4.5, supabase-js 2.119, lucide 1.70, motion 14.10, pdfjs 6.5, tailwind 4.3.5, oxlint 1.92, playwright 1.65, squawk 2.70, d3) | 89 lockfile entries change, none with an install script | **Safe to merge.** One operational note: Playwright 1.65 wants its own browser build, so run `npx playwright install chromium` before the next browser walk |
| **#1872** `@types/node` 24 to 26 | types only | **Close, with the reason.** It passes every check, but the runtime is Node 24 (`.nvmrc`); types for Node 26 would type-check calls Node 24 does not have. Keep `@types/node` on the runtime's major; this branch adds a Dependabot ignore for `@types/node` majors so it is not re-raised, to be lifted when the runtime moves |
| **#1871** `actions/download-artifact` 4.3.0 to 8.0.2 | 1 workflow | **Safe to merge.** Inert while Actions is off. The workflow parses; it uses only `path` and `pattern` |
| **#1870** `supabase/setup-cli` 3.1.0 to 3.2.0, `claude-code-action` 1.0.265 to 1.0.269 | 2 workflows | **Safe to merge.** Inert. Inputs used: `version`; `prompt`, `claude_args`, `claude_code_oauth_token`. The pin comment still reads "v1.0.263" (wrong before and after; TD-28) |
| **#1805** `actions/setup-node` 4 to 7 | 6 workflows | **Safe to merge.** Inert. v7 is already used, SHA-pinned, in other workflows of this repository; inputs used: `node-version`, `cache` |
| **#1804** `actions/checkout` 4 to 7 | 1 workflow | **Safe to merge.** Inert. v7 is already used elsewhere; input used: `fetch-depth` |
| **#1803** `actions/upload-artifact` 4 to 7 | 10 workflows | **Safe to merge.** Inert. Inputs used: `name`, `path`, `if-no-files-found`, `retention-days` |

For every workflow PR: all 29 workflows parse as YAML on the merged tree, all are `workflow_dispatch` only, all jobs
run on `ubuntu-latest`, and no step passes an input the new major removed.

### Security alerts

The GitHub tools available to this session expose no Dependabot-alerts endpoint, and the REST endpoint is not
reachable from here, so the alerts themselves were not read. Instead `npm audit --package-lock-only` was run on the
lockfiles of `main`, #1875 and #1872, for all dependencies and for production only: **0 advisories at any severity in
all six runs.** What matters for production: nothing today. The one known-vulnerable version anywhere is the
`sharp@0.34.5` in the shared gate tree (TD-24), which is not what Vercel installs.

---

## 7. Verification of this branch

| what | result |
|---|---|
| every `scripts/checks/*.test.mjs`, no production token, `origin/main` 5d20a57eb vs this branch, per file | main 570 pass / 8 fail; branch 572 pass / 6 fail. The only differences: `no_module_level_supabase_client` and `every_external_host_and_secret_is_registered` fail on main and pass here. Nothing passes on main and fails here |
| `npm run gate -- --offline --skip=npm-test` @ abe5937cf | **13 PASS, 0 FAIL**, exit 0: ssrf, fetch-timeout, dwg, redact-page, scan-redact, scan-takeoff, migration-lint (squawk), lint, typecheck, audit, deno-gated, deno-all, otp-race (on a throwaway Postgres in tmpfs). 13 SKIPPED: the 12 production steps under `--offline`, and `npm-test` (named in `--skip`; its offline subset is the row above) |
| commits after the gate run | `d06428215` (a standalone script in `scripts/ci/` and a memory note) and this report's results; no gate step reads either |
| tsc, oxlint, `next build` on a lockfile-exact tree after the rename | 0 errors; 0 errors, 272 warnings; exit 0, 524/524 pages |
| `origin/main` at push time | unchanged since the branch was cut (5d20a57eb), so no merge was needed |

## 8. Evidence and method notes

- Counts: `ls`, `find`, `git grep` and `wc` over the worktree at the commits named; the database counts are the
  generated map's (schema mirror). Function ownership and active seats: one SELECT through `scripts/qsql.mjs`,
  10 Nov 2026 23:59 UTC.
- The offline check diff: every `scripts/checks/*.test.mjs` run with `node --test`, no production token and no token
  file, six at a time, on a pristine `origin/main` worktree and on this branch, compared per file.
- The test-kind split (2.5) is a text heuristic (does the file read production, read the mirror, import or spawn
  code, or read source text), not a reading of 578 files.
- Not measured: test coverage, runtime performance under load, GitHub branch protection (the proxy answers 403).
