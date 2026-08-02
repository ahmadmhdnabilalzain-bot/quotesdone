# P2-C1 repository recovery — verification record

Date: 2026-08-02. Branch `feature/phase1-safety-and-decisions`.
Scope: Stage A, Stage B, Stage B.5, Stage B.6. No interpretation rule was changed.

## 1. What was recovered

| window | versions | migrations |
|---|---|---|
| Stage A / B / B.5 | 20260802165328 .. 20260802175843 | 31 |
| Stage B.6 | 20260802181006 .. 20260802183212 | 13 |
| **total** | **20260802165328 .. 20260802183212** | **44** |

Every file is written verbatim from `supabase_migrations.schema_migrations.statements`, with a
six-line provenance header that is excluded from the checksum. Checksums were committed first
(`d026416`, `f885505`, amended at `c69d321`) and the tree was then fitted to them.

### Two counting corrections, both found by measurement rather than by reading

1. `scripts/verify_migrations_in_repo.mjs` reported **22** applied-but-absent migrations. The true
   figure was **30**, because eight hand-written consolidations reused an applied migration's *name*
   while containing merged content. Name matching cannot prove fidelity; only a checksum can.
2. The replay counts applied migrations in the version window instead of trusting either manifest.
   It reported **44** against the manifests' 43. `20260802175843 p2_c1_stage_b5_operator_rollback`
   sat between the two recovery windows and was excluded by both boundaries. Recorded as
   Amendment 1 in `STAGE_A_B_B5_RECOVERY_MANIFEST.md`, committed before the file was written.

Both errors have the same shape: a boundary taken from a human reading of the work instead of from
the applied record. Every count in this document is now derived from `schema_migrations`.

## 2. Production ↔ repository parity

`node scripts/verify_repo_production_parity.mjs`

```
production migrations, all             : 634
production migrations, P2-C1 window    : 44
repository files in supabase/migrations: 207
  recovered, checksum-verifiable       : 44
  hand-authored, version match only    : 124
  no version at all                    : 36

=== P2-C1 WINDOW ===
A. applied in production, absent from repository : 0
B. in repository, not applied in production      : 0
C. checksum drift in recovered files             : 0
D. duplicate claims on one applied version       : 0
E. applied under a different version than the filename : 3
PARITY OK — zero drift in either direction.
```

The three E entries are `p2_01`, `p2_02` and `p2_03`: applied, but under CLI-assigned versions that
differ from their repository filenames. They are present and correct; only the filename version is
wrong. Not fixed here because renaming an applied migration file is a separate, riskier change.

### Pre-existing gap, not created by this work item — flagged, not fixed

**466 of 634 applied migrations have no file in `supabase/migrations`, and 36 files carry no version
prefix at all.** The repository has never been a faithful record of the database. P2-C1 is now the
only window that is. This is a material operational risk: a rebuild from the repository today would
not reproduce production, and no reviewer can see most of what has been applied. It should be a
work item of its own; recovering it uses exactly the tooling built here
(`scripts/qsql.mjs`, `scripts/verify_repo_production_parity.mjs`).

## 3. Replay verification

`node scripts/qsql.mjs scripts/sql/replay_verify.sql`

One `DO` block, therefore one atomic statement: fingerprint the whole `public` schema, tear down
every object these migrations create, assert the teardown left nothing behind, replay all 44
migrations in version order, fingerprint again, diff, then `RAISE EXCEPTION` to roll everything
back. **Production is never mutated** — the report travels out in the exception message.

```
version range: 20260802165328 .. 20260802183212
migrations in range: 44
migrations replayed: 44
statements executed: 44
objects torn down: 96
teardown residue before replay: 0 (asserted)
fingerprint lines pre: 15014
fingerprint lines post: 15014
DIFF: (no differences)
```

The teardown-residue assertion exists because without it a fingerprint match could be produced by a
teardown that quietly did nothing. Teardown set: 11 views, 37 tables, 46 function names across all
overloads, 2 enum types — derived from the recovered files by
`scripts/inventory_recovered.mjs`, not from a name pattern.

Replay source is the recorded `statements`, which are SHA-256 identical to the repository files, so
replaying them replays the repository. A clean empty database is not a usable target: these
migrations depend on the Phase 1 schema, so rebuilding in place against the real dependency graph
is the stronger available test, not a weaker substitute for it.

