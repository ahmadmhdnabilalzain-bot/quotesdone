# START HERE — QuotesDone, 4 August 2026, end of session 6

`d4cab4b` on **`repair/package-conformance-batch-0`** (parent `9d002d3` = `main` = `origin/main`).
**Pushed and in sync with `origin`** — the branch was already on GitHub at `37dac27`; only this
brief was missing. Still **not merged. Production unchanged.**
Migrations **712**. `npm test` exits **0**, 0 failures, now 16 node check files (the new
`scripts/staging/sql_split.test.mjs` is picked up automatically).

Run first (these live in `C:\Users\Opera\qd-check`, a separate repo — `/add-dir` it):
```
node C:\Users\Opera\qd-check\final_sync_check.mjs           # was UNCONFIRMED, now VERIFIED GREEN
node C:\Users\Opera\qd-check\check_branch_isolation.mjs     # PASSES with the branch present
node C:\Users\Opera\qd-check\export_applied_migrations.mjs  # "nothing to write"
```

---

## 0. Settled — do not re-open

**The package-conformance register is gone.** `PACKAGE_CONFORMANCE_MATRIX.csv` and
`PACKAGE_CONFORMANCE_SUMMARY.md` are unrecoverable — searched and negative in the full user
profile, `docs/audit/`, the claude.ai project's file uploads, Dropbox and Gmail; the founder could
not find them either. **Do not spend time looking.**

**Decision taken 4 Aug: do not rebuild now.** The dependency-ordered conformance list survives (see
§5) and covers the next several batches. The matrix is a completeness ledger — *"how far are we?"* —
not the work queue. Rebuild nearer launch, from the six packages (present and hash-verified), in a
session that is **not** implementing the fixes. Any rebuild takes a new name: the published hashes
refer to files that no longer exist.

**Standing process change:** an audit deliverable is committed to `docs/audit/` in the session that
produces it, on its own branch, always. "Audit-only, do not commit" means do not commit changes to
the system. It never means do not record what you found.

---

## 1. What session 6 produced

| step | outcome |
|---|---|
| 1 preserve the audit | **NOT POSSIBLE** — see §0 |
| 2 staging readiness | **DONE, premise corrected** — see §3 |
| 3 A-01 remediation | **PROVEN in staging** — see §4 |
| 4 importer idempotency | **DONE, stronger than specified** — see §4 |
| 5 package counts | **PARTIAL** — corpus verified from source; company-operations pack not extracted |

Staging: `staging-batch0` → **`pglpqrhvozwepymcuunn`**, ~$0.32/day. `kb_stage` fully built,
`decision_rules` column-identical to production, 12,929 rows after the proven cleanup, **0 cron
jobs**. `public` is partial — the rebuild was aborted mid-run, see §3.

**Production still holds 16,254 decision rules.** The remediation is proven, not applied.

Full evidence, committed: `docs/audit/PACKAGE_CONFORMANCE_BATCH_0_EVIDENCE.md`.

---

## 2. Batch 1 — the work, in dependency order

1. **Finish the staging rebuild** using the corrected route in §3, with the 429 backoff now in
   `scripts/staging/qd_guard.mjs`, and record the **real** residual failure count. The number
   session 6 produced (`pass 1: applied 481, failed 1,721`) is contaminated by throttling and must
   not be quoted.
   Then **re-run `check_branch_isolation.mjs` at the END of the rebuild** — a complete replay
   creates the 20 ref-embedding functions the branch currently lacks.
2. **Write a migration for `holdout_v2`** from production's catalog. 8 tables + 2 views are
   reconstructable by nothing: no migration, not in the baseline, not in the superseded folder.
   Check the untracked `holdout_v2_eval/` directory first — it may hold the DDL.
3. **Fix `regen_schema.mjs` to export every schema, not just `public`**, and correct
   `supabase/schema/full_schema.sql`'s header, which cites `final_sync_check.mjs` as proof of a
   guarantee that check explicitly disclaims.
4. **Extract `QuotesDone_COMPANY_OPERATIONS_KNOWLEDGE_v2026.07.31.zip`** (it is in `Downloads`) and
   close the eight company-operations metrics, the 62 record types, 86 route manifests, aliases and
   426 crosswalk rows.
