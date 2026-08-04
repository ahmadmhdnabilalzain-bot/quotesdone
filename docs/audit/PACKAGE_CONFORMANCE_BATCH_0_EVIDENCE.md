# Package conformance — Batch 0 evidence

_Session 6, 4 August 2026. Branch `repair/package-conformance-batch-0`, from `9d002d3`._

Every number below was measured during this session. Where something could not be measured, it
says so and says why. Nothing in Batch 0 changed production.

---

## 0. Summary — what Batch 0 found

Batch 0 was scoped as five small steps. Three of them landed as specified. Two of them turned out
to rest on a premise that is false, and the correction is the most important output of the session.

| step | outcome |
|---|---|
| 1 — preserve the audit | **BLOCKED.** The register does not exist on this machine. See §1. |
| 2 — staging readiness | **DONE, and the premise was wrong.** A branch costs 32 cents. A *usable* branch is a workstream. See §2. |
| 3 — A-01 remediation | **PROVEN in staging.** See §4. |
| 4 — importer idempotency | **DONE, with a stronger fix than specified.** See §3. |
| 5 — package counts | **PARTIALLY DONE.** Corpus counts verified from source; company-operations pack not present. See §5. |

**The headline correction.** The brief said staging was not blocked because a preview branch is one
API call. That is true and it is not the point. The branch was created in 30 seconds and then
**failed to build**: `MIGRATIONS_FAILED`, 31 of 712 migrations replayed. The repository cannot
reconstruct this database, and the reasons are specific, measurable, and were not previously
recorded. See §2.

---

## 1. STEP 1 — the audit register is not recoverable from this machine

Required: verify the SHA-256 of `PACKAGE_CONFORMANCE_MATRIX.csv` and
`PACKAGE_CONFORMANCE_SUMMARY.md`, then commit both unchanged.

**Neither file exists.** A recursive search of `C:\Users\Opera` for `PACKAGE_CONFORMANCE*` returns
nothing. `quotesdone/docs/audit/` holds only `backend-current-state.md`,
`frontend-current-state.md`, `implementation-plan.md` and
`requirements-traceability-updated.csv`.

The audit note records why: *"Deliverables ... sent to the founder — **not committed**, per the
audit-only instruction."* They were produced in a previous session's cloud workspace, which is
discarded when the session ends.

**This was not worked around, deliberately.** Regenerating the matrix would produce a file that
fails both published hashes by construction, and the governing rule for this batch is that the
register may not be reinterpreted from scratch. A regenerated matrix would be a new opinion wearing
the old one's authority.

**Action required from the founder:** re-attach both files. They will be hash-checked against
`0d453a04…` and `f2ae80bc…` and committed unchanged.

Everything else in Batch 0 was completed without them, because the technical steps are fully
specified in the session brief itself.

---

## 2. STEP 2 — staging: created, and why it was never trivial

### 2.1 identity

| field | value |
|---|---|
| production ref | `htdblwldjkcgjvmqkbeh` — READ-ONLY all session |
| staging branch | `staging-batch0` |
| staging ref | `pglpqrhvozwepymcuunn` |
| staging host | `db.pglpqrhvozwepymcuunn.supabase.co` |
| parent | `htdblwldjkcgjvmqkbeh`, `with_data: false` |
| cost | $0.01344/hour ≈ $0.32/day |
| git | `9d002d3` → `repair/package-conformance-batch-0` |
| production migration baseline | 712 applied |

### 2.2 the branch created in 30 seconds and then failed to build

`create_branch` succeeded immediately. The branch then reported **`MIGRATIONS_FAILED`**:

```
applied_on_branch  31        (of production's 712)
max_version        20260611104735
public_tables      17
kb_stage           absent
```

The replay halted at a June migration — earlier than **any** file in `supabase/migrations/`, whose
earliest is `20260724`. The 285 committed files are increments after a baseline; the 647 earlier
applied migrations have no file. `final_sync_check.mjs` is honest about this in its own output:
*"65 of 712 applied migrations are in scope and all present; 647 older ones have no file and are
NOT checked here."*

"Staging is one API call away" was true about the branch and false about the database.

### 2.3 four reconstruction defects, all newly measured

