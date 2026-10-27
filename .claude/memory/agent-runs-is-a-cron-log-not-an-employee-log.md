---
name: agent-runs-is-a-cron-log-not-an-employee-log
description: "agent_runs holds CRON JOB names, not employee keys — 75 of 93 AI employees have never executed anything, which is the real \"AI employees working 11/93\""
metadata: 
  node_type: memory
  type: project
  originSessionId: 6ee28b3e-1f95-4b49-9341-54ffe11ece66
  modified: 2026-08-14T00:34:33.913Z
---

`public.agent_runs.agent` holds **cron job names** (`ai_health`, `backup`, `blog_weekly`,
`archive_rfq`, `graph_rebuild`) written by ~70 routines each logging its own run. `org_agents.agent_key`
holds **employee roles** (`account_mgr`, `bookkeeper`, `boq_analyst`, `backend_engineer`).

Measured on production 14 Aug 2026: 23,295 rows over 136 distinct `agent` values, but only **18 of the
93 active employees** appear at all. It is not a key-shape mismatch — it is two different populations
sharing one table.

**Why:** this is the true cause of the founder's unexplained "AI employees working 11 / 93", and it
blocks four Row #3 checks at once — `employee-performance` (75 of 93 have no run), `employee-current-thoughts`
(68 of 93 no agent_memory/30d), `employee-learning-progress` (93 of 93 have <2 dated exam results), and
`s32-reputation-six-dimensions` (77 null correctness, 93 null learning_speed, 57 null score, because
`fn_reputation_recompute` reads agent_runs for reliability).

`fn_reputation_recompute` already carries a prior session's note admitting agent_runs is the wrong table
for employees and deliberately deferring the question *"what does employee reliability mean"*. That
decision is open.

**How to apply:** the honest source of employee work is `org_tasks.assigned_agent` — 447 of 990 tasks
carry one, 113 done tasks have one, 33 active employees have completed at least one. But
`fn_org_task_execute_sweep` never reads `assigned_agent` and never records a run for the owner, so
completed work is never attributed to the worker. Fixing attribution moves 18 → ~33. It cannot reach 93:
22 active employees have no task at all, and assigning more is gated on `max_open_tasks`, which the
founder reserved as his call because it is spend. Do not write agent_runs rows for employees who did
nothing — that is fabrication. See [[group-per-class-not-in-aggregate]] and
[[addressed-to-an-identity-nobody-models]].