5. **Decide the production route to 12,929** — delete-3,325 (smaller, still not idempotent) vs
   re-key-to-canonical (larger, immune afterwards). Both land on 12,929. Founder decision.
6. **Deploy `kb_corpus_import` to staging + mint a `kb_import_token` there**, then run
   `py -3 test_idempotency.py --project-ref pglpqrhvozwepymcuunn` — the end-to-end double import is
   written but has never executed against a live database.
7. Only then: **wire the 86-route taxonomy** (still the highest value per hour in the system).

### Correct one watch query before using it

The session-5 brief watches a catalog query annotated *"must become non-zero when the router is
wired."* **It already returns 10** — `pg_get_functiondef` includes a function's own name, the
router internals call each other, and five `fn_p2c1_*` test harnesses call it. It will read 10
whether the router is wired or not. The claim it was meant to test is about the application, so
measure the application:

```
rg -n 'fn_kb_route|fn_kb_retrieve|fn_kb_next_question|fn_trade_identify|fn_inquiry_interpret|fn_inquiry_workstream_activate' supabase/functions src
```

**Measured session 6: 0 matches.** The audit's finding stands; only the instrument was wrong.

---

## 3. Staging: the branch is trivial, the database is not

`create_branch` returned in seconds. The branch then reported **`MIGRATIONS_FAILED`**:

```
applied_on_branch  31          (of production's 712)
max_version        20260611104735
public_tables      17
kb_stage           absent
```

The replay halted at a **June** migration — earlier than any file in `supabase/migrations/`, whose
earliest is `20260724`. The repo is baseline-plus-increments; the 647 pre-baseline migrations have
no file. `final_sync_check.mjs` states this in its own output and is not at fault.

### Four defects

**1. `full_schema.sql` exports only `public`.** 1,687,662 bytes, captured `2026-08-04T12:50:17Z`.
388 `CREATE TABLE` statements, **every one `public.`**, and **zero `CREATE SCHEMA` statements**.
Production has four more application schemas:

| schema | tables | views | creating migration in the repo? |
|---|--:|--:|---|
| `ops_kb_stage` | 22 | 0 | yes — `20260802131757` |
| `kb_stage` | 13 | 0 | yes — `20260802122010` (+ later fixes) |
| `holdout_v2` | 8 | 2 | **NONE** |
| `containment` | 4 | 0 | yes — `20260802234149` |

**2. The baseline is 15 tables behind.** 388 vs production's 403. Eleven migrations postdate the
12:50 capture.

**3. `full_schema.sql` is unsafe to apply to a branch, and the old documented route says to.**
It carries a `CRON JOBS` section: 29,139 bytes, **149 `cron.schedule` calls, 45 literal occurrences
of the production ref**. The route in the old `migration-set-cannot-rebuild` note began "apply
`full_schema.sql` to branch". Doing that verbatim arms 149 cron schedules pointing at production —
the 3–4 Aug incident, rebuilt. **Do not follow that step as written.**

**4. The baseline's header overstates what is proven.** It claims the migration set is complete and
cites `final_sync_check.mjs` as proof. The branch replay disproves the first; `final_sync_check`
disclaims the second in its own output (65 of 712 in scope).

### The corrected route

1. Create the branch. It **will** report `MIGRATIONS_FAILED`. Expected, not a failure of the step.
2. Excise the `CRON JOBS` section and refuse any statement carrying the production ref.
   `scripts/staging/rebuild_staging.mjs` does both and quarantines the rest.
3. Reset `public`, apply the baseline in **repeated passes** — dump order is best-effort, so a
   statement that fails on a missing dependency succeeds on a later pass.
4. Replay the `kb_stage` / `ops_kb_stage` / `containment` migrations **filtered to the statements
   that touch those schemas**. Replaying whole files means 35 broad migrations whose other
   statements need a `public` that is not there yet.
5. `holdout_v2` needs a migration written from production's catalog.
6. Re-run `check_branch_isolation.mjs` with the branch present.

### Two traps inside the route

