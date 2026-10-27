-- PROBE: the ceo's five numbers. Pure probe, no DDL: run AFTER the_ceo_reads_five_numbers_every_morning.sql; it
-- always ends in raise exception CHK<<...>>, so nothing it writes survives. It contacts no one: the only rows it
-- adds are two requests with no customer (nobody to write to) and the ceo's own handoff, all rolled back.
-- PROBE OK only if:
--   1. a request with no demo marker counts in requests_created and a qd_run (demo) request does not;
--   2. the duty hands yesterday's numbers to the CEO (agent 'ceo', type report.five_numbers) and the CEO's read answers;
--   3. a second run the same day returns the SAME handoff (one per day);
--   4. nothing was queued to the founder.
do $probe$
declare v_day date := (now() at time zone 'Asia/Dubai')::date; v0 jsonb; v1 jsonb; r1 jsonb; r2 jsonb;
        a public.agent_actions; v_founder int; v_fail text := '';
begin
  v0 := public.fn_ceo_five_numbers(v_day);
  insert into public.inquiries (customer_id, category, trades, emirate, raw_input, status)
  values (null, 'aluminium', array['aluminium'], 'Dubai', 'ZZ DEMO five-numbers probe: counts as a request', 'draft');
  insert into public.inquiries (customer_id, category, trades, emirate, raw_input, status, provenance)
  values (null, 'aluminium', array['aluminium'], 'Dubai', 'ZZ DEMO five-numbers probe: demo, never counted', 'draft',
          '{"qd_run":"probe5num"}'::jsonb);
  v1 := public.fn_ceo_five_numbers(v_day);
  if (v1->>'requests_created')::int <> (v0->>'requests_created')::int + 1 then
    v_fail := v_fail || ' requests_created ' || (v0->>'requests_created') || '->' || (v1->>'requests_created') || ' (want +1);';
  end if;

  r1 := public.fn_ceo_five_number_report();
  r2 := public.fn_ceo_five_number_report();
  select * into a from public.agent_actions where id = (r1->>'handoff_id')::bigint;
  if a.agent is distinct from 'ceo' or a.detail->>'type' is distinct from 'report.five_numbers' then
    v_fail := v_fail || ' handoff went to ' || coalesce(a.agent, 'nobody') || ';';
  end if;
  if a.status is distinct from 'done' or coalesce((a.evidence->>'read')::boolean, false) is not true then
    v_fail := v_fail || ' the CEO did not read it (status ' || coalesce(a.status, 'null') || ');';
  end if;
  if (r2->>'handoff_id') is distinct from (r1->>'handoff_id') then v_fail := v_fail || ' a second run made a second handoff;'; end if;
  select count(*) into v_founder from public.notifications
   where created_at >= now() and (to_role in ('founder', 'admin') or type ~* 'five');
  if v_founder > 0 then v_fail := v_fail || ' ' || v_founder || ' notification(s) queued to the founder;'; end if;

  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK requests ' || (v0->>'requests_created') || '->' || (v1->>'requests_created')
      || ' (demo excluded); handoff ' || (r1->>'handoff_id') || ' to ceo, read; same handoff on re-run; 0 to the founder'
    else 'PROBE FAILED:' || v_fail end;
end $probe$;
