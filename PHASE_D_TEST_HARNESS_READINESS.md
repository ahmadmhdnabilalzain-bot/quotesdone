# Phase D test-harness readiness — independent assessment

**Verdict: PHASE_D_TEST_HARNESS_NOT_READY**

Audit started 2026-08-18 04:23 UTC. Commit `301ecb04c224866823b50f0e20cd22be997e5905`, branch `main`,
project `htdblwldjkcgjvmqkbeh`. Read-only: no repository code, database definition, expected result or
test expectation was changed.

## The run

One run of the repository's whole test command, under
`NO_PAID_AI=true OPENROUTER_DISABLED=true AI_PROVIDER_MODE=mock PHASE_D_EXTERNAL_EFFECT_MODE=mock`:

```
node scripts/checks/run.mjs
```

| | |
|---|---|
| node tests | 288 total, 280 pass, **8 fail** |
| deno tests | 16 total, 16 pass, 0 fail |
| duration | 288 s |
| exit code | **1** |

Every one of the 8 failures was re-run in its own process, one file at a time, and every one
reproduced with the same assertion. None was a 429. `MANAGEMENT_API_RATE_LIMIT = 0` for this run —
that is a measurement of this run, not a claim that the harness bounds concurrency.

## Failure classification

Categories are disjoint and sum to the total.

| primary cause | count |
|---|---|
| ROW3_BACKLOG | 3 |
| TEST_SETUP_DEFECT | 2 |
| KNOWLEDGE_PHASE | 2 |
| PHASE_C_RUNTIME | 1 |
| DELETED_STAGING_REFERENCE | 0 |
| MANAGEMENT_API_RATE_LIMIT | 0 |
| PHASE_A_OR_B_REGRESSION | 0 |
| PRODUCT_DEFECT | 0 |
| OTHER_WITH_EXPLANATION | 0 |
| **total** | **8** |

Per-test detail is in `PHASE_D_TEST_FAILURE_CLASSIFICATION.csv`.

## The eight readiness criteria

**1. No active test references the deleted staging project — MET.**
`pglpqrhvozwepymcuunn` appears in five files under `scripts/`. Four are comments recording that the
project was deleted (`artifact_review_alias_cannot_self_approve.test.mjs:32`, `run.mjs:64`,
`runtime_connection_gate_a.mjs:20`, `v3_remediation_regression.mjs:27`). The fifth,
`export_from_either_source_is_identical.mjs:101,104`, is live code, but the string is only used to
count and print project refs embedded in a schema export — it is never a request target. No test
issues a request to the deleted project.

**2. Management API concurrency bounded, 429s do not create false product failures — NOT MET.**
No throttling occurred in this run and all 8 failures reproduced individually, so no false product
failure was produced today. But the bound is not in the harness: `scripts/apply_sql.mjs` carries a
seven-attempt backoff and the check files do not share it. The suite's protection against the
recorded 429 failure mode is that it happened not to be throttled. That is a condition, not a
mechanism.

**3. No nested stale repository tree — MET.**
No directory carrying its own `.git` exists inside the working tree; the 159 MB `$WT/` copy found by
the previous acceptance was removed in commit `0bf8d5c`. `run.mjs` now skips any directory with its
own `.git`, so a reintroduction would be excluded rather than silently scanned.

**4. Phase A, effective Phase B and Phase C-specific tests pass — NOT MET.**
Phase A drift is 0 and Phase B drift is 0, measured directly. But three failures
(`org_reorg_behaviour` twice, `workflow_ownership_alignment` once) come from
`fn_org_role_violations()` returning the four items — `no_kpi`, `no_knowledge`, `no_authority`,
`no_tools`, all for `product_ux_designer` — that `org_phase_baseline` records as **deferred** for
Phase A, with the note that they are not Phase A defects and must not be hidden. The tests do not
know about the deferral, so the criterion as written is not met even though nothing has regressed.

**5. No unresolved Phase C runtime or evidence test failure — NOT MET.**
`every_executor_kind_has_a_runner` fails because `fn_action_invoke_rpc` has no active cron entry,
and the three `action_invoke_*` jobs are `active=false` — which is the Phase C automation hold that
Gate 17 requires to stay in force. The test asserts the opposite of the state Phase C holds. Nothing
owns or excludes it.

Separately, and worse for readiness: **six of the seven kernel state boards are read by no test and
no CI job**.

| board | read by a test | read by CI |
|---|---|---|
| `fn_kernel_trigger_state` | no | no |
| `fn_kernel_source_cutover_state` | no | no |
| `fn_kernel_signal_state` | no | no |
| `fn_kernel_retired_path_state` | no | no |
| `fn_kernel_trace_integrity` | no | no |
| `fn_kernel_historical_repair_state` | no | no |
| `fn_kernel_system_trace_state` | yes (1) | no |

Two of the unwatched boards are red on production right now (Gate 8/9 and Gate 12 in
`PHASE_C_FINAL_ACCEPTANCE_AUDIT.md`). A green `npm test` therefore does not mean the Phase C estate
is green, and a Phase D suite built on top of this harness would inherit that blind spot.

**6. Every later-phase test explicitly owned and excluded through a documented test profile — NOT MET.**
There is no test profile. Searching the repository for `TEST_PROFILE`, `QD_PROFILE`, a Phase D
profile, or any documented exclusion list returns nothing, and `docs/phase-c/PHASE_C_PHASE_D_HANDOFF.md`
contains no ownership or exclusion section. `run.mjs` discovers every `*.test.mjs` in the tree and
runs it; the only selection mechanism is the directory skip-list. The five later-phase failures
(3 ROW3_BACKLOG, 2 KNOWLEDGE_PHASE) are therefore not excluded — they are simply failing.

**7. Full failure counts reconcile arithmetically — MET.** 3 + 2 + 2 + 1 = 8 = the reported fail count.

**8. A dedicated Phase D zero-cost test command can run reliably — NOT MET.**
`package.json` defines exactly one test script, `npm test` → `node scripts/checks/run.mjs`, and it
exits 1. There is no zero-cost variant. The four zero-cost variables are **set** in
`.github/workflows/project-parity.yml` and in `scripts/phase_c/regenerate_builder_closure.mjs`, and
are **read** only by three edge functions (`ai_health`, `cost_snapshot`, `resend_inbound`). No Node
check reads them. Zero cost during this run was enforced by the database route hold, not by the test
command — which held, and is verified in `PHASE_C_FINAL_ZERO_COST_RESULT.md`, but means the
environment variables are labels on the run rather than a gate the harness applies.

## Conclusion

Three of the eight criteria are met (1, 3, 7). Five are not (2, 4, 5, 6, 8). The decisive ones are
**6** — no test profile exists at all, so later-phase tests are failing rather than owned — and **5**,
because the kernel boards a Phase D suite would need to trust are unread by any gate.

**PHASE_D_TEST_HARNESS_NOT_READY**