### Fingerprint coverage

15,014 lines over the entire `public` schema, not only P2-C1 objects, so collateral damage anywhere
would surface:

| tag | what |
|---|---|
| `R` | relation, kind, `relrowsecurity`, `relforcerowsecurity` |
| `C` | every column: type, `NOT NULL`, default expression, identity, generated |
| `K` | every constraint, by `pg_get_constraintdef` |
| `I` | every index, by `indexdef` |
| `T` | every non-internal trigger, by `pg_get_triggerdef` |
| `W` | every view/matview body, md5 of `pg_get_viewdef` |
| `F` | every function: identity args, md5 of `prosrc`, `prosecdef`, `provolatile`, result type, language |
| `E` | every enum label, in sort order |
| `G` | every table grant, by grantee and privilege |

## 4. Test battery

`node scripts/qsql.mjs scripts/sql/test_battery.sql`

```
stage A selftest        : 14/14 passed
stage B selftest        : 14/14 passed
stage B regression      : 2/2 passed
scope negative tests    : 12/12 passed
language parity suite   : 23/23 passed, false pos 0, false neg 0
disposition tests       : 22/22 passed
holdout v1 executed     : 54/54 cases executed
holdout v1 correctness  : 49/54 cases passed
holdout v1 false pos    : 0
holdout v1 false neg    : 5
holdout v1 EN/AR parity : trade-set 51/54, disposition 54/54, component 54/54,
                          clarification 52/54, conflict handling 54/54
holdout seal integrity  : true (cfb06e11e05b0645527a0ecc9cbded37273eab342826ce34fff1d7bd651fb089)
```

Application gates: `npm run typecheck` clean; `npm test` 31/31; `deno check --no-lock
--node-modules-dir=auto` on the four gated edge functions exits 0.

### On "54/54"

`54/54` is **execution**: every frozen case ran. It is not correctness and not parity.

* cases executed: **54/54**
* cases passed (correctness): **49/54**
* false positives: **0**
* false negatives: **5**
* seal integrity: **passed**
* EN/AR parity is reported per dimension above, each with its own denominator.

The earlier "disposition agreement 54/54" was a **parity** measurement — English against Arabic —
over 54 cases × 2 languages = 108 interpretations. A case where both languages are identically
wrong counts as agreement, which is why parity can read 54/54 while correctness reads 49/54. That
is why the two numbers must never be quoted without their kind.

The five failures are the deferred Part 3 gaps, not regressions:

| kind | count |
|---|---|
| `DISPOSITION_MISMATCH: got[fire=by_others] want[fire=excluded]` | 1 |
| `COMPONENT_MISMATCH: got[supply=by_others] want[supply=client_supplied]` | 1 |
| `PARITY_MISMATCH` | 3 |

Holdout v1 expectations were not edited. Zero expectation drift.

---

## 5. Migration filenames now carry the applied version

The recovered files were first written with a repository sequence number — `2026080222NN` for
Stage B.6, `2026080223NN` for Stage A/B/B.5. Two problems, one of them dangerous:

1. **Order was inverted.** Stage B.6 (`22NN`) sorted *before* Stage A/B/B.5 (`23NN`), the reverse of
   how they actually ran.
2. **`supabase db push` would have re-applied all of them.** Those names are 12 digits, not 14, and
   none exists in `schema_migrations`. Push compares filename versions against the applied record,
   so it would have treated every recovered file as new work and tried to apply an already-applied
   Stage A on top of itself.

All 45 files are now named `<applied version>_<name>.sql`, taken from each file's own recovery
header rather than invented (`scripts/rename_recovered_to_applied_version.mjs`). Filename order is
now applied order, and push sees them as already applied.

The three `p2_01` / `p2_02` / `p2_03` files still carry a filename version that differs from the
version they were applied under. They are present and correct; only the name is wrong. Left alone
here because renaming an applied migration file is a separate change with its own risk.

## 6. Stage B.6 rollback completion — migration 45

`20260802184500 p2_c1_stage_b6_rollback_completion`, sha
`11ed3ca8df17f70a6cee4ef23c6626064fb9a175ad2698b8b8d5e7e43628eb9b`, 17,307 chars.
Manifest entry committed at `71b358b`, before the file was written.

