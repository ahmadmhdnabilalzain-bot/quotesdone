# Phase C → Phase D Handoff

Phase C connected and classified the runtime. **It did not prove the business calculations or the
user journeys correct**, and this document is the list of what it deliberately left.

Measured on `htdblwldjkcgjvmqkbeh`, 15 Aug 2026. **Two door lists corrected 17 Aug 2026** after the
independent final acceptance found this document naming four retired entry points; the inheritance
counts below were re-measured the same day and `137 of 257` deferred steps and `71 of 90` roles
with no execution are both unchanged.

## What Phase D inherits

Every item below already has an **accountable canonical owner**, a **safe entry boundary** that
refuses an unauthorised or out-of-order call, and **no active bypass**. That is the difference
between a gap and a hole: none of these can be reached around.

### 1. 137 of 257 steps are `DEFERRED_RUNTIME_IMPLEMENTATION`

The canonical boundary is the only way in and it enforces ownership, gates, authority, reviewer
independence and output validity. What is missing per step is the **business handler that produces
the step's required output**.

> **CORRECTED 17 Aug 2026.** This sentence named `fn_phase_c_step_advance`. That routine has been
> `DISABLED` in `public.kernel_retired_path` since the kernel cutover on 16 Aug — it derived
> successors from `phase_b_handoff` alone, so a step with a real `next_step_if_pass` and no edge
> returned terminal success and stopped the chain. **The boundary is now `fn_kernel_step_complete`.**
> A handler written against the name in the original sentence would be written against a door that
> is shut.

Four workflows have every step deferred:

| workflow | steps | deferred | note |
| --- | --- | --- | --- |
| W03 customer acquisition | 9 | **9** | |
| W08 supplier-safe payload and file approval | 8 | **8** | the privacy boundary; needs its own correctness pass |
| W21 strategic partnership development | 8 | **8** | Phase B wiring gap #5 — had no runtime implementation at all |
| W22 product discovery to delivery | 7 | **7** | |

The rest range from 1 of 9 (W15, W16) to 8 of 10 (W27).
`select * from public.phase_c_step_binding where connection_status = 'DEFERRED_RUNTIME_IMPLEMENTATION'`
lists all 137 with their owner and the exact missing piece.

### 2. 12 of 19 runtime workflow definitions have never executed

`budget_cycle`, `campaign_publishing`, `change_deployment`, `complaint`, `contract_review`,
`incident_response`, `invoice_approval`, `lead_to_customer`, `payment`, `refund`, `rfq_handling`,
`supplier_suspension`.

`rfq_handling` is the marketplace itself: 18 steps, every one gated, 20 assigned employees,
**0 runs**. Phase C gives it an owner and a boundary. It does not claim it works.

### 3. 286 components with no caller

208 database routines and 78 edge functions that nothing in the repository, database, cron, another
routine or the frontend names. Each is owned and traced; **wiring or retirement is a Phase D
decision** with the evidence attached. Phase C deleted nothing.

The reachability facts are kept separate rather than collapsed — `internal_caller`,
`external_product_entry`, `unauthenticated_only`, `none` — because "reachable without a JWT" is not
"is a product entry surface", and treating them as one is how this number becomes whatever you want
it to be.

### 4. 19 inactive components

18 cron jobs that had run before — one 21,563 times — all switched off on 2026-08-02, classified
`INACTIVE_HISTORICAL`. One switched off having never run, `REPAIR_BEFORE_REACTIVATION`.

**Phase C did not re-enable any of them**, and Phase D should not either without deciding
deliberately why each was switched off.

### 5. 71 of 90 roles have never executed a run

`agent_runs` shows no execution for 71 canonical roles. Their bindings are complete — resolver,
task receiver, authority, review, knowledge scope, tool policy, trace policy — and nothing has
run through them.

### 6. Four functions that cannot be verified

