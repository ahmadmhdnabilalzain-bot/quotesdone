# START HERE — QuotesDone, 5 August 2026, end of session 9

`2d25588` on **`repair/finish-quotesdone`** (branched from `repair/package-conformance-batch-0`).
**Pushed. Not merged. Production unchanged.**

Staging **`pglpqrhvozwepymcuunn`** · production **`htdblwldjkcgjvmqkbeh`** (read-only, never deployed to).

Run these first. All five should be green before you touch anything:

```
node scripts/staging/verify_phase1.mjs        # 12/12  deployed, isolated, in sync
node scripts/staging/smoke_staging.mjs        # 15/15  auth, storage, postgrest, 10 functions
node scripts/staging/verify_cost.mjs          #  7/7   pricing, routing, monitoring — zero spend
node scripts/staging/demo_factory.mjs         # 14/14  factory selftest, ~40 s, cleans up after itself
node scripts/staging/journey_test.mjs         # 37/37  signup -> upload -> quotation comparison
```

`verify_cost.mjs` and the factory selftest are new and fast; run them on every commit. The journey
takes ~7.5 minutes (464 s measured) and produces 34 `agent_runs`. If a step fails, read `agent_runs`
for that function **before** assuming the model is at fault — five of session 8's defects presented
as "the model returned nothing" and none of them were.

`node scripts/staging/verify_cost.mjs --live` adds 4 more checks and spends about 0.0001 AED: it
puts one real inference through the deployed gateway and asserts the meter moved. Run it when you
touch anything in the pricing or budget path, not on every commit.

---

## 0. THE RULE FOR THIS SESSION — demo data, always

> **Anything that needs data to be tested gets demo data built for it. Create it, assert against
> it, delete it. Nothing is "verified" by reading code.**

Production has **0 customers, 0 inquiries, 0 quotes** and 20,464 leads. There is no real data to
test against and there never will be until this ships. So every remaining phase below is written as
*"here is the demo data it needs"*, not *"here is the code to read"*.

Two corollaries, both learned the hard way:

1. **A demo that does not clean up poisons the next run.** Staging is right now carrying the
   wreckage of every previous run — see §2.2.
2. **A demo must vary.** Twelve identically-scored suppliers make every later supplier
   structurally invisible to matching. Sameness is not a shortcut, it is a bug generator.

---

## 1. Settled — do not re-open

**Phase 1 is done and verified.** Staging matches production exactly: 403 tables, 161 views, 739
routines, 5,237 columns. 190/190 Edge Functions deployed, 17 requiring a JWT, zero `verify_jwt`
drift. Migration ledger reconciled at 712 @ `20260804182051`.

**Phase 2 is done.** Signup, OTP, profile, terms, AI intake, drawing upload with BOQ extraction and
verified redaction, CAD upload, reference photos, inquiry creation, dispatch, supplier inbox,
quotation by form **and** by uploaded document, revision, structured review, comparison PDF, and
cross-account isolation — all against deployed staging with real Auth users.

**Staging isolation holds and must keep holding:** 0 cron jobs, 0 routines referencing production,
no live payment or deploy tokens. `verify_phase1.mjs` asserts all three — if it ever fails, stop.

---

## 2. Demo data: what exists, what is rotting, what to build

### 2.1 What exists today

`scripts/staging/journey_test.mjs` is **the only end-to-end demo-data creator in the repo.** Every
helper inside it is a private top-level const, importable by nothing:

| helper | line | makes |
|---|---|---|
| `mkUser()` | :33 | an `auth.users` row + signed-in JWT |
| OTP seed + `kyc` calls | :100-127 | verified email, saved profile, accepted terms |
| `standUpSupplier()` | :501 | approved supplier + capability row + a quote |
| `quotePayload()` | :75 | a complete, non-draft form quote |
| cleanup block | :619-659 | auth users, `Journey Test %` leads, listed storage paths |

Supplier A is built by ~130 inline lines (:307-439) that **duplicate `standUpSupplier`'s body**
almost verbatim — including the 18-column `supplier_capabilities` INSERT written out twice
(:399-416 and :522-536). `standUpSupplier()` returns only `{ok, detail}`: it throws away the
supplier's id, email and JWT, so a caller cannot make a supplier and then *act as* it.

Nothing else creates journey data. `supabase/seeds/` is 2,390 rows of agent knowledge.
`npm test` (`scripts/checks/run.mjs`) runs 16 static source-analysis tests that never open a
database connection.

### 2.2 What staging was carrying — CLEARED in session 9

Purged with `demo_factory.mjs --purge`. Measured before and after:

| leftover | brief said | actually removed |
|---|--:|--:|
| `customers` | 62 | **65 — every single one an orphan** (0 of 65 had a surviving `auth.users` row) |
| `inquiries` | 41 | 42 |
| `inquiry_intake` | 57 | 59 |
| `email_verifications` | 51 | 52 |
| `drawing_redaction_runs` | 29 | 31 |
| `documents` (dangling) | 24 | 26 |
| `doc_versions` | not listed | **601** |
| `notifications` (dangling) | not listed | **481** |
| `company_event` (dangling) | not listed | **177** |
| `signed-terms` objects | 114 | 118 |
| `agent-docs` objects | 19 | 20 |
| `drawing-files` objects | 2 (session-8 probe) | 2 |
| orphaned auth users | 15 | 15 |

Staging now holds **0 customers, 0 inquiries, 0 quotes, 0 leads, 0 documents** and 26 objects, all
of them in `brand` — the fonts `pdf_native` needs, which the purge protects by name.

