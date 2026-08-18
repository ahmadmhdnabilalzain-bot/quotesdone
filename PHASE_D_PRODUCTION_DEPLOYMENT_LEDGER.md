# Phase D — production deployment ledger

Required deliverable 14 of 15. Every Phase D write to `htdblwldjkcgjvmqkbeh`, in order, with the
file that produced it, how it was verified, and how to reverse it.

There is **one** project. Staging `pglpqrhvozwepymcuunn` was deleted on 15 Aug 2026 at the
founder's instruction and nothing here reads it.

## How each increment was applied

Every increment followed `PHASE_D_PRODUCTION_DIRECT_PROTOCOL.md`: read-only inspection → file
written and committed → dry run → rehearsal → apply → **read the definition back out of the
database and compare it to the file** → verify by execution.

`node scripts/apply_sql.mjs <file>` with no flag is a **dry run**. `--apply --ddl` writes and then
reads back; it prints `read back and identical to the file` only when the live definition matches
the committed bytes, so the exit code means something.

## The ledger

### 1. `scripts/sql/phase_d_d1_handler_registry_and_executor.sql`

| | |
|---|---|
| commit | `fb86840`, corrected in `ef1a9db` |
| routines | `fn_phase_d_slug`, `fn_phase_d_schema_validate`, `fn_phase_d_handler_execute`, `fn_phase_d_handler_state` |
| tables | `phase_d_handler_schema` (514 rows), `phase_d_handler_binding` (257 rows) |
| schema shape | `51d663a1e17cff35…` → `a614b87656ac929e…` |
| dry run | guards passed; 4 routines defined, 5 called and all present |
| rehearsal | read-only derivation on production before writing: 257 steps → 257 input schemas, 0 with no parseable input, keys 1–4 per step, 21 capability-dependent, 0 duplicate handler ids |
| verified | read back identical; board `fn_phase_d_handler_state()` 6/6; **executed** end to end in an aborted transaction (W01 run 5151, step run 5195) |
| rollback | `drop function public.fn_phase_d_handler_execute(jsonb), public.fn_phase_d_schema_validate(text,jsonb), public.fn_phase_d_handler_state(), public.fn_phase_d_slug(text); drop table public.phase_d_handler_binding, public.phase_d_handler_schema;` — nothing outside Phase D reads either table, and no frozen object references them |

Applied more than once: the executor was corrected twice after apply (rule applicability, then the
retired-path literal in the board). Each re-apply was `--apply --ddl` and each read back identical.

### 2. `scripts/sql/phase_d_d3_rule_enforcement.sql`

| | |
|---|---|
| commit | `fb86840` |
| routines | `fn_phase_d_rule_applies`, `fn_phase_d_rule_check`, `fn_phase_d_rule_state` |
| tables | `phase_d_rule_enforcement` (54 rows) |
| schema shape | `a614b87656ac929e…` → `7c9c8a089e52808c…` |
| verified | read back identical; board `fn_phase_d_rule_state()` 3/4, the fourth red **by disclosure** (20 rules `OUTSTANDING`) and ratcheted in `kernel-boards.json` |
| rollback | `drop function public.fn_phase_d_rule_check(text,jsonb), public.fn_phase_d_rule_applies(text,text), public.fn_phase_d_rule_state(); drop table public.phase_d_rule_enforcement;` then remove the ratchet entry. `fn_phase_c_rule_check` is **untouched and still live**, so dropping these restores the prior behaviour exactly |

One re-apply widened the `enforcement_kind` check constraint. `create table if not exists` does not
reconcile a constraint on an existing table, so the file carries an explicit
`drop constraint if exists` / `add constraint` pair; without it the second run failed on the first
widened row.

### 3. `scripts/sql/phase_d_d0_auth_debt_discharged.sql`

| | |
|---|---|
| commit | `195cfb4` |
| routines | none |
| data | 2 `update`s to `public.phase_d_preflight_requirement` |
| schema shape | unchanged |
| verified | the file ends in a `do $assert$` that raises unless both rows reached `SATISFIED` with evidence, so it cannot commit having done nothing; read back after apply: both `SATISFIED` at `2026-08-18 14:56:00+00` |
| rollback | `update public.phase_d_preflight_requirement set status='OUTSTANDING', satisfied_at=null, evidence=null where requirement_id in ('D0-AUTH-001','D0-AUTH-002');` |

## Repository artefacts changed alongside the database

| file | why |
|---|---|
| `scripts/sql/MANIFEST.txt` | the three files above appended — a `scripts/sql` file the manifest does not list is a MANIFEST GAP and its live routines are production→repository drift |
| `docs/phase-c-final-kernel/CANONICAL_ROUTINE_MANIFEST.csv` | re-emitted from the engine (`--emit`), not hand-edited |
| `supabase/schema/full_schema.sql` | regenerated — the mirror said 550 tables and production holds 553 |
| `scripts/checks/kernel-boards.json` | one ratchet entry for the 20 outstanding rules, with owner, rule ids, and an instruction to **delete** it at 0 |

`scripts/checks/canonical_routine_manifest.mjs` is a **frozen Phase C subject** and was not edited.
To read a finding it counts but does not print, a copy was taken to the scratchpad and instrumented
there.

## Production must never be ahead of main

| | |
|---|---|
| branch | `feat/phase-d-d1-d3-handler-registry-and-rules` |
| pull request | [#446](https://github.com/ahmadmhdnabilalzain-bot/quotesdone/pull/446) |
| commits | `fb86840`, `195cfb4`, `a8bda15`, `ef1a9db` |

Everything applied to production is committed and pushed on that branch. **Until #446 merges,
`main` legitimately does not contain these definitions**, and a parity gate run against `main`
would report drift for that reason alone — that window is expected, self-resolving on merge, and
must not be "fixed" by re-applying anything.

## Nothing was left behind

| | |
|---|---|
| workflow runs from probes | **0** (`business_object_id like 'PD-PROBE%'`) |
| canary auth identities | **0** (`auth.users` where email like `zz-phase-d-canary%`) |
| business rows created | **0** |

Every write probe ended in `raise exception`. The one identity created was deleted in the same run
and its removal proved by read-back, not inferred from the delete status.

## Frozen state, before and after

| | before | after |
|---|---|---|
| Phase A baseline drift | 0 | **0** |
| Phase B baseline drift | 0 | **0** |
| `fn_phase_c_freeze_drift()` red | 0 of 3 | **0 of 3** |
| `fn_phase_c_invariants()` red | 0 | **0** |

No frozen Phase A, Phase B or Phase C object was edited by any increment in this ledger.