`auth_api`, `dev_login`, `qa_login`, `src_io` yield no distinctive string signature, so deploy
parity reports them **UNVERIFIED, not verified**. Phase B wiring gap #7, unchanged. One
distinctive literal per function closes it.

### 7. 48 project refs embedded in the schema

`https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/…` appears literally in cron and trigger
bodies. Pre-existing; Phase C neither introduced nor parameterised them. An export that names the
project it came from is not portable.

### 8. Historical trace coverage

`public.decision_trace` holds 28 rows from before Phase C, with `v_decision_trace_incomplete`,
`v_executions_without_decision_trace` and `v_approval_trace` beside it. Phase C did not backfill
them and makes no claim about them. The Phase C populations have a hard zero; the historical ones
do not.

### 9. Per-component trace execution

All 1,117 active state-changing components carry a trace policy. That is a **binding**, not a
measurement that each one wrote a trace the last time it ran. Proving that per component is Phase D.

## What Phase D may not do

- Change Phase A organization or Phase B workflows. Both freezes are live and were never
  challenged: `app.phase_a_change_reason` and `app.phase_b_change_reason` appear nowhere in the
  Phase C tree. A genuine need is a formal change request with evidence, brought to the founder.
- Bypass the Phase C runtime boundary. **CORRECTED 17 Aug 2026 — this list named five routines and
  four of them are no longer doors.** `fn_phase_c_step_advance` is `DISABLED`;
  `fn_phase_c_task_create`, `fn_phase_c_handoff_open` and `fn_phase_c_outbox_emit` are
  `KERNEL_INTERNAL_PRIMITIVE` and no ordinary role holds `EXECUTE` on any of them. Only
  `fn_founder_command_submit` survived the cutover. Do not read a door out of this document:
  **derive it**, the way `kernel_positive_controls.test.mjs` does —

  ```sql
  select distinct a.routine_name
    from public.kernel_write_authority a
   where not exists (select 1 from public.kernel_retired_path p where p.path_name = a.routine_name)
   order by 1;
  ```

  Thirteen doors on 17 Aug 2026: `fn_founder_command_clarify`, `fn_founder_command_control`,
  `fn_founder_command_submit`, `fn_kernel_cancel`, `fn_kernel_handoff_accept`,
  `fn_kernel_open_step`, `fn_kernel_outbox_deliver`, `fn_kernel_outbox_emit`,
  `fn_kernel_review_decide`, `fn_kernel_signal_submit`, `fn_kernel_step_complete`,
  `fn_kernel_trigger_submit`, `fn_kernel_workflow_start`. A new writer beside them is a duplicate
  path, and the crosswalk has a classification for that.
- Create a non-refund founder approval queue. Four guards refuse it and a fifth refuses a second
  founder-approval action class.
- Re-enable disabled automation because it is now mapped.

## The Phase D work list, from the contract

Phase D uses the Phase C bindings to run zero-cost deterministic correctness checks for: schema,
constraints and migrations · RLS and ownership · API validation · canonical state transitions ·
dispatch, notification and quotation idempotency · privacy masking and redaction · legal and
financial calculations · refund state correctness without live money movement · tool adapter mocks
and recorded fixtures · command centre edge cases · frontend and API contract behaviour · cron and
event retry and failure behaviour · rollback and compensation · all known audit defects.

## Two lessons worth carrying forward

**Deploying a routine is not running it.** The aborted-transaction rehearsal passed 58/58
invariants and missed five defects, including one that made every canonical step advance impossible.
A rehearsal creates routines and counts rows. It never advances a step, opens a handoff or cancels
a command. Phase D's checks should execute the paths, not assert their existence.

**A guard that refuses your own code is the guard working.** Four of the six defects were found
because a Phase C guard refused a Phase C write: the overlay-ownership trigger, the gate evaluator
failing closed on an unknown id, the NOT NULL on `attempt_no`, and the trace invariant counting 4.
In each case the first instinct — that the guard was too strict — was wrong.