Two of those rows were on nobody's list and are worth understanding, because they are the same
class of bug as the 23 `quoted` inquiries with zero quotes:

- **66 `company_event` `supplier.applied` rows** pointing at leads that no longer existed.
- **66 queued `supplier_registered` notifications** addressed to `management@quotesdone.com`.
  `notifications` is a **queue, not a log**. `email_enabled` is `false` on staging today, so they
  sat there harmlessly — but §6 plans to turn it on behind a recipient allowlist to prove
  notification, and the moment that happened all 66 would have fired at once.

Two rows survive on purpose: `rfq_not_dispatched` notifications carrying no `lead_id` and no
`inquiry_id`. Nothing ties them to a deleted parent, and a rule broad enough to catch them would
also delete a genuine unreferenced system alert. Left deliberately; decide if you disagree.

### 2.3 The factory — BUILT

`scripts/staging/demo_factory.mjs` exists. `node scripts/staging/demo_factory.mjs` runs its
selftest (14/14, ~40 s, tears itself down).

```js
import { withRun, makeCustomer, makeSupplier, makeInquiry, makeQuote, makeBulkCorpus } from './demo_factory.mjs';
await withRun(async (run) => {
  const cust = await makeCustomer(run);                          // { id, email, jwt, customerId }
  const sup  = await makeSupplier(run, { trade: 'aluminium' });   // { leadId, email, jwt, profile }
  const inq  = await makeInquiry(run, { customer: cust });
  await makeQuote(run, { inquiry: inq, supplier: sup, amount: 125000 });
});                                                              // teardown runs even on a throw
```

- **Tagging.** Emails carry `qd-<tag>-…@example.com`, `leads.tags` carries `qd_run:<tag>`,
  `inquiries.provenance->>'qd_run'` carries the tag. Everything else is reached through those.
- **Storage teardown is DERIVED FROM THE DATABASE** (`inquiries.drawing_file_path`,
  `drawing_redacted_paths`, `quotes.original_file_path`, `customers/leads.signed_terms_path`,
  `documents.bucket|path`, `drawing_redaction_runs.output_paths`) — not from a hand-maintained list.
  The hand-maintained list is exactly why 118 `signed-terms` objects accumulated.
- **`withRun()` tears down in a `finally`.**
- **Two speeds.** `mode:'sql'` (auth-admin identity + direct INSERT, zero model calls) and
  `mode:'api'` (the deployed functions, real models). `makeBulkCorpus` builds 100 suppliers in
  **2 management-API round trips**.
- **`capability: 'agent'`** confirms through `capability_agent` instead of the raw INSERT — see §3.1.
- **`makeLicenceGatedSupplier()`** produces a supplier the licence gate has refused.
- **`--purge`** for drift, `--purge --dry-run` to look first. The dry run is a **lower bound**: the
  orphan sweeps only become true once their parents are gone (it predicted 13 dangling documents
  and 382 notifications; the real run removed 26 and 415).

**The selftest's last check is the one that matters:** it snapshots 20 row counters plus every
storage bucket before the run and asserts they are identical after teardown. That check is how
`company_event`, `doc_versions`, `notifications` and `supplier_capability_confirmation` were found —
none of them were on any list of things a demo run touches.

**Two fixture traps found by building it**, both of which produced a green-looking wrong answer:

1. **Vary the score dial, hold the gates still.** The first cut varied `roles` "for realism", which
   is a *gate* in `fn_match_capability`, not a score term — the zero-overlap decoy landed on
   `supplies_only` and was dropped by the role gate before it could be discarded by the relevance
   floor it existed to test. Vary `products_norm`; leave roles, trades and authorities uniform
   unless a test is specifically about them.
2. **`p_value` is not optional.** `w_size` scores 10 only when `p_value is not null` **and** the
   supplier states a range containing it; otherwise every candidate gets 5 and the whole ladder
   shifts down. Omitting it made variant 0 score 45, not 50.

### 2.4 Traps that specifically break demo data — read before writing a fixture

**The licence gate fires on INSERT.** `trg_leads_a_licence_gate` is `BEFORE INSERT OR UPDATE OF
license_doc_path, trade_license_no, license_expiry` on `public.leads`. A bulk corpus INSERT that
carries a `license_doc_path` with a null `trade_license_no` sets `approval_status='action_required'`
on every row, which fails `fn_is_matchable`, which drops all 100 suppliers out of
`fn_match_capability`'s `cand` CTE — **an invisible corpus.** `journey_test` dodges this only
because it approves via an UPDATE whose column list excludes those three columns, short-circuiting
the trigger (:356-359).

**`p_limit 12` is NOT the constraint people think it is.** In `fn_match_capability`,
`sc.trades && p_trades` is a hard eligibility **gate**, not a score term — trades contribute 0 of
the 100 points. A corpus spread across 25 trades puts ~4 candidates in front of a limit of 12, so
the tie-break never binds. The settings that actually constrain a corpus are
**`match_relevance_floor` 35** (`route_inquiry/index.ts:188`) and **`MAX_FANOUT` 5**
(`dispatch_inquiry/index.ts:170`) — and because the score has a floor of `w_size*0.5` = 5 points,
a supplier with zero `products_norm` overlap scores 5 and is silently discarded by the floor.
The tie-break trap *is* real for `journey_test` itself, whose suppliers all carry the identical
6-trade/9-product fixture and therefore tie exactly.

