---
name: phase-freezes-removed-totally
description: Founder order — no phase freezes, no phase gates, no implied limits; OpenRouter is the only hold
metadata:
  type: feedback
---

Phases A to D were scaffolding to get the structure right. Their freezes, gates and implied limits
are removed **totally**. Founder, 7 Sep 2026: *"phase A to D where steps to make sure the structure
was fine. their freezes or implied limits should be removed totally. i dont want any limits in the
workflow"* and *"the only thing on hold open router. any other limit or freeze or gates that is
affecting us should be removed. otherwise we will never be able to finish this code"*.

Removed, in order: `z90_phase_b_freeze` (2 Sep), `fn_phase_a_baseline_drift` and
`fn_phase_b_baseline_drift` (4 Sep), and the last three statement guards
`a10_phase_b_workflow_owner_guard` / `a10_phase_b_owner_guard` / `a10_phase_b_handoff_guard`
with their functions (7 Sep,
`scripts/sql/the_last_phase_b_guards_come_off_because_the_founder_removed_every_limit.sql`).

Workflow ownership, order, states, transitions, gates, business rules, handoff accountability,
overlay authority, departments and roles are all freely changeable. No change request, no
`app.phase_a_change_reason`, no `app.phase_b_change_reason`.

**Why:** a structure that cannot move cannot be corrected, and the live organisation has moved past
the registers. The freezes were costing more than they protected.

**How to apply:** never reinstate a phase freeze or write a check asserting a phase baseline is
unchanged. Append-only triggers on `org_phase_baseline` and `phase_b_change_request` stay — they
refuse no change, they only stop history being rewritten. Correctness guards (CHECK, FK,
`fn_org_authority_guard`, credential and verify_jwt checks) are not limits and stay. See
[[all-founder-system-limits-lifted-except-openrouter]] and [[the-only-hard-rules-and-operating-doctrine]].
