-- PROBE for fixture_supplier_registration_tasks_and_handoffs_are_purged.sql (13 Oct 2026, seat: customer_support).
-- Pure probe: runs the purge's own deletes and always raises CHK<<...>>, so nothing is deleted. It reports what the
-- purge WOULD delete, and that a second pass would delete 0 (idempotent), and that no real-supplier row is in scope.
do $$
declare v_tasks int; v_handoffs int; v_tasks2 int; v_handoffs2 int; v_real_tasks int;
begin
  select count(*) into v_real_tasks from public.org_tasks t
   where t.detail like '[founder_mail:supplier\_registered]%'
     and not (t.detail ~* 'New supplier "\s*zz\s*demo' or t.detail ~* '@example[.]invalid' or t.detail like '%qd\_run:%');

  with fixture_lead as (
    select l.id from public.leads l
     where public.fn_seat_clock_lead_is_fixture(l)
        or exists (select 1 from unnest(coalesce(l.tags, '{}'::text[])) t where t like 'qd\_run:%')
  ), d as (
    delete from public.agent_actions a
     where a.kind = 'handoff' and a.target_table = 'notifications'
       and a.detail #>> '{summary,known,facts,msg_type}' = 'supplier_registered'
       and ((a.detail #>> '{summary,known,facts,supplier_id}') in (select id::text from fixture_lead)
            or a.detail::text ~* 'New supplier \\"\s*zz\s*demo')
    returning 1)
  select count(*) into v_handoffs from d;

  with d as (
    delete from public.org_tasks t
     where t.detail like '[founder_mail:supplier\_registered]%'
       and (t.detail ~* 'New supplier "\s*zz\s*demo' or t.detail ~* '@example[.]invalid' or t.detail like '%qd\_run:%')
    returning 1)
  select count(*) into v_tasks from d;

  -- the second pass: idempotence
  select count(*) into v_tasks2 from public.org_tasks t
   where t.detail like '[founder_mail:supplier\_registered]%'
     and (t.detail ~* 'New supplier "\s*zz\s*demo' or t.detail ~* '@example[.]invalid' or t.detail like '%qd\_run:%');
  select count(*) into v_handoffs2 from public.agent_actions a
   where a.kind = 'handoff' and a.target_table = 'notifications'
     and a.detail #>> '{summary,known,facts,msg_type}' = 'supplier_registered'
     and (exists (select 1 from public.leads l
                   where l.id::text = a.detail #>> '{summary,known,facts,supplier_id}'
                     and (public.fn_seat_clock_lead_is_fixture(l)
                          or exists (select 1 from unnest(coalesce(l.tags, '{}'::text[])) t where t like 'qd\_run:%')))
          or a.detail::text ~* 'New supplier \\"\s*zz\s*demo');

  raise exception 'CHK<<% would delete org_tasks=% handoffs=%; second pass org_tasks=% handoffs=%; real supplier_registered tasks untouched=% (rolled back)>>',
    case when v_tasks2 = 0 and v_handoffs2 = 0 then 'PROBE OK:' else 'PROBE FAILED:' end,
    v_tasks, v_handoffs, v_tasks2, v_handoffs2, v_real_tasks;
end $$;