**Never run a schema rebuild and a data copy against the management API at once.** They throttle
each other. On 4 Aug both began returning `429 ThrottlerException`, and the rebuild recorded each
429 in its failure list as "this statement cannot be replayed" — turning a rate limit into a
fabricated reproducibility defect. `qd_guard.mjs` now retries 429/502/503/504 with backoff.

**"The kb_stage migration" is plural.** `20260802122010` creates `kb_stage.decision_rules` without
`source_rule_id` or `record_id`; they arrive in `20260802130025`. Those two columns are what the
whole A-01 diagnosis rests on.

---

## 4. A-01: proven in staging, and the importer fix

Production's `kb_stage.decision_rules` was copied into staging row for row — 16,254 rows, 3,325
duplicates, a faithful reproduction rather than a simulation — and the cleanup run against the copy
inside a transaction that asserts its own post-condition before committing.

| measure | after cleanup | expected |
|---|--:|--:|
| total rules | **12929** | 12929 |
| duplicates remaining | **0** | 0 |
| wrapped rows | **10392** | 10392 |
| flat rows kept | **2537** | 2537 |
| **bodyless rules remaining** | **0** | 0 |
| categories | **67** | 67 |

Production after: `16254 / 3325 / 112611` — **unchanged**.

Remediation set exported before anything was deleted: `_a01_duplicate_ids.tsv`, 3,325 rows,
sha256 `785eb34c7ee0d808e20616361a0ba40e4276dc4a205cdc3888609de93b8f4218`.

Preconditions, measured on production read-only: all 3,325 duplicates are bodyless in **both**
`when_json` and `then_json`, each has **exactly one** canonical replacement, no canonical is itself
bodyless, and **no duplicate is referenced by any other row**.

> A first-pass query reported 3,325 "duplicates referenced by another row". That was a self-join
> artefact. Excluding self-reference gives 0. Measure the suspect, then measure the measurement.

### The brief's plan for step 3 could not have worked

It said: seed staging with the corrected importer, then delete the duplicates there. A corrected
importer produces no duplicates — nothing to delete, nothing proven. Reproducing the defect is the
only way to demonstrate the cure.

### The importer: two defects, both fixed

**1. The key was not invariant under shape.** `rule_row()` wrote `r['rule_id']` for flat rules and
`r['record_id']` for wrapped ones, so when the shape detector's verdict changed for 28 packages the
key changed with it, and an upsert on a changed key is an insert.

`canonical_rule_key()` returns the **source rule id** — the only identifier present in both shapes:

```
flat     -> r['rule_id']
wrapped  -> structured_data['rule_id']    (fallback: record_id)
```

468 of 10,392 wrapped rules carry no source rule id and take the fallback. Collisions across the
12,929 genuine rules: **zero**, globally and per category.

**2. The report could not have noticed.** `rows=52,697 rejected=0 write_errors=0` counted lines
read from files — identical whether the writes updated 12,929 rows or inserted 3,325 extra. The
importer now measures the database before and after and reports **expected, inserted, stale,
rejected** separately, with `count_matches_archive` and `idempotent` as verdicts. A run that grows
the table exits non-zero.

### The guard that matters is the pre-flight one

Detection happens **before the first write**. Run read-only against production over all 67
packages, it reproduces A-01 independently:

```
preflight: {"expected": 12929, "present_before": 16254, "to_insert": 6599,
            "to_upsert_existing": 6330, "stale": 9924,
            "stale_superseded_by_key_change": 9924}
PREFLIGHT REFUSED — UPSERT KEY CHANGED
```

`expected = 12929` is derived from the archives, not copied from the audit. It matches.

**It also refuses the change session 6 proposes**, and that is correct: adopting the canonical key
re-keys 9,924 production rows, which is a migration requiring approval, not something an import
does in passing. Arithmetic: `16,254 + 6,599 inserted − 9,924 re-keyed = 12,929`.

> The detector initially indexed `source_rule_id` only, and the scheme A-01 left behind keys on
> `record_id` — so it missed the exact case it was written for and reported ordinary staleness.
> Index every identifier a record carries.

### Two decisions left for the founder

**Which route to 12,929 in production?**

