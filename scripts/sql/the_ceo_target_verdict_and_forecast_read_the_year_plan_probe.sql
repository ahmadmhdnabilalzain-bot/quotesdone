-- PROBE for the_ceo_target_verdict_and_forecast_read_the_year_plan.sql. Pure probe: no DDL, always raises, so every
-- row it writes rolls back. It seeds two approved suppliers, one ZZ DEMO at example.invalid and one with NO email or phone
-- (nothing to deliver to), with triggers off for the insert only (session_replication_role = replica, local to the transaction), so no
-- approval message, emit or outbox row can be created; it asserts the notifications count did not move.
-- Asserts: the verdict's metric list is never empty (September run-in, an October day, a November day); the forecast
-- names no withdrawn contract; customer metrics before January 2027 are 'not_yet_due'; a ZZ DEMO supplier moves the
-- supplier metric by 0 (excluded) and a real-shaped one by exactly 1; CUSTOMERS_1000 is closed.
do $probe$
declare r jsonb; r_oct jsonb; r_nov jsonb; f jsonb; a0 numeric; a_demo numeric; a_real numeric; n0 bigint; n1 bigint;
  n_sep int; n_oct int; n_nov int; n_pre int; n_cust_active int;
  metric_of constant text := $$select (m->>'actual')::numeric from jsonb_array_elements($1->'metrics') m where m->>'metric' = 'verified_suppliers_milestone'$$;
begin
  select count(*) into n0 from public.notifications;

  r := public.fn_ceo_target_daily_verdict(timestamptz '2026-09-28 12:00+04');
  n_sep := jsonb_array_length(r->'metrics');
  if n_sep = 0 then raise exception 'CHK<<FAIL september metrics empty>>'; end if;
  execute metric_of into a0 using r;
  if a0 is null then raise exception 'CHK<<FAIL no supplier milestone metric: %>>', r; end if;

  r_oct := public.fn_ceo_target_daily_verdict(timestamptz '2026-10-10 12:00+04');
  r_nov := public.fn_ceo_target_daily_verdict(timestamptz '2026-11-15 12:00+04');
  n_oct := jsonb_array_length(r_oct->'metrics'); n_nov := jsonb_array_length(r_nov->'metrics');
  select count(*) into n_pre from jsonb_array_elements(r_nov->'metrics') m
   where m->>'metric' in ('inquiries_posted', 'reveals_paid', 'fee_aed') and m->>'status' = 'not_yet_due';
  if n_oct = 0 or n_nov = 0 or n_pre <> 3 then raise exception 'CHK<<FAIL oct % nov % prelaunch %>>', n_oct, n_nov, n_pre; end if;

  f := public.fn_ceo_target_forecast();
  if f::text ~ 'REVENUE_AED_1M|SUPPLIERS_1000|CUSTOMERS_1000' then raise exception 'CHK<<FAIL forecast grades a withdrawn contract: %>>', f; end if;
  select count(*) into n_cust_active from public.target_contract where contract_key = 'CUSTOMERS_1000_BY_2027_10_01' and status = 'active';

  set local session_replication_role = replica;   -- no trigger fires for these two rows: nothing can reach anyone
  insert into public.leads (company_name, email, approved_at)
  values ('ZZ DEMO probe verified supplier', 'zz-demo-probe@example.invalid', timestamptz '2026-09-27 10:00+04');
  r := public.fn_ceo_target_daily_verdict(timestamptz '2026-09-28 12:00+04'); execute metric_of into a_demo using r;
  insert into public.leads (company_name, email, approved_at)
  values ('Probe verified supplier (rolled back)', null, timestamptz '2026-09-27 10:00+04');
  r := public.fn_ceo_target_daily_verdict(timestamptz '2026-09-28 12:00+04'); execute metric_of into a_real using r;
  set local session_replication_role = origin;

  select count(*) into n1 from public.notifications;
  if a_demo <> a0 or a_real - a_demo <> 1 or n1 <> n0 or n_cust_active <> 0 then
    raise exception 'CHK<<FAIL demo_delta=% real_delta=% notifications_delta=% customers_1000_active=%>>', a_demo - a0, a_real - a_demo, n1 - n0, n_cust_active;
  end if;
  raise exception 'CHK<<PROBE OK (real_delta=1 is the rolled-back real-shaped control row, not a real row) sep_metrics=% oct_metrics=% nov_metrics=% prelaunch_not_yet_due=% withdrawn_in_forecast=0 customers_1000_active=% demo_delta=% real_delta=% notifications_delta=%>>',
    n_sep, n_oct, n_nov, n_pre, n_cust_active, a_demo - a0, a_real - a_demo, n1 - n0;
end $probe$;
