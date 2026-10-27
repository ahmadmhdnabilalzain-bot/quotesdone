---
name: ownership-lives-in-workflow-step
description: "workflow_step.actor_role is the accountable owner of a step and must resolve to a live employee; employee_workflow is coarse participation and recorded ten \"owners\" for rfq_handling."
metadata: 
  node_type: memory
  type: reference
  originSessionId: 951680f6-998d-4578-b818-e62f587f57e4
  modified: 2026-08-15T02:18:04.767Z
---

Two registries answer "who owns this?" and they are not equivalent.

- **`workflow_step (workflow_key, step_no, step, actor_role, action_class, gate)`** — step-level.
  `actor_role` is the **accountable owner** of that one step. Free text, so it must be checked:
  `coalesce(fn_org_agent_resolve(actor_role), fn_org_role_resolve(actor_role))`.
- **`employee_workflow (agent_key, workflow_key, role_in_workflow)`** — whole-workflow
  participation, `owner` / `reviewer` / `participant` / `approver` / `step actor`. Too coarse to
  express a chain.
- **`workflow_run` / `workflow_step_run`** — execution. `workflow_step_run.actor` is who actually
  did it.

Measured 15 Aug 2026 before the fix: `rfq_handling` #5 "Select suppliers" named `domain specialist`
— resolves to nobody. `employee_workflow` recorded **ten** owners for `rfq_handling` and 43 for
`employee_task`.

**`employee_task` is the one legitimate many-owner workflow**: it is the generic per-employee task
loop, so every employee owns their own instance, and its steps name `owner` and `Director` as
placeholders bound **per run**. Verify binding from `workflow_step_run.actor`, not from the
registry — 2,901 runs bound correctly and one stayed `Director`, queued and unpickable since 10 Aug.

An **overlay can never be an actor**: `runtime_mode = 'knowledge_overlay'` rows have no runtime
agent and cannot be accountable. That is how `domain specialist` came to own supplier selection.

Guards now in place: `trg_step_run_actor_is_a_real_employee` (no queued/running/ok step run with an
unresolvable actor) and `trg_org_role_no_reserved_decision` (no role may OWN a founder-reserved
decision, listed in `founder_reserved_decision`).

Check with `scripts/checks/workflow_ownership_alignment.test.mjs` and
`scripts/agents/role_caller_census.mjs` (seven caller surfaces per role).