**Spread score with `products_norm`, not `rating`.** `products_norm` overlap is the primary
continuous dial: `w_prod * product_hits / cardinality(p_products)` — 40 points in `1/|p_products|`
steps. `leads.rating` is the wrong knob twice over: `supplier_perf` computes
`COALESCE(l.app_rating, l.rating)`, so `app_rating` wins wherever it exists; and
`track = least(1, greatest(0, coalesce(sp.quote_rate, sp.perf_score, 0)))`, where
`quote_rate = quoted/NULLIF(matched,0)`. **The moment your corpus is dispatched to, `matched > 0`,
`quote_rate` stops being NULL and overrides `perf_score` entirely** — a matched-but-not-yet-quoted
supplier gets `track = 0.000` and the whole rating spread collapses on the second run. A
rating-spread corpus is not idempotent.

**Uploads leak even from ad-hoc probes.** Two `drawing-files` objects in staging came from a
one-off diagnostic script in session 8, not from the journey. If you write a throwaway probe, give
it teardown too.

---

## 3. Pending work, in dependency order — each with its demo data

### 3.1 Phase 3 — supplier journey

Phase 3 is three different kinds of gap, not one.

**(a) Wired but never executed.** `supplier_api` `process_docs` does **not** call `doc_extract` —
it calls `license_extract` synchronously (`supplier_api/index.ts:288`, **`max:1500`** — treat that
ceiling as suspect, it is the same shape as the two that were silently truncating in session 8).
`doc_extract` is a queue drainer over `public.documents`, pulled by the `doc_process` cron. Staging
has 0 crons, so **`doc_extract` has never run there**: 24 `documents` rows, every one
`status='pending'`, 0 `agent_runs`.

`license_extract` has **three** callers, not two: `supplier_api:288`, `supplier_portal:194`, and
**`resend_inbound/index.ts:77`** (invoked at :270 and :282), whose `license` branch writes
`leads.license_doc_path`, `trade_license_no`, `license_authority`, `license_expiry`,
`license_city`, `emirate` and `trn` directly. Any licence fixture must account for that inbound-email
entry point.

`public.documents` is written only by `fn_register_document`, fired by **three** triggers:
`reg_lead_docs` on `leads`, `reg_inquiry_doc` on `inquiries`, `reg_quote_doc` on `quotes`. All 24
staging rows (12 `drawing`, 12 `quote`) came from the latter two — created for free by journey runs.

> **Demo data:** a `doc_extract` drain test needs **no new upload** — POST `doc_extract` with one of
> the 24 existing `document_id`s and assert `status='done'` plus real extracted content, capturing
> the output-token count. Separately, build a synthetic **UAE trade licence** fixture (legal name,
> licence number, authority, emirate, expiry) plus an **expired** variant and an **illegible**
> variant, to cover the `supplier-docs` branch and the licence gate. `supplier-docs` has 0 objects.

**(b) Switched off by the routing policy.** `fn_ai_route` returns `use_llm:false, tier:'none'` for
**both `capability_agent` and `supplier_review`** in staging *and* production — both map to
task_class `supplier_matching` (tier none, model none, max_tokens 0). This is the exact
`inquiry_intake → missing_fields_detection` trap. The capability flow is dead at the model layer,
not merely missing a UI.

**The confirm half is now WIRED AND PROVEN (session 9).** `capability_agent` action `confirm` makes
**no model call at all** — the only model call is on the `analyze` path. `seed_staging_secrets.mjs`
now adds `capability_agent` to the `db.internal` credential scope (the credential that already
carries its siblings `enrich_capability` and `dispatch_inquiry`), and
`makeSupplier(run, { capability: 'agent' })` drives it. Measured: `review_status='confirmed'`,
`confirmed_version=1`, one `supplier_capability_confirmation` ledger row, and a 400
`need_at_least_one_trade_and_role` for a trade code outside the controlled vocabulary — which is the
reason to prefer the endpoint over the raw INSERT, since an INSERT will happily store a trade code
`fn_match_capability` can never match.

**This had never run in either project.** Still outstanding:

- `analyze` remains dead — it needs the `supplier_matching` task-class remap.
- `journey_test.mjs` still writes the duplicated 18-column raw INSERT twice (:399-416 and :522-536).
  Replacing both with `capability_agent` confirm is now a small, safe change.
- **`confirm` does not write `min_project_value` / `max_project_value`**, so a supplier confirmed
  this way scores `w_size*0.5` instead of `w_size` in `fn_match_capability`. Either the endpoint
  should accept them or the scorer should stop rewarding their mere presence.
- **Production still has no credential scoping `capability_agent`** — see §8.

**(c) Configuration missing from staging.** `pricing_config` is not in
`sync_staging_reference.mjs`'s TABLES array (18 entries, :27-52), so `auto_approve_suppliers` is
null and `supplier_api:470` always sets `pending`, never `action_required`.

That blocks the exception window *through supplier_api* — but not the fixture.
`fn_leads_licence_gate_rerun` evaluates the gate on INSERT, so **one INSERT** carrying a
`license_doc_path` with a null `trade_license_no` opens a real licence gate with `pricing_config`
still empty.

> **Demo data:** a supplier refused by the licence gate, carried through the 14-day exception window
> — opened, reminded at day 3/7/12 (back-date `exception_opened_at`), auto-rejected at expiry, then
> recovered by uploading a valid licence. `fn_supplier_exception_open/_close/_sweep` and
> `fn_supplier_exception_days` all exist in staging. Also: a founding-cohort supplier
> (`founding_rank` assigned, exempt) **and** a non-exempt one past the charging date — note
> `fn_assign_founding_rank` only fires when `verified` flips true, which `save_profile` never does
> on staging.

**Quotation history** has no table and no writer. Decide whether it is wanted; if not, close the
item as *"by design: quotes are mutable, one row per supplier per inquiry"*.

