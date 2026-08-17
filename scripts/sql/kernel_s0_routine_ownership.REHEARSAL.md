# kernel_s0_routine_ownership.sql — REHEARSAL RECORD

Project `htdblwldjkcgjvmqkbeh` (the one project). 17 Aug 2026.
**Nothing was applied.** The whole file plus the probes were sent as ONE simple query ending in
`raise exception`, so the entire thing ran in one implicit transaction and rolled back.

```
node scratchpad/s0/rehearse.mjs      # = kernel_s0_routine_ownership.sql + probes.sql, one POST
payload bytes: 300651
HTTP 400   (the 400 IS the abort — see the message below)
```

The Supabase management API does not return `NOTICE` output, so every probe result is accumulated
into one string and raised as the aborting exception. The abort is the delivery mechanism.

---

## The aborted-transaction output, verbatim

```
Failed to run sql query: ERROR:  P0001: S0 REHEARSAL — ABORTED ON PURPOSE, NOTHING COMMITTED
---------------- CLASS COUNTS ----------------
  HISTORICAL_APPLICATION                      486
  QUOTESDONE_APPLICATION                      475
  EXTENSION_MANAGED                           218
  SUPABASE_MANAGED                            38
  PLATFORM_INTERNAL                           6
  INTENTIONALLY_UNTRACKED_WITH_JUSTIFICATION  2
COVERAGE  ledger rows 1225, live routines 1225, live routines with NO ledger row 0, ledger rows with NO live routine 0

---------------- D. THE TWO RESTATED ROUTINES ARE BYTE-IDENTICAL TO LIVE ----------------
  zzz_fn_notifications_demo_guard md5 823d0dce6bb8d2a75f496b023d7514f7  pre-apply 823d0dce6bb8d2a75f496b023d7514f7  -> UNCHANGED
  fn_delete_proposer              md5 87e55ae74a5512d0b709ee7656136cdd  pre-apply 87e55ae74a5512d0b709ee7656136cdd  -> UNCHANGED

---------------- B. THE GUARD, IN BOTH DIRECTIONS ----------------
  D1 QuotesDone -> SUPABASE_MANAGED           REFUSED 23514  kernel_routine_ownership refuses public.fn_kernel_workflow_start(p_input jsonb): recorded class SUPABASE_MANAGED, but the facts support QUOTESDONE_APPLICATION. Rule R4_MANIFEST_DEFINES_IT. owner=postg
  D2 extension -> QUOTESDONE_APPLICATION      REFUSED 23514  kernel_routine_ownership refuses public.vector_dims(halfvec): recorded class QUOTESDONE_APPLICATION, but the facts support EXTENSION_MANAGED. Rule R1_PG_DEPEND_EXTENSION. pg_depend deptype=e binds pub
  D2b platform glue -> QUOTESDONE_APPLICATION REFUSED 23514  kernel_routine_ownership refuses extensions.pgrst_ddl_watch(): recorded class QUOTESDONE_APPLICATION, but the facts support PLATFORM_INTERNAL. Rule R3_PLATFORM_ROLE_IN_EXTENSIONS_SCHEMA. proowner=supa
  D3 ownership of a routine that is absent    REFUSED 23514  kernel_routine_ownership refuses public.fn_this_routine_does_not_exist(): recorded class QUOTESDONE_APPLICATION, but the facts support ABSENT_FROM_CATALOG. Rule R0_NOT_IN_PG_PROC. no pg_proc entry for
  D4 untracked with no justification          REFUSED 23514  new row for relation "kernel_routine_ownership" violates check constraint "kernel_routine_ownership_justification_ck"
  CONTROL rewrite a CORRECT row               ACCEPTED — the guard is not refusing everything

---------------- A2. THE DERIVATION, TWO-ARGUMENT FORM ----------------
  ('fn_kernel_workflow_start','p_input jsonb') -> QUOTESDONE_APPLICATION / R4_MANIFEST_DEFINES_IT
  ('auth.uid','')                                -> SUPABASE_MANAGED / R2_PLATFORM_ROLE_IN_PLATFORM_SCHEMA
  ('extensions.pgrst_ddl_watch','')              -> PLATFORM_INTERNAL / R3_PLATFORM_ROLE_IN_EXTENSIONS_SCHEMA
  ('trg_archive_record_version','')  2 schemas   -> AMBIGUOUS_WITHOUT_SCHEMA / R0B_MORE_THAN_ONE_SCHEMA_MATCHES
  ('holdout_v2.fn_eff', <4 args>)                 -> INTENTIONALLY_UNTRACKED_WITH_JUSTIFICATION / R6_NO_SOURCE_ANYWHERE_JUSTIFIED
  ('fn_nope','')                                 -> ABSENT_FROM_CATALOG / R0_NOT_IN_PG_PROC

---------------- C. GATE LINES 1, 2 AND 6 AFTER APPLY ----------------
  gate line 1: the 2 routines kernel_s0 creates now exist on production: 2 of 2
  gate line 2: justified untracked rows now on production: 2 of 2
  gate line 6: ledger rows to compare against the repository: 1225 (was 0 of 0)
CONTEXT:  PL/pgSQL function inline_code_block line 146 at RAISE
```

