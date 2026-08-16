# Phase C — decision-trace coverage (gate 13)

The gate: *trace-required executions; complete traces; missing traces; **required result must be zero
missing***.

## The policy being measured against

`public.phase_c_trace_policy` holds 11 policies. **Ten of the eleven** are `trace_required = YES` with
`completed_without_trace_allowed = NO`. Only `TRACE-MONITORING` (read-only health probes) is relaxed, and only
`YES_WHEN_HEALTHY_AND_AGGREGATED`.

| Policy | Scope | Required |
|---|---|---|
| TRACE-FOUNDER-COMMAND | every founder command/message that becomes or changes work | YES / NO |
| TRACE-WORKFLOW | every workflow run and workflow state transition | YES / NO |
| TRACE-STEP | every required step execution or verdict | YES / NO |
| TRACE-TASK | every command, workflow or management task lifecycle | YES / NO |
| TRACE-HANDOFF | every owner-to-owner handoff | YES / NO |
| TRACE-CONSEQUENTIAL-DECISION | external, financial, privacy, legal, supplier/customer, production or policy decisions | YES / NO |
| TRACE-ROLE-ACTION | non-consequential role work that changes state or creates an output | YES / NO |
| TRACE-CATEGORY-ADVICE | every category-overlay invocation | YES / NO |
| TRACE-TOOL | every external/internal tool invocation | YES / NO |
| TRACE-SYSTEM-EXECUTION | scheduled, webhook, queue, storage and provider-adapter execution that may mutate or deliver state | YES / NO |
| TRACE-MONITORING | read-only health probes | COMPACT / relaxed |

## Coverage as measured

`select count(*) from public.phase_c_trace` = **5 rows**, for the entire life of the table. Three predate this
audit; two (471, 472) are this audit's founder-command canary.

| Subject class | Trace-required executions | Complete traces | Missing |
|---|---|---|---|
| Founder commands (`founder_command`, 5 rows) | 5 | 3 rows carry a `trace_id`; **command 222's trace is `status='open'`, `state_after='interpreting'` while the command reached `tasks_created`** | 1 incomplete, ≥2 with no lifecycle trace |
| Tasks at creation (`phase_c_task`, 12 rows) | 12 | **0** — `trace_id` was NULL on all 12 | **12** |
| Workflow runs | 0 committed; 3 executed in aborted probes | `phase_c_workflow_run.trace_id` was **NULL** on every run created | **3 of 3** |
| Step runs | 0 committed; 1 executed in probe | 1 (trace 473) | 0 |
| Handoff runs | 0 committed; 1 executed in probe | 2 (traces 474 open, 475 accept) | 0 |
| Outbox rows (`phase_c_event_outbox`, 3 rows) | 3 | `trace_id` NULL on all 3 | **3** |
| **Scheduled / system executions (`TRACE-SYSTEM-EXECUTION`)** | see below | **0** | **all of them** |

### The largest gap: scheduled execution

`TRACE-SYSTEM-EXECUTION` covers *"scheduled, webhook, queue, storage and provider-adapter execution that may
mutate or deliver state"*, `trace_required = YES`, `completed_without_trace_allowed = NO`.

`public.phase_c_component` classifies **1,117 active state-changing components**, every one of them carrying a
`trace_policy_id`. Cron ran throughout the audit window — `os_audit_log` shows `ai_health` at 08:37, 08:52,
09:07, 09:22, 09:37, 09:52 and `uptime` at 09:00, 09:15, plus `security` at 09:05. `phase_c_trace` gained **no
rows** from any of them.

Nothing routes real execution into the trace table. `phase_c_trace` is written only by the Phase C runtime
routines (`fn_phase_c_trace_write` and its callers), and the estate's actual scheduled work does not call them.

### Why the invariant board shows this as clean

Three of the 58 invariants cover trace completeness, and all three are computed over empty or near-empty
populations:

| Invariant | Reports | Population it reads |
|---|---|---|
| `closed_tasks_without_trace` | 0 | `phase_c_task where closed_at is not null` — **0 rows** at the time of the run |
| `completed_step_runs_without_trace` | 0 | `phase_c_workflow_step_run` — **0 rows**, ever |
| `handoff_runs_without_trace` | 0 | `phase_c_handoff_run` — **0 rows**, ever |
| `completed_commands_without_trace` | 0 | no command has ever reached `completed` |

None of them looks at a created-but-open task, at a workflow run, at an outbox row, or at a scheduled
execution. The board reads clean because the tables it reads are empty, not because coverage is complete.

## Verdict

Required result: **zero missing.** Measured: at minimum **12 tasks, 3 workflow runs, 3 outbox rows and every
scheduled execution in the window** have no trace, and one founder-command trace is materially incomplete.

**GATE 13: FAIL.**

Boundary on this artifact: the counts above are exact for `phase_c_trace`, `phase_c_task`,
`phase_c_workflow_run`, `phase_c_workflow_step_run`, `phase_c_handoff_run` and `phase_c_event_outbox`. For
`TRACE-SYSTEM-EXECUTION` I measured that cron executed in the window and that the trace table gained no rows
from it; I did not enumerate every scheduled execution in the estate against every component id.
