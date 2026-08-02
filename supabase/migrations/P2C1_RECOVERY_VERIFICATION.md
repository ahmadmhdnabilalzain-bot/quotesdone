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