---

## What each block proves

**COVERAGE.** 1225 ledger rows against 1225 live routines, with `0` live routines carrying no
ledger row and `0` ledger rows naming a routine that is not live. 1225, not 1223, because the two
routines kernel_s0 itself creates exist by the time the seed runs. The ledger has no hole and no
ghost, and both directions are counted — a row count alone cannot tell one from the other.

**D — the two restated routines.** Both md5s are identical before and after. The restatements are
byte-for-byte what production already runs, so applying kernel_s0 changes no behaviour; it changes
which file the manifest names as canonical. `CREATE OR REPLACE` preserves the ACL, and both were
already `postgres=X/postgres, service_role=X/postgres` with no PUBLIC grant.

**B — the guard, both ways.**

| probe | what it tries | result |
|---|---|---|
| D1 | hide a QuotesDone routine inside the managed exclusion (`fn_kernel_workflow_start` → `SUPABASE_MANAGED`) | refused 23514 |
| D2 | claim extension code as application source (`vector_dims` → `QUOTESDONE_APPLICATION`) | refused 23514 |
| D2b | claim platform bootstrap glue as application source (`extensions.pgrst_ddl_watch`) | refused 23514 |
| D3 | record ownership of a routine that does not exist | refused 23514 |
| D4 | file an untracked routine with no justification | refused 23514 (the CHECK, before the guard) |
| CONTROL | rewrite a **correct** row unchanged | **accepted** |

The CONTROL is not decoration. A guard that refuses everything passes every one-sided test and is
an outage, and this repository has shipped both a guard that could not fire and a condition that
could not *not* fire. Five refusals and one acceptance is the pair of facts, not one of them.

**A2 — the derivation.** The two-argument form named in the brief works. A bare name that matches
two schemas (`trg_archive_record_version` exists in both `kb_stage` and `ops_kb_stage` with
identical arguments) returns `AMBIGUOUS_WITHOUT_SCHEMA` rather than guessing, which is why every
seeded row is schema-qualified.

**C — what the apply closes.** After the apply, gate lines 1 and 2 go to zero for the reasons shown,
and line 6 stops being `0 of 0`.

---

## The finding that changed the shape of this increment

The brief said most of the 480 is "certainly Supabase- and extension-managed code that was never
QuotesDone application source". **Measured, that is false.**

```
 nspname   |         owner          |  n  | pg_depend deptype 'e'
-----------+------------------------+-----+----------------------
 public    | postgres               | 953 |   0
 public    | supabase_admin         | 145 | 145
```

`canonical_routines.test.mjs` already excludes extension-owned routines by `pg_depend`, so every one
of the 481 it counts is owned by `postgres`. There is no managed code hiding in that number. The
whole managed estate on this project — every extension routine, every `auth`/`storage`/`realtime`
function, every piece of platform glue — is 262 routines, and none of them was ever inside the
count. The 481 is application code that never entered the apply order, and calling it "mostly
Supabase" would have retired a real problem by relabelling it.

## The two conflicts, and why neither was "landed"

Both are the `fn_phase_c_event_ingress` shape exactly: two files, one routine, **one commit**, so
the manifest's within-commit tie-break decided canon alphabetically.

| routine | manifest canon | what production runs | what actually differs |
|---|---|---|---|
| `zzz_fn_notifications_demo_guard` | `demo_rehearsal_containment.sql` | `containment_wording_no_false_positive.sql` | `\.` vs `[.]` (identical regex), and the held-row message no longer contains `@example.invalid` — which `fn_demo_marker_scan` reads as a demo marker, so the original could never let the teardown proof reach zero |
| `fn_delete_proposer` | `five_delete_proposals_..._miscounted.sql` | `a_decision_that_reopens_next_week_is_not_a_decision.sql` | production carries the whole "a decision holds until the fact changes" suppression (`v_prev`, `reopened_over`, the run note). The manifest-canonical file has none of it, and its only extra content is a 3-line comment; the counting SQL it explains is character-identical in both |

In both cases the manifest-canonical file is the **older** one. "Landing it the K13a way" would have
restored the demo-marker false positive in one and deleted a shipped feature in the other. So the
K13a pattern was applied in the direction the evidence points: only these two routines' definitions
were lifted — no historical feature migration was re-applied — into `kernel_s0_routine_ownership.sql`,
which is appended at the bottom of the manifest and is therefore now the ONE current source file for
each. The comment that would have been lost from `five_delete_proposals_...` is preserved above the
routine.

`scripts/checks/canonical_routines.test.mjs` after the change, unmodified and against the same
production: **conflicting definitions 129 (0 where live does not match canonical), repo -> live
drift 0.** Before, it was 3 and 3.

## Section E — the other 127 multi-file routines

129 routines are defined in more than one manifest file. After the two above, **0** of them have
production running anything other than the last manifest file. Per section E that is
**informational and needs no change**: the manifest order already names exactly one current source
file for each, and production already runs it. They are listed in the gate's output with that
verdict rather than silently dropped, because a conflict nobody can see is how this started.

## Two things repaired on the way, both real

