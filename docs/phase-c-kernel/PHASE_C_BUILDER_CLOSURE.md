# Phase C execution kernel — builder closure, 17 Aug 2026

Measured engineering completion only. No independent audit was run, no certification, no Phase D.
Every number below was read out of production `htdblwldjkcgjvmqkbeh` in the same session that
produced it.

---

## PHASE B AMENDMENT — met

| Required | Measured |
|---|---|
| W14-S05 owner: quote_evaluation_specialist | `accountable_role_id = quote_evaluation`, `package_accountable_token = quote_evaluation_specialist` |
| overlay is contributor, not owner | `contributors = {relevant_category_overlay, relevant_domain_specialist}`; `actor_kind = canonical_role`; `phase_b_dynamic_actor.relevant_category_overlay.may_be_accountable = false` |
| workflows without closure path | **0 of 30** |
| unresolved successor owners | **0** |
| overlay-owned tasks | **0** |

The founder's amendment names `quote_evaluation_specialist`. That is the *package token*; the
canonical Phase A `role_id` behind it is `quote_evaluation`, display name "Quote Evaluation
Specialist", which already owned the other eight W14 steps. No role was created — Phase A drift
stays 0 and the role count did not move.

Verified by **execution**, not by the validator liking the registry:

```
W14-S01 -> S02 -> S03 -> S04 -> S05 -> S06 -> S07 -> S08 -> S09   run state: completed
W14-S05 executed by quote_evaluation
```

Every handoff accepted with a complete packet; a real independent review recorded at W14-S08.

Record: `public.phase_b_change_request` row **PBCR-001** (append-only) and
`docs/phase-b/PBCR-001_W14_S05_ACCOUNTABILITY.md`. Baseline re-recorded through the route
`fn_org_phase_baseline_append_only` names in its own hint. **Phase A drift 0, Phase B drift 0.**

---

## SOURCE CUTOVER — partly met

**Classified: 67 of 67.** The brief says 52. No definition over this estate yields 52 —
41 live-and-creating-work, 43 with the founder command surfaces, 49 CONNECTED_ACTIVE, 51 with the
retired pair, 62 carrying an adapter, 482 inventoried. The register takes the strict superset of
all of them, so whatever population of 52 was meant is inside it.

`docs/phase-c-kernel/ACTIVE_SOURCE_CUTOVER_MATRIX.csv` — 67 rows, all 16 columns the brief names
plus the classification reason and the K10 evidence.

| Status | Count |
|---|---|
| CUTOVER_COMPLETE (trigger calls the kernel, verified against `pg_proc`) | 8 |
| CUTOVER_VIA_TABLE_TRIGGER (new trigger on contact_messages / pdpl_requests / documents) | 3 |
| COVERED_BY_A_CUT_OVER_TABLE_TRIGGER (writes inquiries/quotes/quote_items/transactions) | 8 |
| COVERED_BY_THE_EDGE_FUNCTION_IT_CALLS (frontend routes) | 5 |
| READ_ONLY_CONFIRMED (class C, writes no business-work table) | 14 |
| ADAPTER_ASSIGNED_SOURCE_STAYS_DISABLED (switched off, and stays off) | 13 |
| RECLASSIFIED_INTERNAL_RECOMPUTATION | 2 |
| RETIRED | 2 |
| **ADAPTER_ASSIGNED_CUTOVER_PENDING** | **4** |
| **NOT_YET_CUT_OVER** | **7** |
| **BLOCKED_NO_WORKFLOW_FOR_THIS_SIGNAL** | **1** |

**Twelve sources are not cut over, and they are named rather than rounded off:**

- `dbtrigger:public.inquiry_matches:notify_matched_supplier`
- `dbtrigger:public.notifications:trg_invite_status_on_send`
- `dbtrigger:public.supplier_dues:trg_due_paid`
- `edge:inquiry_intake`
- `edge:inbound_email`, `edge:resend_inbound`, `edge:sup_dob`, `edge:supplier_onboard`,
  `edge:site_assistant`, `edge:wa_inbound`, `edge:attach_photos` — these write `leads`,
  `inbound_messages` or `agent_actions`, and none of those tables carries a kernel route yet
