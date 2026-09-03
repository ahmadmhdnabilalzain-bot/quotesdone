-- REVENUE-LOOP WIRING FIX — the marketplace's entry workflow could never start.
--
-- The RFQ Handling workflow (workflow_key 'rfq_handling') — the first step of the money loop
-- (inquiry → match suppliers → quotes → comparison → reveal → 3% fee) — was defined with
-- trigger_event = 'inquiry.created'. But NOTHING emits 'inquiry.created': the AFTER INSERT
-- trigger on public.inquiries is trg_event_inquiry, which fires fn_emit_event('inquiry',
-- 'rfq.created'). fn_workflow_start_due (cron 195) joins workflow.trigger_event = company_event
-- .event_type exactly, so an inquiry insert emitted 'rfq.created', the workflow waited for
-- 'inquiry.created', and the two never met — the revenue loop's entry point was dead.
--
-- 'rfq.created' is the CANONICAL name, not 'inquiry.created': on 2026-08-10 the agent
-- event_subscription rows for this same inquiry event were deliberately corrected FROM
-- 'inquiry.created' TO 'rfq.created' (the note is preserved on the procurement subscription row),
-- to match what the emitter actually fires. The workflow spine was the one place that correction
-- missed. This aligns it — repointing the consumer to the established event, not re-breaking the
-- two subscriptions that were already fixed and not touching the emitter every other consumer relies on.
--
-- Emit side unchanged. Consumers already on 'rfq.created': rfq_qualification_mgr, procurement.
--
--   node scripts/apply_sql.mjs scripts/sql/fix_rfq_handling_trigger_event.sql --apply --ddl

begin;

update public.workflow
   set trigger_event = 'rfq.created'
 where workflow_key = 'rfq_handling'
   and trigger_event = 'inquiry.created';

-- Guard: exactly one row must have moved, and no workflow may still wait on the unemitted name.
do $$
declare v_rfq int; v_orphan int;
begin
  select count(*) into v_rfq   from public.workflow where workflow_key='rfq_handling' and trigger_event='rfq.created';
  select count(*) into v_orphan from public.workflow where trigger_event='inquiry.created';
  if v_rfq <> 1 then
    raise exception 'rfq_handling is not on rfq.created after the update (got % rows)', v_rfq;
  end if;
  if v_orphan <> 0 then
    raise exception '% workflow(s) still wait on inquiry.created, which nothing emits', v_orphan;
  end if;
end $$;

commit;
