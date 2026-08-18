# QuotesDone Phase C — final independent acceptance audit

**PHASE_C_FINAL_ACCEPTANCE_FAIL**

> **This document records the audit as taken, at commit `301ecb0`, and is deliberately not edited to
> reflect later repairs.** Gates 12 and 15, the PBCR-001 propagation defect under gate 1, the
> instrumentation finding F5, and the entire Phase D harness assessment were remediated on branch
> `fix/phase-c-four-gates` the same day — see `PHASE_C_REMEDIATION_RESULT.md` for what moved and what
> did not. Gates 8 and 9 remain open. One item below is **wrong** and is corrected there: the harness
> already bounded concurrency with `--test-concurrency=1`, so Phase D criterion 2 was met at the time
> of the audit and I recorded it as unmet.

Independent, read-only. I did not implement Phase C or any of its corrections. Nothing in the
repository, the database, production configuration, expected results, Phase A, Phase B, the Phase C
architecture or any test expectation was modified. Nothing was repaired. Phase D was not begun.

---

## Preflight record

| | |
|---|---|
| audit started | 2026-08-18 04:23:16 UTC (`select now() at time zone 'utc'`) |
| audit finished | 2026-08-18 ~04:52 UTC |
| branch | `main` |
| commit | `301ecb04c224866823b50f0e20cd22be997e5905` |
| latest Phase C PRs | #434, #435, #436 all merged into `main` |
| production project | `htdblwldjkcgjvmqkbeh` — the only project; staging `pglpqrhvozwepymcuunn` is deleted and is not read by any test |
| Postgres | 17.6.1.127, region ap-southeast-1, ACTIVE_HEALTHY |
| working tree | 40 untracked entries, **0 tracked modifications** — all 40 pre-date this session (skill directories, screenshots, scratch JSON, stray numeric filenames) |
| nested duplicate repository tree | **none** — no directory with its own `.git` inside the tree; `$WT/` was removed in `0bf8d5c` |
| Phase A drift | **0 rows** |
| Phase B drift | **0 rows** |
| Phase C runtime drift (`fn_phase_c_invariants`) | 71 checks, 71 ok |
| routine drift repo↔prod | 0 and 0, over 1015 canonical routines |
| component crosswalk | 1801 = 1801 = 1801 |
| provider hold | 8 of 8 OpenRouter routes held to 2126-08-15 under the founder's 15 Aug instruction |
| previous business automation | held — the three `action_invoke_*` crons are `active=false`; 23 of 206 cron jobs active, all through `fn_kernel_cron_exec` |
| external-effect paths | none reactivated; 0 notifications, 0 alerts, 0 sends during the window |
| paid inference | USD 0.00; `llm_attempt` 0 and `ai_cost_log` 0 since the Phase C start instant |

Canaries created: founder commands 1680 and 1681, both cancelled through the deployed
`founder_command_control` action. No deletion was used. All other writes were aborted-transaction
probes that ended in `raise exception`.

---

## Gate results

| gate | subject | verdict |
|---|---|---|
| 0 | preflight | PASS |
| 1 | frozen baselines | PASS |
| 2 | component crosswalk | PASS |
| 3 | one authoritative routine source of truth | PASS |
| 4 | founder authentication | PASS |
| 5 | one founder command, one business effect | PASS |
| 6 | command acceptance, CC-020 and founder chain | PASS |
| 7 | same-thread clarification and cancellation | PASS |
| **8** | **autonomous source inventory** | **FAIL** |
| **9** | **real autonomous new-work entry** | **FAIL** |
| 10 | existing-workflow signals | PASS |
| 11 | step engine and workflow closure | PASS |
| **12** | **kernel-only writes and legacy retirement** | **FAIL** |
| 13 | refund-only founder approval | PASS |
| 14 | trace and system-execution integrity | PASS |
| **15** | **event and outbox truth** | **FAIL** |
| 16 | guard contracts | PASS |
| 17 | component reachability and automation hold | PASS |
| 18 | zero-cost observation window | PASS |

Fourteen gates pass. Four do not. Per-gate measurement and evidence commands are in
`PHASE_C_FINAL_GATE_RESULTS.csv`; the canary, trace and zero-cost records are in their own files.

Phase C acceptance requires every gate to pass with no unexplained discrepancy, so the verdict is
**PHASE_C_FINAL_ACCEPTANCE_FAIL**.

---

## Findings

Each names the gate, the exact object, and the smallest responsible issue. None is repaired.

### F1 — 26 of 37 active autonomous sources still start business work without entering the kernel

**Gate 8 and Gate 9. Exact object: `public.fn_kernel_trigger_state()`, check
`active_autonomous_source_not_yet_routing_through_the_inbox`.**

```
expected  0 of 37 active autonomous sources — NOT MET BY K10
actual    26 of 37 active autonomous sources still start or change business work
          without entering the kernel. K10 builds the door and registers the routes;
          moving each source onto it is the wiring increment.
ok        false
```

Corroborated from the other direction by `public.fn_kernel_source_cutover_state()`:

```
active_sources_now_calling_a_kernel_adapter
  11 of 32 active class-A/B sources reach the kernel
  (database triggers only — an Edge Function has no prosrc to scan,
   and saying so beats pretending the scan covered it)
```

Gate 8 requires `active source bypassing kernel = 0`. The deployed check says 26, and its own
expectation string names the shortfall — *NOT MET BY K10*. Gate 9 asks for the universal path
source → adapter → trigger inbox → kernel → run → step run → task; that path is correct where it is
wired (`fn_kernel_trigger_submit` calls `fn_kernel_workflow_start`; 0 routines create work from the
inbox without it; 18 routines call `fn_kernel_source_emit`; the wrapper never reaches past its two
adapters), but it is the path for 11 of 32, not for all.

**Smallest responsible issue:** the K10 increment built and registered the door; the per-source
wiring increment that moves the remaining sources onto it has not been done, and Phase C closure was
declared without it.

### F2 — one overloaded CONNECTED label: 274 of 287 bindings have never been observed at runtime

**Gate 15. Exact object: `public.phase_c_event_binding`, column `connection_status`.**

The table has twelve columns and exactly one status column. There is no runtime-observation status.
Measured by joining each binding to the outbox and to the delivery-attempt log:

| `connection_status` | bindings | ever produced an outbox row | ever produced a delivery attempt |
|---|---|---|---|
| `CONNECTED` | **287** | **13** | **13** |
| `DEFERRED_RUNTIME_IMPLEMENTATION` | 60 | 1 | 1 |

287 + 60 = 347, matching the frozen event count. **274 bindings carry the CONNECTED label and have
never been observed to run.** One binding labelled deferred has run, so the mislabelling goes both
ways.

Gate 15 states the requirement directly: *"Event status must distinguish structural status and
runtime-observation status. Do not accept one overloaded CONNECTED label."* The structural invariant
`event_bindings_claiming_more_than_the_legs_support` is green at 0, but it checks producer, consumer
and worker *legs* — structure. It cannot distinguish wired from observed, and nothing else does.

**Smallest responsible issue:** `phase_c_event_binding` needs a second column recording runtime
observation, and `CONNECTED` needs to mean structurally wired only. A registry-only event is
currently presented under the same word as a runtime-observed one.

### F3 — a red kernel board with a prefix-matching false positive, watched by nothing

**Gate 12. Exact object: `public.fn_kernel_retired_path_state()`, check
`kernel_primitives_called_from_outside_the_kernel`.**

```
expected  0
actual    1 of 9
ok        false
```

The one row is:

| kernel primitive | reported external caller |
|---|---|
| `fn_phase_c_task_transition` | `fn_phase_c_task_state_guard` |

The check matches with `p.prosrc like '%' || r.path_name || '%'`. `fn_phase_c_task_state_guard` is a
trigger guard whose body — read in full — calls `fn_phase_c_task_transition_allowed`,
`fn_phase_c_actor_may_own` and `fn_phase_c_reviewer_independent`, and never calls
`fn_phase_c_task_transition`. The match is the primitive's name occurring as a **prefix** of a
different, longer function name.

So the runtime is correct and the board is wrong. But Gate 12's required result is 0, the deployed
board reports 1 with `ok=false`, and the number is carried into no evidence document that corrects
it. The `like` predicate needs a word boundary.

### F4 — PBCR-001 was applied to Phase B and not to the Phase C runtime bindings

**Gate 1, surfacing in Gate 15. Exact objects: `public.phase_c_handoff_binding` rows
`H-W14-04-05` and `H-W14-05-06`, and the literal `161` inside `public.fn_phase_c_invariants()`.**

PBCR-001 (17 Aug 2026) moved W14-S05 accountability from `relevant_category_overlay` to
`quote_evaluation` and **deleted** two handoffs because both ends became the same role. Handoffs went
161 → 159. `phase_b_handoff` holds 159. Measured:

```
phase_b_handoff rows                         159
phase_c_handoff_binding rows                 161
bindings with no matching phase_b_handoff      2   H-W14-04-05, H-W14-05-06
```

Both orphans are `connection_status = CONNECTED`, and both name `relevant_category_overlay` as
sending or receiving role — the exact authority PBCR-001 removed.

The invariant that should have caught this instead confirms it:

```
check_name  handoffs_bound
expected    161
actual      161
ok          true
```

The pre-amendment number is typed into the check as its own expectation, so it reports green against
a Phase B that now says 159.

**Severity, measured rather than assumed.** `fn_phase_c_handoff_open` reads `phase_b_handoff` as the
authority. Driven in an aborted transaction:

```
fn_phase_c_handoff_open(1,'H-W14-04-05',…)  ->  {"ok": false, "error": "unknown_handoff"}
fn_phase_c_handoff_open(1,'H-W14-05-06',…)  ->  {"ok": false, "error": "unknown_handoff"}
```

Neither orphan can fire. This is a registry-truth defect, not an execution defect — but it is exactly
the class Gate 15 asks about, two rows saying CONNECTED for something that cannot connect.

### F5 — six of the seven kernel boards are read by no test and no CI job

**Cross-cutting; it is why F1, F3 and the red rows in `fn_kernel_trace_integrity` survived a green
suite and a green closure document.**