**(a) `full_schema.sql` exports only `public`.** The committed baseline (1,687,662 bytes, captured
`2026-08-04T12:50:17Z`) contains 388 `CREATE TABLE` statements, every one `public.`, and **zero**
`CREATE SCHEMA` statements. Production has four further application schemas:

| schema | tables | views | reconstructable from the repo? |
|---|--:|--:|---|
| `ops_kb_stage` | 22 | 0 | yes — `20260802131757` |
| `kb_stage` | 13 | 0 | yes — `20260802122010` + later fixes |
| `holdout_v2` | 8 | 2 | **NO — no migration, not in the baseline, not in `migrations-superseded-consolidated/`** |
| `containment` | 4 | 0 | yes — `20260802234149` |

**`holdout_v2` (8 tables, 2 views) can be reconstructed by no committed artefact at all.** That is
the strongest form of the reproducibility defect and it was not previously recorded.

**(b) The baseline is 15 tables behind.** 388 public tables against production's 403; eleven
migrations postdate the 12:50 capture.

**(c) `full_schema.sql` is unsafe to apply to a branch.** It carries a `CRON JOBS` section —
29,139 bytes, **149 `cron.schedule` calls and 45 literal occurrences of the production ref**.
`migration-set-cannot-rebuild.md` recommends, as step 1 of its "practical route to staging",
applying this file to a branch. Doing that verbatim arms 149 cron schedules pointing at
production — the exact 3–4 Aug incident in which branch crons drove production's `send_whatsapp`
and deploy path for eighteen hours. **That doc's route is unsafe as written; §2.6 replaces it.**

**(d) The baseline's header overstates what is proven.** It reads: *"To rebuild a database, replay
`supabase/migrations/` in order — that set is complete, and `final_sync_check.mjs` proves every
applied migration has a file."* The branch replay disproves the first clause and
`final_sync_check` explicitly disclaims the second.

### 2.4 the production-refusal guard (required deliverable)

Code the scripts call, in both languages the tooling uses:

- `scripts/staging/qd_guard.mjs` — `assertNotProduction()`, `assertNoProductionLiteral()`,
  `mgmtWrite()` (refuses production **and** any statement embedding the production ref),
  `mgmtRead()` (permits production, refuses anything that writes), `resolveStagingRef()`.
- `knowledge-import/kb_idempotency.py` — same contract for the importer.

Ref matching is exact (`^[a-z]{20}$` plus string equality) so a typo fails closed.

Proven, not asserted:

```
PASS guard refuses the production ref
PASS guard refuses malformed ref ''
PASS guard refuses malformed ref 'HTDBLWLDJKCGJVMQKBEH'
PASS guard refuses malformed ref 'htdblwldjkcgjvmqkbe'      <- one character short
PASS guard refuses malformed ref 'not-a-ref'
PASS guard refuses malformed ref None
PASS guard permits a valid non-production ref

REFUSED: db_write targeted production (htdblwldjkcgjvmqkbeh). Batch 0 forbids this.
refusing: no --project-ref given and the default is production.
refusing: 'not-a-ref' is not a valid project ref
```

### 2.5 `check_branch_isolation.mjs` re-run with a branch present

Run three times this session, and all three results are worth keeping.

1. **Before the branch existed** — passed vacuously (preview branches = 0).
2. **While the branch was still building** — **failed**, and failed correctly: the branch had no
   `cron.job` relation, so the check could not evaluate its assertion, reported `UNKNOWN`, and
   exited non-zero rather than counting an unevaluatable assertion as a pass. Recorded so a later
   reader does not mistake it for a regression.
3. **With the branch present and `kb_stage` built** — **passes**, and emits a forward-looking
   warning worth acting on:

```
production has 20 function(s) embedding its own ref

--- staging-batch0  (pglpqrhvozwepymcuunn)  status=MIGRATIONS_FAILED
      NOTE  this branch has 0 of production's 20 ref-embedding functions.
            A complete replay would give it more ways to reach production than it has now.
      PASS  0 active jobs reach production

ISOLATED - no branch cron can reach production.
```