### 3.2 Phase 4 — taxonomy

The "0 callers" finding is confirmed **and worse than stated**: staging does not hold the router's
own inputs. `kb_operational_alias` is **0 rows** (production 4,212) and `kb_operational_route_map`
is **0** (production 426), so `fn_kb_route_decide` returns `top_score: 0` for every string in
staging. There are **five** hardcoded lists, not four, and **zero of their 19 short slugs exist in
`catalog_supplier_categories.slug`** — so any wiring PR must also crosswalk the trade vocabulary
`fn_match_capability(p_trades text[])` matches against, or dispatch silently returns nothing.

**Do not scope the sync as "one line added to TABLES".** `copyTable()` paginates with
`select * from public.${t} order by 1 limit 500 offset N`. `kb_operational_alias` is 4,212 rows and
its column 1 (`catalog_num`) is massively non-unique (PK is `(catalog_num, language, alias)`).
LIMIT/OFFSET over a non-unique ORDER BY has no stable row order in Postgres, so batches will both
duplicate and drop rows; a duplicate violates the PK and the INSERT throws. Worse, the guard at :84
(`if (stageRows) … skipped`) then makes a half-loaded table **skip forever**. Fix the ORDER BY to
the full primary key and make the guard resume, before adding anything large.

`kb_stage.*` is a **bulk-load problem, not a schema-prefix problem**: `kb_stage.questions` alone is
16,588 rows / 29 MB of `to_jsonb` text. Either restrict the copy to the columns `fn_kb_next_question`
actually reads, or move `kb_stage` off the management-API transport entirely.
(Production `kb_stage`: `decision_rules` 16,254, `categories` 67, `questions` 16,588.)

> **Demo data:** a synthetic customer inquiry whose free text is written to hit a **known** catalogue
> route, asserted end to end: text → `fn_kb_route_decide` → `catalog_num` → `inquiries.category` →
> `dispatch_inquiry` → a supplier inbox. Plus the **paired negative**: text that routes to a
> catalogue entry for which no capable supplier exists, asserting dispatch's reason string rather
> than a row count. Both need the capability seed parameterised by trade (§2.3).

### 3.3 Phase 5 — portals and API actions

**The "29 package API actions" list does not exist anywhere in the repo or its git history.** The
number survives only as an unsourced count carried between brief revisions. **Find the spec or
retire the number** before planning against it.

> **Demo data — this is the section that most needs it:**
> - A demo customer with **3-4 inquiries spanning statuses** (`sent` / `quoted` / `completed` /
>   `cancelled`), each with **2-3 quotes at different prices**, at least one revealed via a
>   `transactions` row. Today the journey produces exactly one inquiry with two quotes and then
>   deletes the quotes, which is why staging has 23 `quoted` inquiries with zero quotes.
> - A customer whose `auth.users` row exists but whose `customers` row does not — `mkUser()`
>   already produces this state and nothing asserts what the UI does with it.
> - **An Arabic demo customer**: `customers.locale='ar'`, Arabic inquiry summary and `raw_input`,
>   a supplier quote with an Arabic note, and one alert from the `ar` branch. Note `customers.locale`
>   exists and is **unused** — the portal reads `localStorage['qd-lang']` and the `NEXT_LOCALE`
>   cookie (`CustomerPortal.tsx:16`), so the wiring must be made to read it or the Arabic journey
>   tests a code path nobody uses.
>
> `CustomerPortal.tsx:237` still carries the pre-existing `side-tab` design finding.

### 3.4 Phase 6 — AI gateway and cost

**Correction: the session-7/8 briefs had this wrong, including my own.** `fn_llm_log` does **not**
write `llm_calls` — it writes **`ai_cost_log`, which has 643 rows in staging and is working**. The
RPC signature at `ai_gateway/index.ts:435` matches the database definition argument-for-argument
(13 params, no defaults), so `rpcSafe` is swallowing nothing. `llm_calls` is a **dead legacy table**
with exactly one writer left in the repo (`site_assistant/index.ts:25`), which the journey never
exercises. "llm_calls is 0" was true and meaningless.

**The real Phase 6 defect** is that `ai_cost_log.cost_aed` is **0.00 on all 643 staging rows** and
on **238 of 589 production rows**, because `fn_llm_log` prices from **`model_rate`** while
`fn_ai_route` / `fn_model_cost_usd` price from **`model_registry`** — two pricing tables that
disagree about which models exist. `model_rate` has **0 rows in staging** (never copied by the
reference sync) and in production contains no `google/*` entries at all.

Production `ai_cost_log` by model: `anthropic/claude-sonnet-5` 236 rows / 218 priced;
`google/gemini-3.1-flash-lite` 207 / **0**; `~anthropic/claude-haiku-latest` 77 / 76;
`anthropic/claude-opus-4.8` 57 / 57; `google/gemini-3.5-flash` 9 / **0**; `model_used='none'` 3 / 0.
Total priced 351, sum 37.42 AED.

Three monitoring views are blind because they read the dead table: `v_llm_model_mix` and
`v_llm_calls_without_task_class` name `llm_calls` directly; `v_llm_offpolicy` reads
`v_llm_model_mix LEFT JOIN llm_policy` and is blind transitively. Repoint the first two.

**Only 1 of ~70 gateway call sites passes `task_class`** — `agent_brain/index.ts:33`. (An earlier
count of 2 was wrong: `kb_research_test:43` *reads* `task_class` back off the response into its own
JSON output; its request at :32 sends none.)

**DONE in session 9.** `verify_cost.mjs` measured it (2/7 red), `seed_cost_config.mjs` fixed it, and
the live probe proved it. All applied **directly, not as migrations** — a migration breaks the
712-vs-712 ledger parity `verify_phase1.mjs` asserts.

