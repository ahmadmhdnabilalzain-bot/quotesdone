# Phase C — Production Deployment

**One project: `htdblwldjkcgjvmqkbeh`.** There is no staging. Deployed 15 Aug 2026.

## The sequence that was actually followed

| # | step | result |
| --- | --- | --- |
| 1 | verify `main`, clean tracked tree, Phase A/B baselines | HEAD `3adedb8`, one pre-existing modified file left alone |
| 2 | read-only production inventory and fingerprint | 1,799 components; digest `17c3757a…` |
| 3 | reconcile current code into the Phase C templates | 10 CSVs generated from measurement |
| 4 | build additive/compatible changes locally | 19 migration files, additive only |
| 5 | run source, type, SQL, contract and network-denial tests locally | `deno check os_api` clean |
| 6 | commit migrations, rollback, evidence and checksums | commit `03645fe` |
| 7 | **commit before production** | done |
| 8 | rehearse the exact committed SQL in an aborted transaction | 58/58 invariants held; fingerprint unchanged |
| 9 | verify source hashes and rollback versions before deploying | os_api v58 → v59 |
| 10 | deploy database first, then runtime callers | database, then `os_api` |
| 11 | re-run every Phase A, Phase B and Phase C invariant | all pass |
| 12 | compare repo / deployed / database fingerprints | 408/408 routines, 202/202 functions, schema byte-identical |
| 13 | roll back on any mandatory invariant failure | not needed |
| 14 | stop before Phase D | stopped |

## Pre and post fingerprint

The rehearsal proves the file did not commit; the fingerprint proves production did not move
across it.

```text
before: {"org_roles":180,"org_role_aliases":237,"org_dept_aliases":25,"org_departments":32,
         "phase_a_drift":0,"phase_b_drift":0,"cron_jobs":205,"cron_active":186,
         "llm_routes_held":8,"ai_cost_rows":3507,"phase_c_tables":0,
         "public_functions":1004,"public_triggers":189}
digest: 17c3757a6db4143a09d2fff03e7973df78e901316235e0bce57d9a9ea0ba3e2f

after the aborted rehearsal: identical digest
```

After the real deployment, measured:

| | before | after |
| --- | --- | --- |
| `org_role_alias` | 237 | **324** |
| `org_department_alias` | 25 | **34** |
| `phase_c_*` tables | 0 | **29** (+ 11 `founder_command*` = 40 new tables) |
| routines in `public` | 1,004 | **1,050** |
| triggers in `public` | 189 | **200** (11 new Phase C guards; none removed) |
| cron jobs | 205 | **205** |
| cron jobs active | 186 | **186** |
| provider routes held | 8 | **8** |

## What was deployed

19 migration files, applied in dependency order. `apply_sql.mjs` refuses a file whose bindings name
a routine that is not deployed yet, and it caught two real ordering mistakes on the way in:

- `phase_c_02` depends on `fn_phase_c_reviewer_independent` from `phase_c_03`;
- the seven binding files depend on `phase_c_08`.

The order that applied cleanly, and which `scripts/phase_c/rehearse.mjs` now uses so the rehearsal
and the deployment agree:

```text
01_identity_and_registry_schema      2 routines + DDL
03_runtime_core                     15 routines + DDL
02_authority_and_founder_boundary     5 routines + DDL
04_command_center                    7 routines + DDL
08_runtime_writers                  13 routines + DDL
09_invariants                        2 routines + DDL
05_registry_load                     data: actors, policies, action classes, intents, states, rules
06_components_part01..04             1,799 components
07_binding_01..08                    90 · 86 · 30 · 257 · 161 · 347 · 32 · 54
10_command_overlay_and_raise_fixes   3 routines
11_handoff_sla_alias_fix             1 routine
12_step_gate_scope_fix               2 routines
13_step_attempt_no_fix               1 routine
14_command_center_entry_point        1 routine + gate registration
15_cancel_writes_trace_and_selftest_cleanup  1 routine + one targeted delete
```

Each `--apply` reads the routine definition **back out of the database** and compares it to the
file. That read-back is what makes the exit code mean something; a POST returning 200 is not
evidence.

Files were split so none exceeds 294 KB — the largest this repo has previously applied in one
POST. A 1.6 MB single statement is the shape that half-applies and leaves the database in a state
no file describes.

## Edge function

`os_api` v58 → **v59**, `verify_jwt=false` unchanged. Four Command Center actions added, registered
in both gates in the same change. `deno check` clean. Deployed bundle verified against the repo.

