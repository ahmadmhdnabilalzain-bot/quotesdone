-- Wire the live company loop — Tier 1. Founder directive 2026-09-02: "everything needs to be in a
-- loop like a real company since the company is fully automated."
--
-- The live loop is: company_event --(fn_workflow_start_due)--> workflow_run  (a workflow starts only
-- when a company_event.event_type equals a workflow.trigger_event), and independently
-- company_event --(fn_event_dispatch)--> event_subscription --> agent. A deep loop map (read-only,
-- 2026-09-02) found the loop DORMANT and several trigger/sink mismatches the connectivity register
-- cannot see (it checks subscription wiring, not trigger_event<->emitter alignment).
--
--   GAP-00 (critical) the event->workflow bridge cron `workflow_start_due` (job 195) is inactive since
--                     2026-08-15, so NO workflow auto-starts. Its component registry already reads
--                     activation_state='active'; re-enabling aligns reality to the registry.
--   DRIFT-01 (high)   `complaint` keys on 'complaint.received' which nothing emits; the real signal
--                     'customer.complaint' is emitted+subscribed but starts no workflow.
--   DRIFT-02 (high)   `payment` keys on 'reveal.paid' which nothing emits; 'payment.received' is the
--                     emitted+subscribed event.
--   SINK-01 (high)    'rollback.required' (fn_outcome_evaluate, "reverse if worse") reached no
--                     subscriber — the rollback safety signal was dropped.
--   SINK-02/03 (med)  'ai.confidence_dropped' and 'competitor.pricing_changed' emitted to nobody.
--   SINK-05 (low)     'task.assigned' subscription (ops_director) was inactive though the agent is
--                     active; employee_task still auto-started, only the notification was dark.
--
-- fn_workflow_start_due is idempotent (workflow_run.idempotency_key = workflow_key:event_id), bounded
-- at LIMIT 200/run with a 24h lookback, so re-enabling cannot flood or double-start. Re-enabling uses
-- fn_kernel_wrap_and_enable_cron so `active_state_changing_cron_components_not_wrapped` stays 0.
--
-- Tier 2 (emit missing trigger events at their producers: supplier.suspension_proposed, lead.qualified,
-- contract.submitted, invoice.received, refund-from-complaint) is a separate migration.
--
--   node scripts/apply_sql.mjs scripts/sql/wire_the_company_loop_tier1.sql --apply --ddl

begin;

-- GAP-00 — turn the loop on: wrap job 195 as a traced kernel component and enable it.
select public.fn_kernel_wrap_and_enable_cron(195, 'chief_operating_officer', 'people_ops');

-- DRIFT-01 / DRIFT-02 — align each workflow's trigger to the event that actually flows.
update public.workflow set trigger_event = 'customer.complaint' where workflow_key = 'complaint';
update public.workflow set trigger_event = 'payment.received'   where workflow_key = 'payment';

-- SINK-01/02/03 — give each dropped safety/intelligence signal a live consumer.
insert into public.event_subscription (agent_key, event_type, reason, active) values
  ('cto',           'rollback.required',        'Act on a rollback-required signal when a graded outcome is worse than baseline', true),
  ('ai_director',   'ai.confidence_dropped',    'Investigate a drop in AI confidence and remediate', true),
  ('intel_director','competitor.pricing_changed','Re-assess pricing/positioning when a competitor moves', true)
on conflict (agent_key, event_type) do update set active = true, reason = excluded.reason;

-- SINK-05 — reactivate the (active) ops_director's task.assigned notification.
update public.event_subscription set active = true
 where agent_key = 'ops_director' and event_type = 'task.assigned';

commit;
