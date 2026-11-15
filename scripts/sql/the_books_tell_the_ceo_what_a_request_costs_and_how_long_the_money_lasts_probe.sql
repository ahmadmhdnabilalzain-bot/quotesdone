-- PROBE, ROLLED BACK: founder funding feeds the runway; cost per request excludes test spend; break-even and cuts compute.
-- For scripts/sql/the_books_tell_the_ceo_what_a_request_costs_and_how_long_the_money_lasts.sql. Seat: accountant.
-- Pure probe, no DDL: it always ends in raise exception 'CHK<<...>>'. LOCAL Postgres 16 ONLY (built from the schema mirror,
-- whose money tables are empty): it asserts absolute figures on the rows it seeds, so it is never run on production.
--   psql -1 -f <file>.sql -f <file>_probe.sql      (expect CHK<<PROBE OK ...>>)
-- It cannot reach a person: it runs on a local copy and is rolled back. The real-request customer cannot carry a demo
-- address (the demo rule would exclude it, which is the point), so it is 'buyer@probe-books.ae', on that local copy only.
do $probe$
declare
  v_fi bigint; v_d date := (now() at time zone 'Asia/Dubai')::date; v_m date := date_trunc('month', (now() at time zone 'Asia/Dubai')::date)::date;
  v_prev date; f jsonb; r jsonb; e jsonb; v_cust uuid; v_fail text := ''; v_n numeric;
