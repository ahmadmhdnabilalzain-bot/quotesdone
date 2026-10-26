---
name: stage0-defects-2-and-3-closed
description: Stage 0 CoC Defects 2 (self-approvals) and 3 (stale grants) are closed/verified; Defect 1 (AI-managerial approval tier) is THE Stage 1 build
metadata: 
  node_type: memory
  type: project
  originSessionId: 95f8dff2-f1de-4ffd-b43c-3c5d91878414
  modified: 2026-08-27T22:00:58.946Z
---

Stage 0 chain-of-command scan (`docs/STAGE0_CHAIN_OF_COMMAND_FINDINGS.md`), second pass 28 Aug 2026:

- **Defect 2 (182 self-approvals) — CLOSED, mechanism proven.** `fn_pick_reviewer(dept, author)`
  resolves the author via `fn_org_agent_resolve` and never returns them (tested 31/31 depts, 0
  self-reviews). Write-time guard `a00_review_chain_no_self_review` (BEFORE INSERT/UPDATE) resolves
  BOTH sides by alias, raises check_violation on equality, canonicalizes on write — forced to fire in
  an aborted probe (`cfo` ≡ alias `finance_ai`). No self-approval rows since 14 Aug 02:51; the 285
  legacy rows are history, left untouched.
- **Defect 3 (2 stale authority grants) — FIXED + verified.** `gov_relations_mgr/analysis`,
  `marketing_copy/content_draft` were on inactive/superseded keys, already unreachable (consumers
  canonicalize agent_key before matching `employee_authority` raw). Deleted via
  `scripts/sql/stage0_remove_two_stale_authority_grants.sql`; 0 stale grants remain.
- **Defect 1 (AI-managerial approval tier) — BUILT + proven 28 Aug 2026.** The dispatcher
  `fn_action_invoke_dispatch` no longer dead-refuses consequential actions; a middle tier exists:
  `consequential action → the accountable AI head/officer approves → runs autonomously`. New objects
  (`scripts/sql/stage1_ai_managerial_approval_tier.sql`): `action_approval` ledger (uuid key —
  action_execution.id is a UUID, single-use, RLS on), `fn_action_resolve_approver(dept, risk_tier)`
  (medium→dept head; high→execute_high officer, escalating to CEO), `fn_action_head_approve` (refuses
  founder-reserved refunds, irreversible-no-comp, non-entitled approver, self-approval). The dispatcher
  edit lives in the canonical winner `scripts/sql/the_queue_that_had_nobody_to_hand_it_to.sql` (NOT
  action_invoker.sql — check the canonical manifest for the winner before editing). Dispatcher is NOT
  a `phase_c_frozen_subject`; the refund path stays frozen + founder-only. Proven by two
  aborted-transaction probes, zero live effect (crons INACTIVE). Trap hit: re-applying the winner file
  clobbered 3 co-resident routines to stale versions — had to re-apply their own winner files and
  regenerate the schema export.

**Why:** the plan (`docs/LAUNCH_READINESS_PLAN.md`) makes chain-of-command correctness Stage 1, and
Defect 1 is the one mechanism that was never built, not a bug in an existing one.

**How to apply:** two low-severity Stage 1 follow-ups also recorded: (a) `dispute handling path` is
owned by both `payments_and_billing_manager` and `trust_and_safety_manager` — disambiguate scope or
pick one owner; (b) 16 placeholder actor_roles (`owner`×15, `Director`×1) all sit in the
`employee_task` runtime-bound template — confirm runtime binding, do not hard-assign blindly. See
[[the-primary-identity-is-not-how-producers-key-a-subject]], [[closing-a-grant-makes-a-record-stale]].
