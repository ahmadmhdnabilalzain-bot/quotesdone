-- Seat: sales_engineer. PROBE for an_open_supply_gap_becomes_a_recruitment_brief_marketing_reads_and_closes_at_target.sql.
-- Pure probe, no DDL: it always raises, so every ZZ DEMO row it writes is rolled back.
-- It must end with CHK<<PROBE OK ...>>. Fixtures: trade 'zz_demo_recruit', a ZZ DEMO lead at example.invalid.
do $probe$
declare v_lead bigint; v_brief record; v_gap record; r1 jsonb; r2 jsonb;
begin
  insert into public.leads (company_name, email, emirate, invite_trades, invited_at)
  values ('ZZ DEMO recruit supplier', 'zz-demo-recruit@example.invalid', 'Dubai', array['zz_demo_recruit'], now())
  returning id into v_lead;
  insert into public.supply_gap (trade, emirate, matchable, target, demand_90d, short_open, uninvited_pool, status, measured_at, opened_at)
  values ('zz_demo_recruit', 'Dubai', 2, 10, 3, 1, 0, 'open', now(), now());

  -- 1. open gap -> brief row -> gap in 'recruit' linked to it
  r1 := public.fn_sales_engineer_supply_gap_to_recruitment_brief();
  select * into v_brief from public.supply_recruitment_brief where trade = 'zz_demo_recruit' and emirate = 'Dubai';
  select * into v_gap from public.supply_gap where trade = 'zz_demo_recruit' and emirate = 'Dubai';
  if v_brief.id is null or v_brief.status <> 'open' or v_brief.shortfall <> 8 or v_brief.invited <> 1 or v_brief.priority <> 'P1'
     or v_gap.status <> 'recruit' or v_gap.brief_id is distinct from v_brief.id then
    raise exception 'CHK<<PROBE FAILED: step 1 brief=% gap=%>>', to_jsonb(v_brief), to_jsonb(v_gap);
  end if;

  -- 2. supply reaches target -> gap closed and brief row closed
  update public.supply_gap set matchable = 10 where trade = 'zz_demo_recruit' and emirate = 'Dubai';
  r2 := public.fn_sales_engineer_supply_gap_to_recruitment_brief();
  select * into v_brief from public.supply_recruitment_brief where trade = 'zz_demo_recruit' and emirate = 'Dubai';
  select * into v_gap from public.supply_gap where trade = 'zz_demo_recruit' and emirate = 'Dubai';
  if v_gap.status <> 'closed' or v_brief.status <> 'closed' or v_brief.closed_at is null then
    raise exception 'CHK<<PROBE FAILED: step 2 brief=% gap=%>>', to_jsonb(v_brief), to_jsonb(v_gap);
  end if;

  raise exception 'CHK<<PROBE OK: gap open -> brief #% (shortfall 8, invited 1, P1, "%") -> gap recruit linked -> at target gap closed + brief closed. run1=% run2=%. prevented by: a recruit gap with no brief row, or a brief row that stays open once supply reaches target>>',
    v_brief.id, v_brief.suggested_sourcing, r1, r2;
end $probe$;
