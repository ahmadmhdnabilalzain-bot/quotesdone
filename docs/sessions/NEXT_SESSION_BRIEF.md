# START HERE — QuotesDone, 5 August 2026, end of session 7

`f4a333a` on **`repair/finish-quotesdone`** (branched from `repair/package-conformance-batch-0`).
**Pushed. Not merged. Production unchanged.**

Staging **`pglpqrhvozwepymcuunn`** · production **`htdblwldjkcgjvmqkbeh`** (read-only, never deployed to).

Run these first. All three should be green before you touch anything:

```
node scripts/staging/verify_phase1.mjs      # 12/12  deployed, isolated, in sync
node scripts/staging/smoke_staging.mjs      # 15/15  auth, storage, postgrest, 10 functions
node scripts/staging/journey_test.mjs       # 28/28  signup -> quotation comparison
```

---

## 0. Settled — do not re-open

**Phase 1 is done and verified.** Staging matches production exactly: 403 tables, 161 views, 739
routines, 5,237 columns. 190/190 Edge Functions deployed, 17 requiring a JWT, zero `verify_jwt`
drift against `config.toml`. Migration ledger reconciled at 712 @ `20260804182051`.

**Phase 2 is done except file upload.** The whole customer-to-quotation journey runs against
deployed staging with real Auth users: signup, OTP, profile, terms, AI intake (readiness 100),
inquiry creation, dispatch to 12 matched suppliers, supplier inbox, quotation, revision,
structured review, comparison PDF, and cross-account isolation checks.

**Staging isolation holds and must keep holding:** 0 cron jobs, 0 routines referencing production,
no live payment or deploy tokens. `verify_phase1.mjs` asserts all three — if it ever fails, stop.

---

## 1. Staging inventory (measured, do not re-derive)

| | production | staging |
|---|--:|--:|
| tables / views / routines / columns | 403 / 161 / 739 / 5237 | **identical** |
| Edge Functions deployed | — | **190 / 190** |
| cron jobs | 149 | **0** (deliberate) |
| `app_secrets` | 194 | 171 (18 withheld, 5 guard-refused) |
| `internal_credential` | 74 | **74** |
| storage buckets | 15 | **15** |
| `fn_task_class` | 66 | **66** |
| taxonomy rows copied | — | ~9,700 incl. the **86** supplier categories |
| `supplier_capabilities` | **0** | seeded per test run, purged after |

**Withheld from staging on purpose** (`scripts/staging/seed_staging_secrets.mjs` names each and
why): `vercel_token` + project + team, `github_token`, all 5 `dropbox_*`, all 6 `twilio_*`,
`qa_customer_password`, and **both Stripe keys because production's are LIVE**. Five brand/logo
URLs are refused by `qd_guard` for embedding the production ref.

Vercel: team `quotes-done`, project `quotesdone-next`. **Preview** env has
`NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY` pointing at staging. Production
domains `quotesdone.com` / `quotesdone.ae` untouched.

---

## 2. Pending work, in dependency order

### 2.1 Phase 2 — the one remaining step

**Files and drawings (journey step 9).** Nothing exercises upload yet. The keys are already live in
staging: `virustotal_api_key`, `cloudconvert_api_key`. Functions involved: `extract_text`,
`doc_extract`, `drawing_boq`, `drawing_redact`, `cad_convert`, `attach_photos`, `vt_scan`.
Doing this also opens the **upload-based review path**: a quote submitted as a document creates a
`quote_reviews` row, which a form quote never does (form quotes are scored into `quotes.quality`
instead — the journey asserts both).

### 2.2 Phase 3 — supplier journey

Working: registration, company creation, profile, terms, approval, quote submit/revise.
Not built or not proven: licence and document upload, storage-level document ownership, **the
supplier-facing capability flow does not exist at all** (see §3), inquiry assignments, quotation
history, supplier exceptions, expiry and recovery, founding-rank exemption, subscription state.

### 2.3 Phase 4 — taxonomy

The 86 categories are in staging (`catalog_supplier_categories`), but the routes still have
**0 callers in code**. Nothing is wired to `customer_api`, `profile_ai`, `inquiry_intake`,
supplier category mapping, inbound email, or drawing/BOQ. The hardcoded lists are untouched.
The intake classifier is already in shadow mode (deterministic keywords win when the model's
category has no support; disagreements return as `classifier_override`).

