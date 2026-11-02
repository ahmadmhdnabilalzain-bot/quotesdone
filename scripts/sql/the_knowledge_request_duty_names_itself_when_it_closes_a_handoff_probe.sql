-- PROBE (pure, no DDL, aborted transaction) for the_knowledge_request_duty_names_itself_when_it_closes_a_handoff.sql.
-- Run AFTER the definition, in the same transaction. It always ends in raise exception 'CHK<<json>>', so every row it writes rolls back.
-- A ZZ DEMO gap cannot be used: in fixture mode fn_seat_handoff files no handoff for demo rows (demo_activity_files_no_seat_task_or_handoff),
-- so the case that failed (a real gap judged not_a_gap whose knowledge.request handoff is still pending) is run as it stands, and rolled back.
--   before  = knowledge.request handoffs still pending whose gap is no longer open (the ones the duty must close)
--   closed  = what the tick closed          after = the same count after it (must be 0)
-- Before the fix the tick raised P0001 "... is closed only by its originator customer_support ..." as soon as before > 0.
do $p$
declare v_before int; v_after int; v jsonb;
begin
  select count(*) into v_before from public.sales_knowledge_gap g
   where g.status <> 'open' and g.handoff_id is not null and (g.question like 'ZZ DEMO%') = false
     and exists (select 1 from public.agent_actions a where a.id = g.handoff_id and a.status not in ('done', 'failed'));
  v := public.fn_customer_support_knowledge_request_tick();
  select count(*) into v_after from public.sales_knowledge_gap g
   where g.status <> 'open' and g.handoff_id is not null and (g.question like 'ZZ DEMO%') = false
     and exists (select 1 from public.agent_actions a where a.id = g.handoff_id and a.status not in ('done', 'failed'));
  raise exception 'CHK<<%>>', jsonb_build_object('before', v_before, 'closed', v->'closed', 'after', v_after, 'pass', v_after = 0 and (v->>'closed')::int = v_before);
end $p$;