1. **`scripts/sql/MANIFEST.txt` had a hook's stdout appended into it.** Three junk lines
   (`[INFO] Recording command outcome: printf`, `[OK] Command outcome recorded`) and one line where
   two filenames had been concatenated with no separator, so `kernel_k11_component_exposure.sql` and
   `kernel_k5c_invariant_reads_the_new_types.sql` were **both invisible to the manifest**. That is
   what made `fn_phase_c_invariants` report "live matches NEITHER definition": K5c was applied to
   production and its file was not being read. Repaired with an editor, not a shell redirect — the
   redirect is how it happened, and it happened to me once more mid-session before I stopped using it.
2. **The dollar-tag regex in the existing checks misses digits.**
   `canonical_routines.test.mjs` and `sql_files_match_live.test.mjs` both use `/\$[a-z_]*\$/`, which
   does not match `$k11_reach$`, `$k11_state$`, `$k11_guard$` — so three K11 routines are silently
   skipped there, and a skipped definition is indistinguishable from a clean one. The new gate uses
   `/\$[a-z0-9_]*\$/` and its comparable-definition count went 470 → 473 as a result. The two older
   checks are **not** patched here; that is a one-line change to instruments the whole 71-check board
   depends on and it belongs in its own increment.

## The gate, run for real, before the apply

```
node scripts/checks/application_source_of_truth.test.mjs      -> exit 1

  1. in repository, missing from production          4 / 476
        public.a00_kernel_routine_ownership_guard           canonical scripts/sql/kernel_s0_routine_ownership.sql
        public.fn_kernel_routine_ownership                  canonical scripts/sql/kernel_s0_routine_ownership.sql
        public.fn_kernel_historical_repair_state            canonical scripts/sql/kernel_s2_historical_repair.sql
        public.fn_phase_c_historical_repair_append_only     canonical scripts/sql/kernel_s2_historical_repair.sql
  2. on production, missing from repository          2 / 961
        holdout_v2.fn_eff(p_comp jsonb, p_td jsonb, p_trade text, p_component text)
        holdout_v2.fn_run_pending(p_run_id integer, p_limit integer)
  3. conflicting current definitions                 0 / 129
  4. drifted application routines                    0 / 473
  5. uncommitted application DDL                     0 / 7116
  6. ledger claims the repository denies             0 / 0     THIS LINE ASSERTS NOTHING
  countable findings                                 6
```

**Every one of the six is "the file has not been applied yet", and none of them is tuned away.**

* **Line 1, two rows** — `fn_kernel_routine_ownership` and `a00_kernel_routine_ownership_guard` are
  the routines this file creates. They are in the repository and not on production because this
  file has not been applied. Applying it makes both exist; the rehearsal above shows `2 of 2`.
* **Line 1, the other two rows** — `fn_kernel_historical_repair_state` and
  `fn_phase_c_historical_repair_append_only` belong to `scripts/sql/kernel_s2_historical_repair.sql`,
  which a **concurrent session** wrote and appended to the manifest while this increment was being
  measured. They are not mine and they are not defects; they are that session's file, also awaiting
  apply. The manifest went from 671 files to 673 between two runs of the gate. Line 1 counting them
  is the gate working: a routine in the apply order and not on production is exactly what it is for.
* **Line 2, both rows** — `holdout_v2.fn_eff` and `holdout_v2.fn_run_pending`. They have a
  justification, and the justification is a row in `kernel_routine_ownership`, which is not on
  production yet. A justification that exists only in an unapplied file has not justified anything,
  so the gate declines to exclude them. After the apply it reads them from the ledger and the line
  goes to 0 — the rehearsal shows `2 of 2` justified rows present.
* **Lines 3, 4, 5 are genuinely 0**, and each carries its denominator so a clean estate cannot be
  confused with an empty one: 129 multi-file routines all resolved, 473 comparable definitions all
  matching live, 7116 live DDL objects all recorded in the repository.
* **Line 6 is `0 / 0` and says so in words.** The table is not there. Zero over zero is an idle
  instrument, not a clean one, and printing it as a pass would be the exact defect this section was
  opened to resolve.

## Applying this file

```
node scripts/apply_sql.mjs scripts/sql/kernel_s0_routine_ownership.sql --apply     # lead engineer
node scripts/checks/application_source_of_truth.test.mjs                           # must reach 0/0 on all six
```

**Regenerate the seed if the repository has moved.** Section C2 is 961 literal rows recording where
each application routine's source file is, and a concurrent session was moving routines between
files while this was written (`fn_kernel_trace_integrity` left `kernel_k6_trace_ledger.sql` for
`kernel_s3_system_execution_traces.sql`, which is not yet in the manifest). If any routine has
changed file since, gate line 6 will name it — that is the line working, not failing. The seed rows
are produced by re-running the derivation over `MANIFEST.txt` and `git ls-files "*.sql"`; nothing in
them is hand-typed.

## Rollback

`scripts/sql/rollback/kernel_s0_routine_ownership.rollback.sql` drops the trigger, the guard, the
derivation and the table. It deliberately does **not** revert the two restated routines: they were
never changed, and "reverting" them means installing a definition production never ran.