- **Delete** the 3,325 bodyless rows, keep the current key scheme. Smaller change. **Not idempotent
  afterwards** — the same class of bug remains available.
- **Re-key** to the canonical scheme: re-import updates 6,330, inserts 6,599, then delete the 9,924
  rows keyed the old way. Larger change, immune to shape-detector churn afterwards.

Both land on exactly 12,929. Either is a separate, separately-approved production step.

### Incidental fixes

- **The importer could only ever write to production.** The endpoint was a production literal —
  which is also why the 4 Aug re-import could not have been rehearsed anywhere. Now
  `--project-ref` / `KB_PROJECT_REF`, refusing production without `--i-mean-production`.
- **The token was read at module import.** It is minted per run and revoked after, so between runs
  *every* invocation — including `--help` — died with `FileNotFoundError`. Now read on first use.
- **The corpus on disk was 28 of 67 packages.** Restored from
  `Downloads\QuotesDone_ALL_KNOWLEDGE_86_CATEGORIES_v2026.07.31.zip`; all 28 pre-existing are
  byte-identical to the master, 39 added. `company-operations/` is still empty — its archive is in
  `Downloads`, unextracted.

### Tests

`knowledge-import/test_idempotency.py` — 21 behavioural tests over the real 67-package fixture, no
source-string assertions. Archives yield 12,929 rules and 112,611 records. Second import inserts
zero. A store keyed under the old scheme is refused, not doubled.

---

## 5. The surviving conformance list (from the 4 Aug audit)

The 487-row matrix is gone; this ordered list is what survives, and it is the work queue.

1. **Stand up staging.** Converts 119 `BLOCKED` and much of the 77 `INSUFFICIENT_EVIDENCE` into
   real answers. Nothing else can be *proven* without it. _(Session 6: branch exists, `kb_stage`
   done, `public` partial.)_
2. **Clear the stale decision rules** (A-01) and add an idempotency assertion to the importer.
   _(Session 6: proven in staging, importer fixed. Production application still pending.)_
3. **Wire the 86-route taxonomy**: call `fn_kb_route` / `fn_trade_identify` from `customer_api` and
   `profile_ai`, retire the four hardcoded lists. Unlocks the whole knowledge corpus.
4. **Classify risk and idempotency for 55 executors** — `v_executor_registry_gaps` → 0.
   Precondition for re-enabling `cos_execute_hourly`.
5. **Make `cos_execute` write `workflow_run` / `workflow_step_run` / `action_execution` /
   `decision_trace`**, and populate `company_event.dedupe_key`.
6. **Thread `task_class`** through `_shared/llm.ts` call sites; route `designer` and
   `resend_inbound` through `ai_gateway`.
7. **Fix the customer-portal error path** and unify the two Arabic mechanisms.
8. **Then, and only then, the 29 API actions** — a product build, not remediation.

Items 2, 4, 6 and 7 are days. Item 3 is the highest value per hour in the entire system.

### The audit's ranked findings

| # | finding | severity |
|---|---|---|
| B-01 | 86-route taxonomy has 0 callers; live path uses 4 hardcoded lists | HIGH, launch-blocking |
| B-02 | 0 of 29 package API actions exist — no handler, no frontend caller | HIGH |
| B-03 | 17 autonomy/portal tables: 0 writers, 0 readers | HIGH |
| B-04 | 55 of 55 executors lack a declared idempotency strategy | HIGH, blocks `cos_execute` |
| B-05 | `task_class` passed by 1 of 60 LLM callers; cost gates unverifiable | MEDIUM |
| B-06 | `designer` and `resend_inbound` bypass `ai_gateway` for inference | MEDIUM |
| B-07 | Customer portal: `err` never rendered, no `.catch` — failed load shows "Loading…" forever | MEDIUM |
| B-08 | In-portal Arabic toggle does not set `html[dir=rtl]`, so RTL typography never applies | MEDIUM |
| B-09 | OS command centre has no Arabic at all | MEDIUM |
| B-10 | 4 OS call sites bypass `unwrap`/`gateCheck`; Control-Mode refusal surfaces as raw 403 | LOW |
| B-11 | 3,324 scenario tests never executed | MEDIUM |
| B-12 | `company_event.dedupe_key` populated on 0 of 125 rows | MEDIUM |
| B-13 | Rollback functions exist; no evidence any was ever rehearsed | MEDIUM |
| B-14 | No staging project — 119 acceptance criteria unverifiable | HIGH, structural |

