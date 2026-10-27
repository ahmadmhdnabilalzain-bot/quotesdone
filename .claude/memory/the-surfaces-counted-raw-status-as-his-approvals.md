---
name: the-surfaces-counted-raw-status-as-his-approvals
description: 5-6 Sep 2026 — the refund-only rule held on both routing paths, yet the OS showed the founder 14 non-refund "decisions": every fn_ws_* figure counted raw pending agent_actions by status, decision_policy still named him for 6 kinds, the brief called department backlog his approval, and auto/notify rows were left pending by the sweep. Fixed by PR #521; two CI checks now guard it.
metadata:
  type: project
---

What "routes to his approval" means has three layers and only the first was guarded: (1) routing
(org_tasks.needs_founder trigger, fn_event_dispatch) — refund-only since 4 Sep; (2) the SURFACES
(fn_founder_queue, fn_ws_exec_home/operations/governance/notifications, fn_os_command,
fn_ops_dashboard, fn_founder_brief, OsxShell) — counted raw status and offered Approve/Reject;
(3) the ROWS — auto/notify kinds the sweep left pending, 34 org_tasks proposed on missing
org_authority rows, 7 decision_records proposed with no router, 6 founder_commands bounced as
"no registered intent" (his own PCCR approvals after the ritual was abolished).

Fix (PR #521, 6 Sep): fn_founder_refund_approvals_open() is the one count every surface reads;
non-refund rows are published as held-with-role (fn_action_holder) with yours=false; decision_policy
names roles; fn_agent_action_work_sweep settles auto/notify/officer kinds; fn_decide routes a
proposed decision to the dept lead; fn_task_approve sends holds into the lane; CR-005 answers a
retired-ritual approval plainly. Checks: founder_approval_is_refunds_only.test.mjs,
held_rows_have_a_non_founder_owner.test.mjs.

**How to apply:** when he says "things wait for my approval", measure all three layers, not the
routing rule. See [[every-refund-needs-the-founder]] and [[a-gated-task-is-not-a-founder-task]].
