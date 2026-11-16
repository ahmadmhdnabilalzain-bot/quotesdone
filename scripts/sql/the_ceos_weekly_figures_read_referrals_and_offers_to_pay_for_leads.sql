-- THE CEO'S WEEKLY FIGURES READ REFERRALS AND OFFERS TO PAY FOR LEADS.
--
-- Assigned: ceo. Agent: W3_PEOPLE, 16 Nov 2026. Founder ledgers 1711-1713; SUPPLIER hole #12 ("I'll pay for more leads or
-- exclusivity" is answered correctly but forgotten) and #11 / CUSTOMER #11 (referrals).
--
-- MEASURED BEFORE WRITING (16 Nov 2026, light SELECTs on production): #2017 records each offer as a demand signal
-- (supplier_demand_signal, fn_supplier_demand_signal_record, read by fn_ceo_supplier_demand_signals), but no routine calls that
-- reading: of the 75 fn_ceo_* routines none names fn_ceo_supplier_demand_signals, so the CEO never sees an offer. fn_ceo_weekly_figures
-- (md5 7cf53792ceec99f6eac1c014806120d9, read 16 Nov 2026) is what fn_ceo_weekly_report hands the CEO every week.
--
-- THE CHANGE: the production body, unchanged, plus two figures under `supply`, for the days since the week began:
--   offers_to_pay_for_leads  fn_ceo_supplier_demand_signals (how many, by what was asked and by trade, the latest words). They are
--                            demand, never an offer we make: nobody can pay to rank higher (company brief).
--   referrals                fn_ceo_referrals (a_referral_is_recorded_counted_and_thanked.sql: registrations per referring supplier,
--                            the customers' words).
--
-- prevented by: the_ceos_weekly_figures_read_referrals_and_offers_to_pay_for_leads_probe.sql (LOCAL Postgres 16; fails on the
-- production body with "1:offers").

set local lock_timeout = '3s';

CREATE OR REPLACE FUNCTION public.fn_ceo_weekly_figures(p_from date, p_to date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_prev_from date := p_from - (p_to - p_from) - 1;
  v_prev_to   date := p_from - 1;
  j jsonb;
begin
  select jsonb_build_object(
    'window', jsonb_build_object('from', p_from, 'to', p_to,
                                 'prior_from', v_prev_from, 'prior_to', v_prev_to),

    'money', jsonb_build_object(
      'revenue_week_aed',  (select coalesce(sum(l.credit-l.debit),0) from gl_journal_lines l join gl_journal g on g.id=l.journal_id
                             where l.account_code like '4%' and g.status='posted' and g.entry_date between p_from and p_to),
      'revenue_prior_aed', (select coalesce(sum(l.credit-l.debit),0) from gl_journal_lines l join gl_journal g on g.id=l.journal_id
                             where l.account_code like '4%' and g.status='posted' and g.entry_date between v_prev_from and v_prev_to),
      'revenue_life_aed',  (select coalesce(sum(l.credit-l.debit),0) from gl_journal_lines l join gl_journal g on g.id=l.journal_id
                             where l.account_code like '4%' and g.status='posted'),
      -- SPEND COMES FROM THE LEDGER, NOT FROM expense_entries. Those rows carry a raw amount in
      -- the currency the vendor billed (USD and AED are both present), so summing them would add
      -- dollars to dirhams. The GL is already converted and is the accountant's authoritative
      -- figure, which is also where revenue above is read from — one source, one basis.
      'spend_week_aed',    (select coalesce(sum(l.debit-l.credit),0) from gl_journal_lines l join gl_journal g on g.id=l.journal_id
                             where l.account_code like '6%' and g.status='posted' and g.entry_date between p_from and p_to),
      'spend_life_aed',    (select coalesce(sum(l.debit-l.credit),0) from gl_journal_lines l join gl_journal g on g.id=l.journal_id
                             where l.account_code like '6%' and g.status='posted'),
      'vat_position',      public.fn_accountant_vat_threshold_check(false)),

    'supply', jsonb_build_object(
      'leads_total',       (select count(*) from leads),
      'contactable',       (select count(*) from leads where email is not null and coalesce(invite_status,'') <> 'bounced'),
      'invited_ever',      (select count(*) from leads where invite_status is not null),
      'invited_week',      (select count(*) from leads where invited_at::date between p_from and p_to),
      'registered',        (select count(*) from leads where registration_status is not null),
      'verified',          (select count(*) from leads where verified),
      'matchable',         (select count(*) from supplier_capabilities where confirmed_at is not null),
      -- 14 Sep 2026: suppliers the sales engineer put on matching hold after three consecutive held
      -- quotes were left unanswered (founder_instruction #158). Only the founder lifts it (#160).
      'on_matching_hold',  (select count(*) from leads where matching_block_reason = 'collaboration_hold'),
      'days_since_last_invite', (select case when max(invited_at) is null then null
                                   else (current_date - max(invited_at)::date) end from leads),
      -- W3_PEOPLE 16 Nov 2026 (SUPPLIER #12, #11; CUSTOMER #11): what suppliers offered to pay for, and who brought whom
      'offers_to_pay_for_leads', public.fn_ceo_supplier_demand_signals(greatest(1, current_date - p_from + 1)),
      'referrals',               public.fn_ceo_referrals(greatest(1, current_date - p_from + 1))),

    'demand', jsonb_build_object(
      'customers',         (select count(*) from customers),
      'customers_real',    ((select public.fn_customer_counts())->>'substantiated')::int,
      'inquiries_week',    (select count(*) from inquiries where created_at::date between p_from and p_to),
      'inquiries_ever',    (select count(*) from inquiries),
      'quotes_ever',       (select count(*) from quotes),
      'comparisons_ever',  (select count(*) from quote_comparisons),
      'reveals_ever',      (select count(*) from transactions)),

    'seats', (select jsonb_object_agg(s.seat, jsonb_build_object(
                'runs_week', (select count(*) from agent_runs r
                               where regexp_replace(r.agent,'^fn:','') = s.seat
                                 and r.started_at::date between p_from and p_to),
                'errors_week', (select count(*) from agent_runs r
                               where regexp_replace(r.agent,'^fn:','') = s.seat
                                 and r.status = 'error' and r.started_at::date between p_from and p_to)))
              from (select unnest(array['ceo','customer_support','sales_engineer','accountant','it_engineer','marketing']) as seat) s),

    'health', jsonb_build_object(
      'it_findings_open',   (select count(*) from it_watch_finding where status='open'),
      'it_alerts_week',     (select count(*) from notifications where kind like 'it_%' and created_at::date between p_from and p_to),
      'reports_awaiting_ceo',(select count(*) from support_ceo_report where accepted_at is null and status='sent'),
      'founder_instructions_open', (select count(*) from founder_instruction where status='open'))
  ) into j;
  return j;
end $function$
;

revoke execute on function public.fn_ceo_weekly_figures(date, date) from public, anon, authenticated;
grant execute on function public.fn_ceo_weekly_figures(date, date) to service_role;
