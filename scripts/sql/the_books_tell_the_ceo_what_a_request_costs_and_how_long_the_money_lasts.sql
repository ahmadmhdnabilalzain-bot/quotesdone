-- THE BOOKS TELL THE CEO WHAT A REQUEST COSTS AND HOW LONG THE MONEY LASTS.
-- Seat: accountant (agent: accountant seat builder). 15 Nov 2026. Founder rulings 1701 ("I want to be profitable and that
-- should be the main concern for the CEO"), 1702/1703 (every bill is a cost), 1706 (bring solutions, not issues).
--
-- MEASURED BEFORE THIS FILE (SELECT, 15 Nov 2026)
--   * Founder money recorded in the ledger: 3000 Owner Capital AED 1,000.00 (the 19 Aug 2026 transfer, journal 696) and
--     2500 Due to Owner AED 14,235.23 (company bills he paid on his own card, ruling 1011). break_even_basis.founder_spent_aed
--     says AED 19,000 (ledger 1609, 10 Nov). No monthly funding commitment is recorded (gl_settings has no
--     founder_committed_funding_aed_per_month), so fn_accountant_cash_13_weeks counts none and the forecast runs negative
--     from week 1, and fn_accountant_cash_position reads runway 0 months (cash AED 59.25 on the 30 Sep statement).
--   * GL 1000 Cash & Bank reads AED -3,956.58: the bank cannot be below zero, so that much of what the company paid from the
--     account since 30 Sep was covered by founder transfers that no statement on file shows yet (October has not arrived).
--   * October 2026: ai_cost_log AED 640.72 (432.19 untagged, 208.53 e2e_run_tag), 199 calls unpriced; booked 6000 Software &
--     AI AED 7,802.50; booked OpenRouter metered usage AED 753.29. Real (non-demo) requests: 0 in Oct and 0 ever (3 demo in
--     Sep). fn_accountant_unit_economics counted every ai_cost_log row, test runs included, as request cost.
--   * Request journeys: 176 e2e-tagged runs reached inquiry_intake in 60 days and their request-side model spend was AED
--     162.41 (inquiry_intake 98.88, quote_compare 58.96, customer_api 2.87, drawing_boq 1.11, wa_inbound 0.37, quote_extract
--     0.22): AED 0.92 a request.
--   * break_even_cost_line (the CEO's break-even ledger) carries OpenAI (ChatGPT) AED 799 a month as recurring although the
--     founder stopped it (ledger 1538: "won't happen anymore as i stopped it"); the expenses register carries Vercel twice
--     ("Vercel" and "Vercel Inc.", both active); GitHub Actions (USD 684.68 on 9 Oct), Namespace (USD 100, renews 21 Nov)
--     and Ubicloud are CI runners and CI is off since 10 Nov (ledger 1564: the local gate replaces it).
--
-- THE ACCOUNT FOR FOUNDER MONEY, AND WHY. QuotesDone is a UAE SOLE ESTABLISHMENT (DET licence 1633275, one natural person,
-- no separate legal personality: the establishment and its owner are the same person in law). Money the owner puts in is
-- therefore OWNER'S CAPITAL (3000, equity), never a loan: an establishment cannot owe its own owner, so a "founder loan"
-- would show a creditor that does not exist and overstate liabilities (memory: owner money in is capital, "unless he says
-- loan"). 2500 "Due to Owner (founder current account)" holds the bills he paid on his card (ruling 1011); in a sole
-- establishment that current account is equity in substance and is counted here as founder funding received. It is not
-- reclassified (that is the founder's ruling 1011 to change), but every reading below treats 3000 + 2500 as his money in.
--
-- WHAT THIS FILE ADDS
--   1. public.accountant_cost_driver: each model function and vendor named per_request / per_supplier / fixed / test /
--      stopped, with its function group (ci_runner, llm_subscription, hosting ...) and the date it was stopped. Data, not code.
--   2. fn_accountant_founder_funding(): founder money in to date (3000 + 2500, by month), the commitment if recorded, and
--      the money the account shows was paid with no statement-recorded funding yet (-GL 1000).
--      public.founder_funding_commitment + fn_accountant_founder_commitment_record(aed, from, ledger id, dry_run): the
--      founder's monthly commitment, recorded only from a ledger entry, mirrored to gl_settings.
--   3. fn_accountant_cash_13_weeks and fn_accountant_runway_figures now read founder funding: the commitment when recorded,
--      else the funding he has actually provided (the measured burn he covered, 0 revenue), labelled as measured.
--   4. fn_accountant_request_economics(month): cost per request and margin per request WITHOUT test spend (e2e_run_tag rows
--      and test-driver functions excluded), the reconciliation of the model-cost log against booked Software & AI (which
--      costs scale with requests and which are fixed), the break-even (requests and reveals a month at the 3% fee and
--      today's fixed costs, before and after the recommended cuts) and the top recommended cost cuts with their evidence.
--   5. public.accountant_request_economics + fn_accountant_request_economics_tick() (duty accountant.request_economics,
--      daily) + fn_accountant_ceo_economics(): ONE JSON the CEO's planning pack reads (economics, funding, runway).

-- ---------------------------------------------------------------------------------------------------------------
-- 1. COST DRIVERS
create table if not exists public.accountant_cost_driver (
  scope text not null check (scope in ('model_fn', 'vendor')),
  key text not null,
  driver text not null check (driver in ('per_request', 'per_supplier', 'fixed', 'test', 'stopped')),
  function_group text not null,
  stopped_on date,
  basis text not null,
  primary key (scope, key)
);
comment on table public.accountant_cost_driver is
  'What each model function (ai_cost_log.fn) and vendor (lower first word) costs per: request, supplier, fixed, test or stopped (scripts/sql/the_books_tell_the_ceo_what_a_request_costs_and_how_long_the_money_lasts.sql).';
alter table public.accountant_cost_driver enable row level security;
drop policy if exists accountant_cost_driver_service_role_only on public.accountant_cost_driver;
create policy accountant_cost_driver_service_role_only on public.accountant_cost_driver as permissive for all to public using (false) with check (false);
revoke all on public.accountant_cost_driver from anon, authenticated;

insert into public.accountant_cost_driver (scope, key, driver, function_group, stopped_on, basis) values
  ('model_fn', 'inquiry_intake',        'per_request',  'request', null, 'qualifies each customer request'),
  ('model_fn', 'quote_compare',         'per_request',  'request', null, 'compares the quotes of each request'),
  ('model_fn', 'quote_extract',         'per_request',  'request', null, 'reads each quote of a request'),
  ('model_fn', 'customer_api',          'per_request',  'request', null, 'customer portal actions on a request'),
  ('model_fn', 'drawing_boq',           'per_request',  'request', null, 'a request''s drawing to bill of quantities'),
  ('model_fn', 'drawing_redact',        'per_request',  'request', null, 'a request''s drawing redaction'),
  ('model_fn', 'drawing_redact_verify', 'per_request',  'request', null, 'a request''s drawing redaction check'),
  ('model_fn', 'extract_text',          'per_request',  'request', null, 'documents attached to a request'),
  ('model_fn', 'reasoned_delivery',     'per_request',  'request', null, 'delivers a request to its suppliers'),
  ('model_fn', 'site_assistant',        'per_request',  'conversation', null, 'visitor and customer chat that becomes requests'),
  ('model_fn', 'wa_inbound',            'per_request',  'conversation', null, 'WhatsApp conversations (customers and suppliers)'),
  ('model_fn', 'sales_engineer',        'per_request',  'conversation', null, 'the portal assistant on requests and quotes'),
  ('model_fn', 'supplier_api',          'per_supplier', 'supplier', null, 'supplier portal: registration and quoting'),
  ('model_fn', 'supplier_doc_trades',   'per_supplier', 'supplier', null, 'reads each supplier''s documents into trades'),
  ('model_fn', 'license_extract',       'per_supplier', 'supplier', null, 'reads each supplier''s licence'),
  ('model_fn', 'supplier_directive',    'per_supplier', 'supplier', null, 'supplier instructions'),
  ('model_fn', 'knowledge_exam',        'test',         'certification', null, 'seat knowledge exams: certification, not work'),
  ('model_fn', 'canon_eval',            'test',         'certification', null, 'canon evaluation'),
  ('model_fn', 'load_probe',            'test',         'certification', null, 'load test'),
  ('model_fn', 'conversation_rehearsal','test',         'certification', null, 'rehearsal'),
  ('model_fn', 'sales_engineer_conversation_drill', 'test', 'certification', null, 'drill'),
  ('model_fn', 'cs_chat_5q_judge',      'test',         'certification', null, 'judge of a test'),
  ('model_fn', 'chat_answers_the_question_judge', 'test', 'certification', null, 'judge of a test'),
  ('model_fn', 'resilience_ping',       'fixed',        'overhead', null, 'health pings on a clock, whatever the volume'),
  ('model_fn', 'marketing',             'fixed',        'overhead', null, 'the marketing seat'),
  ('model_fn', 'ceo_agent',             'fixed',        'overhead', null, 'the CEO seat'),
  ('model_fn', 'accountant',            'fixed',        'overhead', null, 'the accountant seat'),
  ('model_fn', 'email_triage',          'fixed',        'overhead', null, 'mailbox triage'),
  ('model_fn', 'resend_inbound',        'fixed',        'overhead', null, 'inbound mail reading'),
  ('model_fn', 'public_site',           'fixed',        'overhead', null, 'site pages'),
  ('model_fn', 'marketing_social_inbox','fixed',        'overhead', null, 'social inbox'),
  ('model_fn', 'founder_directive',     'fixed',        'overhead', null, 'founder channel'),
  ('model_fn', 'transcribe',            'fixed',        'overhead', null, 'voice notes'),
  ('vendor', 'openrouter', 'per_request', 'model_api',       null, 'metered model calls; the request share is the ai_cost_log share of per_request functions'),
  ('vendor', 'twilio',     'per_request', 'messaging',       null, 'auto-recharge on message volume'),
  ('vendor', 'anthropic',  'fixed',       'llm_subscription', null, 'Claude Max subscription (ruling 1702: since May)'),
  ('vendor', 'openai',     'stopped',     'llm_subscription', date '2026-09-19', 'ChatGPT Pro: the founder stopped it (ledger 1538, 3 Nov: "won''t happen anymore as i stopped it"); last charge 19 Sep'),
  ('vendor', 'supabase',   'fixed',       'hosting',         null, 'database and functions plan'),
  ('vendor', 'vercel',     'fixed',       'hosting',         null, 'site hosting plan'),
  ('vendor', 'mashreq',    'fixed',       'bank',            null, 'account fee AED 199 + 9.95 VAT a month'),
  ('vendor', 'godaddy',    'fixed',       'mailbox',         null, 'Microsoft 365 mailbox for supplier@'),
  ('vendor', 'tasjeel',    'fixed',       'mailbox',         null, 'deliverability-test mailbox hosting (1544)'),
  ('vendor', 'resend',     'fixed',       'email',           null, 'Transactional Pro, flat USD 20 a month'),
  ('vendor', 'google',     'fixed',       'storage',         null, 'Google Play: Dropbox Simple'),
  ('vendor', 'glockapps',  'fixed',       'deliverability',  null, 'inbox-placement test credits'),
  ('vendor', 'tripo',      'fixed',       'tools',           null, 'Tripo AI 3D generation credits, bought one-off'),
  ('vendor', 'github',     'stopped',     'ci_runner',       date '2026-11-10', 'GitHub Actions minutes; CI off since 10 Nov (ledger 1564), the local gate replaces it'),
  ('vendor', 'namespace',  'stopped',     'ci_runner',       date '2026-11-10', 'Namespace CI runners, Team plan; CI off since 10 Nov (ledger 1564)'),
  ('vendor', 'ubicloud',   'stopped',     'ci_runner',       date '2026-11-10', 'Ubicloud CI runners; CI off since 10 Nov (ledger 1564)')
on conflict (scope, key) do update set driver = excluded.driver, function_group = excluded.function_group,
  stopped_on = excluded.stopped_on, basis = excluded.basis;

-- the vendor key every reading uses: the first word, lower case, letters and digits only ("Vercel Inc." -> vercel)
create or replace function public.fn_accountant_vendor_key(p_vendor text)
returns text language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select nullif(regexp_replace(lower(split_part(btrim(regexp_replace(coalesce(p_vendor, ''), '^\s*ZZ DEMO\s*', '', 'i')), ' ', 1)), '[^a-z0-9]', '', 'g'), '');
$fn$;
revoke execute on function public.fn_accountant_vendor_key(text) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------
-- 2. FOUNDER FUNDING
create table if not exists public.founder_funding_commitment (
  id bigint generated always as identity primary key,
  aed_per_month numeric(14,2) not null check (aed_per_month >= 0),
  from_month date not null,
  founder_instruction_id bigint not null references public.founder_instruction(id),
  recorded_at timestamptz not null default now()
);
comment on table public.founder_funding_commitment is
  'The founder''s monthly funding commitment, each from a founder ledger entry; the latest row is mirrored to gl_settings.founder_committed_funding_aed_per_month.';
alter table public.founder_funding_commitment enable row level security;
drop policy if exists founder_funding_commitment_service_role_only on public.founder_funding_commitment;
create policy founder_funding_commitment_service_role_only on public.founder_funding_commitment as permissive for all to public using (false) with check (false);
revoke all on public.founder_funding_commitment from anon, authenticated;

create or replace function public.fn_accountant_founder_commitment_record(p_aed_per_month numeric, p_from_month date,
  p_founder_instruction_id bigint, p_dry_run boolean default true)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_id bigint;
begin
  if p_aed_per_month is null or p_aed_per_month < 0 then raise exception 'fn_accountant_founder_commitment_record: the amount must be 0 or more'; end if;
  if not exists (select 1 from public.founder_instruction where id = p_founder_instruction_id) then
    raise exception 'fn_accountant_founder_commitment_record: founder ledger entry % does not exist; a commitment is recorded only from his word', p_founder_instruction_id;
  end if;
  if p_dry_run then
    return jsonb_build_object('recorded', false, 'dry_run', true, 'aed_per_month', p_aed_per_month,
                              'from_month', date_trunc('month', coalesce(p_from_month, current_date))::date, 'ledger', p_founder_instruction_id);
  end if;
  insert into public.founder_funding_commitment (aed_per_month, from_month, founder_instruction_id)
  values (round(p_aed_per_month, 2), date_trunc('month', coalesce(p_from_month, current_date))::date, p_founder_instruction_id)
  returning id into v_id;
  insert into public.gl_settings (key, num_value, txt_value) values ('founder_committed_funding_aed_per_month', round(p_aed_per_month, 2), 'ledger ' || p_founder_instruction_id)
  on conflict (key) do update set num_value = excluded.num_value, txt_value = excluded.txt_value, updated_at = now();
  return jsonb_build_object('recorded', true, 'id', v_id, 'aed_per_month', round(p_aed_per_month, 2), 'ledger', p_founder_instruction_id);
end $fn$;
revoke execute on function public.fn_accountant_founder_commitment_record(numeric, date, bigint, boolean) from public, anon, authenticated;

create or replace function public.fn_accountant_founder_funding(p_as_of date default null)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_d date := coalesce(p_as_of, (now() at time zone 'Asia/Dubai')::date);
  v_cap numeric; v_owner numeric; v_bank_gl numeric; v_by_month jsonb; v_commit record; v_burn numeric; v_burn_months int;
  v_rev numeric;
begin
  select coalesce(sum(l.credit - l.debit) filter (where l.account_code = '3000'), 0),
         coalesce(sum(l.credit - l.debit) filter (where l.account_code = '2500'), 0),
         coalesce(sum(l.debit - l.credit) filter (where l.account_code = '1000'), 0)
    into v_cap, v_owner, v_bank_gl
    from public.gl_journal j join public.gl_journal_lines l on l.journal_id = j.id
   where j.status = 'posted' and j.entry_date <= v_d;
  select coalesce(jsonb_agg(jsonb_build_object('month', m, 'capital_aed', cap, 'paid_by_owner_aed', own, 'total_aed', cap + own) order by m), '[]'::jsonb)
    into v_by_month
    from (select to_char(date_trunc('month', j.entry_date), 'YYYY-MM') m,
                 round(coalesce(sum(l.credit - l.debit) filter (where l.account_code = '3000'), 0), 2) cap,
                 round(coalesce(sum(l.credit - l.debit) filter (where l.account_code = '2500'), 0), 2) own
            from public.gl_journal j join public.gl_journal_lines l on l.journal_id = j.id
           where j.status = 'posted' and j.entry_date <= v_d and l.account_code in ('3000', '2500')
           group by 1) z;
  select * into v_commit from public.founder_funding_commitment where from_month <= v_d order by from_month desc, id desc limit 1;
  -- the burn he has covered: average booked monthly expenses of the last three closed months, less revenue booked in them
  select round(avg((figures #>> '{cash_out,expenses_aed}')::numeric), 2), count(*) into v_burn, v_burn_months
    from (select figures from public.accountant_month_close where month < date_trunc('month', v_d) order by month desc limit 3) z;
  select coalesce(sum(l.credit - l.debit), 0) into v_rev
    from public.gl_journal j join public.gl_journal_lines l on l.journal_id = j.id join public.gl_accounts a on a.code = l.account_code and a.type = 'revenue'
   where j.status = 'posted' and j.entry_date >= (date_trunc('month', v_d) - interval '3 months') and j.entry_date < date_trunc('month', v_d);
  return jsonb_build_object(
    'as_of', v_d,
    'received_aed', round(v_cap + v_owner, 2), 'owner_capital_3000_aed', round(v_cap, 2), 'paid_by_owner_2500_aed', round(v_owner, 2),
    'by_month', v_by_month,
    'paid_from_the_account_with_no_recorded_funding_aed', case when v_bank_gl < 0 then round(-v_bank_gl, 2) else 0 end,
    'committed_aed_per_month', v_commit.aed_per_month, 'committed_from', v_commit.from_month, 'committed_ledger', v_commit.founder_instruction_id,
    'covered_burn_aed_per_month', case when v_burn is not null then greatest(round(v_burn - coalesce(v_rev, 0) / 3.0, 2), 0) end,
    'covered_burn_months', v_burn_months,
    'funding_per_month_used_aed', coalesce(v_commit.aed_per_month, case when v_burn is not null then greatest(round(v_burn - coalesce(v_rev, 0) / 3.0, 2), 0) end),
    'funding_basis', case when v_commit.aed_per_month is not null then 'committed: founder ledger ' || v_commit.founder_instruction_id
                          else 'measured: no commitment is recorded, so the funding he has actually provided is used (the average booked spend of the last '
                               || coalesce(v_burn_months, 0) || ' closed month(s), less revenue; the company has no other funder)' end,
    'account', '3000 Owner Capital for money he puts in (a UAE sole establishment cannot owe its owner, so never a loan); 2500 Due to Owner for bills he paid on his card (ruling 1011), counted as his funding',
    'basis', 'received = credits net of debits to 3000 and 2500 in posted journals; paid_from_the_account_with_no_recorded_funding = how far GL 1000 is below zero (a bank account cannot be), i.e. founder transfers a statement not yet received will show; they are booked as capital when it arrives.');
end $fn$;
revoke execute on function public.fn_accountant_founder_funding(date) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------
-- 3a. fn_accountant_cash_13_weeks: the live body; founder inflow = the commitment, else the funding he has provided.
CREATE OR REPLACE FUNCTION public.fn_accountant_cash_13_weeks()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_cp jsonb := public.fn_accountant_cash_position(current_date, null);
  v_cash numeric := (v_cp #>> '{cash_in_bank,aed}')::numeric;
  v_spend numeric := (v_cp #>> '{runway,monthly_spend_aed}')::numeric;
  v_ff jsonb := public.fn_accountant_founder_funding(null);
  v_fund numeric; w int; v_s date; v_in numeric; v_bud numeric; v_ar numeric; v_out jsonb := '[]'::jsonb;
  v_missing text[] := '{}';
begin
  v_fund := (v_ff->>'funding_per_month_used_aed')::numeric;
  if v_cash is null then v_missing := v_missing || text 'no bank closing balance is recorded, so there is no opening cash'; end if;
  if (v_ff->>'committed_aed_per_month') is null then
    v_missing := v_missing || text 'no founder funding commitment is recorded (fn_accountant_founder_commitment_record); the funding he has actually provided is used instead';
  end if;
  for w in 0..12 loop
    v_s := current_date + w * 7;
    select coalesce(sum(l.amount), 0) * 12 / 52.0 into v_bud from public.budget_lines l join public.budgets b on b.id = l.budget_id
      join public.gl_accounts a on a.code = l.account_code and a.type = 'revenue'
     where b.status = 'active' and l.period_month = date_trunc('month', v_s)::date;
    select coalesce(sum(amount_due), 0) into v_ar from public.supplier_dues
     where public.fn_supplier_due_is_owed(status, paid_at) and coalesce(due_date_30, reveal_date + 30) >= v_s and coalesce(due_date_30, reveal_date + 30) < v_s + 7;
    v_in := v_bud + v_ar + coalesce(v_fund, 0) * 12 / 52.0;
    v_cash := v_cash + v_in - coalesce(v_spend, 0) * 12 / 52.0;
    v_out := v_out || jsonb_build_object('week_from', v_s, 'inflow_budget_revenue_aed', round(v_bud, 2), 'inflow_receivables_aed', round(v_ar, 2),
               'inflow_founder_funding_aed', round(coalesce(v_fund, 0) * 12 / 52.0, 2),
               'outflow_spend_aed', round(coalesce(v_spend, 0) * 12 / 52.0, 2), 'closing_cash_aed', round(v_cash, 2));
  end loop;
  return jsonb_build_object('opening_cash_aed', v_cp #> '{cash_in_bank,aed}', 'weeks', v_out, 'missing', to_jsonb(v_missing),
    'founder_funding', jsonb_build_object('aed_per_month', v_fund, 'basis', v_ff->>'funding_basis'),
    'basis', 'Opening = the bank statement balance. Outflow = the average booked monthly spend (fn_accountant_cash_position) x 12/52. Inflow = the active budget''s revenue lines, supplier dues falling due in the week, and founder funding (fn_accountant_founder_funding: his recorded commitment, else the funding he has actually provided) x 12/52.');
end $function$;
revoke execute on function public.fn_accountant_cash_13_weeks() from public, anon, authenticated;

-- 3b. fn_accountant_runway_figures: the live body plus the founder funding and the runway with it.
CREATE OR REPLACE FUNCTION public.fn_accountant_runway_figures(p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_m date := date_trunc('month', p_month)::date;
  v_close jsonb; v_exp numeric; v_cp jsonb; v_avail numeric; v_budget numeric; v_budget_lines int; v_run_b numeric;
  v_missing text[] := '{}'; v_ff jsonb; v_fund numeric; v_spend numeric; v_net numeric; v_run_f numeric;
begin
  select figures into v_close from public.accountant_month_close where month = v_m;
  if v_close is null then v_missing := v_missing || ('the month ' || to_char(v_m, 'YYYY-MM') || ' is not closed'); end if;
  v_exp := (v_close #>> '{cash_out,expenses_aed}')::numeric;
  v_cp := public.fn_accountant_cash_position(v_m, v_exp);
  v_avail := (v_cp #>> '{runway,available_aed}')::numeric;
  if (v_cp #>> '{runway,missing}') is not null then v_missing := v_missing || (v_cp #>> '{runway,missing}'); end if;

  select round(sum(l.amount), 2), count(*) into v_budget, v_budget_lines
    from public.budget_lines l join public.budgets b on b.id = l.budget_id
    join public.gl_accounts ga on ga.code = l.account_code and ga.type = 'expense'   -- spend only; revenue lines are not spend
   where b.status = 'active' and l.period_month = v_m;
  if v_budget_lines = 0 then v_missing := v_missing || ('no active budget has a line for ' || to_char(v_m, 'YYYY-MM') || ', so there is no runway against the budget');
  elsif v_budget <= 0 then v_missing := v_missing || 'the budgeted spend for the month is not positive, so the runway against it is undefined';
  elsif v_avail is not null then v_run_b := round(v_avail / v_budget, 1);
  end if;

  -- FOUNDER FUNDING (15 Nov 2026): the company is founder-funded (instruction 1013), so runway is cash over the burn LEFT
  -- after his funding. With his funding covering the burn, the runway is not a number of months: it lasts while he funds.
  v_ff := public.fn_accountant_founder_funding((v_m + interval '1 month' - interval '1 day')::date);
  v_fund := (v_ff->>'funding_per_month_used_aed')::numeric;
  v_spend := (v_cp #>> '{runway,monthly_spend_aed}')::numeric;
  v_net := case when v_spend is not null then round(v_spend - coalesce(v_fund, 0), 2) end;
  v_run_f := case when v_net > 0 and v_avail is not null then round(greatest(v_avail, 0) / v_net, 1) end;

  return jsonb_build_object(
    'month', to_char(v_m, 'YYYY-MM'),
    'cash_in_bank_aed', v_cp #> '{cash_in_bank,aed}',
    'held_for_possible_refunds_aed', v_cp -> 'held_for_possible_refunds_aed',
    'available_aed', v_avail,
    'monthly_spend_aed', v_cp #> '{runway,monthly_spend_aed}',
    'runway_months_at_actual_spend', v_cp #> '{runway,months}',
    'budgeted_spend_aed', case when v_budget_lines > 0 then v_budget end,
    'runway_months_at_budget', v_run_b,
    'founder_funding', v_ff,
    'monthly_burn_after_founder_funding_aed', v_net,
    'runway_months_with_founder_funding', v_run_f,
    'runway_with_founder_funding', case when v_net is null then 'not measurable: no booked spend'
                                        when v_net <= 0 then 'covered: founder funding of AED ' || v_fund || ' a month (' || (v_ff->>'funding_basis') || ') meets the burn of AED ' || v_spend || '; the runway lasts while he funds'
                                        when v_run_f is null then 'not measurable: no bank balance'
                                        else v_run_f || ' months: AED ' || v_net || ' a month of burn is not covered by founder funding' end,
    'cash_13_weeks', public.fn_accountant_cash_13_weeks(),
    'missing', to_jsonb(v_missing),
    'basis', 'Runway at actual spend is fn_accountant_cash_position''s (available cash / average booked monthly expenses). '
          || 'Runway at budget = the same available cash / the month''s lines of the active budgets. '
          || 'Runway with founder funding = available cash / (spend - founder funding a month, fn_accountant_founder_funding). Nothing is estimated.');
end $function$;
revoke execute on function public.fn_accountant_runway_figures(date) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------
-- 4. WHAT A REQUEST COSTS, WHAT IT EARNS, WHERE THE BREAK-EVEN IS, AND WHAT TO CUT
create or replace function public.fn_accountant_request_economics(p_month date)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_m date := date_trunc('month', p_month)::date; v_e date := (date_trunc('month', p_month) + interval '1 month')::date;
  v_fx numeric; v_req int; v_ai jsonb; v_ai_total numeric; v_ai_test numeric; v_ai_req numeric; v_ai_sup numeric; v_ai_fixed numeric;
  v_unpriced int; v_or_booked numeric; v_msg numeric; v_var_real numeric; v_cpr_real numeric;
  v_jr_tags int; v_jr_spend numeric; v_cpr_est numeric; v_cpr numeric; v_booked jsonb; v_6000 numeric;
  v_basis public.break_even_basis; v_net_reveal numeric; v_rev_req numeric; v_margin numeric;
  v_fixed numeric; v_fixed_lines jsonb; v_or_line numeric; v_or_fixed_share numeric; v_cuts jsonb; v_cut_monthly numeric;
  v_fixed_after numeric; v_be_req numeric; v_be_req_after numeric; v_be_rev numeric; v_be_rev_after numeric; v_missing text[] := '{}';
begin
  select num_value into v_fx from public.gl_settings where key = 'usd_to_aed'; v_fx := coalesce(v_fx, 3.6725);

  -- real requests: the same definition as fn_accountant_unit_economics (ZZ DEMO and demo e-mails excluded)
  select count(*) into v_req from public.inquiries i join public.customers c on c.id = i.customer_id
   where i.created_at >= v_m and i.created_at < v_e and not (coalesce(c.is_demo, false) or public.fn_is_demo_email(c.email));

  -- the model-cost log by driver; test = an e2e_run_tag row (a run, a journey, a certification) or a test-driver function
  select coalesce(jsonb_object_agg(drv, aed), '{}'::jsonb), coalesce(sum(aed), 0),
         coalesce(sum(aed) filter (where drv = 'test'), 0), coalesce(sum(aed) filter (where drv = 'per_request'), 0),
         coalesce(sum(aed) filter (where drv = 'per_supplier'), 0), coalesce(sum(aed) filter (where drv = 'fixed'), 0)
    into v_ai, v_ai_total, v_ai_test, v_ai_req, v_ai_sup, v_ai_fixed
    from (select case when a.e2e_run_tag is not null then 'test' else coalesce(d.driver, 'fixed') end drv, round(sum(a.cost_aed), 2) aed
            from public.ai_cost_log a left join public.accountant_cost_driver d on d.scope = 'model_fn' and d.key = a.fn
           where a.occurred_at >= v_m and a.occurred_at < v_e group by 1) z;
  select count(*) into v_unpriced from public.ai_cost_log
   where occurred_at >= v_m and occurred_at < v_e and cost_aed is null and not cached and coalesce(model_used, 'none') <> 'none';
  if v_unpriced > 0 then v_missing := v_missing || (v_unpriced || ' model call(s) carried no price: the log is a lower bound'); end if;

  -- booked Software & AI (6000) for the month, by vendor and driver
  select coalesce(sum(l.debit - l.credit), 0) into v_6000 from public.gl_journal j join public.gl_journal_lines l on l.journal_id = j.id
   where j.status = 'posted' and l.account_code = '6000' and j.entry_date >= v_m and j.entry_date < v_e;
  select coalesce(jsonb_agg(jsonb_build_object('vendor', k, 'aed', aed, 'driver', drv, 'group', grp) order by aed desc), '[]'::jsonb)
    into v_booked
    from (select coalesce(public.fn_accountant_vendor_key(e.vendor), j.source) k, coalesce(d.driver, 'fixed') drv, coalesce(d.function_group, 'unclassified') grp,
                 round(sum(l.debit - l.credit), 2) aed
            from public.gl_journal j join public.gl_journal_lines l on l.journal_id = j.id and l.account_code = '6000'
            left join public.expense_entries e on j.source = 'expense' and e.id::text = j.source_ref
            left join public.accountant_cost_driver d on d.scope = 'vendor' and d.key = public.fn_accountant_vendor_key(e.vendor)
           where j.status = 'posted' and j.entry_date >= v_m and j.entry_date < v_e
           group by 1, 2, 3) z;
  select coalesce(sum(case when upper(currency) = 'USD' then amount * v_fx else amount end), 0) into v_or_booked
    from public.expense_entries where public.fn_accountant_vendor_key(vendor) = 'openrouter' and charged_on >= v_m and charged_on < v_e;
  select coalesce(sum(case when upper(currency) = 'USD' then amount * v_fx else amount end), 0) into v_msg
    from public.expense_entries e join public.accountant_cost_driver d on d.scope = 'vendor' and d.key = public.fn_accountant_vendor_key(e.vendor)
   where d.driver = 'per_request' and d.key <> 'openrouter' and e.charged_on >= v_m and e.charged_on < v_e;

  -- COST PER REQUEST, test spend excluded. (a) real: per-request model cost + per-request vendors / real requests.
  -- (b) measured on the e2e request journeys of the last 60 days (each run tag that reached inquiry_intake is one request).
  v_var_real := v_ai_req + v_msg;
  v_cpr_real := case when v_req > 0 then round(v_var_real / v_req, 2) end;
  select count(distinct a.e2e_run_tag) into v_jr_tags from public.ai_cost_log a
   where a.fn = 'inquiry_intake' and a.e2e_run_tag is not null and a.occurred_at >= v_e - 60 and a.occurred_at < v_e;
  select coalesce(sum(a.cost_aed), 0) into v_jr_spend from public.ai_cost_log a join public.accountant_cost_driver d on d.scope = 'model_fn' and d.key = a.fn
   where d.driver = 'per_request' and a.e2e_run_tag in (select x.e2e_run_tag from public.ai_cost_log x
                                                         where x.fn = 'inquiry_intake' and x.e2e_run_tag is not null and x.occurred_at >= v_e - 60 and x.occurred_at < v_e);
  v_cpr_est := case when v_jr_tags > 0 then round(v_jr_spend / v_jr_tags, 2) end;
  v_cpr := coalesce(v_cpr_real, v_cpr_est);
  if v_req = 0 then v_missing := v_missing || text 'no real request in the month: cost per request is the one measured on the request journeys'; end if;

  -- MARGIN PER REQUEST at the 3% fee: the reveal rate and quote size are the break-even basis's until measured
  select * into v_basis from public.break_even_basis limit 1;
  v_net_reveal := coalesce((select (m.assumptions->>'net_per_reveal_aed')::numeric from public.ceo_break_even_month m order by m.month desc limit 1),
                           v_basis.assumed_quote_aed * 0.03);
  v_rev_req := round(coalesce(v_basis.assumed_reveal_rate, 0) * coalesce(v_net_reveal, 0), 2);
  v_margin := round(v_rev_req - coalesce(v_cpr, 0), 2);

  -- FIXED COSTS TODAY: the break-even ledger's recurring lines; OpenRouter counts only its fixed (non-request) share
  select coalesce(sum(monthly_aed) filter (where vendor_key = 'openrouter'), 0) into v_or_line from public.break_even_cost_line where kind = 'recurring';
  v_or_fixed_share := case when (v_ai_total - v_ai_test) > 0 then round((v_ai_fixed + v_ai_sup) / (v_ai_total - v_ai_test), 4) else 1 end;
  select coalesce(jsonb_agg(jsonb_build_object('vendor', c.vendor_key, 'label', c.label, 'monthly_aed',
                                              case when c.vendor_key = 'openrouter' then round(c.monthly_aed * v_or_fixed_share, 2) else c.monthly_aed end,
                                              'driver', coalesce(d.driver, 'fixed')) order by c.monthly_aed desc), '[]'::jsonb),
         coalesce(sum(case when c.vendor_key = 'openrouter' then round(c.monthly_aed * v_or_fixed_share, 2) else c.monthly_aed end), 0)
    into v_fixed_lines, v_fixed
    from public.break_even_cost_line c left join public.accountant_cost_driver d on d.scope = 'vendor' and d.key = c.vendor_key
   where c.kind = 'recurring';

  -- THE CUTS, each with its evidence and its monthly saving
  with stopped_billed as (     -- a vendor marked stopped that the books still carry or that billed in the last 60 days
    select d.key, d.function_group, d.stopped_on, d.basis,
           (select round(sum(case when upper(e.currency) = 'USD' then e.amount * v_fx else e.amount end), 2) from public.expense_entries e
             where public.fn_accountant_vendor_key(e.vendor) = d.key and e.charged_on > v_e - 60 and e.charged_on < v_e) billed_60d,
           (select round(sum(case when upper(e.currency) = 'USD' then e.amount * v_fx else e.amount end), 2) from public.expense_entries e
             where public.fn_accountant_vendor_key(e.vendor) = d.key and d.stopped_on is not null and e.charged_on > d.stopped_on) billed_after_stop,
           (select c.monthly_aed from public.break_even_cost_line c where c.vendor_key = d.key and c.kind = 'recurring') still_recurring
      from public.accountant_cost_driver d where d.scope = 'vendor' and d.driver = 'stopped'),
  dup_register as (            -- the subscription register holding one vendor twice
    select public.fn_accountant_vendor_key(vendor) k, count(*) n, jsonb_agg(vendor || ' ' || amount || ' ' || currency order by id) rows_,
           round(min(case when upper(currency) = 'USD' then amount * v_fx else amount end), 2) smaller
      from public.expenses where active group by 1 having count(*) > 1),
  overhead as (                -- model spend on a clock (fixed functions), last 30 days
    select a.fn, round(sum(a.cost_aed), 2) aed30 from public.ai_cost_log a join public.accountant_cost_driver d on d.scope = 'model_fn' and d.key = a.fn
     where d.driver in ('fixed', 'test') and a.e2e_run_tag is null and a.occurred_at > least(now(), v_e::timestamptz) - interval '30 days'
       and a.occurred_at <= least(now(), v_e::timestamptz)
     group by 1 having sum(a.cost_aed) > 20),
  cuts as (
    select 'stop_' || s.key as id,
           case when s.function_group = 'ci_runner' then 'Close the CI runner account ' || s.key || ': CI is off since ' || s.stopped_on || ' (ledger 1564); set the spending limit to 0 and cancel the plan before it renews'
                else 'Remove ' || s.key || ' from the recurring costs: ' || s.basis end as action,
           greatest(coalesce(s.still_recurring, 0), case when s.function_group = 'ci_runner' then coalesce(s.billed_60d, 0) / 2.0 else 0 end) as saving_aed_per_month,
           jsonb_build_object('billed_last_60_days_aed', s.billed_60d, 'billed_after_it_was_stopped_aed', s.billed_after_stop,
                              'still_in_break_even_as_recurring_aed', s.still_recurring, 'stopped_on', s.stopped_on, 'basis', s.basis) as evidence
      from stopped_billed s where coalesce(s.billed_60d, 0) > 0 or coalesce(s.still_recurring, 0) > 0
    union all
    select 'duplicate_' || d.k, 'Close the duplicate register entry for ' || d.k || ' (' || d.n || ' active rows: one subscription, counted ' || d.n || ' times in the register)',
           d.smaller, jsonb_build_object('register_rows', d.rows_)
      from dup_register d
    union all
    select 'overhead_' || o.fn, 'Cap the clock-driven model spend of ' || o.fn || ' (AED ' || o.aed30 || ' in 30 days, whatever the request volume): run it less often or on the cheaper route',
           round(o.aed30 / 2.0, 2), jsonb_build_object('model_aed_30d', o.aed30, 'saving_assumed', 'half (ASSUMPTION: halving the frequency)')
      from overhead o)
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'action', action, 'saving_aed_per_month', round(saving_aed_per_month, 2), 'evidence', evidence)
                            order by saving_aed_per_month desc), '[]'::jsonb),
         coalesce(sum(saving_aed_per_month) filter (where id like 'stop_%' or id like 'duplicate_%'), 0)
    into v_cuts, v_cut_monthly from cuts;
  -- only cuts that lower TODAY's fixed lines lower the break-even (a CI bill is not in the break-even ledger)
  v_fixed_after := round(v_fixed - coalesce((select sum((x #>> '{evidence,still_in_break_even_as_recurring_aed}')::numeric) from jsonb_array_elements(v_cuts) x
                                              where x->>'id' like 'stop_%'), 0), 2);

  v_be_req := case when v_margin > 0 then ceil(v_fixed / v_margin) end;
  v_be_req_after := case when v_margin > 0 then ceil(v_fixed_after / v_margin) end;
  v_be_rev := case when v_net_reveal > 0 then ceil(v_fixed / v_net_reveal) end;
  v_be_rev_after := case when v_net_reveal > 0 then ceil(v_fixed_after / v_net_reveal) end;
  if not coalesce(v_margin > 0, false) then v_missing := v_missing || text 'the margin per request is not positive, so there is no break-even volume'; end if;

  return jsonb_build_object(
    'month', to_char(v_m, 'YYYY-MM'),
    'requests_real', v_req,
    'cost_per_request', jsonb_build_object(
      'aed', v_cpr, 'source', case when v_cpr_real is not null then 'real requests' else 'request journeys (e2e runs that reached inquiry_intake, 60 days)' end,
      'real_aed', v_cpr_real, 'real_numerator_aed', round(v_var_real, 2), 'real_requests', v_req,
      'journeys_aed', v_cpr_est, 'journeys_numerator_aed', round(v_jr_spend, 2), 'journeys', v_jr_tags,
      'excludes', 'every ai_cost_log row with an e2e_run_tag (runs, journeys, certifications) and the test functions in accountant_cost_driver'),
    'margin_per_request', jsonb_build_object('aed', v_margin, 'revenue_per_request_aed', v_rev_req, 'reveal_rate', v_basis.assumed_reveal_rate,
      'net_per_reveal_aed', v_net_reveal, 'quote_aed', v_basis.assumed_quote_aed, 'fee', 0.03,
      'basis', 'revenue per request = reveal rate x net fee per reveal (3% of the quote less Stripe), both from break_even_basis / ceo_break_even_month until measured; margin = that less the cost per request'),
    'reconciliation', jsonb_build_object(
      'model_cost_log_aed', round(v_ai_total, 2), 'model_cost_log_by_driver', v_ai, 'model_calls_unpriced', v_unpriced,
      'openrouter_booked_aed', round(v_or_booked, 2),
      'openrouter_minus_log_aed', round(v_or_booked - v_ai_total, 2),
      'booked_software_and_ai_6000_aed', round(v_6000, 2), 'booked_by_vendor', v_booked,
      'scales_with_requests_aed', round(v_or_booked * case when v_ai_total > 0 then v_ai_req / v_ai_total else 0 end + v_msg, 2),
      'fixed_aed', round(v_6000 - (v_or_booked * case when v_ai_total > 0 then v_ai_req / v_ai_total else 0 end + v_msg), 2),
      'basis', 'The log prices model calls only (it is a lower bound: unpriced calls and card FX are not in it); the booked OpenRouter usage is what was paid for them. Everything else in 6000 is subscriptions, hosting and CI, which do not move with requests. Of OpenRouter, only the per-request functions'' share of the log scales with requests.'),
    'fixed_costs_today', jsonb_build_object('aed_per_month', v_fixed, 'lines', v_fixed_lines, 'openrouter_fixed_share', v_or_fixed_share),
    'break_even', jsonb_build_object(
      'requests_per_month', v_be_req, 'reveals_per_month', v_be_rev,
      'requests_per_month_after_cuts', v_be_req_after, 'reveals_per_month_after_cuts', v_be_rev_after,
      'fixed_aed_per_month', v_fixed, 'fixed_aed_per_month_after_cuts', v_fixed_after,
      'basis', 'requests = fixed costs / margin per request; reveals = fixed costs / net fee per reveal'),
    'cost_cuts', v_cuts,
    'cost_cuts_saving_aed_per_month', round(v_cut_monthly, 2),
    'missing', to_jsonb(v_missing));
end $fn$;
revoke execute on function public.fn_accountant_request_economics(date) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------
-- 5. DELIVERED DAILY, AS DATA, FOR THE CEO'S PLANNING PACK
create table if not exists public.accountant_request_economics (
  month date primary key,
  figures jsonb not null,
  computed_at timestamptz not null default now()
);
comment on table public.accountant_request_economics is 'Cost and margin per request, break-even and cost cuts per month (fn_accountant_request_economics), written daily.';
alter table public.accountant_request_economics enable row level security;
drop policy if exists accountant_request_economics_service_role_only on public.accountant_request_economics;
create policy accountant_request_economics_service_role_only on public.accountant_request_economics as permissive for all to public using (false) with check (false);
revoke all on public.accountant_request_economics from anon, authenticated;

create or replace function public.fn_accountant_request_economics_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_now date := (now() at time zone 'Asia/Dubai')::date; m date; f jsonb;
begin
  foreach m in array array[date_trunc('month', v_now - interval '1 month')::date, date_trunc('month', v_now)::date] loop
    f := public.fn_accountant_request_economics(m);
    insert into public.accountant_request_economics (month, figures) values (m, f)
    on conflict (month) do update set figures = excluded.figures, computed_at = now();
  end loop;
  return public.fn_accountant_ceo_economics();
end $fn$;
revoke execute on function public.fn_accountant_request_economics_tick() from public, anon, authenticated;

create or replace function public.fn_accountant_ceo_economics()
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.accountant_request_economics; v_close date; v_run jsonb;
begin
  select * into r from public.accountant_request_economics order by month desc limit 1;
  select month into v_close from public.accountant_month_close order by month desc limit 1;
  if v_close is not null then v_run := public.fn_accountant_runway_figures(v_close) - 'cash_13_weeks'; end if;
  return jsonb_build_object(
    'seat', 'accountant',
    'economics', case when r.month is null then jsonb_build_object('unavailable', 'fn_accountant_request_economics_tick has not run yet')
                      else r.figures || jsonb_build_object('computed_at', r.computed_at) end,
    'founder_funding', public.fn_accountant_founder_funding(null),
    'runway', coalesce(v_run, jsonb_build_object('unavailable', 'no month is closed yet')),
    'basis', 'scripts/sql/the_books_tell_the_ceo_what_a_request_costs_and_how_long_the_money_lasts.sql');
end $fn$;
revoke execute on function public.fn_accountant_ceo_economics() from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('accountant.request_economics', 'accountant', interval '1 day', 'fn_accountant_request_economics_tick',
   'Cost and margin per request without test spend, the model-cost log reconciled to booked Software & AI, the break-even and the top cost cuts, for this month and last; read by the CEO''s planning pack (fn_accountant_ceo_economics).',
   'scripts/sql/the_books_tell_the_ceo_what_a_request_costs_and_how_long_the_money_lasts.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;