### Classification of the four objects the previous rollback left unaccounted for

| object | class | disposition |
|---|---|---|
| `p2c1_holdout_result_of_record` | **B — permanent audit evidence** | intentionally survives |
| `trg_holdout_record_immutable()` | **B** | survives; it protects the row above |
| trigger `holdout_record_immutable` | **B** | survives; it protects the row above |
| `fn_p2c1_rollback_stage_b6` | instrument | retained; it is the tool doing the removal |

`p2c1_holdout_result_of_record` is **B**, on four grounds:

1. It is the once-only record of the first and only independent evaluation of holdout v1. If
   rollback deleted it, a rollback-then-reapply cycle would permit a second "first evaluation" —
   defeating the `holdout_record_immutable` trigger, whose entire purpose is that a holdout measures
   an implementation exactly once. Rollback would become a way to launder the holdout's
   independence.
2. It has no operational role. No interpretation function, view, dispatch path or route reads it.
   Removing it changes no behaviour; keeping it costs nothing.
3. It has no foreign keys in either direction, so surviving leaves no dangling reference.
4. Its creating migration is already survival-safe — `create table if not exists` plus
   `insert … on conflict do nothing` — so re-applying B.6 over a surviving table is idempotent.
   The original author's intent was almost certainly B; it was simply never stated. It is stated now.

### One declared exception

`fn_mep_full_scope(text)` is **not** restored to its Stage B.5 text. The B.6 change
(`20260802182423`) was a defect fix to a Stage B.5 rule: B.5 said the full-scope modifier had to sit
in the same clause as the MEP anchor, and its regex excluded clause punctuation from the intervening
*words* but not from the *separators*. Reverting it reintroduces a false positive — three trades
activated across a full stop. Reversion is unsafe, so the corrected form is kept and named in the
report.

`fn_term_matches` **is** restored to the Stage B.5 form. Reverting it costs only English plural and
Arabic internal-article tolerance: a false *negative*, which degrades to a clarification question
rather than to a wrong dispatch. The governing rule is now explicit — restore prior-stage objects to
their prior-stage form, except where the reversion is unsafe.

### The verification now asserts what it used to only print

Aborts on any of: a removable object surviving; missing audit evidence; `fn_term_matches` or
`fn_group_dispatch_report` not in Stage B.5 form; `fn_mep_full_scope` not in its corrected form;
Stage A or Stage B below 14/14; Stage B.5 language parity below 23/23 or scope negatives below
12/12; any fixture data remaining. The last three were previously reported but not enforced.

### Both paths rehearsed against production, both rolled back

**Abort path** — `fn_p2c1_rollback_stage_b6('rehearse', …)`:

```
removable objects 22 -> 0, all_removed true
stage_a 14/14  stage_b 14/14  lang_parity 23/23  scope_negatives 12/12
intentional survivors 4, declared exceptions 1
fixtures remaining: 0 groups, 0 answers, 0 audit rows
```

**Commit path** — the real `'commit'` branch inside a `DO` block that raises at the end, the only
way to reach the code past the rehearsal `RAISE` without leaving B.6 removed:

```
audit rows written: 1
removable B.6 relations left: 0
audit-evidence rows surviving: 1
re-run response: {"ok": false, "error": "stage_b6_not_present"}
verdict: stage b6 removed; audit evidence retained; prior stage restored
```

## 7. Final state

```
replay        45 migrations replayed, teardown residue 0 asserted,
              fingerprint 15,014 lines before and after, no differences
parity        A 0, B 0, C 0, D 0 in the P2-C1 window
battery       stage A 14/14, stage B 14/14, regression 2/2, scope negatives 12/12,
              language parity 23/23, disposition 22/22
holdout v1    54/54 executed, 49/54 passed, 0 false positives, 5 false negatives, seal intact
app gates     typecheck clean, npm test 31/31, gated deno check exit 0
activation    mep_trade_route 6 (unchanged), live workstreams 0, live groups 0,
              scope dispositions 0, audit rows 0
expectations  holdout cases 54, result of record 1 row, seal checksum unchanged
```

No interpretation rule changed. No route activated. No holdout expectation edited.
Part 3 and holdout v2 are not started.