- `model_rate` seeded with 6 rows **derived from `model_registry`** at 3.6725 AED/USD. Deriving one
  table from the other is the actual fix: the two disagreeing is the root defect, and a hand-written
  `model_rate` is what let production lose every `google/*` row in the first place.
- `department_budget` seeded with production's 13 `dept_key`s and thresholds, `spent_aed` at 0.
- `fn_task_class` row added for **`drawing_redact_verify`**, which was the only 1 of 34 gateway call
  sites falling through to `UNMAPPED -> general_drafting` (medium, **900** `max_tokens`) while its
  siblings `drawing_redact` and `drawing_boq` both get `document_extraction` at 8000. It is the
  function that verifies a drawing redaction actually landed — the check the journey asserts privacy
  on. **Production is missing this row too.**
- `v_llm_model_mix`, `v_llm_calls_without_task_class` and `v_llm_offpolicy` repointed off the dead
  `llm_calls` onto `ai_cost_log`, grants restored.
- 601 `ai_cost_log` rows removed: every one recorded 0.00 because `model_rate` was empty, so they
  measure a broken meter rather than a cost. The 80 that remain are cache hits and `model_used='none'`.

**Measured end to end with `--live`:** one real `google/gemini-3.1-flash-lite` call billed
**0.000045 AED**, `department_budget.spent_aed` moved by **exactly** that, and the next call to an
over-budget department returned `outcome:'budget_halted'` with `used_llm:false` — without reaching a
provider.

Three notes for whoever picks this up:

1. **The brief's own halt fixture was wrong.** `monthly_aed=0.01` with `halt_at_pct=95` never fires:
   `fn_ai_route` computes `100 * month_spend / monthly_aed`, and a flash-lite call costs ~0.000045
   AED, which is 0.45% of that ceiling. The ceiling must be set relative to what was actually spent.
   `verify_cost.mjs` sets it to the logged cost, putting the department at exactly 100%.
2. **Column count is part of schema parity.** The first cut of the repointed views added three
   columns and turned `verify_phase1`'s 5,237-column check red. `v_llm_model_mix` now swaps the
   dead `cached_tokens` for `cost_aed` rather than adding it.
3. **`v_llm_offpolicy` was repointed further than the brief said.** Fixing only its parent would
   have left it joining `llm_policy`, which has 3 rows in production and **0 in staging** and is not
   what `fn_ai_route` consults — turning a silent all-clear into a loud false alarm. It now asks:
   was a model used that no active `model_policy` can select?

Still open: **`resend_inbound/index.ts:262` calls OpenRouter directly**, outside the gateway, so it
is outside routing, logging and the budget halt. Adding `model_rate` and `department_budget` to
`sync_staging_reference.mjs`'s allowlist is still not done — `seed_cost_config.mjs` covers a rebuild
instead, and derives rather than copies, which is better.

### 3.5 Phase 7 — workflow and autonomy

The executor registry is **`public.org_action_executor`** (PK `action_class`), with allow-list
`public.org_action_executor_rpc_allowed`. Staging has **0 rows in both** against production's **55**
and **16** — and the whole org layer around them is empty in staging because the reference sync
copies only `decision_policy` from this family: `workflow` 0/14, `workflow_step` 0/117,
`employee_workflow` 0/157, `operating_system` 0/10, `org_departments` 0/15, `org_agents` 0/67,
`org_authority` 0/196, `org_tasks` 0/231.

The "no writers" claim is **confirmed two ways**: zero routines in either project contain a write
against `workflow_run`, `workflow_step_run`, `action_execution` or `decision_trace` (pg_proc regex),
zero triggers exist on them, and the only repo references are two *reads* of `org_action_executor`
(`cos_execute:133`, `dept_plan:76`). **`cos_execute` is not the missing writer** — it runs executors
but records to `org_tasks` / `org_memory` / `agent_runs` / `agent_actions`. `orchestrate` is a 410 stub.

> **Demo data — and note the blocker is code, not data:**
> - Copy the config: add `org_action_executor_rpc_allowed`, `org_action_executor`,
>   `operating_system`, `workflow`, `workflow_step`, `org_departments`, `org_agents`,
>   `org_authority` to the reference-sync TABLES (definitions, not business records — the script's
>   own no-real-data rule is not breached). All 39 distinct edge targets are already inside
>   staging's `fn.cos_execute` credential scope.
> - Bring staging's `org_action_executor` constraint shape up to production's (NOT NULL on
>   `risk_tier`/`reversible`/`timeout_seconds`/`max_attempts`, plus the two CHECK constraints).
>   Apply directly — a migration breaks the 712-vs-712 ledger parity.
> - Then a new `scripts/staging/autonomy_test.mjs` in `journey_test`'s create-then-delete shape:
>   one `workflow_run` + its `workflow_step_run` rows + one `action_execution` + the matching
>   `decision_trace`, **all sharing one `correlation_id`** (`workflow_run` needs
>   `workflow_key`/`correlation_id`/`idempotency_key`, all NOT NULL with no default;
>   `action_execution` needs `correlation_id`/`action_class`/`executor`/`idempotency_key`/
>   `risk_tier`/`request`), plus a synthetic `company_event` and `decision_log` row.
>
> **This cannot be a data-only fixture.** Writing those four tables by hand proves the schema, not
> the system. The orchestrator that leases a run, walks `workflow_step` into `workflow_step_run`,
> dispatches through `org_action_executor` into `action_execution` and writes `decision_trace`
> **does not exist**. Decide explicitly whether Phase 7 means building it or seeding it.