**The branch is isolated partly because it is incomplete.** Finishing the rebuild (§2.6) will
create the 20 ref-embedding functions on it. This check must be re-run at the end of that rebuild,
not just at its start — the same trap as 3–4 Aug, when a halted replay made an incomplete branch
look safe.

### 2.6 corrected route to a usable staging database

1. Create the branch. It will report `MIGRATIONS_FAILED`. Expected.
2. **Excise the `CRON JOBS` section** and refuse any statement carrying the production ref —
   `scripts/staging/rebuild_staging.mjs` does both, and quarantines the remainder.
3. Reset `public`, then apply the baseline in repeated passes (dump order is best-effort, so a
   statement failing on a missing dependency succeeds on a later pass).
4. Replay the **kb_stage / ops_kb_stage / containment** migrations — filtered to the statements
   that touch those schemas, not whole files. See §3.3.
5. `holdout_v2` cannot be built; it needs a migration written from production's catalog.
6. Re-run `check_branch_isolation.mjs` and confirm it passes with the branch present.

**Never run a schema rebuild and a data copy against the management API at once.** See §6.

---

## 3. STEP 4 — importer idempotency

### 3.1 the two defects, separated

A-01 was not one bug. It was a key that was not invariant, and a report that could not have
noticed. Fixing either alone leaves the failure available.

**Defect 1 — the key changed meaning with the shape.** `rule_row()` wrote `r['rule_id']` for flat
rules and `r['record_id']` for wrapped ones. When the shape detector's verdict changed for 28
packages, the key changed with it, and an upsert on a changed key is an insert.

`canonical_rule_key()` now returns the **source rule id**, the only identifier present in both
shapes:

```
flat     -> r['rule_id']
wrapped  -> structured_data['rule_id']   (fallback: record_id)
```

Measured: 468 of 10,392 wrapped rules carry no source rule id and take the fallback. Collisions of
that key across the 12,929 genuine rules: **zero**, globally and per category.

**Defect 2 — the report counted the wrong thing.** "rows=52,697 rejected=0 write_errors=0" counted
lines read from files, a quantity identical whether the writes updated 12,929 rows or inserted
3,325 extra. The importer now measures the database before and after and reports **expected,
inserted, updated/unchanged, stale and rejected separately**, with `count_matches_archive` and
`idempotent` as explicit verdicts. A run that grows the table exits non-zero.

### 3.2 the guard that matters: detection *before* the first write

`--preflight` scans the archives, reads the database's key set, and classifies. It refuses on:

- **`stale_superseded_by_key_change` > 0** — a key in the database that is an alias of a key the
  archive now produces. This is the A-01 signature and is never permitted silently.
- **`stale` > 0** — keys in the database and in no archive. Refused unless `--allow-stale`.

**Run against production, read-only, over all 67 packages, it independently reproduces A-01:**

```
preflight: {"expected": 12929, "present_before": 16254, "to_insert": 6599,
            "to_upsert_existing": 6330, "stale": 9924,
            "stale_superseded_by_key_change": 9924}

PREFLIGHT REFUSED
UPSERT KEY CHANGED: 9924 rows in the database are keyed under a scheme this archive no
longer produces. Importing now would insert a duplicate of each instead of updating it -
finding A-01, exactly.
  old_key "QD-KB-008-soft-furnishings-...-decision_rule-0135"
  now_keyed_as ["R-008-soft-furnishings-...-ask-site-or-client-context"]
```

`expected = 12,929` is derived from the archives, not copied from the audit. It matches.

**A note on this refusal.** The guard is refusing the change *this session proposes*. Adopting the
canonical key in production re-keys 9,924 rows and is therefore a migration requiring approval —
not something an import may do on its way past. That is the guard working, and the reason the
production cleanup stays a separate, separately-approved step.

The arithmetic closes: 16,254 + 6,599 inserted − 9,924 re-keyed = **12,929**.

### 3.3 two further defects found while fixing it

- **The importer could only ever write to production.** `FN_URL` was a production literal, which
  is also why the 4 Aug re-import could not have been rehearsed anywhere. It now resolves from
  `--project-ref` / `KB_PROJECT_REF` and refuses production without `--i-mean-production`.
- **`TOKEN` was read at module import.** The import token is minted per run and revoked after, so
  between runs *every* invocation — including `--help` and every guard test — died with a
  `FileNotFoundError` before doing anything. It is now read on first use.
