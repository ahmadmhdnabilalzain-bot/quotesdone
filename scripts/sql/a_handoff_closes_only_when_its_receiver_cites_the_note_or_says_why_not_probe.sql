
-- ROLLED-BACK PROBE (27 Oct 2026). Everything above and below is one transaction; the final raise rolls it all back.
do $probe$
declare
  v_t0 timestamptz := now();   -- decided_at = now() is the transaction start; clock_timestamp() would miss every probe row
  v_id bigint; v_ok_a boolean := false; v_res jsonb; v_row public.agent_actions; v_nid bigint; v_ad public.agent_actions;
  v_gaps jsonb; v_fail text := ''; v_err text;
  v_real_before bigint := (select count(*) from public.agent_actions where kind = 'handoff' and status = 'done');
begin
  insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
  values ('customer_support', 'handoff', 'pending', 'low', 'ZZ DEMO probe handoff 1013',
          jsonb_build_object('type', 'delivery.request', 'from', 'sales_engineer', 'subject_table', 'notifications',
                             'subject_id', 'zz-demo-1013-probe', 'decision', 'ZZ DEMO: send the probe notice'),
          'notifications', 'zz-demo-1013-probe')
  returning id into v_id;

  -- a. closing it with no citation and no reason is refused
  begin
    perform set_config('qd.handoff_closer', 'sales_engineer', true);
    update public.agent_actions set status = 'done', decided_at = now(), evidence = '{"verdict":"closed by hand"}'::jsonb where id = v_id;
    v_fail := v_fail || ' a(not refused)';
  exception when check_violation then v_ok_a := true; v_err := sqlerrm;
  end;

  -- b. a reason is accepted
  update public.agent_actions set status = 'done', decided_at = now(),
         evidence = '{"not_cited":{"reason":"ZZ DEMO probe: a reason is enough","by":"probe"}}'::jsonb where id = v_id
  returning * into v_row;
  if v_row.status <> 'done' then v_fail := v_fail || ' b'; end if;

  -- c. a closed row that had a reason cannot lose it
  begin
    update public.agent_actions set evidence = '{}'::jsonb where id = v_id;
    v_fail := v_fail || ' c(reason stripped)';
  exception when check_violation then null;
  end;

  -- d. the citing closer still closes (fn_seat_handoff_complete stamps cites_note)
  update public.agent_actions set status = 'pending', evidence = null, decided_at = null where id = v_id and false; -- no reopen path needed
  insert into public.agent_actions (agent, kind, status, risk, title, detail, target_table, target_id)
  values ('customer_support', 'handoff', 'pending', 'low', 'ZZ DEMO probe handoff 1013 b',
          jsonb_build_object('type', 'delivery.request', 'from', 'sales_engineer', 'subject_table', 'notifications',
                             'subject_id', 'zz-demo-1013-probe-b'),
          'notifications', 'zz-demo-1013-probe-b')
  returning id into v_id;
  perform set_config('qd.handoff_closer', 'sales_engineer', true);
  v_res := public.fn_seat_handoff_complete(v_id, '{"verdict":"ZZ DEMO closed through the closer"}'::jsonb);
  select * into v_row from public.agent_actions where id = v_id;
  if v_row.status <> 'done' or (v_row.evidence->'cites_note'->>'handoff_id') is distinct from v_id::text then v_fail := v_fail || ' d'; end if;

  -- e. a notification written directly is adopted, closed WITH a reason, not refused
  insert into public.notifications (type, to_email, to_role, subject, body, channel, requested_by)
  values ('zz_demo_probe', 'zz-1013-probe@example.invalid', 'customer', 'ZZ DEMO probe', 'ZZ DEMO probe body', 'email', 'sales_engineer')
  returning id into v_nid;
  select * into v_ad from public.agent_actions where kind = 'handoff' and target_id = 'delivery.request:notification:' || v_nid;
  if v_ad.id is null then v_fail := v_fail || ' e(not adopted)';
  elsif v_ad.status <> 'done' or nullif(v_ad.evidence->'not_cited'->>'reason', '') is null then v_fail := v_fail || ' e(no reason)';
  end if;

  -- f. the measurement: nothing closed since t0 is 'neither'
  v_gaps := public.fn_handoff_citation_gaps(v_t0);
  if (v_gaps->>'neither')::int <> 0 or (v_gaps->>'closed_with_note')::int < 3 then v_fail := v_fail || ' f(' || (v_gaps->>'neither') || ' neither)'; end if;

  -- g. no real row was touched: the done count grew by exactly the three probe rows
  if (select count(*) from public.agent_actions where kind = 'handoff' and status = 'done') <> v_real_before + 3 then
    v_fail := v_fail || ' g(done count moved by ' || ((select count(*) from public.agent_actions where kind = 'handoff' and status = 'done') - v_real_before) || ')';
  end if;

  raise exception 'CHK<<%>>', case when v_fail = '' and v_ok_a
    then 'PROBE OK refused=' || left(v_err, 120) || ' gaps=' || v_gaps::text
    else 'PROBE FAILED:' || v_fail || ' gaps=' || coalesce(v_gaps::text, 'null') end;
end $probe$;