- `dbtrigger:public.company_goals:trg_goal_cascade` — **blocked, not forgotten**. K10 mapped it to
  `kpi.company_target_miss` → W02. The deployed body fires on `old.active is true and new.active
  is false`: a goal being *retired*, which is not a missed target. Routing it to W02 would open a
  corrective-management run every time the founder tidies up a goal. It creates business work
  outside the kernel (an `org_tasks` re-plan row) and no Phase B workflow starts from a goal
  retirement, so it is recorded as owing a handler rather than forced into the nearest workflow.

**So: active sources bypassing the kernel is NOT 0.** It is 11 plus 1 blocked.

Nothing was activated. Thirteen sources carry an adapter and remain switched off.

---

## K13 — met

`fn_kernel_retired_path_state`: **0 failing of 5.** Old cron jobs invoking the old runtime 0;
direct grants permitting bypass 0; active callers of disabled paths 0; paths with no recorded
disposition 0; kernel primitives called from outside the kernel 0.

---

## WRITE CONTROL — met

`fn_kernel_write_guard_state`: **0 failing of 6.** Eight tables protected —
`phase_c_workflow_run`, `phase_c_workflow_step_run`, `phase_c_task`, `phase_c_handoff_run`,
`kernel_trigger_inbox`, `kernel_signal_inbox`, `phase_c_event_outbox`, `phase_c_refund_decision`.

The token is the **call stack**, read with `get diagnostics pg_context`, because a GUC is something
an untrusted caller can mint and a stack frame is not. Rehearsed: a direct insert is refused with
the stack in the error, the audited maintenance door works and records its reason, and the full
W14 walk completes through the guard.

Direct business writes outside kernel context accepted: **0**.

---

## TRACE — met, with history reported separately

- Active state-changing components without trace instrumentation: **0**
  (`docs/phase-c-kernel/SYSTEM_EXECUTION_TRACE_INSTRUMENTATION.csv`, 1,607 active/deployed
  components, 1,074 of which change business state). Proved structurally; no component was run
  merely to produce a trace.
- `fn_kernel_system_trace_state`: **0 failing of 13**
- `fn_kernel_trace_integrity`: current terminal objects with incomplete trace **0**; current active
  orphan traces **0**
- `fn_kernel_historical_register_state`: **0 failing of 9**

**Preserved historical exceptions, reported separately and never as compliance:**
HISTORICAL_STATE_TRACE_MISMATCH **22**, HISTORICAL_ORPHAN_TRACE **7**,
HISTORICAL_DUPLICATE_EFFECT **6**, VALID_HISTORICAL_RECORD **3**, retrofit entries **31**.

The brief says 4 state/trace mismatches; the measurement says 22. The measurement is reported.
Every exception now carries its original timestamp, the kernel cutover it is judged against,
whether any active effect remains (all false), and **why it cannot be reconstructed honestly**.
Historical exceptions dated after the kernel cutover: 0 of 38.

---

## COMMAND CENTER — met

`fn_kernel_founder_approval_state`: **0 failing of 5.** Founder approval classes are refund-only;
non-refund rows in the founder approval request 0; in `v_founder_inbox` 0; org_tasks newly routed
to the founder that are not refunds 0; refund decisions that are mutable 0.
Clarification real UI caller present, same command ID retained (K9/K2c, unchanged this session).

---

## COST — met

