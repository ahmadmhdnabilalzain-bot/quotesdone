# Phase C — Trace Coverage

Measured on `htdblwldjkcgjvmqkbeh`, 15 Aug 2026.

## The denominator problem, stated first

The master prompt says: *"Do not use a denominator that mixes unrelated execution populations."*

A trace-coverage percentage over "everything that ran" is meaningless — it puts a health probe and
a refund decision in the same fraction and lets one drown the other. Phase C therefore defines
**eleven trace-required populations**, each with its own required fields and its own answer to
"may this complete without a trace?".

| policy | scope | required | may complete untraced |
| --- | --- | --- | --- |
| `TRACE-FOUNDER-COMMAND` | every founder message that becomes or changes work | YES | no |
| `TRACE-WORKFLOW` | every workflow run and state transition | YES | no |
| `TRACE-STEP` | every required step execution or verdict | YES | no |
| `TRACE-TASK` | every command/workflow/management task lifecycle | YES | no |
| `TRACE-HANDOFF` | every owner-to-owner handoff | YES | no |
| `TRACE-CONSEQUENTIAL-DECISION` | external, financial, privacy, legal, supplier/customer, production, policy | YES | no |
| `TRACE-ROLE-ACTION` | non-consequential role work that changes state or creates an official output | YES | no |
| `TRACE-CATEGORY-ADVICE` | every category-overlay invocation | YES | no |
| `TRACE-TOOL` | every tool invocation | YES | no |
| `TRACE-SYSTEM-EXECUTION` | scheduled, webhook, queue, storage, provider-adapter execution | YES | no |
| `TRACE-MONITORING` | read-only health probes | COMPACT | **yes**, when healthy and aggregated |

Only the last one may be aggregated, and it is the only one that is read-only.

## Every component carries its policy

All 1,799 inventoried components carry a `trace_policy_id`, assigned from what the component is:

| component type | policy |
| --- | --- |
| cron job, edge function, database trigger, event subscription | `TRACE-SYSTEM-EXECUTION` |
| database function, frontend route | `TRACE-ROLE-ACTION` |
| state table, runtime workflow definition | `TRACE-WORKFLOW` |

The column is a foreign key into `phase_c_trace_policy`, so an unregistered policy cannot be
assigned.

## The trace itself

`public.phase_c_trace` carries the consequential-decision minimum from the contract: trace id;
command / task / run / step links; canonical actor and manager; system actor; component; evidence
refs; gates; rules; authority result; reviewer identity **and the independence result**; input and
output hashes; state before and after; event ids; status and timestamps.

`model`, `provider`, `input_tokens`, `output_tokens`, `cost_usd` exist and are **null** — the
schema supports later phases while paid inference is prohibited. That is the contract's own
allowance, not a shortcut.

### Sealed evidence is append-only

`z10_phase_c_trace_append_only` allows exactly one edit to a sealed row: setting `superseded_by`.
Every other change raises. Correcting a trace creates a **superseding row**; it does not rewrite
history.

Injected and refused: `update phase_c_trace set status = 'rewritten'` on a sealed row.

Injected and refused: writing a trace under an unregistered policy —
`fn_phase_c_trace_write('TRACE-INVENTED', …)` → *unknown trace policy*.

## Coverage on the Phase C fixtures

Every fixture that is a command, task, workflow, step, handoff, consequential action, overlay
invocation or state-changing system execution has its trace. Asserted as invariants, all returning
zero:

| invariant | result |
| --- | --- |
| completed trace-required command without trace | **0** |
| closed task without trace | **0** |
| completed step run without trace | **0** |
| handoff run without trace | **0** |

Each of those is a query over a real population, not a self-report.

### One of them was not zero

`closed_tasks_without_trace` returned **4**.

`fn_founder_command_control` cancelled child tasks with a bulk `UPDATE`, which bypasses
`fn_phase_c_task_transition` — the routine that writes `TRACE-TASK`. Four tasks were closed with
`trace_id` null.

The invariant was right and the code was wrong. A cancellation is a state change a manager has to
be able to explain later; it needs its trace exactly as much as a completion does. Cancellation and
supersession now iterate task by task, write one trace each, and record who cancelled it and why.

That is the check earning its place: it converted a silent gap into a fix rather than into
confidence.

## What writes a trace, and when

| event | policy | written by |
| --- | --- | --- |
| founder command submitted | `TRACE-FOUNDER-COMMAND` | `fn_founder_command_submit`, before it returns |
| task state change | `TRACE-TASK` | `fn_phase_c_task_transition` |
| task cancelled or superseded by the founder | `TRACE-TASK` | `fn_founder_command_control`, one per task |
| step advanced | `TRACE-STEP` | `fn_phase_c_step_advance`, sealed, with gates and authority |
| handoff opened / decided | `TRACE-HANDOFF` | `fn_phase_c_handoff_open` / `_decide` |
| category overlay invoked | `TRACE-CATEGORY-ADVICE` | `fn_phase_c_overlay_invoke` |

The step trace carries the **gates it actually evaluated** — every gate whose frozen
`workflow_scope` covers the step, with its pass result and reason — plus the founder boundary
sentence from `phase_b_workflow_step.founder_gate`. So the trace answers "which boundary applied
here?" from the record rather than from a reader's memory.

## Retrieval

`fn_founder_command_control(command_id, 'explain', target)` returns the recorded interpretation and
every trace attached to the command. It reads; it does not narrate. If no interpretation was
recorded it says so rather than inventing one.

`fn_founder_command_inbox` surfaces blocked tasks with their blocker and resolution owner, and
overdue handoffs with hours late, so a manager sees the trace-bearing exceptions without a query.

## What this did not measure

- **Historical coverage.** `public.decision_trace` holds 28 rows from before Phase C, with
  `v_decision_trace_incomplete`, `v_executions_without_decision_trace` and `v_approval_trace`
  beside it. Phase C did not backfill them and does not claim they are complete. The Phase C
  populations above are the ones with a hard zero.
- **Coverage of the 1,117 active state-changing components at runtime.** Each carries a trace
  policy; that is a binding, not a measurement that each one wrote a trace the last time it ran.
  Proving that per component is Phase D correctness work, and it is named as such in the handoff.
