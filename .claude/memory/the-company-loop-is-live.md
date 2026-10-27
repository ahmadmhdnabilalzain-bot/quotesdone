---
name: the-company-loop-is-live
description: the live company loop (company_event -> fn_workflow_start_due -> workflow_run) is ON again after being dormant since 2026-08-15
metadata: 
  node_type: memory
  type: project
  originSessionId: cd432ea4-4602-4dcf-a262-875622bbb1d9
  modified: 2026-09-02T17:10:39.922Z
---

The live company loop had been **dormant since 2026-08-15**: a workflow auto-starts only when a
`company_event.event_type` equals a `workflow.trigger_event` (via `fn_workflow_start_due`), and that
bridge cron (job 195) was `active=false`. Re-enabled 2026-09-02 (wrapped via
`fn_kernel_wrap_and_enable_cron`, registered in `phase_d_committed_scenario_cron`). It is idempotent
(`workflow_run.idempotency_key = workflow_key:event_id`), bounded (LIMIT 200/run, 24h lookback).

Two independent consequences of a `company_event`: `fn_workflow_start_due` starts the workflow, and
`fn_event_dispatch` delivers to agents via `event_subscription` (the dispatcher does NOT read
`workflow`). So trigger-alignment and subscription-wiring are separate axes.

Real bug the loop-start exposed and fixed: `fn_workflow_actor_resolve` returned null for the
`employee_task` `'Director'` placeholder when the task owner had no active manager (only the ceo),
stalling every such run at step 10. Fixed: the top of the org is its own department head
(`coalesce(manager, owner)`).

Wiring done 2026-09-02: repointed `complaint`→`customer.complaint` and `payment`→`payment.received`
(old triggers emitted by nothing); wired dropped sinks (`rollback.required`→cto,
`ai.confidence_dropped`→ai_director, `competitor.pricing_changed`→intel_director, reactivated
`task.assigned`→ops_director); emit `refund.requested` from a `refunds` INSERT (record-only, still
founder-gated) and `supplier.suspension_proposed` from a daily expired-licence cron;
`campaign.launched`→marketing_analyst. Genuinely external (correctly latent, no internal producer):
`lead.qualified`, `contract.submitted`. Already wired: `invoice.received` (ap_bills).

**`public.fn_company_connectivity_register()` now has 6 classes** (added
`workflow_trigger_has_no_producer`) and returns 0 — every active workflow can start, every step has
an executor, every role resolves, every emitted event has a consumer. The
`company_is_fully_wired.test.mjs` CI gate holds it at 0. The external-intake events are a documented
allowlist inside the register, not silent exclusions. `docs/UPGRADE_PLAN.md` is the hardening plan.
Relates to [[connectivity-audit-is-deterministic-now]] and [[phase-freezes-removed-totally]].
