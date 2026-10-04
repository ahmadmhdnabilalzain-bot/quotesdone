-- PROBE: the CEO writes an internal UAE market report every month. Pure probe, no DDL: run AFTER its .sql in the
-- SAME query through node scripts/qsql.mjs; it always ends in raise exception CHK<<...>>, so nothing survives
-- (the founder notice and the held question it files roll back with it). Demo-inclusive run (p_include_demo).
-- PROBE OK only if:
--   1. the September 2026 report is stored with audience 'internal', all four sections, and the #1164 check run;
--   2. the binding finding (a trade below target with demand) opened a market_report improvement for the sales
--      engineer, assigned with a handoff;
--   3. an earlier market_report improvement whose gap reached target is closed by the run;
--   4. a second run for the same month answers 'already'; the duty answers not-due on the 2nd;
--   5. anon and authenticated can neither read the table nor execute the routines.
do $probe$
declare v jsonb; r public.ceo_market_report; v_fail text := ''; v_old bigint; g record;
begin
  -- 3: an older finding on a trade whose gap is closed inside this transaction
  select trade, emirate into g from public.supply_gap where emirate = 'UAE' order by trade limit 1;
  update public.supply_gap set matchable = target where trade = g.trade and emirate = g.emirate;
  v_old := public.fn_ceo_improvement_open('market_report', 'zz-demo-probe', 'sales_engineer', 'ZZ DEMO probe finding',
                                          jsonb_build_object('trade', g.trade, 'emirate', g.emirate));

  v := public.fn_ceo_market_report(date '2026-09-01', true);
  select * into r from public.ceo_market_report where month = date '2026-09-01';
  if r.month is null then v_fail := v_fail || ' no report;';
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
  if coalesce((public.fn_ceo_market_report(date '2026-09-01', true)->>'already')::boolean, false) is false then v_fail := v_fail || ' not idempotent;'; end if;
  if (public.fn_ceo_market_report_now(date '2026-10-02')->>'due')::boolean then v_fail := v_fail || ' due on the 2nd;'; end if;
  if has_table_privilege('anon', 'public.ceo_market_report', 'select') or has_table_privilege('authenticated', 'public.ceo_market_report', 'select')
     or has_function_privilege('anon', 'public.fn_ceo_market_report(date, boolean)', 'execute')
     or has_function_privilege('authenticated', 'public.fn_ceo_market_report_now(date)', 'execute')
    then v_fail := v_fail || ' reachable by anon/authenticated;'; end if;

  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK binding=' || coalesce(r.binding->>'trade', 'none') || '/' || coalesce(r.binding->>'emirate', '-')
                                     else 'PROBE FAILED:' || v_fail end;
end $probe$;
