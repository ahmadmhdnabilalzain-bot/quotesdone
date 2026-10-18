-- PROBE: the CEO improvement sweep settles in ONE run. Pure probe -- NO DDL; it ends in raise exception, so every
-- row it writes rolls back and only the CHK<<...>> verdict comes out. Seat: ceo. 30 Sep 2026.
-- Pairs with the_ceo_improvement_sweep_closes_before_it_proposes_and_settles_in_one_run.sql. Against the body that
-- proposes before it closes it FAILS (run 2 proposes what run 1's closures freed; a month rollover opens a second
-- improvement for the same metric). To prove the fix before it is applied, send the fix file and this probe as ONE
-- request -- the raise rolls both back.
--
-- FIXTURES: six ZZ DEMO metrics (metric_key zz_demo_target_*) on the active year-one contract, owned by marketing.
-- Five are behind their path (8 misses in 14 days, the latest today); one missed 7-13 days back and has been on
-- its path for the last 7 days, today included (recovered). The founder notify path is stubbed.
do $$
declare c bigint; r1 jsonb; r2 jsonb; r3 jsonb; o jsonb; v_first int; v_keys int; v_open2 int; v_rec int;
  v_closed1 text; v_reopen1 int; v_open3 int; v_id2 bigint;
begin
  set local statement_timeout = '120s';
  perform set_config('app.qd_stub_founder_notify', 'on', true);
  select id into c from public.target_contract where contract_key = 'FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30' and status = 'active';
  if c is null then raise exception 'CHK<<{"error":"no active year-one contract"}>>'; end if;

  insert into public.target_daily_verdict (day, contract_id, metric_key, owner_seat, expected, actual, gap_pct, status)
  select current_date - g, c, 'zz_demo_target_' || k, 'marketing', 10, 0, -100, 'miss'
    from generate_series(1, 5) k, generate_series(0, 7) g;
  insert into public.target_daily_verdict (day, contract_id, metric_key, owner_seat, expected, actual, gap_pct, status)
  select current_date - g, c, 'zz_demo_target_recovered', 'marketing', 10, case when g <= 6 then 10 else 0 end,
         case when g <= 6 then 0 else -100 end, case when g <= 6 then 'on_track' else 'miss' end
    from generate_series(0, 13) g;

  -- RUN 1: every missed ZZ target gets exactly one improvement; the recovered one gets none
  r1 := public.fn_ceo_improvement_sweep();
  select count(*), count(distinct evidence->>'metric') into v_first, v_keys
    from public.ceo_improvement where source_kind = 'recurring_miss' and evidence->>'metric' like 'zz_demo_target_%';
  select count(*) into v_rec from public.ceo_improvement where evidence->>'metric' = 'zz_demo_target_recovered';

  -- a month turns over while zz_demo_target_2 is still behind: its open improvement carries last month's key
  update public.ceo_improvement set source_ref = 'zz_demo_target_2:' || to_char(current_date - interval '1 month', 'YYYY-MM')
   where source_kind = 'recurring_miss' and evidence->>'metric' = 'zz_demo_target_2' returning id into v_id2;

  -- RUN 2: nothing changed that matters, so nothing new anywhere -- not one row, not only the ZZ ones
  r2 := public.fn_ceo_improvement_sweep();
  select count(*) into v_open2 from public.ceo_improvement
   where source_kind = 'recurring_miss' and evidence->>'metric' like 'zz_demo_target_%' and status in ('open', 'assigned');

  -- zz_demo_target_1 recovers: 7 days on its path since its improvement opened
  update public.ceo_improvement set created_at = now() - interval '10 days'
   where source_kind = 'recurring_miss' and evidence->>'metric' = 'zz_demo_target_1';
  update public.target_daily_verdict set status = 'on_track', actual = 10, gap_pct = 0
   where contract_id = c and metric_key = 'zz_demo_target_1' and day > current_date - 7;
  -- ...while still showing 7 misses in its 14-day window, and under last month's key, so neither the miss count nor
  -- the (source_kind, source_ref) key can be what keeps it from being proposed again: only the recovery rule can
  insert into public.target_daily_verdict (day, contract_id, metric_key, owner_seat, expected, actual, gap_pct, status)
  select current_date - g, c, 'zz_demo_target_1', 'marketing', 10, 0, -100, 'miss' from generate_series(8, 13) g;
  update public.ceo_improvement set source_ref = 'zz_demo_target_1:' || to_char(current_date - interval '1 month', 'YYYY-MM')
   where source_kind = 'recurring_miss' and evidence->>'metric' = 'zz_demo_target_1';
  -- RUN 3: it is closed, and not proposed again
  r3 := public.fn_ceo_improvement_sweep();
  select status into v_closed1 from public.ceo_improvement where source_kind = 'recurring_miss' and evidence->>'metric' = 'zz_demo_target_1'
   order by id limit 1;
  select count(*) into v_reopen1 from public.ceo_improvement where evidence->>'metric' = 'zz_demo_target_1' and status in ('open', 'assigned');
  select count(*) into v_open3 from public.ceo_improvement
   where source_kind = 'recurring_miss' and evidence->>'metric' like 'zz_demo_target_%' and status in ('open', 'assigned');

  o := jsonb_build_object('run1', r1, 'run2', r2, 'run3', r3, 'zz_first', v_first, 'zz_distinct', v_keys, 'zz_recovered', v_rec,
         'zz_open_after_rollover', v_open2, 'target1_status', v_closed1, 'target1_reopened', v_reopen1, 'zz_open_after_recovery', v_open3,
         'run3_proposed', (r3->>'proposed')::int);
  o := o || jsonb_build_object('verdict', case
    when v_first <> 5 or v_keys <> 5 then 'PROBE FAILED: 5 missed ZZ targets opened ' || v_first || ' improvement(s) for ' || v_keys || ' target(s)'
    when v_rec <> 0 then 'PROBE FAILED: the recovered ZZ target was proposed'
    when (r2->>'proposed')::int <> 0 then 'PROBE FAILED: the second run proposed ' || (r2->>'proposed') || ' more (the sweep does not settle in one run)'
    when v_open2 <> 5 then 'PROBE FAILED: after a month turned over the 5 ZZ targets have ' || v_open2 || ' open improvements'
    when v_closed1 is distinct from 'done' then 'PROBE FAILED: the recovered target''s improvement is ' || coalesce(v_closed1, 'missing')
    when v_reopen1 <> 0 then 'PROBE FAILED: the recovered target was proposed again'
    when v_open3 <> 4 then 'PROBE FAILED: after the recovery ' || v_open3 || ' ZZ improvements are open, expected 4'
    else 'PROBE OK' end);
  raise exception 'CHK<<%>>', o::text;
end $$;
