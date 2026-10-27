---
name: connectivity-audit-is-deterministic-now
description: "the company-connectivity audit is a reproducible SQL register + CI gate now, not rotating LLM agents"
metadata: 
  node_type: memory
  type: project
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-02T15:27:47.134Z
---

The connectivity "audit" of the autonomous company used to be run by fleets of LLM agents. They
explore differently every run, so the finding set **rotated** and never converged — 114 one pass,
7 the next, a different 8 after — which is why "finish the 114 then the rest" was unanswerable. The
founder pushed back on this directly (2 Sep 2026): *"why you keep jumping from one point to another."*

Replaced with **`public.fn_company_connectivity_register()`** (in
`scripts/sql/company_connectivity_register.sql`): one STABLE, reproducible instrument that returns
the same real-gap set every run. Five SQL-decidable classes, each with by-design exclusions named in
the body: `step_without_executor` (mirror of `v_workflow_side_effects_without_executor`),
`actor_role_unresolved` (via the runtime resolver `fn_org_agent_resolve`, excluding contextual
`owner`/`Director` in employee_task), `event_emitted_no_subscriber` (emitted into `company_event`
with no active subscription, excluding `task.assigned` = direct-assignment path),
`dead_subscription` (active sub → missing/inactive agent), `executor_target_needs_args` (reachable
rpc executor whose target needs args the queue invoker can't supply).

`scripts/checks/company_is_fully_wired.test.mjs` asserts it returns **0** — a GATE, added to the
credentialed `project-parity.yml` list. So a dangling edge now reddens CI instead of waiting for an
LLM to notice it.

**Key correction learned here:** my hand-written role-resolution query flagged 11 unresolved
actor_roles; calling the actual runtime resolver `fn_org_agent_resolve` showed it resolves **9 of
11** (fuzzy/normalized matching my query didn't replicate) — the classic
[[a-verifier-that-reads-what-it-expects]]. Always call the real resolver, not a re-implementation.

The register found exactly **3 real gaps** (all fixed 2 Sep, all in wiring tables — no frozen
subject): EXEC-01 (goal_retirement_replan verify executor + `fn_verify_objectives_superseded`),
OA-01 (`goal.retired` → cpo subscription; emitted by `trg_goal_cascade`, delivered only via
`event_subscription`), and metric.alert repointed off inactive `analytics_director` → active
`intel_director`. Everything else the LLM audits flagged was **latent pre-launch** (emitter exists,
no real traffic yet) or **by-design**. Relates to [[never-state-what-you-have-not-measured]] and
[[agents-are-expert-human-staff-who-act]].
