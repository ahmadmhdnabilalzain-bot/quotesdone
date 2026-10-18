-- PROBE: ruling 1199, demo activity files no seat task or handoff. Pure probe, no DDL: run AFTER its .sql in the SAME
-- query; it always ends in raise exception CHK<<...>>, so nothing survives, including the .sql it ran after. Its rows
-- are ZZ DEMO / example.invalid fixtures plus one non-demo customer that never commits; nothing is sent.
-- PROBE OK only if:
--   D1 a demo customer's rating (the real reviews trigger when a demo transaction exists, and the task shape
--      fn_sales_rating_landed writes) files 0 org_tasks
--   D2 a demo complaint handoff (complaint.due about a demo customer) returns null and files 0 agent_actions
--   D3 a demo supplier registration task (ZZ DEMO in its detail, or a demo lead_id) files 0 org_tasks
--   R1 the same rating-shaped task and the same handoff for a NON-demo customer each file exactly 1
do $probe$
declare
  v_fail text := ''; v_demo uuid := gen_random_uuid(); v_real uuid := gen_random_uuid(); v_lead bigint;
  v_before bigint; v_n int; v_h bigint; v_tx uuid;
begin
  insert into public.customers (id, email, full_name) values (v_demo, 'zzprobe-1199@example.invalid', 'ZZ DEMO probe 1199');
  insert into public.customers (id, email, full_name) values (v_real, 'probe1199-real@probe-1199.qd', 'Probe Real 1199');
  select id into v_lead from public.leads where is_demo order by id desc limit 1;
  select coalesce(max(id), 0) into v_before from public.org_tasks;

  -- D1
  select t.id into v_tx from public.transactions t where public.fn_transaction_is_demo(t.id)
     and not exists (select 1 from public.reviews r where r.transaction_id = t.id) limit 1;
  if v_tx is not null then
    insert into public.reviews (supplier_id, customer_id, inquiry_id, transaction_id, rating, comment)
    select t.supplier_id, t.customer_id, t.inquiry_id, t.id, 2, 'ZZ PROBE 1199' from public.transactions t where t.id = v_tx;
  end if;
  insert into public.org_tasks (title, detail, status, assigned_agent, result)
  values ('Customer rating landed: probe - 2/5', 'probe', 'assigned', 'sales_engineer',
          jsonb_build_object('sales_rating', jsonb_build_object('customer_id', v_demo, 'rating', 2)));
  -- D3
  insert into public.org_tasks (title, detail, status, assigned_agent)
  values ('Supplier registration incomplete', 'New supplier "ZZ DEMO Walk probe" registered', 'assigned', 'customer_support');
  if v_lead is not null then
    insert into public.org_tasks (title, detail, status, assigned_agent, result)
    values ('Supplier registration incomplete', 'probe', 'assigned', 'customer_support', jsonb_build_object('lead_id', v_lead));
  end if;
  select count(*) into v_n from public.org_tasks where id > v_before;
  if v_n <> 0 then v_fail := v_fail || ' D1/D3 ' || v_n || ' demo task(s) filed;'; end if;

  -- D2
  v_h := public.fn_seat_handoff('customer_support', 'customer_support', 'complaint.due', 'customers', v_demo::text, '{}'::jsonb);
  if v_h is not null or exists (select 1 from public.agent_actions where target_id = 'complaint.due:' || v_demo) then
    v_fail := v_fail || ' D2 a demo complaint handoff was filed;'; end if;

  -- R1
  insert into public.org_tasks (title, detail, status, assigned_agent, result)
  values ('Customer rating landed: probe - 2/5', 'probe', 'assigned', 'sales_engineer',
          jsonb_build_object('sales_rating', jsonb_build_object('customer_id', v_real, 'rating', 2)));
  select count(*) into v_n from public.org_tasks where id > v_before;
  if v_n <> 1 then v_fail := v_fail || ' R1 a real rating filed ' || v_n || ' tasks, not 1;'; end if;
  v_h := public.fn_seat_handoff('customer_support', 'customer_support', 'complaint.due', 'customers', v_real::text, '{}'::jsonb);
  if v_h is null then v_fail := v_fail || ' R1 a real complaint handoff was not filed;'; end if;

  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK' else 'PROBE FAILED:' || v_fail end;
end $probe$;
