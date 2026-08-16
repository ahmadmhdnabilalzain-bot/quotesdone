# Phase C correction 6 — trace policy and coverage

**Migration:** `scripts/sql/phase_c_36_trace_policy_and_invariants.sql`

## What the audit measured

12 of 12 tasks, 3 of 3 workflow runs and 3 of 3 outbox rows had no trace, while the invariant board
reported **58/58 green**. Four trace checks were computed over tables holding **zero rows**:
`closed_tasks_without_trace` (no task had ever closed), `completed_step_runs_without_trace`,
`handoff_runs_without_trace`, `completed_commands_without_trace`. A zero numerator over a zero
denominator is not coverage, and it is indistinguishable from a dead guard.

## trace_required, by execution type

Ten of the eleven policies in `phase_c_trace_policy` are `trace_required = YES` with
`completed_without_trace_allowed = NO`, covering everything the brief lists: founder commands,
command plans, operational tasks, workflow runs, workflow-step runs, handoffs, review verdicts,
state-changing outbox deliveries, consequential decisions and externally visible actions.

One exemption was added, with its reason written where the exemption is granted:

| Policy | trace_required | Scope |
|---|---|---|
| `TRACE-MONITORING` | COMPACT | read-only health probes, aggregated |
| `TRACE-INFRASTRUCTURE` | **NOT_REQUIRED** | infrastructure-only execution that changes no business state and produces no official output: schema/DDL helpers, read-only exports, cache primers, and health probes already aggregated into `TRACE-MONITORING`. `completed_without_trace_allowed = YES_WITH_DOCUMENTED_REASON` |

## The vacuous invariants are gone

Every coverage check now reports **`<missing> of <required>`** and is `ok` only when the denominator
is above zero. `public.fn_phase_c_trace_coverage()` is the single place that answers
required / complete / incomplete / missing / excluded, so a report and a test can never disagree
about the denominator.

Eleven further checks were added — one for each thing the audit found that nothing could see:
`tasks_without_trace`, `workflow_runs_without_trace`, `outbox_rows_without_trace`,
`commands_ahead_of_their_trace`, `outbox_events_naming_another_workflow`,
`outbox_superseded_without_a_stated_reason`, `outbox_delivery_attempts_exist`,
`outbox_rows_stuck_pending_over_an_hour`, `outbox_dead_letter`,
`event_bindings_claiming_more_than_the_legs_support`, `active_state_changing_without_authority`,
`active_state_changing_without_trace_policy`, `clarification_required_has_an_exit`.

## Coverage after the canaries

| Subject | Policy | Required | Complete | Incomplete | Missing | Excluded | Reason for exclusion |
|---|---|---|---|---|---|---|---|
| `founder_command` | TRACE-FOUNDER-COMMAND | 7 | 7 | 0 | **0** | 0 | — |
| `phase_c_task` | TRACE-TASK | 27 | 27 | 0 | **0** | 0 | — |
| `phase_c_workflow_run` | TRACE-WORKFLOW | 7 | 7 | 0 | **0** | 0 | — |
| `phase_c_workflow_step_run` | TRACE-STEP | 7 | 1 | 0 | **0** | 6 | open step runs — the step has not produced a verdict yet |
| `phase_c_handoff_run` | TRACE-HANDOFF | 1 | 1 | 0 | **0** | 0 | — |
| `phase_c_event_outbox` | TRACE-SYSTEM-EXECUTION | 12 | 12 | 0 | **0** | 0 | — |
| `phase_c_event_delivery_attempt` | TRACE-SYSTEM-EXECUTION | 12 | 12 | 0 | **0** | 0 | — |

**Missing required traces: 0. Incomplete required traces: 0.** Every denominator is above zero.

`fn_phase_c_invariants()`: **71 checks, 71 passing.**
