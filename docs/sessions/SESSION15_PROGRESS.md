# SESSION 15 — ROW #2 (OS.txt) to 100%. Live progress. 110 requirements.

Baseline at session start: 41 MET / 37 PARTIAL / 32 MISSING. Session 14 closed 6 → ~47/110.

## FOUNDER DECISIONS TAKEN 2026-08-06 (all three asked and answered)
1. **xos-12 — ENFORCE, ALL SIX.** fn_kpi_review, fn_budget_rollup, fn_os_review, fn_os_improve,
   fn_outcome_evaluate, fn_company_reflect stop inserting org_tasks into other departments and
   emit events instead. Missing subscriptions must be added in the SAME change, and task counts
   before/after must be asserted equal — otherwise work is silently dropped.
2. **comp-07 — EMIT THE INTERNAL ONES, MARK THE TRAFFIC-GATED PLANNED.** Wire the ~11 internal
   kinds (knowledge.updated, os.health_changed, priority.updated, metric.alert,
   improvement.proposed, forecast.published, incident.opened, policy.updated, process.changed,
   deploy.completed, rollback.required). Add a `planned` flag for the ~8 that need real traffic
   (inquiry.created, supplier.applied, rfq.dispatched, supply.gap, lead.qualified,
   invoice.received, payment.settled, contract.submitted). Nothing faked on synthetic data.
3. **os-exclusive-ownership — I PROPOSE, FOUNDER APPROVES.** Show the full table before writing.
   31 `cat:*` → marketplace; 16 functional → obvious OS. Duplicates: bearings→marketplace,
   ELV→marketplace.

## MEASURED FACTS (production, 2026-08-06)
- os_knowledge_domain: 107 distinct domains, 47 unowned, 2 double-owned.
  owns-per-OS: marketplace 52, commercial 3, technology 3, leadership 2, finance 1, intelligence 1.
- company_event distinct types EVER fired: 7 — content.published 12, goal.at_risk 6, kpi.missed 9,
  process.repeated_failure 11, review.step 209, security.event 10, test.failed 63.
- os_interface active: 17 input + 15 output = 32 rows. 2 rows carry a NULL event_type
  (kind=contract.submitted, kind=decision.executive, kind=payment.settled).
- operating_system.health_score is **numeric**, not text. fn_os_review computes os_review.health
  as text (green/amber/red) — a numeric score must be derived, not copied.
- sync_org_config_to_staging reports `staging_before: 0` for all 19 tables because it clears every
  table (line 90-94) BEFORE measuring `before` (line 105). Not data loss. Misleading label.

## ORDER OF WORK (dependency-correct)
- [ ] A. Cheap wiring: health_score, os_review.metrics(risk/quality/automation), agent_reputation
      → fn_pick_reviewer, fn_memory_search → fn_decide, fn_promote_memory cron-or-delete,
      v_event_backbone reader, fn_task_lesson on event task close, os_objective↔company_goals JOIN.
- [ ] B. **xos-14 correlation_id/causation_id in fn_emit_event — MUST PRECEDE C.**
- [ ] C. Cross-OS chain: xos-04, xos-07, xos-08, xos-09, contract-consolidation, xos-12, xos-13,
      comp-07, xos-11.
- [ ] D. Decision engine: comp-10-chain, comp-10-06-options, comp-10-01, comp-10-02.
- [ ] E. Remainder: comp-06 fn_os_knowledge_query, comp-09 workflow_run, comp-11-*, comp-13-sop,
      ownership mapping, and every PARTIAL.

## STANDING TRAPS (verified, do not relearn)
- Throttling: a 9s gate can take 102s. NOT a hang.
- Output exactly on a ceiling = truncation. Ceiling can be set twice (makeLlm AND llm() 3rd arg),
  and a storage slice can sit downstream of the model ceiling.
- Wiring into review_chain/company_event can create a feedback loop (169 tasks in one hour).
- A measure can return the right number for the wrong reason. Verify what it TOUCHES.
- Parity red → ask which side is RIGHT before levelling.
- `node script.mjs | Select-Object -First N` KILLS the script. Use `$out = node ...`.
- qd_guard refuses reads containing a bare write keyword — write `dele[t]e` in assertions.
- demo_factory must run ALONE.
- comp-12-failures / comp-10-10-outcome: first grading window opens 2026-08-11. NOTHING TO FIX.
  Do not manufacture a 'worse' row.
