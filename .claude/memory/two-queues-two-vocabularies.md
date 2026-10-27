---
name: two-queues-two-vocabularies
description: The 199 pending agent_actions cannot be drained by the executor path — agent_actions.kind and org_action_executor.action_class are different vocabularies.
metadata: 
  node_type: memory
  type: project
  originSessionId: 03690ce0-a2c8-41da-b9d4-9343ce87c730
  modified: 2026-08-10T14:38:35.553Z
---

Measured on production 10 Aug 2026. Two queues that look like one:

- **`agent_actions`** — work addressed to an employee. `kind` is `handoff`,
  `improvement_question`, `knowledge_task`, `report_recommendation`… 199 pending, 124 of them
  addressed to a real active employee. **Not one has a matching executor.**
- **`action_execution`** — the decision→execution queue `fn_decide` writes and the HTTP invoker
  drains. `action_class` is `recommend`, `knowledge_acquire`, `exec_review`… It held 4 rows and
  ZERO queued.

So building an HTTP invoker does not drain the 199, and neither does bridging the 199 into
`org_tasks`: that queue is **already 439 open rows against a `cos_execute` throughput of about
three an hour**. Pouring an inbox into a saturated queue moves a backlog, it does not clear one.

What does help: 84 of the 439 open `org_tasks` carry an `action_class` with an edge-function
executor, and `fn_org_task_execute_sweep` feeds those to the invoker five a run.

**Why:** every brief since part 7 has proposed the executor as the fix for the 199, and it is not.
**How to apply:** before building a drain, count the destination queue's own backlog and its
throughput. `approval-center-everything-else-automatic` (204 of 1,269, 16.1% against a 10% bar)
goes green when the work is done, at the rate the company can do it.

Related: [[executors-are-edge-functions]], [[session-briefs-carry-misdiagnoses]]