- **The creating migration does not define the columns the diagnosis rests on.**
  `20260802122010` creates `kb_stage.decision_rules` without `source_rule_id` or `record_id`;
  they arrive in `20260802130025`. Any "apply the kb_stage migration" instruction that means the
  singular is wrong.

### 3.4 the behavioural test

`knowledge-import/test_idempotency.py` — real 67-package fixture, measured outcomes, no
source-string assertions. All 21 pass:

```
PASS fixture is the complete 67-package corpus  found 67
PASS archives yield 12,929 decision rules  got 12929
PASS archives yield 112,611 knowledge records  got 112611
PASS key derivation is deterministic across runs
PASS record id set is deterministic across runs
PASS first import inserts every rule  {"expected":12929,"to_insert":12929,"stale":0}
PASS first import has nothing stale
PASS SECOND IMPORT INSERTS ZERO  to_insert=0
PASS second import sees nothing stale  stale=0
PASS second import matches every existing row
PASS key is invariant under re-derivation
PASS A-01 regression: old-scheme store is refused  9924 rows flagged as re-keyed
PASS reconcile calls an unchanged rerun idempotent
PASS reconcile refuses a run that grew the table  inserted=3325
+ 7 guard tests (§2.4)
```

The A-01 regression case is the one to keep: a store keyed under the old scheme is **refused**,
not silently doubled.

### 3.5 what is NOT proven

The end-to-end double import against a live database (`test_idempotency.py --project-ref`) has
**not** been run. It needs `kb_corpus_import` deployed to staging and a `kb_import_token` minted
there; neither exists yet. The test is written and will run once staging carries edge functions.
Until then, idempotency is proven against the real archives and a simulated store, plus the
pre-flight measured against the real production database — not through the edge function.

---

## 4. STEP 3 — A-01 remediation, proven in staging

### 4.1 a correction to the method

The brief said: seed staging with the corrected importer, then delete the duplicates there. That
cannot demonstrate the cleanup — a corrected importer produces no duplicates, so there is nothing
to delete and nothing proven.

So the state was **reproduced instead of simulated**: production's `kb_stage.decision_rules` was
copied into staging row for row, and the remediation run against the copy. The corrected importer
is proven separately (§3).

Script: `scripts/staging/prove_a01_remediation.mjs`. Production is read-only throughout, enforced
by `qd_guard`, and re-verified after.

### 4.2 the exported remediation set

```
file    _a01_duplicate_ids.tsv          (category_slug, rule_id, source_rule_id)
rows    3325
sha256  785eb34c7ee0d808e20616361a0ba40e4276dc4a205cdc3888609de93b8f4218
```

### 4.3 preconditions, measured on production, read-only

| check | value | required |
|---|--:|---|
| duplicates with exactly one canonical replacement | 3325 | all |
| duplicates with a wrong canonical count | 0 | 0 |
| duplicates carrying `record_id` null | 3325 | all |
| duplicates with empty `when_json` | 3325 | all |
| duplicates with empty `then_json` | 3325 | all |
| canonical rows that are themselves bodyless | 0 | 0 |
| duplicates referenced by another row | 0 | 0 |

Every one of the 3,325 is bodyless, has exactly one non-bodyless canonical replacement, and is
referenced by nothing. The script aborts before touching anything if any of these fails.

The last row corrects a first-pass measurement of my own: a naive self-join reported 3,325
"duplicates referenced by another row". Excluding self-reference gives **0**. The first number was
an artefact of the query, not a property of the data.

### 4.4 fidelity of the reproduction

```
copied 16254 rows
staging now: rules=16254 duplicates=3325
faithful reproduction: true
```

### 4.5 the remediation and its result

The cleanup runs in one transaction that asserts the post-condition **before** committing:

```sql
begin;
create temp table _a01_target as
  select d1.rule_id, d1.category_slug from kb_stage.decision_rules d1
   where d1.record_id is null
     and exists (select 1 from kb_stage.decision_rules d2
                  where d2.category_slug = d1.category_slug
                    and d2.record_id is not null
                    and d2.source_rule_id = d1.rule_id);
delete from kb_stage.decision_rules d using _a01_target t
 where d.rule_id = t.rule_id and d.category_slug = t.category_slug and d.record_id is null;
do $$ declare n int; begin
  select count(*) into n from kb_stage.decision_rules;
  if n <> 12929 then raise exception 'post-cleanup count is %, expected 12929 - rolling back', n; end if;
end $$;
commit;
```

