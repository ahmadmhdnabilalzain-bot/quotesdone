-- PROBE (pure, no DDL, aborted transaction) for every_org_task_kind_has_a_handler_and_a_decision_goes_to_its_owner.sql.
-- Seat: ceo. Run AFTER the definition in the same transaction; it ends in raise exception, so nothing survives.
--   1. the tick over today's assigned org_tasks: what moved to its owner, what closed, what stays open and why;
--   2. a new task of the CEO's kind filed on customer_support's queue lands on the CEO (the trigger);
--   3. a task of a kind nobody registered raises the one finding.
-- PROBE OK needs: no registered-kind routine_operational_decision task left with a non-owner, no task closed that the
-- register calls 'consumer', the trigger routes the new task, the unregistered kind is a finding.
do $p$
declare v jsonb; v_left_misrouted int; v_wrong_close int; v_new bigint; v_new_seat text; v_odd bigint; v2 jsonb; v_finding int; v_ok boolean;
begin
  v := public.fn_org_task_kind_handlers_tick();
  select count(*) into v_left_misrouted from public.org_tasks o join public.org_task_kind_handler k
      on k.action_class = o.action_class and k.mail_kind = public.fn_org_task_mail_kind(o.detail, o.result)
   where o.status = 'assigned' and k.handler <> 'consumer' and o.assigned_agent is distinct from k.owner_seat;
  select count(*) into v_wrong_close from public.org_tasks o join public.org_task_kind_handler k
      on k.action_class = o.action_class and k.mail_kind in (coalesce(public.fn_org_task_mail_kind(o.detail, o.result), '*'), '*')
   where o.status = 'done' and o.decided_by = 'fn_org_task_kind_handlers_tick' and k.handler = 'consumer';

  insert into public.org_tasks (title, detail, status, tier, needs_founder, action_class, assigned_agent)
  values ('CEO: the forecast needs your decision (week of 2026-11-09)', '[founder_mail:business_health_at_risk] probe row', 'assigned', 'advisory', false,
          'routine_operational_decision', 'customer_support')
  returning id, assigned_agent into v_new, v_new_seat;

  insert into public.org_tasks (title, detail, status, tier, needs_founder, action_class, assigned_agent)
  values ('A kind nobody registered', '[founder_mail:probe_kind_nobody_owns] probe row', 'assigned', 'advisory', false,
          'routine_operational_decision', 'ceo')
  returning id into v_odd;
  v2 := public.fn_org_task_kind_handlers_tick();
  select count(*) into v_finding from public.it_engineer_finding
   where issue_key = 'duty:org_task_kind_unregistered:routine_operational_decision:probe_kind_nobody_owns' and closed_at is null;

  v_ok := v_left_misrouted = 0 and v_wrong_close = 0 and v_new_seat = 'ceo' and v_finding = 1;
  raise exception '% CHK<<%>>', case when v_ok then 'PROBE OK' else 'PROBE FAILED' end, jsonb_build_object(
    'tick', v - 'settled', 'left_misrouted', v_left_misrouted, 'closed_a_consumer_kind', v_wrong_close,
    'new_task_lands_on', v_new_seat, 'unregistered_finding', v_finding, 'second_tick_unregistered', v2->'unregistered');
end $p$;