- OpenRouter HTTP requests: **0**
- Paid inference requests: **0**
- Paid inference cost: **USD 0.00** (`phase_c_invariants`: "paid inference cost since Phase C began
  is AED 0.00")
- No fallback provider key. `fn_kernel_paid_provider_state`: 0 failing of 5, all 8 provider routes
  held open-circuit.

---

## BASELINES — met

- `fn_phase_a_baseline_drift()`: **0 rows**
- `fn_phase_b_baseline_drift()`: **0 rows** after the approved CR and re-record
- All frozen changes went through the formal change request: PBCR-001, stated in the same
  transaction as `set local app.phase_b_change_reason`, recorded in an append-only table

---

## Defects found and fixed that were nobody's brief

| | |
|---|---|
| **K14** | `fn_kernel_workflow_start` created the entry step's *outgoing* handoff run at start time, and `fn_kernel_step_complete` created the same edge again on completion. Two open handoff runs on one edge, on **16 of 30 workflows**; the successor could never be opened. Never seen because no run had ever completed an entry step with an outgoing edge. Found by driving a run, not by any of the 25 watchers. |
| **K15** | Fifteen count expectations were literals inside `fn_phase_b_invariants`. After an approved amendment the only way to make it pass was to retype them — the person changing the architecture changing the number it is checked against. They now read the append-only baseline. |
| **K21** | `fn_page_high_agent_action` tested `NEW.agent IN ('finance_ai','security_ai','operations_ai')`, but `a00_agent_action_resolve_addressee` runs BEFORE it and rewrites `security_ai` to `security`. **Zero `agent_escalation` notifications exist in the entire history** — the founder has never once been paged for a high-risk security action, and nothing ever failed. |
| **K22c** | The class-C check measured "writes a sibling table", not "creates business work". |
| **K24** | A cron trace stamped 3 ms *before* cron's own `start_time` was read as no trace at all. The predicate was a timestamp window, not the relationship; it is now overlap plus job identity. |
| **K27** | `sql_files_match_live` extracted routine bodies with a dollar-tag pattern of `[a-z_]*` — **no digits**. Every kernel routine is tagged `$k2_start$`, `$k10_submit$`, `$s3_state$`. It matched none of them, silently skipped the definition, let an older file win, and reported drift against routines that were perfectly in step. It saw **488** routines; it now sees **510**. The estate's "repo matches live" check had been blind to the entire execution kernel. |

---

## What is NOT clean, stated plainly

1. **11 active sources still bypass the kernel**, plus 1 blocked with no workflow for its signal.
   Named above. This alone means the required "active sources bypassing kernel: 0" is not met.
2. **Row #3 scorer did not complete.** `verify_os2_blueprint.mjs` aborted twice with
   `transport failed after 7 attempts: TimeoutError` inside `ui_closure`. That is infrastructure,
   not a finding — and it is also not a pass. It was not run to completion, so nothing is claimed
   from it.
3. **Pack scorecard not run** this session.
4. **9 of 55 guard-injection cases assert on stale messages.** Every one of the nine defects is
   still refused — by a *newer, stricter* guard than the substring the test expects (e.g. the
   refund case is refused by `fn_phase_c_require_founder`, the transition case by
   `fn_kernel_workflow_run_trace_guard`, the step-advance case because `fn_phase_c_step_advance` is
   retired). Refusal count went 36 → 46 once the harness stopped being blocked by K18 itself; the
   remaining nine need their expected strings updated to the guard that actually fires. One case
   ("a delivery reported ok with NO downstream record") fails on `invalid input syntax for type
   timestamp with time zone: ""` — traced to the harness passing an empty string, not to
   `fn_phase_c_outbox_settle`, which uses a `case` expression and never casts `''`.
5. **`edge:inquiry_intake` writes `inquiry_intake` and `customers`, never `inquiries`.** The intake
   draft does not become an inquiry in that function, so nothing there starts W05 today.

---

## Estate sweep

| Check | Result |
|---|---|
| GitHub Actions, last 6 runs | all **success** (4 checks, 2 deploy edge functions) |
| `verify_deploy_parity.mjs --all` | **DEPLOY PARITY OK** — 202 functions carry the repo's current code |
| `sql_files_match_live.test.mjs` | **510 routines, 0 drifted, 0 missing** (was reporting 13 drifted; see K27) |
| `export_from_either_source_is_identical.mjs` | 0 project refs embedded in the export |
| `fn_os_portals_gates()` | 22 met, 1 not_met (pre-existing, unrelated to this session) |
| `kernel_invariants.test.mjs` | **PASS**, 1 unmeasured — reported, never scored |
| `phase_c_invariants.test.mjs` | **PASS**, paid inference AED 0.00 |
| `phase_b_invariants.test.mjs` | **77/77** |
| `phase_b_guards_reject_injected_defects` | **20/20 guards fired**, row counts unchanged |
| Row #3 scorer | **DID NOT COMPLETE** — transport timeout, twice. Not a pass. |

## Verdict

`PHASE_C_EXECUTION_KERNEL_NOT_READY` — on item 1 above, and only on it. Every other required
result in §11 is met and measured.
