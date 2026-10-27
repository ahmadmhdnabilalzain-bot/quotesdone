---
name: executors-are-edge-functions
description: "The 39 QuotesDone action classes that 'cannot execute' need one HTTP invoker for edge functions — the executor table already has every column for it and nothing implements them."
metadata: 
  node_type: memory
  type: project
  originSessionId: 89075d82-5230-476c-8c2c-979664458fc5
  modified: 2026-08-10T10:37:59.605Z
---

Measured 10 Aug 2026. `org_action_executor` holds 55 action classes and only 16 appear in
`org_action_executor_rpc_allowed`. The other 39 are **not broken rows**: their `target` is an
**edge function** (`quote_compare`, `uptime_check`, `match`, `knowledge_exam`, `ai_health`,
`send_outbox`), not a database routine.

`fn_execution_run` cannot call them because it **invokes nothing** — it writes an `agent_actions`
row addressed to an employee. "Execution" in this estate currently means *tell a person*.

**Why:** one HTTP invoker is the missing piece, and `org_action_executor` was already designed for
it — `idempotency_strategy`, `timeout_seconds`, `max_attempts`, `backoff`, `required_authority`
and `compensation_action_class` are all columns on that table and **not one is implemented**.

**How to apply:**
- Do not "fix" the 39 by adding them to `org_action_executor_rpc_allowed`. That table is for RPC
  targets; these are HTTP endpoints.
- Build in risk order: the 28 that are `advisory_safe = true, reversible = true,
  risk_tier = low` first, one at a time, each proved by execution.
- `outreach_send`, `pdpl_action` and `collections_chase` are high-risk and **not reversible**, and
  `refund_within_window` is the one action the founder reserves to himself — see
  [[quotesdone-autonomy-and-staging-rules]]. Those come last or not at all.

Related: [[os-dashboard-still-basic]] — the same estate computes far more than it acts on.
