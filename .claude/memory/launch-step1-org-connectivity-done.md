---
name: launch-step1-org-connectivity-done
description: Launch Step 1 (org connectivity/workflow/approval chemistry) — what was fixed and proven
metadata: 
  node_type: memory
  type: project
  originSessionId: 98fd9354-41f6-44c4-aefd-9361a73cd530
  modified: 2026-08-31T20:01:22.939Z
---

Launch Step 1 of ~6 (org connectivity) done 31 Aug 2026 on PR #476 / branch launch-readiness-plan-2026-08-27.
The four signals a real company depends on are proven to travel, by aborted-tx probes with zero paid
inference. Durable proof: `scripts/checks/org_connectivity_signal_path.test.mjs` (PASS).

Fixes (all deployed + read-back-verified; nothing frozen touched; Phase A/B drift 0):
- **CEO→founder escalation**: `fn_should_escalate` gained an apex branch (active actor with NULL
  manager_key → route_to='founder', 'apex_to_founder'). It used to fall to fallback_exec and route the
  apex DOWN to chief_of_staff. See [[a-signed-in-surface-with-no-identity]] pattern of missing identity.
- **org_objectives is dead**: 0 rows, 0 writers; `fn_company_state` + `fn_founder_brief` read it and
  reported 0 objectives while 92 live in `department_objective`. Repointed both. (open_objectives now 92.)
- **fn_org_task_assign** piled a dept's tasks on one idle agent (pick=1 only). Rewrote as a greedy
  per-dept fill (least-loaded eligible colleague, recomputed each pick): 37/37 in one sweep.
- **trg_goal_cascade** fired on retirement only; widened to AFTER INSERT OR UPDATE + a single-goal
  decompose arm (objectives only, K31's no-task rule kept). A new target now cascades at once.
- **escalation_targets** data: 3 HR roles used agent_key `hr_director` instead of role_id
  `agent_workforce_capability_director`; a chief_of_staff self-edge; organization_designer→retired
  chief_performance_officer; marketplace_director dup. Corrected (no count change → Phase-A-safe).

Already-correct (confirmed, not rebuilt): the AI-managerial approval tier (all 10 active depts resolve
a real approver, medium→head high→CEO, refund-only founder gate); reporting-line escalation; 10/10
depts reachable. See [[stage0-defects-2-and-3-closed]].

Deferred to later stages, disclosed in `docs/LAUNCH_STEP1_ORG_CONNECTIVITY.md`, NOT silently dropped:
32 goals with no measure_sql (instrument backlog); 29 unlinked objectives / 29 orphan KPIs (curation);
org_tasks.objective_id 100% NULL (Stage-3 backlink); escalate_founder on the irreversible-refuse floor
(Stage-4 founder-notification); stood-down driver crons (Stage-3, founder's call).