Result:

| measure | value | expected |
|---|--:|--:|
| total rules | **12929** | 12929 |
| duplicates remaining | **0** | 0 |
| wrapped rows | **10392** | 10392 |
| flat rows kept | **2537** | 2537 |
| **bodyless rules remaining** | **0** | 0 |
| categories | **67** | 67 |

`VERDICT: REMEDIATION PROVEN`

### 4.6 production is unchanged

```
PRODUCTION AFTER: rules=16254 duplicates=3325 records=112611
PRODUCTION UNCHANGED: true
```

**Production still holds 16,254.** The remediation is proven, not applied. Applying it is a
separate, separately-approved step. No route was activated; no edge function was deployed; no cron
was enabled.

---

## 5. STEP 5 — package counts

### 5.1 the corpus was incomplete on this machine and has been restored

`knowledge-import/all86/.../01_CATEGORY_KNOWLEDGE_PACKAGES` held **28** of 67 packages — the 28
affected by the 4 Aug shape fix. The full corpus was recovered from
`C:\Users\Opera\Downloads\QuotesDone_ALL_KNOWLEDGE_86_CATEGORIES_v2026.07.31.zip` (27,480,392
bytes, 169 entries, 67 inner package zips).

All 28 pre-existing packages are **byte-identical** (SHA-256) to their counterparts in the master
archive; 39 were added. The corpus is now complete at 67 and provenance-checked.

### 5.2 counts verified from source

Derived by walking all 67 archives, not read from the audit:

| metric | source | expected | status |
|---|--:|--:|---|
| decision rules (canonical keys) | 12,929 | 12,929 | **exact** |
| knowledge records | 112,611 | 112,611 | **exact** |
| categories represented in staging after remediation | 67 | 67 | **exact** |
| production `kb_stage.records` | 112,611 | 112,611 | **exact, unchanged** |
| production `kb_stage.records` where `record_type='decision_rule'` | 10,392 | 10,392 | **exact** |

The 112,611 figure counts distinct validated `record_id` values, so the consolidated
`23_all_records.jsonl` cannot double-count it.

### 5.3 not verified, and why

- **The eight company-operations metrics** (24 departments · 3,959 records · 18 workflows ·
  132 handoffs · 100 event subscriptions · 96 roles · 21 sources · 569 code-evidence rows).
  `knowledge-import/company-operations/` is **empty**. The archive exists at
  `C:\Users\Opera\Downloads\QuotesDone_COMPANY_OPERATIONS_KNOWLEDGE_v2026.07.31.zip` and was not
  extracted this session.
- **62 knowledge record types**, **86 route manifests**, **aliases**, **426 crosswalk rows** — all
  require either the extracted company-operations pack or a populated staging `kb_stage.records`,
  which this session did not seed (only `decision_rules` was copied, deliberately: it is the table
  the finding is about).

---

## 6. Things that bit, this session

- **A rate limit recorded as a reproducibility defect.** A schema rebuild and a data copy ran
  against the management API at the same time; both began failing with
  `429 ThrottlerException`, and the rebuild wrote each 429 into its failure list as "this
  statement cannot be replayed". Its "pass 1: applied 481, failed 1,721" is therefore **not** a
  measurement of anything and is not quoted as one anywhere in this document. `qd_guard` now
  retries 429/502/503/504 with exponential backoff so that a recorded failure means what it says.
  *A measurement taken under an unnoticed confound is worse than no measurement, because it gets
  quoted.*

- **A detector that only knew one of the two identifiers.** The upsert-key-change detector indexed
  `source_rule_id` only. The scheme A-01 actually left behind keys on `record_id`, so the detector
  missed the exact case it was written for and reported the run as ordinary staleness. Same family
  as "a shape detector that tests the weaker signal first". Fixed by indexing both.

