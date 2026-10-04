-- PROBE: the CEO writes an internal UAE market report every month. Pure probe, no DDL: run AFTER its .sql in the
-- SAME query through node scripts/qsql.mjs; it always ends in raise exception CHK<<...>>, so nothing survives
-- (the founder notices and the held questions it files roll back with it).
-- PROBE OK only if:
--   1. a DEMO run (p_include_demo) stores its own row, leaves the real month's slot free and touches no
--      improvement: nothing closed, nothing opened, no handoff (review of #1192);
--   2. the REAL September 2026 run is then stored with audience 'internal', every section, the #1164 check run
--      clean and the commentary filed;
--   3. its binding finding (a trade below target with demand) opened a market_report improvement for the sales
--      engineer, assigned with a handoff, and an earlier finding whose gap reached target is closed;
--   4. a second run for the same month answers 'already'; the duty answers not-due on the 2nd;
--   5. anon and authenticated can neither read the table nor execute the routines.
do $probe$
declare r public.ceo_market_report; v_fail text := ''; v_old bigint; g record; v_impr_before bigint; v_impr_after bigint;
begin
  select trade, emirate into g from public.supply_gap where emirate = 'UAE' order by trade limit 1;
  update public.supply_gap set matchable = target where trade = g.trade and emirate = g.emirate;
  v_old := public.fn_ceo_improvement_open('market_report', 'zz-demo-probe', 'sales_engineer', 'ZZ DEMO probe finding',
                                          jsonb_build_object('trade', g.trade, 'emirate', g.emirate));

  -- 1. demo run first
  select count(*) into v_impr_before from public.ceo_improvement;
  perform public.fn_ceo_market_report(date '2026-09-01', true);
  select count(*) into v_impr_after from public.ceo_improvement;
  if not exists (select 1 from public.ceo_market_report where month = date '2026-09-01' and include_demo) then v_fail := v_fail || ' demo row missing;'; end if;
  if exists (select 1 from public.ceo_market_report where month = date '2026-09-01' and not include_demo) then v_fail := v_fail || ' demo took the real slot;'; end if;
  if v_impr_after <> v_impr_before then v_fail := v_fail || ' demo opened an improvement;'; end if;
  if not exists (select 1 from public.ceo_improvement where id = v_old and status = 'assigned') then v_fail := v_fail || ' demo closed a real improvement;'; end if;
  if exists (select 1 from public.ceo_market_report where include_demo and improvement_id is not null) then v_fail := v_fail || ' demo recorded an improvement;'; end if;

  -- 2-3. the real run
  if coalesce((public.fn_ceo_market_report(date '2026-09-01', false)->>'already')::boolean, false) then v_fail := v_fail || ' real month answered already;'; end if;
  select * into r from public.ceo_market_report where month = date '2026-09-01' and not include_demo;
  if r.month is null then v_fail := v_fail || ' no real report;';
  else
    if r.audience <> 'internal' then v_fail := v_fail || ' audience;'; end if;
    if r.body !~ '1\. DEMAND' or r.body !~ '2\. SUPPLY' or r.body !~ '3\. PRICES' or r.body !~ '5\. THE BINDING FINDING' then v_fail := v_fail || ' sections;'; end if;
    if r.named_check is not null then v_fail := v_fail || ' body names a supplier: ' || r.named_check || ';'; end if;
    if r.held_id is null then v_fail := v_fail || ' commentary not filed;'; end if;
    if r.binding is not null and not exists (select 1 from public.ceo_improvement where id = r.improvement_id and seat = 'sales_engineer'
                                                and source_kind = 'market_report' and status = 'assigned' and handoff_id is not null)
      then v_fail := v_fail || ' binding finding not assigned;'; end if;
  end if;
  if not exists (select 1 from public.ceo_improvement where id = v_old and status = 'done') then v_fail := v_fail || ' recovered finding not closed;'; end if;

  -- 4-5
  if coalesce((public.fn_ceo_market_report(date '2026-09-01', false)->>'already')::boolean, false) is false then v_fail := v_fail || ' not idempotent;'; end if;
  if (public.fn_ceo_market_report_now(date '2026-10-02')->>'due')::boolean then v_fail := v_fail || ' due on the 2nd;'; end if;
  if has_table_privilege('anon', 'public.ceo_market_report', 'select') or has_table_privilege('authenticated', 'public.ceo_market_report', 'select')
     or has_function_privilege('anon', 'public.fn_ceo_market_report(date, boolean)', 'execute')
     or has_function_privilege('authenticated', 'public.fn_ceo_market_report_now(date)', 'execute')
    then v_fail := v_fail || ' reachable by anon/authenticated;'; end if;

  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK binding=' || coalesce(r.binding->>'trade', 'none') || '/' || coalesce(r.binding->>'emirate', '-') || ' demo_isolated'
                                     else 'PROBE FAILED:' || v_fail end;
end $probe$;
