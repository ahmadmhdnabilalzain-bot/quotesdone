---
name: two-swallowed-errors-hid-a-leg-that-never-ran
description: "fn_org_task_promote raised 42703 on every call (a plpgsql RECORD shadowed a table alias) and then 23502 (an eventless fn_workflow_start left correlation_id null), each swallowed by a catch-all handler, so MASTER_PLAN 4.3's one-spine promotion never inserted a row"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-04T11:49:23.279Z
---

Fixed 4 Sep 2026, and it took an adversarial audit to find because every symptom was suppressed.

1. `fn_org_task_promote` declared `r record` and also aliased `from public.workflow_run r`, so
   `r.workflow_key` resolved against the RECORD: **42703 on every call, before any row was read**.
   Its three callers in the live loop (`fn_org_task_assign`, `fn_org_task_deterministic_done`,
   `fn_workflow_step_release`) all catch and continue, so the lane reported itself healthy.
2. With the alias fixed it ran and promoted 0 of a 654-task backlog. `fn_workflow_start` reads
   `correlation_id` from the triggering `company_event`; called with a null event — exactly how a
   backlog task is promoted — the read finds nothing, `workflow_run.correlation_id` is NOT NULL, and
   the insert raised **23502** inside the promoter's own `exception when others then null`. The
   statement immediately above already anticipates the eventless case (it mints a fresh idempotency
   key with `gen_random_uuid()`), so the omission was one missing `coalesce` on the next line.

Proof shape: `select count(*) from workflow_run where context->>'promoted_by' = 'fn_org_task_promote'`
returned **0 of 301** employee_task runs ever created. After both fixes, an aborted-transaction probe
returned `promoted: 3` with three runs on the spine.

**Why:** a catch-all handler around a call turns "this never worked" into "nothing to see". Two of
them in one call path made an entire architectural leg invisible for weeks
([[error-and-empty-must-not-return-the-same-value]], [[a-refusal-that-is-not-an-error]]).

**How to apply:** when a routine reports work done and the effect is absent, probe the routine
directly in an aborted transaction rather than reading its return value — the return value is what
the handler chose to say. And when a function anticipates a null argument in one statement, check the
next statement anticipates it too.