Rollback: redeploy v58, and the four actions become `action_classification_required` refusals
rather than silent failures — the function fails closed on an unclassified action by design.

## Rollback

Every Phase C object is **additive**. Nothing pre-existing was dropped, renamed or altered except:

| change | reversal |
| --- | --- |
| 96 alias rows in `org_role_alias` / `org_department_alias` | delete by `reason like 'Phase C%'` |
| INSERT trigger on `founder_release_approval` | `drop trigger z10_phase_c_no_new_release_approval` |
| INSERT trigger on `procurement_approval_request` | `drop trigger z10_phase_c_no_new_procurement_approval` |
| 4 rows in `control_mode_action` | delete where `action like 'founder_command%'` |
| `os_api` v59 | redeploy v58 |

`scripts/sql/phase_c_ROLLBACK.sql` carries the exact statements.

**No Phase A or Phase B row was written.** `z90_phase_a_freeze` and `z90_phase_b_freeze` were never
challenged, and `app.phase_a_change_reason` / `app.phase_b_change_reason` were never set — neither
string appears anywhere in the Phase C tree.

## Activation states

**Nothing was enabled or disabled.**

cron jobs 205 → 205, active 186 → 186, provider routes held 8 → 8. The 11 new triggers in `public`
are all Phase C guards on Phase C tables plus the two INSERT refusals on the pre-existing approval
tables; nothing existing was disabled or removed.

The 18 deliberately deactivated cron jobs that had run before — one 21,563 times, all stopped
2026-08-02 — are classified `INACTIVE_HISTORICAL` and left off. Phase C does not re-enable business
automation because it has now been mapped.

## Parity

| check | result |
| --- | --- |
| `scripts/checks/sql_files_match_live.test.mjs` | 408 routines · 0 missing · **0 drifted** |
| `scripts/checks/export_from_either_source_is_identical.mjs` | **byte-identical** |
| `node scripts/verify_deploy_parity.mjs --all` | **DEPLOY PARITY OK — 202 functions** |
| `fn_os_portals_gates()` | **23/23 met** |
| `fn_phase_a_baseline_drift()` | **0 rows** |
| `fn_phase_b_baseline_drift()` | **0 rows** |
| `fn_phase_c_baseline_drift()` | **0 rows** |

Two of those needed work and it is worth saying which.

**The drift check reported a false positive, and the check was fixed, not the code.**
`fn_phase_c_step_advance` is defined in both `phase_c_12` and `phase_c_13`, committed together.
The check ranked files by their line number in `git log`, which orders files *within* one commit by
git's own listing, so `phase_c_12` came out "newer" than the file that supersedes it. Ranking is
now by **commit**, and where two files in one commit define the same routine the check keeps **both
candidates** and accepts live if it matches either — because which was applied last is not a fact
git records, and guessing it is what produced the false positive. Two legacy pairs benefit from the
same change. Drift is still drift: if live matches neither candidate, both are named.

**The schema mirror was stale before this session and is now current.**
`supabase/schema/full_schema.sql` showed 459 tables against 518 live. Regenerated from live and
byte-identical. The 48 embedded project refs the check also reports are **pre-existing** — they sit
in cron and trigger bodies as full `https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/…` URLs.
Phase C did not introduce them and did not parameterise them; that is a real portability finding
and it is recorded here rather than quietly absorbed.

## Four functions that remain UNVERIFIED

`auth_api`, `dev_login`, `qa_login`, `src_io` yield no distinctive string signature, so deploy
parity cannot confirm they carry the repo's code. They are **UNVERIFIED, not verified** — this is
Phase B wiring gap #7 and it is unchanged. Adding a distinctive literal to each would close it and
is a one-line change per function; it was not made because touching four auth-adjacent functions to
satisfy a checker is a change with more risk than the finding.

## No persistent synthetic records

```text
founder_command 0 · founder_command_message 0 · phase_c_task 0 · founder_approval_request 0
phase_c_workflow_run 0 · phase_c_workflow_step_run 0 · phase_c_handoff_run 0
phase_c_event_outbox 0 · phase_c_trace 0
```

One artefact was created and removed, and it is recorded rather than quietly cleaned. An earlier
version of the entry-point test committed a real command to prove the path had run, then could not
delete it: `founder_command_message` is append-only and the trigger refused. The guard is correct
and was not weakened. The deeper problem was that the harness had put an instruction in the
founder's inbox that he never gave. `scripts/sql/phase_c_15_…` removes that one row by name, with
the reason in the file and the trigger dropped and recreated in the same file, and the test now
runs inside an aborted transaction so no future run can create another.