`v_executor_registry_gaps` returning 0 in staging still means nothing until the 55 rows are loaded.
`cos_execute` correctly stays off.

### 3.6 Phase 8 — acceptance

**The "100 customers / 100 suppliers / 5 admins + Playwright + drive the deployed Vercel URL"
standard is written down in exactly one place — a previous revision of this brief — and nowhere
upstream.** The older audit docs name the pack's acceptance gates (unit, contract, integration,
idempotency, provider-outage, privacy, Arabic/RTL, staging E2E) but never the 100/100/5 numbers.
Treat the corpus size as a working figure, not a spec.

**Replaying `journey_test` 100 times is not viable:** 464 s and 34 agent runs per run → ~12.9 hours
and ~3,400 agent runs.

> **Demo data — the corpus design:**
> - **205 identities via SQL + auth-admin, zero model calls.** Reserve the API path (2 billable
>   calls per supplier) for the 2-3 "deep" cases actually being asserted end to end.
> - **100 suppliers spread 4-per-trade across the 25 taxonomy trades**, with `products_norm`
>   overlap — not rating — as the score dial (§2.4). Vary brands, `project_types`,
>   `min/max_project_value`, `coverage_emirates`.
> - **Leave `license_doc_path` NULL on bulk INSERT** or all 100 land on `action_required` and the
>   corpus is invisible (§2.4).
> - **100 customers** with `customers` row, `email_verified`, accepted terms and a pre-canned
>   inquiry each; only 2-3 run the real AI intake.
> - Torn down **as a set**, by run tag.
>
> Then assert the things a corpus is actually for: `match_relevance_floor` 35 and `MAX_FANOUT` 5
> behaviour, a supplier with zero `products_norm` overlap scoring 5 and being correctly discarded,
> and dispatch fanning out to a *different* five for a *different* trade.

Nothing has yet run against the deployed Vercel preview URL. The frontend was verified by reading
its built bundle, not by driving it. There is no browser test harness in the repo.

---

## 4. Corrections to earlier briefs — do not re-inherit these

| earlier claim | truth |
|---|---|
| "`llm_calls` is 0, so cost is not recorded — `fn_llm_log` is swallowed by `rpcSafe`" | `fn_llm_log` writes **`ai_cost_log`** (643 staging rows, working). `llm_calls` is dead legacy with one writer. The real defect is `cost_aed=0` from the `model_rate` vs `model_registry` split |
| "`quote_reviews` row is created by an uploaded quote" | `quote_reviews` has **no writer anywhere** and 0 rows in production. The subsystem does not exist |
| "29 package API actions" | **No such list exists** in the repo or its git history |
| "`p_limit 12` makes a 100-supplier corpus mostly invisible" | Trades are a hard **gate**, not a score term. A trade-spread corpus never binds the tie-break. The real limits are `match_relevance_floor` 35 and `MAX_FANOUT` 5 |
| "spread corpus score with `leads.rating`" | `supplier_perf` prefers `app_rating`; and `quote_rate` overrides `perf_score` once `matched>0`, collapsing the spread on run 2. Use `products_norm` overlap |
| "standing up a supplier costs 3 model calls" | **2.** `supplier_review` resolves to `use_llm:false` — a free no-op |
| "`doc_extract` is fed only by `trg_reg_lead_docs`" | `fn_register_document` has **three** trigger callers (`reg_lead_docs`, `reg_inquiry_doc`, `reg_quote_doc`). All 24 staging rows came from the latter two |
| "`license_extract` has two callers" | **Three** — `resend_inbound/index.ts:77` is an inbound-email entry point that writes the same licence columns |
| "2 of ~70 call sites pass `task_class`" | **1** (`agent_brain:33`). `kb_research_test:43` reads it back into its response |
| "add `kb_operational_alias` to TABLES — one line" | Its 4,212 rows break `copyTable`'s non-unique `order by 1` pagination, and the skip-guard makes a half-load permanent |
| `capability_requirement` | No such object. The table is **`inquiry_requirement`** (33 staging rows) |
| "216 of 589 production calls billed at zero" | **238** of 589, across **6** model groups including `model_used='none'` |

### Corrections found in session 9 — including to this brief

| earlier claim | truth |
|---|---|
| "62 synthetic `customers` rows" | **65, and every one of them an orphan.** 0 of 65 had a surviving `auth.users` row, so none could ever log in. The count was the smaller finding |
| §2.2's litter list | Missed **601 `doc_versions`**, **481 `notifications`** and **177 `company_event`** rows — more rows than everything it did list, combined |
| "the cleanup leaves `signed-terms` and `agent-docs` behind" | True, and the cause generalises: any hand-maintained path list rots. Teardown now derives paths from the database |
| "a low-ceiling department `monthly_aed=0.01, halt_at_pct=95` trips the halt" | It does not. That is 0.45% of the ceiling for a real flash-lite call. `fn_ai_route` halts on `100*spend/monthly_aed >= halt_at_pct` |
| "`p_limit 12` / trades are the corpus constraint" (already corrected) | Confirmed again, and the **real** fixture trap is different: `roles` is a hard gate, so varying it "for realism" silently removes candidates from scoring |
| "2 of ~70 gateway call sites pass `task_class`" | The count that matters is different: **34** distinct `fn` literals reach the gateway, and **1** (`drawing_redact_verify`) had no `fn_task_class` row at all — in staging **or production** |
| "`fn_task_class` mapping" | `fn_task_class` is a **table**, not a function. `fn_ai_route` reads it and falls back to `general_drafting` with `UNMAPPED` in the `why` string |
| `capability_requirement` → `inquiry_requirement` (already corrected) | Still right. Also: `supplier_capability_confirmation` is a real table and `capability_agent confirm` is its only writer |
| "`seed_staging_secrets.mjs` can be re-run" | It could not. The `internal_credential` INSERT had no `ON CONFLICT` and the table has no unique key on `context`, so a second run would **double all 74 credentials** and leave `fn_internal_auth` choosing between duplicates. Fixed: it now skips the bulk copy when the table is non-empty |

