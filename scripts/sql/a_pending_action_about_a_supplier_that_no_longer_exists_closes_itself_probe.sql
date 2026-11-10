-- Assigned: customer_support
-- PURE PROBE (no DDL) for a_pending_action_about_a_supplier_that_no_longer_exists_closes_itself.sql. It always ends in
-- raise exception 'CHK<<...>>', so every row it writes or closes rolls back. Run it with the file in one rolled-back
-- transaction (node scripts/ci/rehearse_sql.mjs <file> <this>) or after the file is applied.
--   delete  : a ZZ DEMO lead created here with a pending action, then deleted -> its action is dismissed by the trigger
--   control : a pending action naming a lead that exists                       -> stays pending (and every real one does)
--   sweep   : the rule over every supplier                                     -> the actions naming deleted suppliers close,
--             the two named in #1901 (340683, 324789) among them
--   heartbeat: fn_supplier_doc_reading_escalate runs the rule                    (read from its live definition)
do $$
declare v_lead bigint; v_ctl bigint; a_gone bigint; a_ctl bigint; s_gone text; s_ctl text; v_swept int; v_named int;
        v_live_before int; v_live_after int; v_two text; v_beat boolean; fail text := '';
begin
  select count(*) into v_live_before from public.agent_actions a
   where a.status = 'pending' and a.detail ? 'supplier_id' and (a.detail ->> 'supplier_id') ~ '^[0-9]{1,18}$'
     and exists (select 1 from public.leads l where l.id = (a.detail ->> 'supplier_id')::bigint);
  insert into public.leads (company_name, email) values ('ZZ DEMO Gone Supplier Probe LLC', 'zz-demo-gone@example.invalid') returning id into v_lead;
  insert into public.leads (company_name, email) values ('ZZ DEMO Kept Supplier Probe LLC', 'zz-demo-kept@example.invalid') returning id into v_ctl;
  insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
  values ('sales_engineer', 'document_read_stuck', 'pending', 'low', 'ZZ DEMO probe: a document of a supplier that will be deleted',
          jsonb_build_object('supplier_id', v_lead, 'path', 'profiles/' || v_lead || '/zz_probe.pdf'), 'supplier_capabilities', v_lead || ':profiles/zz_probe.pdf')
  returning id into a_gone;
  insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
  values ('sales_engineer', 'document_read_stuck', 'pending', 'low', 'ZZ DEMO probe: a document of a supplier that stays',
          jsonb_build_object('supplier_id', v_ctl, 'path', 'profiles/' || v_ctl || '/zz_probe.pdf'), 'supplier_capabilities', v_ctl || ':profiles/zz_probe.pdf')
  returning id into a_ctl;

  delete from public.leads where id = v_lead;
  select status into s_gone from public.agent_actions where id = a_gone;
  select status into s_ctl from public.agent_actions where id = a_ctl;
  if s_gone is distinct from 'dismissed' then fail := fail || format('delete: the action stayed %s; ', s_gone); end if;
  if s_ctl is distinct from 'pending' then fail := fail || format('control: the action became %s; ', s_ctl); end if;

  select count(*) into v_named from public.agent_actions a
   where a.status = 'pending' and a.kind <> 'handoff' and a.detail ? 'supplier_id' and (a.detail ->> 'supplier_id') ~ '^[0-9]{1,18}$'
     and not exists (select 1 from public.leads l where l.id = (a.detail ->> 'supplier_id')::bigint);
  v_swept := public.fn_agent_actions_close_for_gone_suppliers(null);
  if v_swept < v_named then fail := fail || format('sweep: closed %s of %s; ', v_swept, v_named); end if;
  select string_agg(id || '=' || status, ',' order by id) into v_two from public.agent_actions where id in (324789, 340683);
  if exists (select 1 from public.agent_actions where id in (324789, 340683) and status = 'pending') then fail := fail || 'sweep: a #1901 action is still pending; '; end if;
  if (select status from public.agent_actions where id = a_ctl) <> 'pending' then fail := fail || 'sweep: closed an action whose supplier exists; '; end if;

  select count(*) into v_live_after from public.agent_actions a
   where a.status = 'pending' and a.detail ? 'supplier_id' and (a.detail ->> 'supplier_id') ~ '^[0-9]{1,18}$'
     and exists (select 1 from public.leads l where l.id = (a.detail ->> 'supplier_id')::bigint);
  if v_live_after <> v_live_before + 1 then fail := fail || format('real actions of living suppliers moved: %s -> %s (+1 control expected); ', v_live_before, v_live_after); end if;
  v_beat := pg_get_functiondef('public.fn_supplier_doc_reading_escalate(integer,integer)'::regprocedure) ilike '%fn_agent_actions_close_for_gone_suppliers(null)%';
  if not v_beat then fail := fail || 'the heartbeat step does not run the rule; '; end if;

  raise exception 'CHK<<%>>', jsonb_build_object('verdict', case when fail = '' then 'PROBE OK' else 'PROBE FAILED: ' || fail end,
    'deleted_lead_action', s_gone, 'control_action', s_ctl, 'orphans_before_sweep', v_named, 'swept', v_swept, 'the_two', v_two,
    'living_before', v_live_before, 'living_after', v_live_after, 'heartbeat_runs_rule', v_beat);
end $$;