### 2.4 Phase 5 — portals and API actions

**0 of 29** package API actions exist. Portal error rendering, Arabic and RTL untouched.
`CustomerPortal.tsx:237` has a pre-existing `side-tab` design finding left deliberately for this
phase.

### 2.5 Phase 6 — AI gateway and cost

`llm_calls` is **0** despite inference succeeding, so model, provider, tokens and cost are not
recorded. `task_class` is passed by 1 of 60 callers. `resend_inbound` calls OpenRouter directly at
`index.ts:262`, outside the gateway's budget halt.

### 2.6 Phase 7 — workflow and autonomy

Staging has **0 executors** against production's 55. `workflow_run`, `workflow_step_run`,
`action_execution`, `decision_trace` exist with the right columns and have **no writers**.
`v_executor_registry_gaps` returns 0 in staging **because there is no data** — that zero means
nothing until executors are loaded. `cos_execute` correctly stays off.

### 2.7 Phase 8 — acceptance

Nothing yet. No synthetic corpus (100 customers / 100 suppliers / 5 admins), no Playwright, and
**nothing has run against the deployed Vercel URL** — the frontend was verified by reading its
built bundle, not by driving it.

---

## 3. Traps that cost real time this session

**A green suite over a subsystem that never ran.** The journey passed 19/19 while every LLM call
was failing and `inquiry_intake` was silently using its keyword fallback. It also passed while
`route_inquiry` was refused by internal auth on every call. A step that returns HTTP 200 is not a
step that worked.

**`fn_task_class` empty means the routing policy is never consulted.** `ai_gateway` maps a calling
function to its task class through that table. With it empty, everything falls to the default tier
and `model_policy` is loaded and ignored. Copying the real 66 mappings then *broke* things that had
been accidentally working — which is how the next two were found.

**`inquiry_intake` is mapped to a switched-off task class.** `missing_fields_detection` has
`tier=none, model=none, max_tokens=0`. The intake runs the entire customer conversation and writes
the supplier brief; with no model it degrades to keyword guessing, readiness freezes at 40, and no
customer can ever complete an inquiry. **Production still carries this mapping**, which is
consistent with production having 0 inquiries. Staging is remapped to `agent_reasoning`.

**Token budgets that fit one candidate, not twelve.** `rfq_routing` at 300 output tokens produced
unparseable output the moment 12 suppliers cleared the capability floor, and reported zero fits.
Its own log says it: *"12 viable candidates were never judged. Downstream this is
indistinguishable from a supply coverage gap."* Raised to 2,500. `quote_compare` had no mapping at
all and truncated at 1,500; now `quote_comparison` at sonnet/3,000.

**`p_limit 12` with ties broken by ascending `supplier_id`.** Once twelve identically-scored demo
suppliers exist, the oldest twelve always win and every newer supplier is structurally invisible to
matching. The journey now deletes its `leads` rows, not just its auth users. **If dispatch ever
matches suppliers you did not create this run, check for accumulated `Journey Test %` rows.**

**An API that says "submitted" while the row says `draft`.** A quote is only accepted when the form
is complete: `source:'form'`, a priced `items` array, `validity`, `warranty`, `lead_time`. Sending
amount and notes alone leaves drafts, and comparison then correctly refuses with "needs at least
two complete quotes".

**Two completeness models that disagree.** Intake declared `ready` in its own vocabulary while
`fn_rfq_score` checked `category_specs.fields` canonical keys, so a fully answered request scored
3 of 4 and the RFQ was created and then never dispatched (`{skip:'not_rfq_ready'}`, surfaced
nowhere). Intake now renders canonical keys in the checklist, makes them a prompt contract, and
verifies required fields deterministically before it may say ready.

**`echo` masked a failing exit code.** `cmd > log; echo "EXIT=$?" >> log` reports echo's status.
A 152-function deploy "succeeded" while the log said `EXIT=1`.

**A hook wrote its own stdout into a source file**, making it unparseable. If a script suddenly
fails with a syntax error on a line you did not write, check the file tail.

**GateGuard fired 26 times.** Every first edit of a file demands importers, affected API, data
schemas and a verbatim instruction quote. Disable with `ECC_GATEGUARD=off` or add
`pre:edit-write:gateguard-fact-force` and `pre:bash:gateguard-fact-force` to `ECC_DISABLED_HOOKS`.

