-- Seat: sales_engineer. PROBE for an_open_supply_gap_becomes_a_recruitment_brief_marketing_reads_and_closes_at_target.sql.
-- Pure probe, no DDL: it always raises, so every row it writes (ZZ DEMO fixtures and the real-data
-- run in step 4) is rolled back. It must end with CHK<<PROBE OK ...>>.
-- Fixtures: trades 'zz_demo_recruit', 'zz_demo_recruit_2', 'zz_demo_pool_a', 'zz_demo_pool_b', and one
-- ZZ DEMO lead at example.invalid.
do $probe$
declare v_lead bigint; v_brief record; v_gap record; r1 jsonb; r2 jsonb; r3 jsonb; r4 jsonb; rf jsonb;
  v_day_start timestamptz := date_trunc('day', now() at time zone 'Asia/Dubai') at time zone 'Asia/Dubai';
  v_promoted int; v_open_before int; v_open_after int; v_groups int; v_findings int; v_pergap int; v_ungrouped jsonb;
begin
  insert into public.leads (company_name, email, emirate, invite_trades, invited_at)
  values ('ZZ DEMO recruit supplier', 'zz-demo-recruit@example.invalid', 'Dubai', array['zz_demo_recruit'], now())
  returning id into v_lead;
  -- two open demo gaps with a customer waiting: they outrank every real open gap (none has one)
  insert into public.supply_gap (trade, emirate, matchable, target, demand_90d, short_open, uninvited_pool, status, measured_at, opened_at)
  values ('zz_demo_recruit', 'Dubai', 2, 10, 3, 1, 5, 'open', now(), now()),
         ('zz_demo_recruit_2', 'Dubai', 2, 10, 3, 1, 0, 'open', now(), now());

  -- 1. with a budget of ONE, only the best-ranked open gap is promoted: brief row, recruit, linked
  r1 := public.fn_sales_engineer_supply_gap_to_recruitment_brief(1);
  select * into v_brief from public.supply_recruitment_brief where trade = 'zz_demo_recruit' and emirate = 'Dubai';
  select * into v_gap from public.supply_gap where trade = 'zz_demo_recruit' and emirate = 'Dubai';
  if v_brief.id is null or v_brief.status <> 'open' or v_brief.shortfall <> 8 or v_brief.invited <> 1 or v_brief.priority <> 'P1'
     or v_gap.status <> 'recruit' or v_gap.brief_id is distinct from v_brief.id then
    raise exception 'CHK<<PROBE FAILED: step 1 brief=% gap=%>>', to_jsonb(v_brief), to_jsonb(v_gap);
  end if;
  if (select status from public.supply_gap where trade = 'zz_demo_recruit_2') <> 'open'
     or exists (select 1 from public.supply_recruitment_brief where trade = 'zz_demo_recruit_2') then
    raise exception 'CHK<<PROBE FAILED: step 1 a second open gap was promoted on a budget of one: %>>', r1;
  end if;

  -- 2. the same day, the same budget: nothing more is promoted
  r2 := public.fn_sales_engineer_supply_gap_to_recruitment_brief(1);
  if (select status from public.supply_gap where trade = 'zz_demo_recruit_2') <> 'open' then
    raise exception 'CHK<<PROBE FAILED: step 2 a second run on the same day spent a fresh budget: %>>', r2;
  end if;

  -- 3. supply reaches target -> gap closed and brief row closed
  update public.supply_gap set matchable = 10 where trade = 'zz_demo_recruit' and emirate = 'Dubai';
  r3 := public.fn_sales_engineer_supply_gap_to_recruitment_brief(1);
  select * into v_brief from public.supply_recruitment_brief where trade = 'zz_demo_recruit' and emirate = 'Dubai';
  select * into v_gap from public.supply_gap where trade = 'zz_demo_recruit' and emirate = 'Dubai';
  if v_gap.status <> 'closed' or v_brief.status <> 'closed' or v_brief.closed_at is null then
    raise exception 'CHK<<PROBE FAILED: step 3 brief=% gap=%>>', to_jsonb(v_brief), to_jsonb(v_gap);
  end if;

  -- 4. THE FLOOD THE REVIEW FOUND, on real data: the default run promotes at most 10 a day in total.
  select count(*) into v_open_before from public.supply_gap where status = 'open' and trade not like 'zz_demo%';
  r4 := public.fn_sales_engineer_supply_gap_to_recruitment_brief();
  select count(*) into v_promoted from public.supply_gap
   where decided_by = 'sales_engineer:recruitment_brief' and decided_at >= v_day_start;
  select count(*) into v_open_after from public.supply_gap where status = 'open' and trade not like 'zz_demo%';
  if v_promoted > 10 then
    raise exception 'CHK<<PROBE FAILED: step 4 % gaps promoted today, cap is 10: %>>', v_promoted, r4;
  end if;

  -- 5. two recruiting demo gaps with an empty pool -> ONE finding for their group, none per gap,
  --    and never more open pool_empty findings than there are trade groups.
  insert into public.supply_gap (trade, emirate, matchable, target, demand_90d, short_open, uninvited_pool, status, measured_at, opened_at)
  values ('zz_demo_pool_a', 'Dubai', 0, 10, 0, 0, 0, 'recruit', now(), now()),
         ('zz_demo_pool_b', 'Dubai', 0, 10, 0, 0, 0, 'recruit', now(), now());
  rf := public.fn_marketing_recruitment_funnel();
  select count(distinct coalesce(tt.group_code, 'ungrouped')) into v_groups
    from public.supply_gap s left join public.taxonomy_trade tt on tt.code = s.trade where s.status = 'recruit';
  select count(*) filter (where issue_key !~ '^recruitment:pool_empty:[^:]+:'),
         count(*) filter (where issue_key ~ '^recruitment:pool_empty:[^:]+:')
    into v_findings, v_pergap
    from public.it_engineer_finding where issue_key like 'recruitment:pool_empty:%' and closed_at is null;
  select evidence into v_ungrouped from public.it_engineer_finding
   where issue_key = 'recruitment:pool_empty:ungrouped' and closed_at is null;
  if v_ungrouped is null or not (v_ungrouped->'gaps' @> '[{"trade":"zz_demo_pool_a"},{"trade":"zz_demo_pool_b"}]'::jsonb)
     or v_pergap > 0 or v_findings > v_groups then
    raise exception 'CHK<<PROBE FAILED: step 5 group findings=% per-gap findings=% groups=% ungrouped=% funnel=%>>',
      v_findings, v_pergap, v_groups, v_ungrouped, rf;
  end if;

  raise exception 'CHK<<PROBE OK: budget 1 promoted only the top-ranked open gap (brief #%, shortfall 8, invited 1, P1), a second run the same day promoted none, at target gap + brief closed. Real data: % open before, % after, % promoted today (cap 10), run=%. Funnel: % recruiting gaps, % open pool_empty findings for % trade groups, 0 per-gap; funnel=%. prevented by: this probe>>',
    v_brief.id, v_open_before, v_open_after, v_promoted, r4, rf->'gaps_recruiting', v_findings, v_groups, rf;
end $probe$;
