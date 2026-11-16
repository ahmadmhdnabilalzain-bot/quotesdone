-- PROBE: THE CEO'S WEEKLY FIGURES READ REFERRALS AND OFFERS TO PAY FOR LEADS. Seat: ceo. Agent: W3_PEOPLE, 16 Nov 2026.
-- Pure probe: no DDL, never applied; run after the_ceos_weekly_figures_read_referrals_and_offers_to_pay_for_leads.sql on a LOCAL
-- Postgres 16. It always raises, so every row is rolled back. Every party is a ZZ DEMO fixture on @example.invalid.
-- PROBE OK only if fn_ceo_weekly_figures (what fn_ceo_weekly_report hands the CEO each week) carries, for the week:
--   1. the offers to pay for more requests or exclusivity (fn_ceo_supplier_demand_signals: count, what was asked, the trade);
--   2. the referrals (fn_ceo_referrals: registrations through a supplier's link, the customers' words);
--   and the figures it already gave are still there.
do $probe$
declare fails text := ''; s bigint; j jsonb;
begin
  insert into public.leads (company_name, email, claimed_by, claimed, emirate, phone, owner_email_verified)
  values ('ZZ DEMO W3C Painter', 'zz-demo-w3c@example.invalid', 'zz-demo-w3c@example.invalid', true, 'Dubai', '+971500000741', true) returning id into s;
  -- the accountant's VAT setting as production holds it (a local database built from the schema has none)
  if not exists (select 1 from public.gl_settings where key = 'vat_registration_threshold_aed') then
    insert into public.gl_settings (key, num_value) values ('vat_registration_threshold_aed', 375000);
  end if;
  if not exists (select 1 from public.gl_settings where key = 'vat_voluntary_threshold_aed') then
    insert into public.gl_settings (key, num_value) values ('vat_voluntary_threshold_aed', 187500);
  end if;
  perform public.fn_supplier_demand_signal_record(s, 'whatsapp', 'exclusivity on villa painting', 'painting', 'villas', 'ZZ DEMO I will pay for all villa jobs');
  j := public.fn_ceo_weekly_figures(current_date - 6, current_date);
  if coalesce((j->'supply'->'offers_to_pay_for_leads'->>'signals')::int, 0) < 1
     or coalesce(j->'supply'->'offers_to_pay_for_leads'->'by_ask'->>'exclusivity on villa painting', '') <> '1' then
    fails := fails || ' 1:offers(' || coalesce(left((j->'supply')::text, 300), 'none') || ')'; end if;
  if jsonb_typeof(j->'supply'->'referrals'->'suppliers') is distinct from 'object' or jsonb_typeof(j->'supply'->'referrals'->'customers') is distinct from 'object' then
    fails := fails || ' 2:referrals'; end if;
  if j->'money' is null or j->'demand' is null or j->'supply'->>'leads_total' is null or j->'seats' is null then fails := fails || ' 3:lost_a_figure'; end if;
  if coalesce(fails, 'a check wrote null') <> '' then raise exception 'CHK<<PROBE FAILED:%>>', fails; end if;
  raise exception 'CHK<<PROBE OK: the weekly figures carry the week''s offers to pay for leads and the referrals, and every figure they gave before>>';
end $probe$;