---

## 5. Traps that cost real time (sessions 7-8)

**A green suite over a subsystem that never ran.** The journey passed 19/19 while every LLM call
failed and `inquiry_intake` silently used its keyword fallback. `quote_extract` returned `ok:true`
with a fully-formed but **entirely empty** proposal, because a failed parse left `{}` and every
field was then scrubbed to `''`. A step that returns HTTP 200 is not a step that worked.

**A token ceiling inside the output's natural range truncates INTERMITTENTLY.** Four times now:
`quote_comparison` at haiku/1500, `rfq_routing` at 300, `quote_comparison` again at sonnet/3000
(natural range 2618–7266), `quote_extract` at 2000 (needs ~2400). A cap mid-distribution fails
roughly one run in three, which reads exactly like model flakiness. **Measure the natural output
with the ceiling lifted, then set the budget above the maximum.** `license_extract` at `max:1500` is
the next suspect.

**gemini spends most of its output budget on reasoning tokens** — a `quote_extract` call reported
1,996 output tokens carrying **206 characters** of visible JSON. Sizing from expected JSON length is
wrong by an order of magnitude on that model.

**`ai_gateway` now returns `finish_reason` and `truncated`** and logs `TRUNCATED:` with the ceiling
and task class. **Use it.** All four truncations above presented as "unparseable output".

**A caller-declared timeout the per-attempt cap ignored.** `client_timeout_ms` set the wall while
each attempt was still aborted at a hardcoded 45s, so declaring 100s only bought more doomed
retries. Fixed; it derives from the wall now.

**Silent failure at two layers looks identical to silent failure at one.** A CAD upload was refused
by `customer_api`'s allow-list AND by the bucket's `allowed_mime_types`, both returning null. Fixing
the first changed nothing visible. If a fix "does not take", look for a second gate downstream.

**Phase 1 counted buckets, not objects.** "15/15 storage buckets" was true and useless: `brand` held
0 objects, so `pdf_native` never got its fonts and fell back to WinAnsi Helvetica — which throws on
any character above U+00FF. One `≠` from a model 502'd the customer's comparison.

**A whole task class can be switched off in production.** `inquiry_intake` →
`missing_fields_detection`, and `capability_agent` + `supplier_review` → `supplier_matching`, all
`tier=none, model=none, max_tokens=0`. Check `fn_ai_route` before assuming a function is merely
unwired.

**GateGuard fires on the first edit of every file.** `.claude/settings.local.json` sets
`ECC_DISABLED_HOOKS` for the two fact-force hooks. That file is gitignored, so a fresh clone gets
the prompts back.

---

## 6. Blocked on the founder — exactly one thing

**Stripe test-mode keys.** Production's are LIVE (`sk_live` / `pk_live`), withheld by a prefix rule.
Test keys can only come from the Stripe dashboard. This is also the one action the founder's own
spec says needs approval.

Everything else is unblocked: Resend, OpenRouter, VirusTotal, CloudConvert and Apify keys are live
in staging. `email_enabled` is `false` deliberately — turn it on behind a recipient allowlist when
proving notification. Twilio and Dropbox stay withheld on purpose.

---

## 7. Findings about PRODUCTION worth acting on

Measured read-only and **not** fixed. Production has 0 inquiries, 0 quotes, 0 customers and 20,464
leads, so every one is **prospective damage, not damage already done** — which is exactly why now.

- **No supplier could ever quote by uploading a document.** `require_structured_quotes` is `'true'`,
  `formComplete` required `source==='form'`, and the structured scorer returns false for every real
  quote. Every uploaded quotation would have become a silent draft. *(Fixed in staging.)*
- **`ai_cost_log.cost_aed` is 0 on 238 of 589 calls**, including 100% of both `google/*` models,
  because `model_rate` has no `google/*` rows. Cost reporting understates real spend today.
- **CAD originals would be discarded** — `drawing-files` `allowed_mime_types` is still
  `pdf, jpeg, jpg, png, webp`, and `customer_api` still passes `SAFE_UPLOAD`.
- **`quote_extract` at 2000 output tokens** would return empty proposals, hidden by `ok:true`.
- **`inquiry_intake`, `capability_agent` and `supplier_review` all map to switched-off task classes.**
- **`quote_comparison` capped at 3000** and **`document_extraction` at 4000** while `drawing_boq`
  asks for 8000.
- **`stripe_secret_key` and `stripe_publishable_key` are LIVE keys.**
- **`supplier_capabilities` has 0 rows**, so capability-gated dispatch has never run.
- `github_token` and `vercel_token` live in the `app_secrets` **table** — a database row can deploy
  the site via `run_auto_deploy()` / `run_site_autodeploy()`.
- 149 cron jobs armed, including `vt_scan_daily` (03:00, `fn_run_vt()`). Uploads are **not**
  AV-scanned inline; `sanitizeUpload`'s structural sniffing is the inline gate and VirusTotal is a
  nightly sweep. A design, not a gap — but know it before claiming uploads are scanned.
