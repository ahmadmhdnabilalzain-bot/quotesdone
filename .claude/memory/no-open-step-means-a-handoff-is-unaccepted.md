---
name: no-open-step-means-a-handoff-is-unaccepted
description: A Phase D run with no open step run is usually waiting for a handoff to be accepted, not stopped; max_steps cannot leave a step open.
metadata:
  type: project
---

Measured 23 Aug 2026. The four-mode failure arm was refused 22023 ("step_run_id required") on 19 of
30 workflows, and the diagnosis in the brief — "step 1 executes without reading the business
object, so nothing keeps a step open" — was right about the first half and wrong about the cause.
Probed: W01 `waiting_handoff`, 0 open step runs, 1 open handoff, S01 completed. **The kernel opens
no successor step run until the receiving owner accepts the open handoff.**

Since PCCR-001 the dispatch fires at step OPENING (see [[the-phase-d-dispatch-fires-at-step-open]]),
so `max_steps` cannot leave a step open either — the cascade happens inside
`fn_kernel_workflow_start`.

**How to apply:** to act on an open step, drive with `hold_at_first_open_step` or
`hold_at_step_id` (J01), which accepts handoffs through `fn_phase_d_handoff_accept` and stops with
one step open and nothing done to it. For a step whose handler always executes, set
`app.phase_d_hold_step` (J03) at transaction level BEFORE building the scenario — the scenario's own
product trigger can start the run while it is still being built.
