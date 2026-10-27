---
name: launch-governance-loop-closed
description: "The only-refunds boundary, the real-company org restructure (PACR-002), and the governance/reasoning-loop gaps are built and proven on PR #476."
metadata: 
  node_type: memory
  type: project
  originSessionId: 70bbee7f-3c64-46d9-869f-716c4d48b72e
  modified: 2026-08-31T23:45:14.760Z
---

Session 1 Sep 2026 closed the founder's three launch priorities on branch launch-readiness-plan-2026-08-27 (PR #476), production-direct + proven by aborted-tx probes, no LLM:

1. **Only refunds reach the founder.** The residual founder-blocking was the OLD `agent_action_kind_policy` queue (the "two vocabularies" — see [[two-queues-two-vocabularies]]): 10 kinds marked `policy='founder'` surfaced by `fn_founder_queue`/`fn_founder_brief`. Reclassified to `officer` (prompt_approval→cto, finance_marketing_budget→CRO, simulation_apply→COO, compliance_update→GC) and `notify` (the alerts → `fn_notify_founder`, the Stage-4 helper writing founder_alerts + queued email/whatsapp). The CHECK is now `('auto','officer','notify')` — `founder` is structurally illegal for an agent_action kind. `fn_agent_action_work_sweep` re-addresses officer→authority and notify→authority+notification.

2. **Real-company org via PACR-002.** COO (ops_director) owns marketplace+customer+people/ops; CEO chairs the 8 direct reports; Chief of Staff runs the Office of the CEO (cpo, strategy_director). Four manager edges through the Phase A change request. See [[org-phase-baseline-is-append-only]].

3. **The reasoning loop.** fn_kpi_review now opens remediation + assigns practice on a miss; fn_reputation_recompute computes learning_speed from graded training; org_tasks gets an owner + objective at creation (a05_org_task_fill_ownership trigger; objective_id FK repointed off dead org_objectives to department_objective); dual approval for spend/contract (org_action_executor.second_authority + fn_action_invoke_dispatch/fn_action_head_approve); fn_report_recommendation_approve creates routed work. The 32 goals + 14 KPIs were ALREADY honestly marked aspirational (no_measure_reason) — the marketplace has no demand yet, so their measures would be meaningless zeros; left intact.

The **only** hold now is OpenRouter (the founder confirmed 1 Sep: "not holding anything except open router"). The wiring is ready; it thinks when he funds the LLM.