- **`quote_reviews` has no writer anywhere** and 0 rows.
- **`drawing_redact_verify` has no `fn_task_class` row**, so `fn_ai_route` reports
  `UNMAPPED function` and routes it to `general_drafting` — medium tier at **900 `max_tokens`**,
  against `document_extraction`'s 8000 for its two siblings. This is the function that verifies a
  drawing redaction actually removed the customer's identity before competing suppliers see it, and
  §5 records four separate defects caused by a ceiling sitting inside the output's natural range.
  *(Fixed in staging.)*
- **No `internal_credential` in production scopes `capability_agent`**, so its `confirm` action —
  the only writer of a confirmed `supplier_capabilities` row and its
  `supplier_capability_confirmation` ledger entry, and one that makes no model call — is
  unreachable. Combined with `supplier_capabilities` having 0 rows, capability-gated dispatch
  cannot ever have run. *(Fixed in staging.)*
- **`department_budget.spent_aed` never moves in production for the unpriced models.** `fn_llm_log`
  updates the budget only `if p_dept is not null and v_cost > 0`, and `v_cost` is 0 whenever
  `model_rate` has no row — so the budget halt cannot fire for `google/*` traffic no matter how much
  of it there is.

---

## 8. Production deployment sequence — NOT READY

Do not prepare one yet; the acceptance suite (Phase 8) does not exist. When it does, the sequence
must cover **both code and configuration**, because several session-8 fixes live in the database:

*Code:* the 4 Edge Functions whose production URL was replaced with `SUPABASE_URL`,
`inquiry_intake`, `ai_gateway` (finish_reason + per-attempt deadline), `quote_compare`,
`quote_extract`, `supplier_api` (`formComplete`), `customer_api` (`SAFE_CAD` + storage logging),
`pdf_native` (encoding), `attach_photos`.

*Configuration, applied directly and NOT as a migration* (a migration breaks the 712-vs-712 ledger
parity `verify_phase1.mjs` asserts):
- `model_policy.quote_comparison.max_tokens` 3000 → **10000**
- `model_policy.document_extraction.max_tokens` 4000 → **8000**
- `model_policy.rfq_routing.max_tokens` → **2500**
- `fn_task_class` mapping for `quote_compare` (absent in production)
- `inquiry_intake` task-class remap off `missing_fields_detection`
- `storage.buckets.allowed_mime_types` for `drawing-files` += `image/vnd.dwg`, `image/vnd.dxf`
- **`model_rate` rows for the `google/*` models** (new — see §3.4)

*Added in session 9 — all reproducible by re-running the scripts named:*
- **`model_rate` rows for every active `model_registry` model**, derived at 3.6725 AED/USD
  (`seed_cost_config.mjs`). Production currently prices 0 of its 2 Gemini models, which is why 238
  of 589 calls bill at zero
- **`fn_task_class` row for `drawing_redact_verify` → `document_extraction`** (`seed_cost_config.mjs`).
  Missing in production; it is currently routed to `general_drafting` at 900 `max_tokens`
- **`v_llm_model_mix` / `v_llm_calls_without_task_class` / `v_llm_offpolicy` repointed** off
  `llm_calls` onto `ai_cost_log` (`seed_cost_config.mjs`). Note these are DROP + CREATE, and the
  grants must be reapplied — `postgres` and `service_role` hold the full set on all three
- **`internal_credential` `db.internal` scope += `capability_agent`** (`seed_staging_secrets.mjs`).
  Without it the only non-blocked half of the capability flow is unreachable

*Code added in session 9 (no production effect until deployed):* `scripts/staging/demo_factory.mjs`,
`scripts/staging/verify_cost.mjs`, `scripts/staging/seed_cost_config.mjs`, and the idempotency fix
in `scripts/staging/seed_staging_secrets.mjs`.

---

## 9. Tooling (all in `scripts/staging/`)

| file | what it does |
|---|---|
| `verify_phase1.mjs` | 12 measurements: repo clean+pushed, functions deployed, jwt parity, schema parity, isolation, ledger |
| `smoke_staging.mjs` | real Auth user, storage, PostgREST, 10 functions |
| `journey_test.mjs` | the 37-step journey; cleanup is **incomplete** — see §2.2 |
| `sync_staging_assets.mjs` | copies the `brand` bucket; refuses every bucket holding real data |
| `seed_staging_secrets.mjs` | copies `app_secrets` + `internal_credential`, withholds by name and by live-key prefix |
| `sync_staging_reference.mjs` | 18-table allowlist copy; **pagination is unsafe above 500 rows** — see §3.2 |
| `sync_staging_grants.mjs` | restores table privileges in production's shape after a schema rebuild |
| `apply_missing_objects.mjs` | catalogue diff: enums, sequences, columns, tables, views, routines. Does **not** diff constraints — which is why staging's `org_action_executor` lost production's NOT NULLs and CHECKs |
| `fixtures/` | the two synthetic upload documents + `README.md` |
| **`demo_factory.mjs`** | the demo-data factory (§2.3). `--selftest` (default) 14/14, `--purge`, `--purge --dry-run`, `--corpus N [--customers N] [--keep]` |
| **`verify_cost.mjs`** | 7 zero-spend checks over pricing, routing and monitoring; `--live` adds 4 that put one real inference through the gateway |
| **`seed_cost_config.mjs`** | `model_rate` (derived from `model_registry`), `department_budget`, the missing `fn_task_class` row, and the three repointed views. Idempotent; `--reset-telemetry` also clears `ai_cost_log` rows written while the meter was broken |

`sync_staging_reference.mjs` still leaves `field_definition` and `field_definition_source` unloaded
(FK to a parent outside the allowlist). Neither is on the journey path.