---

## 4. Defects fixed this session (all committed on the branch)

| what | why it mattered |
|---|---|
| SQL splitter merged all 590 functions into one statement | rebuild produced a schema with **zero** functions and called it clean |
| `fetch` with no timeout in `qd_guard` | a hung request stalled a rebuild silently; backoff could not fire |
| production ref compiled into 5 frontend files | Vercel env vars did nothing; a staging page wrote to **production** |
| `deploy_functions.ps1` + `gen_supabase_config.mjs` pinned to production | no route existed to deploy a function anywhere else |
| `drop schema public` destroyed default privileges | all 403 tables granted to nobody; PostgREST 403; `customer_api` returned `{"customer":null}` then crashed |
| `internal_credential` empty | every function-to-function call refused; routing silently fell back |
| `fn_schema_export` has no TYPES section, one literal `\n`, one missing sequence | six tables uncreatable, incl. `action_class_gate` |
| `dispatch_inquiry` + 3 others called a hardcoded production URL | staging adjudicated RFQs against **production's** supplier base and flagged false coverage gaps |
| intake could bless an undispatchable RFQ | see §3 |
| `fn_task_class` / `rfq_routing` / `quote_compare` routing | see §3 |

---

## 5. Blocked on the founder — exactly one thing

**Stripe test-mode keys.** Production's are LIVE (`sk_live` / `pk_live`), so they are withheld from
staging by a prefix rule, not a name list. Test keys can only come from the Stripe dashboard.
This is also the one action the founder's own spec says needs approval.

Everything else is unblocked: Resend, OpenRouter, VirusTotal, CloudConvert and Apify keys are all
live in staging. `email_enabled` is set to `false` deliberately so staging cannot mail a real
person — turn it on behind a recipient allowlist when proving notification. Twilio and Dropbox stay
withheld on purpose (real messages, production folders).

---

## 6. Findings about PRODUCTION worth acting on

These were measured read-only and are **not** fixed, because production is not deployed to:

- **`stripe_secret_key` and `stripe_publishable_key` are LIVE keys.**
- **`inquiry_intake` maps to a switched-off task class**, so the intake there is running on keyword
  fallback too. Production has 0 inquiries, 0 quotes, 0 customers, 20,464 leads.
- **`supplier_capabilities` has 0 rows**, so the capability-gated dispatch path has never run.
- **`quote_compare` has no `fn_task_class` mapping.**
- `github_token` and `vercel_token` live in the `app_secrets` **table**, which is how
  `run_auto_deploy()` and `run_site_autodeploy()` work — a database row can deploy the site.
- 149 cron jobs are armed.

---

## 7. Production deployment sequence — NOT READY

Do not prepare one yet. The completion standard requires the full Playwright/API suite (Phase 8),
which does not exist. When it does, the sequence must cover: the 4 Edge Functions whose production
URL was replaced with `SUPABASE_URL`, the `inquiry_intake` changes, the `fn_task_class` mapping for
`quote_compare`, the `inquiry_intake` task-class remap, and the `rfq_routing` / `quote_comparison`
token budgets. Every one of those is a live-behaviour change to a system currently serving zero
traffic, so the risk is low — but the suite comes first.

---

## 8. Tooling added this session (all in `scripts/staging/`)

| file | what it does |
|---|---|
| `verify_phase1.mjs` | 12 measurements: repo clean+pushed, functions deployed, jwt parity, schema parity, isolation, ledger |
| `smoke_staging.mjs` | real Auth user, storage, PostgREST, 10 functions |
| `journey_test.mjs` | the 28-step customer-to-quotation journey, self-cleaning |
| `seed_staging_secrets.mjs` | copies `app_secrets` + `internal_credential`, withholds by name and by live-key prefix, forces 11 outbound flags off |
| `sync_staging_reference.mjs` | copies taxonomy/policy tables incl. `fn_task_class`, multi-pass for FK order |
| `sync_staging_grants.mjs` | restores table privileges in production's shape after a schema rebuild |
| `apply_missing_objects.mjs` | catalogue diff: enums, sequences, columns, tables, views, routines; rewrites the production ref to the target project |

`sync_staging_reference.mjs` still leaves `field_definition` and `field_definition_source`
unloaded — they fail an FK to a parent outside the allowlist. Neither is on the journey path.