| board | read by a test | read by CI | red rows now |
|---|---|---|---|
| `fn_kernel_trigger_state` | no | no | **1** (F1) |
| `fn_kernel_retired_path_state` | no | no | **1** (F3) |
| `fn_kernel_trace_integrity` | no | no | 5 (all accounted for as historical or unobservable — see the trace record) |
| `fn_kernel_source_cutover_state` | no | no | 0 |
| `fn_kernel_signal_state` | no | no | 0 |
| `fn_kernel_historical_repair_state` | no | no | 0 |
| `fn_kernel_system_trace_state` | yes (1 file) | no | 0 |

`node scripts/checks/run.mjs` ran 288 node tests and 16 deno tests and did not read any of the six.
`PHASE_C_BUILDER_CLOSURE.md` generates 15 headlines from five invariant suites, the crosswalk, the
routine engine, the Command Center and the guards — and none of the 15 reads them either. Its
"headlines FAILED **0**" is truthful about what it measured and silent about the boards that are red.

**Smallest responsible issue:** no gate reads the kernel state functions, so a red kernel board
cannot block a merge or fail an acceptance run.

---

## Generated closure evidence

`docs/phase-c-kernel/PHASE_C_BUILDER_CLOSURE.md` was verified against production at this commit.

**What is sound.** It is machine-generated with the generator named at the top, and it says so. Every
headline carries a command, a numerator, a denominator, an environment and a measurement type. There
are 0 headlines shown as CREDENTIAL_BLOCKED, and the document states in words that a
CREDENTIAL_BLOCKED headline is not a pass and is not folded into one. The positive-control
denominator is derived, not declared, and the derivation is cross-referenced. The "what this document
does not claim" section correctly disclaims independence, reactivation and paid inference. The
crosswalk headline (1801/1801, 0 findings), the Command Center headlines (30, 20/20) and the guard
headlines all reproduce exactly.

**Where it is not current.** Three items:

1. **It is stamped at a different commit.** The header reads
   `commit d15a03a57a59069bef2a84a5e8073b7168db5e43`, branch
   `fix/phase-c-independent-acceptance-six`. `main` is now `301ecb0`, **ten commits ahead**, including
   the merges of #434, #435 and #436. The document has not been regenerated since.
2. **The routine count is stale.** It reports `1014 canonical routines`. The same engine run at this
   commit reports **1015** (`canonical_routine_manifest.mjs --all`: 1534 files scanned, 1015 canonical).
   The count moved with the merged commits and the headline did not.
3. **The invariant headline is scoped narrower than its name.** "Phase C invariants — PASS — 17 checks"
   is generated from `phase_c_invariants.test.mjs`, while `fn_phase_c_invariants()` itself now returns
   71 checks. Both are green, so nothing is misreported, but "Phase C invariants" is 17 of 71.

None of these is a fabricated number, and none is a credential-blocked check shown as a pass. The
document's defect is staleness relative to `main` plus the coverage hole in F5 — it cannot fail on a
board it never reads.

---

## What was measured, and what was not

Stated so no verdict here is read wider than the evidence behind it.

**Driven by execution:** the founder HTTP authorization matrix (5 header modes × 7 actions, live);
one full founder command through the deployed Command Center, measured before and after the outbox
worker; a clarification round-trip through the same thread; two cancellations through the real
control action plus their replays; six signal handlers × four cases each; 55 injected defects; 13
positive controls; the kernel write guard in both directions; a forced two-file routine conflict; the
crosswalk with and without a management credential; a goal retirement; the paid-AI gate on an emptied
route table; both orphan handoff opens; and one real scheduled `ai_health` firing observed live.

**Measured by query, not driven:** the reachability, exposure, retirement, trace-integrity,
historical-repair and system-trace boards; the source inventory; the workflow graph for all 30.

**Not done, and not claimed:** W14 was not driven through W14-S05 to explicit closure — Gate 11
rests on graph validation for all 30 plus one runtime workflow (W20) driven to cancellation closure,
not on a W14 execution. The five representative execution classes were not each driven separately.
The five safe aborted system-execution cases (begin/finish, failed execution, duplicate idempotency
key, subject-insert failure, finish failure) were not driven as five probes; Gate 14 rests on the
live population and one real scheduled execution end to end.

Per the zero-cost rule: no V3 certification, no knowledge-agent certification, no knowledge-pack
scorecard, no paid-model test and no unrelated Row #3 backlog test was run by me. Three V3 tests and
three deferred-role tests appear in the full-suite run because `run.mjs` discovers every test file in
the tree and there is no profile to exclude them — that is itself recorded as Phase D readiness
criterion 6.

---

## Verdicts

**PHASE_C_FINAL_ACCEPTANCE_FAIL** — gates 8, 9, 12 and 15.

**PHASE_D_TEST_HARNESS_NOT_READY** — see `PHASE_D_TEST_HARNESS_READINESS.md`; five of the eight
readiness criteria are not met, the decisive ones being that no documented test profile exists at all
and that the kernel boards a Phase D suite would need to trust are read by no gate.

Do not begin Phase D.