Status distribution of the lost matrix, for reconciliation if it is ever rebuilt:
`APPLIED_BUT_NOT_CONNECTED` 177 · `BLOCKED` 119 · `INSUFFICIENT_EVIDENCE` 77 ·
`PARTIALLY_APPLIED` 43 · `NOT_APPLIED` 39 · `PRESENT_AS_DATA_ONLY` 17 · `APPLIED_AND_WORKING` 14 ·
`SUPERSEDED_WITH_JUSTIFICATION` 1 = **487**.

---

## 6. Still open — do not re-derive

The 55 executor gaps (re-measured 4 Aug: still 55), `cos_execute` writing no run model
(`workflow_run` 0), `company_event.dedupe_key` 0 of 125, `task_class` passed by 1 of 60, the
customer-portal error path (`CustomerPortal.tsx:220` sets `err` and never renders it; neither
loader has a `.catch`), the two Arabic mechanisms (`globals.css:484-512` scopes every RTL fix to
`html[dir="rtl"]`, but the in-portal toggle sets `dir` on an inner `<div>`), the 29 API actions,
the invite engine, `kpi_review_weekly` timing out on `v_supply_gap` (weekly Mon 04:00),
`send_whatsapp` rejecting its own cron's credential (`wa_flush` passes `cred_cron_notifications`;
the function does not accept it), the 18 deliberately-held crons, `executive_control_session` being
a view **on purpose** — do not "fix" it by creating the table — and the 6 non-existent model IDs in
the routing pack (do not retire `claude-opus-4.8`; its replacement does not exist).

Also open: 131 `proposed` org_tasks with no approval button; 13 of 14 task writers never consult the
authority model; `regulated_scope` gates 259 rules and nothing sets it; `day_cadence` and
`edge_health_probe` have 20,083 probes written and never read; 113.7 MB of `02_category_master.md`
narrative is in no database; Meta Business Verification is founder-only; Sentry and an
email-verification provider are the two absent P0 connectors; Stripe test-mode keys absent;
47 routes still `requires_review`; rollback functions exist but none rehearsed.

The live traffic picture: inquiries 0, quotes 0, customers 0, leads 20,464.

---

## 7. Things that bit

- **A rule that did the opposite of its job.** "Audit-only, do not commit" destroyed the register
  it was meant to keep honest. Protect the system, record the finding — different verbs.
- **An artifact that exists only in a chat does not exist.** Cloud session workspaces are discarded.
- **A rate limit recorded as a reproducibility defect.** *A measurement taken under an unnoticed
  confound is worse than no measurement, because it gets quoted.*
- **A signal that is always non-zero is worse than one that is always zero** — it looks like
  progress.
- **A detector that knew only one of the two identifiers.**
- **"The migration" was singular and the schema needed two.**
- **A file that reads its credential at import time cannot run `--help`.**
- **A generated file asserting a guarantee the check it names does not make.**
- **"Doesn't exist" is not "can't be created" — and "can be created" is not "is usable."**
- **A branch can be isolated because it is broken.** Finishing the rebuild reduces its isolation.
- **A plan that removes the defect cannot demonstrate the cure.** Reproduce, remediate, measure.
- **A session that measures only current state cannot distinguish "was always so" from "became so
  five minutes ago."** This brief inherited "not pushed" and carried it forward as fact; the branch
  had been on GitHub the whole time. Write **is**, not **was**, about anything you did not watch
  change. `git reflog` is the cheap check.

_Carried forward: an alarm is only as good as its reader · `cron.job_run_details` is a log nobody
reads · a ramp that measures time instead of output ratchets through an outage · a monitor can fail
exactly when it matters and pass the rest of the time · measure the suspect before rewriting it ·
imported is not called · a passing test suite is not acceptance evidence · the guard read the wrong
file — assert on the call, not the name · a broken thing can be the only thing holding another
broken thing · committed is not deployed, deployed is not verified, and committed is not running._