- **`JSON.stringify` of a string is a double-quoted literal, and Postgres reads double quotes as
  an identifier.** Cost: one 740 KB error body.

- **"The migration" was singular and the schema needed two.** The creating migration for
  `kb_stage.decision_rules` has neither `source_rule_id` nor `record_id`.

- **A file that reads the token at import time cannot run `--help`.** The importer was unusable
  between imports, which is exactly when someone would be reading it.

- **A generated file asserting a guarantee the named check does not make.** `full_schema.sql`'s
  header cites `final_sync_check.mjs` as proof the migration set is complete;
  `final_sync_check.mjs` says in its own output that it checks 65 of 712.

- **"Doesn't exist" is not "can't be created" — and "can be created" is not "is usable."** The
  brief corrected the audit's first error and introduced the second.

---

## 7. State at the end of Batch 0

```
git                 repair/package-conformance-batch-0 from 9d002d3
production          htdblwldjkcgjvmqkbeh — UNCHANGED, read-only all session
                    kb_stage.decision_rules 16254 (3325 stale, remediation proven not applied)
                    kb_stage.records        112611
staging             pglpqrhvozwepymcuunn (staging-batch0)
                    kb_stage 13 tables, decision_rules column-identical to production
                    kb_stage.decision_rules 12929 after proven remediation
                    public  partial — baseline rebuild aborted, see §6
routes activated    0
edge functions deployed 0
crons enabled       0
migrations applied to production 0
```

## 8. What Batch 1 should be

1. **Commit the audit register** once the founder re-attaches it (§1). Until then there is no
   defect register, only this document.
2. **Finish the staging rebuild** with the corrected route (§2.6) and backoff in place, and record
   the *real* residual failure count — the number this session could not honestly produce.
3. **Write a migration for `holdout_v2`** from production's catalog. 8 tables and 2 views are
   currently reconstructable by nothing.
4. **Regenerate `full_schema.sql` to cover all schemas**, and correct its header. `regen_schema.mjs`
   walks `public` only.
5. **Extract the company-operations pack** and close §5.3.
6. **Decide on the canonical key for production.** Adopting it re-keys 9,924 rows and converges
   the table to 12,929 without a delete; the alternative is the §4.5 delete and keeping the current
   scheme. Both reach 12,929. The first is idempotent afterwards; the second is not.
7. Only then the §4 work in the previous brief — wiring the 86-route taxonomy.

---

## 9. Addendum — a watch query that can never fire

The session-5 brief lists this under "Watch", annotated *"the router. Must become non-zero when
§4 item 1 is done."*

```sql
select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.prokind='f'
   and pg_get_functiondef(p.oid) ~* 'fn_kb_route\(|fn_kb_retrieve\(|fn_trade_identify\(';
```

**It already returns 10.** Measured on production, 4 Aug:

```
fn_inquiry_interpret · fn_kb_retrieve · fn_kb_route · fn_kb_route_decide · fn_trade_identify
fn_p2c1_rollback_stage_b · fn_p2c1_run_lang_case · fn_p2c1_scope_rule_tests
fn_p2c1_stage_b_regression · fn_p2c1_stage_b_selftest
```

Three compounding reasons it cannot signal what it was written to signal:

1. `pg_get_functiondef` of a function includes its **own** name, so `fn_kb_route` matches itself.
2. The router's internals call each other — `fn_kb_route_decide`, `fn_inquiry_interpret`.
3. Five `fn_p2c1_*` **test harnesses** call it, which is the audit's own point: 344 route tests
   execute and pass while nothing in the application calls in.

So the number is 10 today and will be 10 after the router is wired, and 10 if it is never wired.
The claim it was written to test — *"the 86-route taxonomy has zero callers"* — is about
`supabase/functions/**` and `src/**`, which is a repo search, not a catalog query. Replace it with:

```
rg -n 'fn_kb_route|fn_kb_retrieve|fn_kb_next_question|fn_trade_identify|fn_inquiry_interpret|fn_inquiry_workstream_activate' supabase/functions src
# 0 today. Non-zero is the signal that §4 item 1 landed.
```

Same family as the carried-forward lesson *"a deterministic signal that is always zero is worse
than no signal"* — here inverted, and worse, because a non-zero reading looks like progress.