begin
  v_prev := (v_m - interval '1 month')::date;
  if exists (select 1 from public.gl_journal) or exists (select 1 from public.accountant_month_close) then
    raise exception 'CHK<<PROBE FAILED: not an empty local ledger; this probe runs only on a local copy built from the mirror>>';
  end if;
  insert into public.founder_instruction (said_at, instruction, subject, status)
  values (now(), 'probe: I fund the company', 'probe', 'open') returning id into v_fi;

  -- the ledger: capital 1,000 in; 500 paid on his card; 2,300 paid from the account (so 1,300 has no recorded funding)
  perform public.fn_gl_entry(v_m, 'probe capital', 'owner_capital', 'probe:1', '[{"account":"1000","debit":1000},{"account":"3000","credit":1000}]'::jsonb, 'probe');
  perform public.fn_gl_entry(v_m, 'probe owner card', 'manual', 'probe:2', '[{"account":"6000","debit":500},{"account":"2500","credit":500}]'::jsonb, 'probe');
  perform public.fn_gl_entry(v_m, 'probe bank paid', 'manual', 'probe:3', '[{"account":"6000","debit":2300},{"account":"1000","credit":2300}]'::jsonb, 'probe');
  insert into public.accountant_month_close (month, figures) values
    ((v_m - interval '3 months')::date, '{"cash_out":{"expenses_aed":3000}}'),
    ((v_m - interval '2 months')::date, '{"cash_out":{"expenses_aed":3000}}'),
    (v_prev, '{"cash_out":{"expenses_aed":3000}}');
  insert into public.bank_statement_intake (source_ref, account, statement_month, state, lines, closing_balance_aed, balance_on)
  values ('probe:funding', 'mashreq', v_prev, 'parsed', 0, 1000, (v_m - 1));

  -- 1. founder funding read from the ledger
  f := public.fn_accountant_founder_funding(null);
  if (f->>'received_aed')::numeric <> 1500 or (f->>'owner_capital_3000_aed')::numeric <> 1000 or (f->>'paid_by_owner_2500_aed')::numeric <> 500
     or (f->>'paid_from_the_account_with_no_recorded_funding_aed')::numeric <> 1300 or f->>'committed_aed_per_month' is not null
     or (f->>'funding_per_month_used_aed')::numeric <> 3000 or f->>'funding_basis' not like 'measured%' then
    v_fail := v_fail || ' funding:' || f::text || ';';
  end if;
  -- the forecast now carries his funding (measured 3,000 a month = 692.31 a week)
  r := public.fn_accountant_cash_13_weeks();
  if (r #>> '{weeks,0,inflow_founder_funding_aed}')::numeric <> 692.31 then v_fail := v_fail || ' 13w-measured:' || (r->'weeks'->0)::text || ';'; end if;

  -- 2. a commitment is recorded only from his word; dry run writes nothing
  begin perform public.fn_accountant_founder_commitment_record(1000, v_m, -1, false); v_fail := v_fail || ' commitment-without-ledger;';
  exception when others then null; end;
  r := public.fn_accountant_founder_commitment_record(1000, v_prev, v_fi, true);
  if exists (select 1 from public.founder_funding_commitment) then v_fail := v_fail || ' commitment-dry-run-wrote;'; end if;
  r := public.fn_accountant_founder_commitment_record(1000, v_prev, v_fi, false);
  if (select num_value from public.gl_settings where key = 'founder_committed_funding_aed_per_month') <> 1000 then v_fail := v_fail || ' commitment-setting;'; end if;

  -- 3. runway with founder funding: cash 1,000; spend 3,000; funding 1,000 -> 2,000 uncovered -> 0.5 months
  r := public.fn_accountant_runway_figures(v_prev);
  if (r->>'runway_months_with_founder_funding')::numeric is distinct from 0.5 or (r->>'monthly_burn_after_founder_funding_aed')::numeric <> 2000
     or (r #>> '{cash_13_weeks,weeks,0,inflow_founder_funding_aed}')::numeric <> 230.77 then
    v_fail := v_fail || ' runway:' || (r - 'cash_13_weeks' - 'founder_funding')::text || ';';
  end if;
  -- a commitment that meets the burn: covered, no month count
  perform public.fn_accountant_founder_commitment_record(5000, v_prev, v_fi, false);
  r := public.fn_accountant_runway_figures(v_prev);
  if r->>'runway_months_with_founder_funding' is not null or r->>'runway_with_founder_funding' not like 'covered%' then
    v_fail := v_fail || ' runway-covered:' || (r->>'runway_with_founder_funding') || ';';
  end if;

  -- 4. request economics: one real request; test spend never reaches the cost per request
  insert into public.customers (email) values ('buyer@probe-books.ae') returning id into v_cust;
  insert into public.inquiries (customer_id) values (v_cust);
  insert into public.ai_cost_log (fn, model_used, cost_aed, e2e_run_tag) values
    ('inquiry_intake', 'probe', 2.00, null),        -- a real request's model cost
    ('knowledge_exam', 'probe', 5.00, null),        -- certification: test
    ('resilience_ping', 'probe', 3.00, null),       -- clock overhead: fixed
    ('inquiry_intake', 'probe', 4.00, null),        -- a journey (tagged below: the insert trigger keeps only an open run's tag)
    ('quote_compare',  'probe', 2.00, null);
  update public.ai_cost_log set e2e_run_tag = 'proberun1' where model_used = 'probe' and cost_aed in (4.00, 2.00) and fn in ('inquiry_intake', 'quote_compare')
     and id > (select max(id) - 5 from public.ai_cost_log) and not (fn = 'inquiry_intake' and cost_aed = 2.00);
  insert into public.break_even_basis (id, founder_spent_aed, spent_as_of, target_date, customer_launch, licence_aed, licence_due,
         assumed_quote_aed, assumed_reveal_rate, assumed_requests_per_supplier_month, assumed_invite_to_verified, reason)
  values (1, 0, v_d, v_d + 200, v_d + 30, 1200, v_d + 200, 13000, 0.15, 0.2, 0.03, 'probe')
  on conflict (id) do update set assumed_quote_aed = 13000, assumed_reveal_rate = 0.15;
  insert into public.break_even_cost_line (vendor_key, label, kind, source, monthly_aed, basis) values
    ('openai', 'probe ChatGPT', 'recurring', 'expense_entries_subscription', 799, 'probe'),
    ('anthropic', 'probe Claude', 'recurring', 'expense_entries_subscription', 775.01, 'probe'),
    ('openrouter', 'probe OpenRouter', 'recurring', 'openrouter_day', 1000, 'probe');
  insert into public.expenses (vendor, category, amount, currency, active) values ('Vercel', 'Subscription', 49.90, 'USD', true), ('Vercel Inc.', 'Subscription', 56.75, 'USD', true);

  e := public.fn_accountant_request_economics(v_d);
  if (e->>'requests_real')::int <> 1 or (e #>> '{cost_per_request,real_aed}')::numeric <> 2.00
     or (e #>> '{cost_per_request,journeys_aed}')::numeric <> 6.00 or (e #>> '{cost_per_request,journeys}')::int <> 1
     or (e #>> '{reconciliation,model_cost_log_by_driver,test}')::numeric <> 11.00 then
    v_fail := v_fail || ' cpr:' || (e->'cost_per_request')::text || (e #> '{reconciliation,model_cost_log_by_driver}')::text || ';';
  end if;
  -- margin: 0.15 x 390 = 58.50 less 2.00 = 56.50; fixed: 799 + 775.01 + 1000 x 0.6 = 2,174.01 -> 39 requests; after cuts 1,375.01 -> 25
  if (e #>> '{margin_per_request,aed}')::numeric <> 56.50 or (e #>> '{fixed_costs_today,aed_per_month}')::numeric <> 2174.01
     or (e #>> '{break_even,requests_per_month}')::numeric <> 39 or (e #>> '{break_even,requests_per_month_after_cuts}')::numeric <> 25
     or (e #>> '{break_even,reveals_per_month}')::numeric <> 6 then
    v_fail := v_fail || ' break-even:' || (e->'margin_per_request')::text || (e->'break_even')::text || ';';
  end if;
  if not exists (select 1 from jsonb_array_elements(e->'cost_cuts') x where x->>'id' = 'stop_openai' and (x->>'saving_aed_per_month')::numeric = 799)
     or not exists (select 1 from jsonb_array_elements(e->'cost_cuts') x where x->>'id' = 'duplicate_vercel') then
    v_fail := v_fail || ' cuts:' || (e->'cost_cuts')::text || ';';
  end if;

  -- 5. the daily duty writes this month and last, and the CEO reading carries economics, funding and runway
  r := public.fn_accountant_request_economics_tick();
  if (select count(*) from public.accountant_request_economics where month in (v_m, v_prev)) <> 2
     or r #>> '{economics,month}' <> to_char(v_m, 'YYYY-MM') or r->'founder_funding' is null or r #>> '{runway,month}' <> to_char(v_prev, 'YYYY-MM') then
    v_fail := v_fail || ' tick:' || left(r::text, 300) || ';';
  end if;
  if not exists (select 1 from public.seat_duty where duty = 'accountant.request_economics' and routine = 'fn_accountant_request_economics_tick') then
    v_fail := v_fail || ' duty;';
  end if;

  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK: founder funding feeds the runway, test spend is out of the cost per request, break-even and cuts compute'
                                     else 'PROBE FAILED:' || v_fail end;
end $probe$;
