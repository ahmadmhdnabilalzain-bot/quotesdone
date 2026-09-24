-- THE CEO RUNS THE COMPANY ON THE FOUNDER'S YEAR-ONE TARGETS: A MANDATE, A MONTHLY PATH PER SEAT, AND A DAILY,
-- WEEKLY AND MONTHLY ROUTINE THAT DIRECTS THE SEATS, UNBLOCKS THEM AND IMPROVES THE COMPANY.
-- Seat: ceo. 24 Sep 2026. Needs, in this order: every_seat_duty_has_an_owner_a_clock_and_a_check.sql (#901),
-- the_ceo_reviews_the_week_watches_pricing_and_forecasts_the_target.sql (#906) and
-- the_ceo_sets_the_target_runs_experiments_and_watches_competitors.sql (#913).
--
-- THE FOUNDER'S WORDS (24 Sep 2026): "imagine I hired a real CEO tomorrow. What would I ask him for? Build him
-- accordingly." The targets he set the same day: 50 suppliers within two weeks from his own network, 200 by 30 Nov
-- 2026, 300 by 31 Dec 2026, about 500 by Jul/Aug 2027 and at least 3,000 by year 5; a AED 1,000 yearly supplier
-- subscription from supplier #1,001; the 3 % reveal fee, with enterprise procurement accounts; costs under about
-- AED 250,000 a year (his fee AED 10,000 a month, ads at most AED 5,000 a month, the Claude and OpenAI subscriptions
-- AED 799 a month each). The AED 1M target stays withdrawn. The CEO is given targets and ceilings, nothing else.
--
-- WHAT WAS MEASURED (production, 24 Sep 2026)
--   * target_contract: 21 (AED 1M) and 22 (1,000 suppliers by 1 Oct 2027) are still active; #913's base-case contract
--     (AED 244,801 of reveal fees) is committed, not applied. Both numbers contradict the founder's targets.
--   * ceo_plan_month holds Sep 2026 - Aug 2027 on the AED 1M ramp (Oct: 30 verified; Aug: 850 requests).
--   * CEO duties on a clock: target_forecast, management_review, pricing_monitor (weekly). Nothing issues a seat its
--     month, nothing reads the day as a whole, nothing sweeps stuck handoffs, nothing turns lessons into changes.
--
-- THE YEAR-ONE PATH (Oct 2026 - Sep 2027). Every number is one of these rules; the check
-- scripts/checks/the_ceo_year_one_plan_follows_the_founder_targets.test.mjs recomputes each one from them.
--   verified suppliers (cumulative) 125 Oct, 200 Nov, 300 Dec, then +25 a month to 500 in Aug and 525 in Sep
--       (the founder's 50 by 8 Oct are the first wave of October);
--   CUSTOMERS LAUNCH IN JANUARY 2027 (founder, 24 Sep 2026): Oct - Dec 2026 is supplier registration only, with zero
--       requests, quotes, reveals and fees and no customer-facing campaign;
--   paying suppliers and subscription revenue 0 all year: the subscription starts at supplier #1,001, not reached;
--   enterprise accounts 1 in Jan, then one more every two months, 5 by Sep;
--   requests posted (from Jan) = 20 % of the verified suppliers (a month) + 6 per enterprise account;
--   quotes = 1.8 a request (a planning average: at least three quotes on 60 % of requests; any number of suppliers may quote);
--   reveals = 15 % of the non-enterprise requests + 3 awards per enterprise account;
--   reveal fees = AED 390 a reveal (3 % of AED 13,000) + AED 1,500 an enterprise award (3 % of AED 50,000);
--   cost ceiling = AED 18,598 a month (fee 10,000; ads 5,000; Claude 799; OpenAI 799; other software 1,200; model
--       usage 800) + LLC AED 7,000 in Oct and trademark AED 5,000 in Nov = AED 235,176 for the year (< 250,000).
--   Year: 915 requests, 1,647 quotes, 191 reveals, AED 157,740 of reveal fees; revenue passes the cost ceiling in
--   July 2027.
--   registrations submitted = verified added / 0.75; invitations delivered = (registrations - the founder's 50 in Oct) / 0.041.
--
-- OWNERSHIP (founder, 24 Sep 2026): sales_engineer owns suppliers AND customers (inquiries, drawings, matching, quotes,
-- the comparison, reveals, enterprise); customer_support is the communication seat (homepage chat, email, WhatsApp,
-- delivering every seat's messages) and owns no reveal; marketing owns social, SEO/GEO, trends, the recruitment funnel,
-- reputation and analytics; it_engineer owns platform service levels; the CEO owns the whole and the direction. Rates are assumptions until real transactions exist; the experiments of #913 measure them.
--
-- WHAT THIS ADDS
--   1. ceo_mandate: what the founder asks of the CEO: targets, cost ceilings, hard rules, what he decides alone
--      (every approval, refunds included; the founder is informed, not asked) and how he reports.
--   2. The contract FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30 replaces #913's AED 244,801 contract, the AED 1M
--      contract and the 1,000-supplier contract. target_path carries its month-by-month path per metric and seat
--      (a ceiling reads as direction max); ceo_plan_month follows it; ceo_plan_action holds each seat's actions.
--   3. DAILY (ceo.daily_run): the morning read against the path, the day's priorities per seat, stuck handoffs and
--      stale tasks turned into CEO tasks, the experience, cash and incident signals, and one short note to the
--      founder only on a day when something matters.
--   4. WEEKLY: the management review (#906) now carries each seat's own targets and month directive; the forecast
--      reads this contract. Experiments and the competitor watch stay #913's.
--   5. MONTHLY (ceo.month_plan): last month closed per seat (met / missed), the next month re-planned (a cumulative
--      shortfall carries into the month's need), each seat's directive issued from the plan table
--      (ceo.month_directive), and the founder's monthly report sent through customer_support.
--   6. The weekly summary email to the founder carries plan against actual for every metric (target, actual, gap,
--      owning seat, the action being taken).
--   7. IMPROVING (ceo.improvement, weekly): recurring misses, lessons in seat_case_memory and recurring IT findings
--      become improvement proposals assigned to a seat and tracked to done.
--
-- DETERMINISTIC: every routine here is code. Judgement stays where #906 and #913 put it (think() on the review,
-- the forecast, root causes and experiments); nothing here calls a model or matches words.

-- ═════════════════════════════════════════════════════════════════════════════════════════════════════
-- 0. TWO MEASURES THE PATH NEEDS (quotes received, costs booked), beside the ambition build's
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════
create or replace function public.fn_ambition_measure(p_key text, p_from timestamptz, p_to timestamptz)
returns numeric
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v numeric; v_den numeric; v_num numeric;
  -- the four highest-fee trades in the plan (61 % of the fee from 12.6 % of requests), as category_specs keys
  c_top4 constant text[] := array['fitout', 'commercial-retail-fitout', 'kitchens', 'carpentry-joinery', 'steel', 'structural-steel-fabrication'];
begin
  case p_key
  when 'fee_aed_cumulative' then
    v := public.fn_ceo_plan_measure('fee_aed', timestamptz '2026-01-01', p_to);
  when 'reveal_conversion_pct', 'top4_category_request_share_pct' then
    with i as (
      select i.id, i.category from public.inquiries i join public.customers c on c.id = i.customer_id
       where i.parent_inquiry_id is null and i.created_at >= p_from and i.created_at < p_to
         and coalesce(i.provenance->>'source', '') not in ('demo_factory', 'e2e')
         and not (coalesce(c.is_demo, false) or coalesce(c.full_name, '') ilike 'ZZ DEMO%'
                  or coalesce(c.email, '') ilike '%@example.invalid' or coalesce(c.phone, '') like '+9715000000%'))
    select case when p_key = 'reveal_conversion_pct' then count(*) filter (where exists (select 1 from public.quotes q where q.inquiry_id = i.id))
                else count(*) end,
           case when p_key = 'reveal_conversion_pct'
                then count(*) filter (where exists (select 1 from public.transactions t where t.inquiry_id = i.id and t.revealed_at is not null
                                                     and t.payment_ref ~ '^(pi|ch|py)_'))
                else count(*) filter (where i.category = any (c_top4)) end
      into v_den, v_num from i;
    -- under 20 in the denominator a percentage is noise: not measurable, never zero
    v := case when v_den >= 20 then round(100.0 * v_num / v_den, 1) end;
  when 'b2b_active_accounts' then
    -- a business buyer (customers.industry set) that posted a real request in the 30 days to p_to
    select count(distinct c.id) into v from public.customers c join public.inquiries i on i.customer_id = c.id
     where nullif(btrim(coalesce(c.industry, '')), '') is not null and i.parent_inquiry_id is null
       and i.created_at >= p_to - interval '30 days' and i.created_at < p_to
       and coalesce(i.provenance->>'source', '') not in ('demo_factory', 'e2e')
       and not (coalesce(c.is_demo, false) or coalesce(c.full_name, '') ilike 'ZZ DEMO%' or coalesce(c.email, '') ilike '%@example.invalid');
  when 'checkout_success_pct' then
    -- a Stripe checkout that completed, over every checkout that completed or expired
    select count(*) filter (where type = 'checkout.session.completed'),
           count(*) filter (where type in ('checkout.session.completed', 'checkout.session.expired'))
      into v_num, v_den from public.stripe_events where first_seen_at >= p_from and first_seen_at < p_to;
    v := case when v_den >= 20 then round(100.0 * v_num / v_den, 1) end;
  when 'reveals_paid_30d' then
    v := public.fn_ceo_plan_measure('reveals_paid', p_to - interval '30 days', p_to);
  when 'fee_aed_30d' then
    v := public.fn_ceo_plan_measure('fee_aed', p_to - interval '30 days', p_to);
  when 'registrations_verified_cumulative' then
    v := public.fn_ceo_plan_measure('registrations_verified', timestamptz '2026-01-01', p_to);
  when 'reveals_paid_cumulative' then
    v := public.fn_ceo_plan_measure('reveals_paid', timestamptz '2026-01-01', p_to);
  when 'quotes_received' then
    -- quotes received on real requests, created in the window
    select count(*) into v from public.quotes q join public.inquiries i on i.id = q.inquiry_id join public.customers c on c.id = i.customer_id
     where q.created_at >= p_from and q.created_at < p_to and i.parent_inquiry_id is null
       and coalesce(i.provenance->>'source', '') not in ('demo_factory', 'e2e')
       and not (coalesce(c.is_demo, false) or coalesce(c.full_name, '') ilike 'ZZ DEMO%'
                or coalesce(c.email, '') ilike '%@example.invalid' or coalesce(c.phone, '') like '+9715000000%');
  when 'costs_aed' then
    -- company costs booked in the expense ledger in the window (Dubai dates), in AED at the fixed USD peg 3.6725.
    -- A currency other than AED or USD has no fixed rate here: the reading is then not measurable, never understated.
    select case when count(*) filter (where currency not in ('AED', 'USD')) > 0 then null
                else coalesce(sum(case currency when 'AED' then amount else amount * 3.6725 end), 0) end
      into v from public.expense_entries
     where charged_on >= (p_from at time zone 'Asia/Dubai')::date
       and charged_on <= ((p_to - interval '1 microsecond') at time zone 'Asia/Dubai')::date;
  when 'uptime_pct' then
    -- the platform's own health checks in the window; under 20 checks is not a rate
    select count(*) filter (where ok), count(*) into v_num, v_den from public.health_checks where created_at >= p_from and created_at < p_to;
    v := case when v_den >= 20 then round(100.0 * v_num / v_den, 2) end;
  when 'duties_on_clock_pct' then
    -- enabled seat duties whose last success is within twice their interval, at p_to
    select count(*) filter (where last_ok_at >= p_to - 2 * every), count(*) into v_num, v_den from public.seat_duty where enabled;
    v := case when v_den > 0 then round(100.0 * v_num / v_den, 1) end;
  when 'it_findings_open' then
    select count(*) into v from public.it_engineer_finding where closed_at is null and started_at < p_to;
  else
    v := public.fn_ceo_plan_measure(p_key, p_from, p_to);   -- raises on an unknown key
  end case;
  return v;
end $fn$;
revoke execute on function public.fn_ambition_measure(text, timestamptz, timestamptz) from public, anon, authenticated;
grant execute on function public.fn_ambition_measure(text, timestamptz, timestamptz) to service_role;


-- ═════════════════════════════════════════════════════════════════════════════════════════════════════
-- 1. THE MANDATE: what the founder asks of his CEO, in one place the CEO's routines and an auditor can read
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════
create table if not exists public.ceo_mandate (
  clause_key text primary key check (clause_key ~ '^[a-z0-9_]+$'),
  kind       text not null check (kind in ('target', 'cost_ceiling', 'hard_rule', 'decision_right', 'reporting')),
  statement  text not null check (btrim(statement) <> ''),
  value      numeric,
  unit       text,
  source     text not null,
  created_at timestamptz not null default now()
);
alter table public.ceo_mandate enable row level security;
drop policy if exists ceo_mandate_service_role_only on public.ceo_mandate;
create policy ceo_mandate_service_role_only on public.ceo_mandate as permissive for all to public using (false) with check (false);
revoke all on public.ceo_mandate from anon, authenticated;

insert into public.ceo_mandate (clause_key, kind, statement, value, unit, source) values
  ('suppliers_50_by_2026_10_08', 'target', '50 verified suppliers within two weeks, from the founder''s own network (separate from the leads).', 50, 'verified suppliers', 'founder, 24 Sep 2026'),
  ('suppliers_200_by_2026_11_30', 'target', '200 verified suppliers by 30 November 2026.', 200, 'verified suppliers', 'founder, 24 Sep 2026'),
  ('suppliers_300_by_2026_12_31', 'target', '300 verified suppliers by 31 December 2026.', 300, 'verified suppliers', 'founder, 24 Sep 2026'),
  ('suppliers_500_by_2027_08_31', 'target', 'About 500 verified suppliers by July/August 2027.', 500, 'verified suppliers', 'founder, 24 Sep 2026'),
  ('suppliers_3000_by_year_5', 'target', 'At least 3,000 verified suppliers by year 5; a minimum, and higher is the aim.', 3000, 'verified suppliers', 'founder, 24 Sep 2026'),
  ('subscription_from_supplier_1001', 'target', 'Supplier subscriptions are a main revenue line: AED 1,000 a year for every supplier from #1,001.', 1000, 'AED a year', 'founder, 24 Sep 2026'),
  ('reveal_fees_and_enterprise', 'target', 'Reveal fees at 3 %, including enterprise accounts that run their procurement through QuotesDone.', 3, '%', 'founder, 24 Sep 2026'),
  ('year_costs_under_250k', 'cost_ceiling', 'All costs together stay under about AED 250,000 a year.', 250000, 'AED a year', 'founder, 24 Sep 2026'),
  ('founder_fee', 'cost_ceiling', 'The founder''s management fee is the only human cost.', 10000, 'AED a month', 'founder, 24 Sep 2026'),
  ('ads_ceiling', 'cost_ceiling', 'Paid advertising at most AED 5,000 a month.', 5000, 'AED a month', 'founder, 24 Sep 2026'),
  ('claude_subscription', 'cost_ceiling', 'The Claude subscription, as charged by the bank.', 799, 'AED a month', 'founder, 24 Sep 2026'),
  ('openai_subscription', 'cost_ceiling', 'The OpenAI subscription, as charged by the bank.', 799, 'AED a month', 'founder, 24 Sep 2026'),
  ('one_off_llc_and_trademark', 'cost_ceiling', 'One-off: LLC AED 7,000 and trademark AED 5,000.', 12000, 'AED once', 'founder, 24 Sep 2026'),
  ('no_other_spend', 'cost_ceiling', 'Nothing for staff, legal, insurance, accounting, content or branding: the seats do that work.', null, null, 'founder, 24 Sep 2026'),
  ('reveal_fee_rule', 'hard_rule', 'The 3 % reveal fee is paid by the customer, plus card processing; comparing quotes is free.', null, null, 'terms and conditions (founder, 3 and 14 Sep 2026)'),
  ('comparison_rule', 'hard_rule', 'The comparison report shows the best 3 technical quotes, and every other quote is listed too.', null, null, 'terms and conditions (founder, 14 Sep 2026)'),
  ('consented_channels', 'hard_rule', 'Business buyers are reached only through consented channels; nobody is contacted cold.', null, null, 'founder, Sep 2026'),
  ('posting_days', 'hard_rule', 'No posting on weekends (Saturday, Sunday) or on UAE public holidays.', null, null, 'founder, 24 Sep 2026'),
  ('routine_is_code', 'hard_rule', 'Routine operations are code; a model is used only where real judgement is needed.', null, null, 'founder, 24 Sep 2026'),
  ('all_approvals_are_the_ceos', 'decision_right', 'Every approval is the CEO''s, refunds included. The founder is informed, not asked.', null, null, 'founder, 8 Sep 2026'),
  ('founder_decides', 'decision_right', 'Only these go to the founder: spend beyond a ceiling above, a change to a commercial rule or price, and his own intentions.', null, null, 'founder, 13 Aug and 24 Sep 2026'),
  ('daily_note', 'reporting', 'One short daily note, only on a day when something matters.', null, null, 'founder, 24 Sep 2026'),
  ('weekly_summary', 'reporting', 'A weekly summary email.', null, null, 'founder, 24 Sep 2026'),
  ('monthly_review', 'reporting', 'A monthly review: each target against the plan, each seat met or missed, what changes next month.', null, null, 'founder, 24 Sep 2026')
on conflict (clause_key) do update set kind = excluded.kind, statement = excluded.statement, value = excluded.value, unit = excluded.unit, source = excluded.source;

-- ═════════════════════════════════════════════════════════════════════════════════════════════════════
-- 2. THE YEAR-ONE PLAN TABLE, THE CONTRACT, THE PATH PER SEAT AND THE CEO'S MONTH PLAN
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════
create table if not exists public.ceo_year_plan (
  month            date primary key check (extract(day from month) = 1),
  verified         integer not null check (verified >= 0),        -- cumulative at month end
  verified_added   integer not null check (verified_added >= 0),
  paying           integer not null default 0 check (paying >= 0),
  subscription_aed numeric not null default 0 check (subscription_aed >= 0),
  requests         integer not null check (requests >= 0),
  quotes           integer not null check (quotes >= 0),
  reveals          integer not null check (reveals >= 0),
  fee_aed          numeric not null check (fee_aed >= 0),
  fee_cum_aed      numeric not null check (fee_cum_aed >= 0),
  enterprise       integer not null check (enterprise >= 0),
  cost_ceiling_aed numeric not null check (cost_ceiling_aed > 0),
  basis            text not null
);
alter table public.ceo_year_plan enable row level security;
drop policy if exists ceo_year_plan_service_role_only on public.ceo_year_plan;
create policy ceo_year_plan_service_role_only on public.ceo_year_plan as permissive for all to public using (false) with check (false);
revoke all on public.ceo_year_plan from anon, authenticated;

insert into public.ceo_year_plan (month, verified, verified_added, requests, quotes, reveals, fee_aed, fee_cum_aed, enterprise, cost_ceiling_aed, basis)
select m::date, v, va, r, q, rv, f, fc, e, c, 'founder targets 24 Sep 2026; rules in the header of scripts/sql/the_ceo_runs_the_company_on_the_founders_year_one_targets.sql'
  from (values
('2026-10-01', 125, 125, 0, 0, 0, 0, 0, 0, 25598),
    ('2026-11-01', 200, 75, 0, 0, 0, 0, 0, 0, 23598),
    ('2026-12-01', 300, 100, 0, 0, 0, 0, 0, 0, 18598),
    ('2027-01-01', 325, 25, 71, 128, 13, 8400, 8400, 1, 18598),
    ('2027-02-01', 350, 25, 76, 137, 14, 8790, 17190, 1, 18598),
    ('2027-03-01', 375, 25, 87, 157, 17, 13290, 30480, 2, 18598),
    ('2027-04-01', 400, 25, 92, 166, 18, 13680, 44160, 2, 18598),
    ('2027-05-01', 425, 25, 103, 185, 22, 18570, 62730, 3, 18598),
    ('2027-06-01', 450, 25, 108, 194, 23, 18960, 81690, 3, 18598),
    ('2027-07-01', 475, 25, 119, 214, 26, 23460, 105150, 4, 18598),
    ('2027-08-01', 500, 25, 124, 223, 27, 23850, 129000, 4, 18598),
    ('2027-09-01', 525, 25, 135, 243, 31, 28740, 157740, 5, 18598)) x(m, v, va, r, q, rv, f, fc, e, c)
on conflict (month) do update set verified = excluded.verified, verified_added = excluded.verified_added, requests = excluded.requests,
  quotes = excluded.quotes, reveals = excluded.reveals, fee_aed = excluded.fee_aed, fee_cum_aed = excluded.fee_cum_aed,
  enterprise = excluded.enterprise, cost_ceiling_aed = excluded.cost_ceiling_aed, basis = excluded.basis;

insert into public.target_contract (contract_key, version, status, objective, business_reason, priority, accountable_owner,
  metric_definition, metric_unit, metric_population, authoritative_source, measure_sql, baseline_value, baseline_state, baseline_at,
  baseline_note, desired_value, desired_basis, deadline, timezone, measurement_cadence, guardrails, assumptions, confidence_note,
  escalation_threshold, success_definition, evidence_required, created_by, activated_at)
select 'FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30', 1, 'active',
  'The founder''s year-one targets: 50 verified suppliers by 8 Oct 2026, 200 by 30 Nov, 300 by 31 Dec, about 500 by 31 Aug 2027, with reveal fees, enterprise accounts and costs held to the monthly path per seat.',
  'Set by the founder on 24 Sep 2026. They replace the withdrawn AED 1M target, the 1,000-supplier target and the AED 244,801 base case.',
  1, 'ceo',
  'Verified suppliers since 1 Jan 2026, demo rows excluded: fn_ambition_measure(''registrations_verified_cumulative'').',
  'verified suppliers', 'Every real supplier lead approved since 1 Jan 2026 (ZZ DEMO and example.invalid excluded).',
  'public.leads.approved_at, through fn_ceo_plan_measure(''registrations_verified'').',
  'select public.fn_ambition_measure(''registrations_verified_cumulative'', timestamptz ''2026-01-01'', now())',
  public.fn_ambition_measure('registrations_verified_cumulative', timestamptz '2026-01-01', now()), 'measured', now(),
  'Measured live from the contract''s own measure_sql on the day it was written.',
  500, 'cumulative', date '2027-08-31', 'Asia/Dubai', 'daily',
  coalesce((select guardrails from public.target_contract where id = 21), '[]'::jsonb),
  jsonb_build_array('The month-by-month path per metric is public.ceo_year_plan, from the founder''s targets and stated rules (file header).',
                    'Requests, quotes, reveal and award rates are assumptions until real transactions exist; #913''s experiments measure them.',
                    'Suppliers #1-1,000 pay nothing, so subscription revenue is zero in year one.'),
  'The supplier milestones are the founder''s; every demand and revenue rate is assumed.',
  'Any day a seat''s path metric is behind its tolerance (target_path.tolerance_pct), or over a cost ceiling: a CEO task and a root-cause question to that seat.',
  'Verified suppliers reach 500 by 31 August 2027, with the monthly path per seat met or explained by a root cause.',
  'The measure_sql result, the daily verdicts, the month directives closed met or missed, and the monthly report.', 'ceo', now()
where not exists (select 1 from public.target_contract where contract_key = 'FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30');

update public.target_contract
   set status = 'superseded', closed_at = now(),
       superseded_by = (select id from public.target_contract where contract_key = 'FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30'),
       close_reason = 'Replaced by the founder''s year-one targets of 24 Sep 2026 (FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30).'
 where contract_key in ('REVEAL_FEES_BASE_PATH_BY_2027_08_31', 'REVENUE_AED_1M_BY_2027_10_01', 'SUPPLIERS_1000_BY_2027_10_01')
   and status = 'active';

-- the supply chain the forecast walks: invitations -> registrations -> verified. Rates assumed, capacity the invite ramp.
insert into public.target_driver (contract_id, stage_order, stage_key, stage_label, from_stage_key, rate, rate_source, rate_evidence, lag_days, capacity_per_day, owner_seat, note)
select c.id, x.o, x.k, x.l, x.f, x.r, 'assumed', x.e, x.lag, x.cap, x.s, 'Founder targets 24 Sep 2026.'
  from public.target_contract c
  cross join (values
    (1, 'invitations_delivered', 'Supplier invitations delivered', null, 1.0, 'The top of the chain.', 0, 100::numeric, 'sales_engineer'),
    (2, 'registrations_submitted', 'Registrations submitted', 'invitations_delivered', 0.041, 'The CEO month plan''s ratio (45 of 1,100 in Oct 2026); unmeasured.', 6, null, 'customer_support'),
    (3, 'registrations_verified', 'Suppliers verified', 'registrations_submitted', 0.75, 'Assumed: three in four registrations pass verification.', 1, null, 'sales_engineer')) x(o, k, l, f, r, e, lag, cap, s)
 where c.contract_key = 'FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30'
   and not exists (select 1 from public.target_driver d where d.contract_id = c.id);

-- a ceiling is read the other way: over it is the miss
alter table public.target_path add column if not exists direction text not null default 'min' check (direction in ('min', 'max'));

insert into public.target_path (contract_id, month, metric_key, owner_seat, kind, value, tolerance_pct, source, direction)
select c.id, p.month, x.metric, x.seat, x.kind,
       case x.metric when 'registrations_verified_cumulative' then p.verified when 'inquiries_posted' then p.requests
                     when 'quotes_received' then p.quotes when 'reveals_paid' then p.reveals when 'fee_aed' then p.fee_aed
                     when 'fee_aed_cumulative' then p.fee_cum_aed when 'b2b_active_accounts' then p.enterprise
                     when 'costs_aed' then p.cost_ceiling_aed
                     when 'registrations_submitted' then ceil(p.verified_added / 0.75)
                     when 'invitations_delivered' then ceil((ceil(p.verified_added / 0.75) - case when p.month = date '2026-10-01' then 50 else 0 end) / 0.041)
                     when 'bounce_pct_7d' then 5
                     -- a customer rate has no target before customers launch (January 2027)
                     when 'quote_coverage_pct' then case when p.requests > 0 then 60 else 0 end
                     when 'checkout_success_pct' then case when p.requests > 0 then 98 else 0 end
                     when 'uptime_pct' then 99.5 when 'duties_on_clock_pct' then 99 when 'it_findings_open' then 5 end,
       x.tol, 'ceo_year_plan (founder targets 24 Sep 2026)', x.dir
  from public.target_contract c
  cross join public.ceo_year_plan p
  cross join (values
    ('registrations_verified_cumulative', 'sales_engineer', 'cumulative', 20, 'min'),
    ('inquiries_posted', 'sales_engineer', 'month', 30, 'min'),
    ('quotes_received', 'sales_engineer', 'month', 30, 'min'),
    ('quote_coverage_pct', 'sales_engineer', 'rate', 20, 'min'),
    ('reveals_paid', 'sales_engineer', 'month', 30, 'min'),
    ('b2b_active_accounts', 'sales_engineer', 'level', 30, 'min'),
    ('registrations_submitted', 'marketing', 'month', 30, 'min'),
    ('invitations_delivered', 'customer_support', 'month', 30, 'min'),
    ('bounce_pct_7d', 'customer_support', 'rate', 20, 'max'),
    ('fee_aed', 'accountant', 'month', 30, 'min'),
    ('costs_aed', 'accountant', 'month', 5, 'max'),
    ('fee_aed_cumulative', 'ceo', 'cumulative', 30, 'min'),
    ('checkout_success_pct', 'it_engineer', 'rate', 2, 'min'),
    ('uptime_pct', 'it_engineer', 'rate', 1, 'min'),
    ('duties_on_clock_pct', 'it_engineer', 'rate', 2, 'min'),
    ('it_findings_open', 'it_engineer', 'level', 20, 'max')) x(metric, seat, kind, tol, dir)
 where c.contract_key = 'FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30'
on conflict (contract_id, month, metric_key) do update set owner_seat = excluded.owner_seat, kind = excluded.kind, value = excluded.value,
  tolerance_pct = excluded.tolerance_pct, source = excluded.source, direction = excluded.direction;

-- The CEO's month plan (read by fn_ceo_plan_decide, the plan review and the marketing packet) follows the path.
-- verified = the month's additions; registered = additions / 0.75; invites = (registrations - the founder's 50 in
-- October) / 0.041, the ratio this table already carried.
insert into public.ceo_plan_month (month, invites, registered, verified, inquiries, reveals, fee_aed, basis)
select p.month,
       ceil((ceil(p.verified_added / 0.75) - case when p.month = date '2026-10-01' then 50 else 0 end) / 0.041)::int,
       ceil(p.verified_added / 0.75)::int, p.verified_added, p.requests, p.reveals, p.fee_aed,
       'founder year-one targets (24 Sep 2026): ' || p.verified || ' verified by month end'
         || case when p.month = date '2026-10-01' then '; the founder''s own 50 by 8 Oct' else '' end
  from public.ceo_year_plan p
on conflict (month) do update set invites = excluded.invites, registered = excluded.registered, verified = excluded.verified,
  inquiries = excluded.inquiries, reveals = excluded.reveals, fee_aed = excluded.fee_aed, basis = excluded.basis, updated_at = now();

-- Each seat's actions, month by month: the plan table the CEO's directives are coded from.
create table if not exists public.ceo_plan_action (
  id         bigserial primary key,
  seat       text not null references public.org_role (role_id),
  from_month date not null check (extract(day from from_month) = 1),
  to_month   date not null check (to_month >= from_month),
  action     text not null check (btrim(action) <> ''),
  unique (seat, from_month, action)
);
alter table public.ceo_plan_action enable row level security;
drop policy if exists ceo_plan_action_service_role_only on public.ceo_plan_action;
create policy ceo_plan_action_service_role_only on public.ceo_plan_action as permissive for all to public using (false) with check (false);
revoke all on public.ceo_plan_action from anon, authenticated;
revoke all on sequence public.ceo_plan_action_id_seq from anon, authenticated;

insert into public.ceo_plan_action (seat, from_month, to_month, action) values
  ('sales_engineer', '2026-10-01', '2026-10-01', 'Onboard the founder''s own network first: 50 verified suppliers by 8 October, each verified within 24 hours of registering.'),
  ('sales_engineer', '2026-10-01', '2026-12-01', 'Build the supplier base in daily campaign waves, trades by expected demand, to 200 verified by 30 November and 300 by 31 December; every trade able to quote before customers launch.'),
  ('sales_engineer', '2026-12-01', '2026-12-01', 'Prove the customer journey end to end in the sandbox (request, drawings, matching, quotes, comparison, reveal) before the January launch.'),
  ('sales_engineer', '2027-01-01', '2027-09-01', 'Own every customer request: specs and drawings complete, matched to the exact trade, at least three quotes on every request (any number of suppliers may quote), the comparison report, and the reveal.'),
  ('sales_engineer', '2027-01-01', '2027-09-01', 'Recruit 25 verified suppliers a month, weighted to the trades where requests went unquoted.'),
  ('sales_engineer', '2027-01-01', '2027-09-01', 'Enterprise procurement accounts through consented channels only: one new account every two months.'),
  ('customer_support', '2026-10-01', '2027-09-01', 'Deliver the daily supplier-campaign email and the PDF of the suppliers contacted the next day; keep bounces under 5 %.'),
  ('customer_support', '2026-10-01', '2027-09-01', 'Answer the homepage chat, email and WhatsApp, and deliver every seat''s messages, on time and in the customer''s language.'),
  ('marketing', '2026-10-01', '2026-12-01', 'Supplier recruitment only: the recruitment funnel, social posts and SEO/GEO pages aimed at suppliers; no customer-facing campaign before January.'),
  ('marketing', '2026-10-01', '2027-09-01', 'Run the monthly content loop: ideas, the founder''s content, the calendar for his one-step approval; no posts on weekends or UAE public holidays.'),
  ('marketing', '2026-10-01', '2027-09-01', 'Watch trends, reputation and analytics; report what moved each week; ads within AED 5,000 a month.'),
  ('marketing', '2027-01-01', '2027-09-01', 'Launch to customers in January: SEO and GEO blog pages, social reach and replies, and the buyer funnel.'),
  ('accountant', '2026-10-01', '2027-09-01', 'Close the month''s books by day 3: every cost booked against the ceiling, and from January reveal fees reconciled to Stripe.'),
  ('accountant', '2026-10-01', '2026-11-01', 'Book the one-off LLC (AED 7,000, October) and trademark (AED 5,000, November).'),
  ('accountant', '2027-06-01', '2027-09-01', 'Have supplier subscription billing ready before supplier #1,001 registers.'),
  ('it_engineer', '2026-10-01', '2027-09-01', 'Hold the service levels: uptime 99.5 %, every seat duty on its clock (99 %), open findings 5 or fewer, and from January checkout success 98 %; backups verified.')
on conflict (seat, from_month, action) do update set to_month = excluded.to_month;

-- The current month of the path and each metric's latest daily verdict: what the weekly review, the forecast
-- and the founder's reports read.
create or replace function public.fn_ceo_year_plan_status(p_at timestamptz default now())
returns jsonb
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with c as (select id from public.target_contract where contract_key = 'FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30' and status = 'active'),
       m as (select date_trunc('month', p_at at time zone 'Asia/Dubai')::date as m0)
  select jsonb_build_object('month', (select m0 from m),
    'plan', (select to_jsonb(y) from public.ceo_year_plan y, m where y.month = m.m0),
    'metrics', coalesce((select jsonb_agg(jsonb_build_object('metric', p.metric_key, 'owner_seat', p.owner_seat, 'kind', p.kind,
                 'direction', p.direction, 'month_target', p.value, 'day', v.day, 'expected', v.expected, 'actual', v.actual,
                 'gap_pct', v.gap_pct, 'status', v.status) order by p.owner_seat, p.metric_key)
        from public.target_path p join c on c.id = p.contract_id cross join m
        left join lateral (select * from public.target_daily_verdict d where d.contract_id = p.contract_id and d.metric_key = p.metric_key
                            and d.day <= (p_at at time zone 'Asia/Dubai')::date order by d.day desc limit 1) v on true
       where p.month = m.m0), '[]'::jsonb))
$fn$;
revoke execute on function public.fn_ceo_year_plan_status(timestamptz) from public, anon, authenticated;
grant execute on function public.fn_ceo_year_plan_status(timestamptz) to service_role;

create or replace function public.fn_ceo_target_daily_verdict(p_at timestamptz default now())
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_local timestamp := p_at at time zone 'Asia/Dubai'; v_day date := v_local::date;
  v_m0 date := date_trunc('month', v_local)::date; v_from timestamptz := v_m0::timestamp at time zone 'Asia/Dubai';
  v_frac numeric := extract(day from v_local) / extract(day from (date_trunc('month', v_local) + interval '1 month - 1 day'));
  p record; v_exp numeric; v_act numeric; v_gap numeric; v_status text; v_task bigint; v_hid bigint; v_prev_cum numeric;
  n_miss int := 0; n_new int := 0; n_closed int := 0; v_out jsonb := '[]'::jsonb; c_id bigint;
begin
  select id into c_id from public.target_contract where contract_key = 'FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30' and status = 'active';
  if c_id is null then return jsonb_build_object('day', v_day, 'contract', null); end if;

  for p in select * from public.target_path where contract_id = c_id and month = v_m0 order by metric_key loop
    v_act := public.fn_ambition_measure(p.metric_key, v_from, p_at);
    if p.kind = 'cumulative' then
      -- the day's line starts from last month's TARGET; a real shortfall is carried by the month directive (still_needed)
      select coalesce(max(value), 0) into v_prev_cum from public.target_path where contract_id = c_id and metric_key = p.metric_key and month < v_m0;
      v_exp := round(v_prev_cum + (p.value - v_prev_cum) * v_frac, 1);
    elsif p.kind = 'month' and p.direction = 'min' then v_exp := round(p.value * v_frac, 1);
    else v_exp := p.value; end if;   -- a ceiling (direction max) is the whole month's: costs are lumpy, never pro-rated

    v_gap := case when v_exp > 0 and v_act is not null then round(100.0 * (v_act - v_exp) / v_exp, 1) end;
    v_status := case when p.direction = 'max' then
                       case when v_act is null then 'not_measurable'
                            when v_act <= v_exp then 'on_track'
                            when v_gap <= p.tolerance_pct then 'within_tolerance'
                            else 'miss' end
                     when p.kind in ('month', 'cumulative') and extract(day from v_local) < 7 then 'too_early'
                     when v_exp is null or v_exp <= 0 then 'no_target'
                     when v_act is null then 'not_measurable'
                     when v_act >= v_exp then 'on_track'
                     when -v_gap <= p.tolerance_pct then 'within_tolerance'
                     else 'miss' end;

    -- the month's open task for this metric, if any
    select t.task_id into v_task from public.target_daily_verdict d join public.ceo_task t on t.task_id = d.task_id
     where d.contract_id = c_id and d.metric_key = p.metric_key and d.day >= v_m0 and d.day <= v_day
       and t.state in ('open', 'working', 'blocked') order by d.day desc limit 1;
    v_hid := null;
    if v_status = 'miss' then
      n_miss := n_miss + 1;
      if v_task is null then
        v_task := public.fn_ceo_task_open(format('Target miss: %s (%s) %s', p.metric_key, p.owner_seat, to_char(v_m0, 'Mon YYYY')),
          format(E'On %s %s read %s against %s (%s) on the founder''s year-one path (%s%% gap, tolerance %s%%).\nOwner: %s. The root-cause question went to the owner; this task closes when the measure is back within tolerance.',
                 v_day, p.metric_key, v_act, v_exp, case when p.direction = 'max' then 'the month''s ceiling' else 'expected by today' end,
                 v_gap, p.tolerance_pct, p.owner_seat));
        n_new := n_new + 1;
        if p.owner_seat = 'ceo' then
          perform public.fn_ceo_root_cause_ask('ceo', v_task, jsonb_build_object('metric', p.metric_key, 'day', v_day, 'expected', v_exp,
                                               'actual', v_act, 'gap_pct', v_gap, 'tolerance_pct', p.tolerance_pct, 'month_target', p.value));
        else
          v_hid := public.fn_seat_handoff('ceo', p.owner_seat, 'ceo.root_cause', 'ceo_task', v_task::text,
            jsonb_build_object('task_id', v_task, 'metric', p.metric_key, 'day', v_day, 'expected', v_exp, 'actual', v_act,
                               'gap_pct', v_gap, 'tolerance_pct', p.tolerance_pct, 'month_target', p.value));
        end if;
      end if;
    elsif v_task is not null and v_status in ('on_track', 'within_tolerance') then
      update public.ceo_task set state = 'done', closed_at = now(),
             evidence = format('Recovered on %s: %s read %s against %s expected (%s).', v_day, p.metric_key, v_act, v_exp, v_status)
       where task_id = v_task;
      n_closed := n_closed + 1; v_task := null;
    elsif v_task is not null and v_status = 'not_measurable' then
      -- the miss can no longer be confirmed or cleared: say so on the task instead of leaving it silently open
      update public.ceo_task set state = 'blocked',
             blocked_reason = format('On %s %s became not measurable (under 20 in its denominator); the miss is neither confirmed nor cleared.', v_day, p.metric_key)
       where task_id = v_task and state <> 'blocked';
    end if;

    insert into public.target_daily_verdict (day, contract_id, metric_key, owner_seat, expected, actual, gap_pct, status, task_id, handoff_id)
    values (v_day, c_id, p.metric_key, p.owner_seat, v_exp, v_act, v_gap, v_status, case when v_status = 'miss' then v_task end, v_hid)
    on conflict (day, contract_id, metric_key) do update set expected = excluded.expected, actual = excluded.actual, gap_pct = excluded.gap_pct,
      status = excluded.status, task_id = coalesce(target_daily_verdict.task_id, excluded.task_id),
      handoff_id = coalesce(target_daily_verdict.handoff_id, excluded.handoff_id);
    v_out := v_out || jsonb_build_object('metric', p.metric_key, 'status', v_status, 'expected', v_exp, 'actual', v_act);
  end loop;
  return jsonb_build_object('day', v_day, 'contract_id', c_id, 'metrics', v_out, 'misses', n_miss, 'tasks_opened', n_new, 'tasks_closed', n_closed);
end $fn$;
revoke execute on function public.fn_ceo_target_daily_verdict(timestamptz) from public, anon, authenticated;
grant execute on function public.fn_ceo_target_daily_verdict(timestamptz) to service_role;

-- The weekly forecast (#906) reads the founder's year-one contract.
create or replace function public.fn_ceo_target_forecast()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare c record; v jsonb; v_all jsonb := '[]'::jsonb; v_rev jsonb; v_week date := public.fn_ceo_review_week(); v_held bigint;
begin
  for c in select id, contract_key from public.target_contract where status = 'active' and measure_sql is not null order by priority, id loop
    v := public.fn_target_feasibility(c.id, true);
    v_all := v_all || jsonb_build_object('contract', c.contract_key, 'verdict', v->>'verdict', 'verdict_reason', v->>'verdict_reason',
                                         'remaining', v->'remaining_outcome', 'days_remaining', v->'days_remaining',
                                         'required_run_rate_per_day', v->'required_run_rate_per_day', 'binding_stage', v->>'binding_stage',
                                         'what_must_change', v->'what_must_change');
    if c.contract_key = 'FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30' then v_rev := v; end if;   -- the founder's year-one targets (24 Sep 2026)
  end loop;

  insert into public.ceo_review (kind, period, facts) values ('target_forecast', v_week, jsonb_build_object('verdicts', v_all))
  on conflict (kind, period) do update set facts = excluded.facts;

  if v_rev is not null and coalesce(v_rev->>'verdict', '') <> 'ON_TRACK'
     and (select held_id from public.ceo_review where kind = 'target_forecast' and period = v_week) is null then
    v_held := public.fn_seat_duty_reason('ceo', 'ceo.target_forecast',
      'This week''s forecast says the founder''s year-one target (about 500 verified suppliers by 31 August 2027, on the monthly path per seat) is not on track. '
        || 'As the chief executive, decide the company''s response, and say what must change and who owns it.',
      ('[{"id":"hold_course","meaning":"the plan in force is right; the gap is expected at this stage and closes as it runs"},'
      || '{"id":"change_plan","meaning":"the plan must change: a different binding constraint, channel or sequence"},'
      || '{"id":"tell_founder","meaning":"the gap needs a decision only the founder holds (money, a commercial rule, his intent)"}]')::jsonb,
      jsonb_build_object('forecast', v_rev - 'chain', 'all_contracts', v_all, 'year_plan', public.fn_ceo_year_plan_status(now())),
      jsonb_build_object('kind', 'target_forecast', 'period', v_week), 'ceo_forecast:' || v_week);
    update public.ceo_review set held_id = v_held where kind = 'target_forecast' and period = v_week;
  end if;
  return jsonb_build_object('week', v_week, 'verdicts', v_all, 'reasoning_filed', v_held is not null);
end $fn$;
revoke execute on function public.fn_ceo_target_forecast() from public, anon, authenticated;
grant execute on function public.fn_ceo_target_forecast() to service_role;

-- The weekly management review (#906): each seat now reports against its own targets and month directive.
create or replace function public.fn_ceo_management_review()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_week date := public.fn_ceo_review_week(); v_facts jsonb; v_held bigint;
begin
  if (select held_id from public.ceo_review where kind = 'management_review' and period = v_week) is not null then
    return jsonb_build_object('week', v_week, 'already_filed', true);
  end if;
  select jsonb_build_object(
    'seats', (select jsonb_object_agg(r.role_id, jsonb_build_object(
        'duties', (select coalesce(jsonb_agg(jsonb_build_object('duty', d.duty, 'last_ok_at', d.last_ok_at, 'failures', d.failures, 'last_result', d.last_result)), '[]'::jsonb)
                     from public.seat_duty d where d.owner_seat = r.role_id),
        'open_findings', (select count(*) from public.it_engineer_finding f where f.closed_at is null
                            and coalesce(f.evidence->>'owner_seat', f.raised_by) = r.role_id),
        'reasoning_waiting', (select count(*) from public.reasoning_held_question h where h.seat = r.role_id and h.status = 'held'),
        'handoffs_pending', (select count(*) from public.agent_actions a where a.agent = r.role_id and a.kind = 'handoff' and a.status = 'pending'),
        -- the seat reports against its own year-one targets and its month directive
        'targets', (select coalesce(jsonb_agg(x), '[]'::jsonb) from jsonb_array_elements(public.fn_ceo_year_plan_status(now())->'metrics') x
                     where x->>'owner_seat' = r.role_id),
        'month_directive', (select jsonb_build_object('actions', d.actions, 'targets', d.targets, 'handoff_id', d.handoff_id, 'status', d.status)
                              from public.ceo_seat_directive d where d.seat = r.role_id and d.month = date_trunc('month', now() at time zone 'Asia/Dubai')::date),
        'improvements_open', (select count(*) from public.ceo_improvement i where i.seat = r.role_id and i.status in ('open', 'assigned'))))
      from public.org_role r where r.status = 'active'),
    'duties_unhealthy', public.fn_seat_duty_health(),
    'week_revenue_aed', (select coalesce(sum(reveal_fee), 0) from public.transactions where fee_status in ('paid', 'collected', 'succeeded') and revealed_at > now() - interval '7 days'),
    'requests_7d', (select count(*) from public.inquiries where created_at > now() - interval '7 days'),
    'customers', (select count(*) from public.customers where not coalesce(is_demo, false)),
    'suppliers_approved', (select count(*) from public.leads where approval_status = 'approved' and not coalesce(is_demo, false)),
    'forecast', (select facts from public.ceo_review where kind = 'target_forecast' and period = v_week),
    'last_review', (select jsonb_build_object('week', period, 'verdict', decision, 'fields', fields) from public.ceo_review
                     where kind = 'management_review' and period < v_week and decision is not null order by period desc limit 1))
  into v_facts;
  insert into public.ceo_review (kind, period, facts) values ('management_review', v_week, v_facts)
  on conflict (kind, period) do update set facts = excluded.facts;

  v_held := public.fn_seat_duty_reason('ceo', 'ceo.management_review',
    'The weekly management review. Read each seat''s week — its duties, failures, open findings, what waits in its '
      || 'reasoning queue, and its own targets and month directive on the founder''s year-one path — against last week''s review. Give the verdict, name the one '
      || 'binding constraint, and one concrete line of direction for each seat.',
    ('[{"id":"on_track","meaning":"the company is on its plan this week"},'
    || '{"id":"at_risk","meaning":"the plan holds but something material is slipping"},'
    || '{"id":"off_track","meaning":"the plan is not working and must change"}]')::jsonb,
    v_facts, jsonb_build_object('kind', 'management_review', 'period', v_week), 'ceo_mreview:' || v_week);
  -- The fields the review must fill, beside the verdict (think() fills them from its reasoning, with evidence).
  update public.reasoning_held_question
     set request = jsonb_set(request, '{decision,fields}', jsonb_build_array(
           jsonb_build_object('key', 'binding_constraint', 'question', 'the one constraint that most limits progress this week'),
           jsonb_build_object('key', 'sales_engineer', 'question', 'the sales engineer''s direction for the coming week'),
           jsonb_build_object('key', 'customer_support', 'question', 'customer support''s direction for the coming week'),
           jsonb_build_object('key', 'accountant', 'question', 'the accountant''s direction for the coming week'),
           jsonb_build_object('key', 'it_engineer', 'question', 'the IT engineer''s direction for the coming week'),
           jsonb_build_object('key', 'marketing', 'question', 'marketing''s direction for the coming week')))
   where id = v_held;
  update public.ceo_review set held_id = v_held where kind = 'management_review' and period = v_week;
  return jsonb_build_object('week', v_week, 'filed', v_held);
end $fn$;
revoke execute on function public.fn_ceo_management_review() from public, anon, authenticated;
grant execute on function public.fn_ceo_management_review() to service_role;

-- ═════════════════════════════════════════════════════════════════════════════════════════════════════
-- 3. IMPROVING THE COMPANY: proposals from misses, lessons and recurring findings, assigned and tracked to done
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════
create table if not exists public.ceo_improvement (
  id            bigserial primary key,
  source_kind   text not null check (source_kind in ('recurring_miss', 'month_miss', 'lesson', 'recurring_finding')),
  source_ref    text not null,
  seat          text not null references public.org_role (role_id),
  proposal      text not null check (btrim(proposal) <> ''),
  evidence      jsonb not null default '{}'::jsonb,
  status        text not null default 'open' check (status in ('open', 'assigned', 'done', 'dropped')),
  task_id       bigint,
  handoff_id    bigint,
  done_evidence text,
  created_at    timestamptz not null default now(),
  closed_at     timestamptz,
  unique (source_kind, source_ref)
);
alter table public.ceo_improvement enable row level security;
drop policy if exists ceo_improvement_service_role_only on public.ceo_improvement;
create policy ceo_improvement_service_role_only on public.ceo_improvement as permissive for all to public using (false) with check (false);
revoke all on public.ceo_improvement from anon, authenticated;
revoke all on sequence public.ceo_improvement_id_seq from anon, authenticated;

-- Opens one improvement (idempotent on its source), with a CEO task and, for another seat, a handoff it acts on.
create or replace function public.fn_ceo_improvement_open(p_kind text, p_ref text, p_seat text, p_proposal text, p_evidence jsonb)
returns bigint
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_id bigint; v_task bigint; v_hid bigint;
begin
  insert into public.ceo_improvement (source_kind, source_ref, seat, proposal, evidence)
  values (p_kind, p_ref, p_seat, p_proposal, coalesce(p_evidence, '{}'::jsonb))
  on conflict (source_kind, source_ref) do nothing returning id into v_id;
  if v_id is null then return null; end if;   -- proposed already
  v_task := public.fn_ceo_task_open(format('Improvement #%s for %s: %s', v_id, p_seat, left(p_proposal, 200)),
                                    format(E'%s\nSource: %s %s.\nEvidence: %s', p_proposal, p_kind, p_ref, coalesce(p_evidence, '{}'::jsonb)));
  if p_seat <> 'ceo' then
    v_hid := public.fn_seat_handoff('ceo', p_seat, 'ceo.improvement', 'ceo_improvement', v_id::text,
      jsonb_build_object('improvement_id', v_id, 'task_id', v_task, 'proposal', p_proposal, 'source', p_kind, 'evidence', p_evidence));
  end if;
  update public.ceo_improvement set status = 'assigned', task_id = v_task, handoff_id = v_hid where id = v_id;
  return v_id;
end $fn$;
revoke execute on function public.fn_ceo_improvement_open(text, text, text, text, jsonb) from public, anon, authenticated;

-- The seat takes the improvement into its work; the CEO closes it when its source shows it worked.
create or replace function public.fn_seat_takes_ceo_improvement(p_id bigint)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare a public.agent_actions;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  return jsonb_build_object('accepted', true, 'seat', a.agent, 'improvement_id', a.detail->'improvement_id', 'proposal', a.detail->>'proposal',
    'waiting', 'the CEO closes this when its source recovers: the metric back on its path, the finding closed, or no repeat of the case');
end $fn$;
revoke execute on function public.fn_seat_takes_ceo_improvement(bigint) from public, anon, authenticated;

create or replace function public.fn_ceo_improvement_close(p_id bigint, p_evidence text)
returns void
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare i public.ceo_improvement;
begin
  update public.ceo_improvement set status = 'done', closed_at = now(), done_evidence = p_evidence
   where id = p_id and status in ('open', 'assigned') returning * into i;
  if not found then return; end if;
  update public.ceo_task set state = 'done', closed_at = now(), evidence = left(coalesce(evidence || E'\n', '') || p_evidence, 8000)
   where task_id = i.task_id and state in ('open', 'working', 'blocked');
  if i.handoff_id is not null and exists (select 1 from public.agent_actions where id = i.handoff_id and status = 'pending') then
    perform set_config('qd.handoff_closer', 'ceo', true);
    perform public.fn_seat_handoff_complete(i.handoff_id, jsonb_build_object('verified_by', 'ceo', 'improvement_id', i.id, 'evidence', p_evidence));
    perform set_config('qd.handoff_closer', '', true);
  end if;
end $fn$;
revoke execute on function public.fn_ceo_improvement_close(bigint, text) from public, anon, authenticated;

-- WEEKLY. Finds the sources, proposes, and closes what recovered.
create or replace function public.fn_ceo_improvement_sweep()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r record; n_new int := 0; n_done int := 0; c_id bigint; v bigint;
begin
  select id into c_id from public.target_contract where contract_key = 'FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30' and status = 'active';

  -- a metric behind its path on 7 or more of the last 14 days: the plan for it is not working
  for r in select d.metric_key, d.owner_seat, count(*) filter (where d.status = 'miss') as misses,
                  min(d.actual) filter (where d.status = 'miss') as low, max(d.expected) as expected
             from public.target_daily_verdict d
            where d.contract_id = c_id and d.day > current_date - 14
            group by 1, 2 having count(*) filter (where d.status = 'miss') >= 7 loop
    v := public.fn_ceo_improvement_open('recurring_miss', r.metric_key || ':' || to_char(current_date, 'YYYY-MM'), r.owner_seat,
      format('%s has been behind its path on %s of the last 14 days. Change how the seat moves it, not the target: name the step that is not converting and fix that step.', r.metric_key, r.misses),
      jsonb_build_object('metric', r.metric_key, 'misses_14d', r.misses, 'lowest_actual', r.low, 'expected', r.expected));
    n_new := n_new + (v is not null)::int;
  end loop;

  -- a lesson a seat wrote down (seat_case_memory) in the last 30 days becomes a change to its routine
  for r in select m.id, m.seat, m.case_kind, m.lessons[1] as lesson from public.seat_case_memory m
            where cardinality(m.lessons) > 0 and coalesce(m.updated_at, m.opened_at) > now() - interval '30 days'
              and exists (select 1 from public.org_role o where o.role_id = m.seat and o.status = 'active') loop
    v := public.fn_ceo_improvement_open('lesson', 'seat_case_memory:' || r.id, r.seat,
      format('Make this lesson part of the routine, so the same case does not come back: %s', r.lesson),
      jsonb_build_object('case_memory_id', r.id, 'case_kind', r.case_kind));
    n_new := n_new + (v is not null)::int;
  end loop;

  -- an open finding seen three or more times is a process fault, not a one-off
  for r in select f.issue_key, f.title, f.seen_count, coalesce(nullif(f.evidence->>'owner_seat', ''), f.raised_by) as seat
             from public.it_engineer_finding f where f.closed_at is null and f.seen_count >= 3 loop
    if exists (select 1 from public.org_role o where o.role_id = r.seat and o.status = 'active') then
      v := public.fn_ceo_improvement_open('recurring_finding', r.issue_key, r.seat,
        format('Remove the cause of a finding seen %s times: %s', r.seen_count, left(r.title, 300)),
        jsonb_build_object('issue_key', r.issue_key, 'seen_count', r.seen_count));
      n_new := n_new + (v is not null)::int;
    end if;
  end loop;

  -- tracked to done
  for r in select i.* from public.ceo_improvement i where i.status in ('open', 'assigned') loop
    if r.source_kind in ('recurring_miss', 'month_miss')
       and (select count(*) filter (where d.status in ('on_track', 'within_tolerance')) = 7 and count(*) = 7
              from public.target_daily_verdict d where d.contract_id = c_id and d.metric_key = r.evidence->>'metric'
               and d.day > current_date - 7 and d.day > r.created_at::date) then
      perform public.fn_ceo_improvement_close(r.id, format('%s back on its path for 7 days running (%s).', r.evidence->>'metric', current_date));
      n_done := n_done + 1;
    elsif r.source_kind = 'recurring_finding'
       and exists (select 1 from public.it_engineer_finding f where f.issue_key = r.source_ref and f.closed_at is not null) then
      perform public.fn_ceo_improvement_close(r.id, format('Finding %s closed.', r.source_ref));
      n_done := n_done + 1;
    elsif r.source_kind = 'lesson' and r.created_at < now() - interval '30 days'
       and not exists (select 1 from public.seat_case_memory m where m.seat = r.seat and m.case_kind = r.evidence->>'case_kind' and m.opened_at > r.created_at) then
      perform public.fn_ceo_improvement_close(r.id, format('No repeat of a %s case for %s in the 30 days since the lesson was assigned.', r.evidence->>'case_kind', r.seat));
      n_done := n_done + 1;
    end if;
  end loop;
  return jsonb_build_object('proposed', n_new, 'closed', n_done,
    'open', (select count(*) from public.ceo_improvement where status in ('open', 'assigned')));
end $fn$;
revoke execute on function public.fn_ceo_improvement_sweep() from public, anon, authenticated;
grant execute on function public.fn_ceo_improvement_sweep() to service_role;

-- ═════════════════════════════════════════════════════════════════════════════════════════════════════
-- 4. MONTHLY: close last month per seat, re-plan, issue each seat its directive, report to the founder
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════
create table if not exists public.ceo_seat_directive (
  month      date not null check (extract(day from month) = 1),
  seat       text not null references public.org_role (role_id),
  targets    jsonb not null,           -- per metric: the month's target and, for a cumulative metric, what is still needed
  actions    text[] not null,
  handoff_id bigint,
  status     text not null default 'issued' check (status in ('issued', 'met', 'missed', 'not_measurable')),
  outcome    jsonb,
  issued_at  timestamptz not null default now(),
  closed_at  timestamptz,
  primary key (month, seat)
);
alter table public.ceo_seat_directive enable row level security;
drop policy if exists ceo_seat_directive_service_role_only on public.ceo_seat_directive;
create policy ceo_seat_directive_service_role_only on public.ceo_seat_directive as permissive for all to public using (false) with check (false);
revoke all on public.ceo_seat_directive from anon, authenticated;

create table if not exists public.ceo_month_report (
  month      date primary key check (extract(day from month) = 1),
  facts      jsonb not null,
  body       text not null,
  handoff_id bigint,
  created_at timestamptz not null default now()
);
alter table public.ceo_month_report enable row level security;
drop policy if exists ceo_month_report_service_role_only on public.ceo_month_report;
create policy ceo_month_report_service_role_only on public.ceo_month_report as permissive for all to public using (false) with check (false);
revoke all on public.ceo_month_report from anon, authenticated;

-- A metric of the path read over a whole month (or at its end), and whether it met its target.
create or replace function public.fn_ceo_path_month_result(p_contract bigint, p_month date)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare p record; v_from timestamptz := p_month::timestamp at time zone 'Asia/Dubai';
  v_to timestamptz := (p_month + interval '1 month')::timestamp at time zone 'Asia/Dubai'; v_act numeric; v_out jsonb := '[]'::jsonb;
begin
  for p in select * from public.target_path where contract_id = p_contract and month = p_month order by owner_seat, metric_key loop
    v_act := public.fn_ambition_measure(p.metric_key, v_from, v_to);
    v_out := v_out || jsonb_build_object('metric', p.metric_key, 'owner_seat', p.owner_seat, 'direction', p.direction, 'target', p.value, 'actual', v_act,
      'result', case when v_act is null then 'not_measurable'
                     when p.direction = 'max' then case when v_act <= p.value then 'met' else 'missed' end
                     when p.value <= 0 then 'met'
                     when v_act >= p.value then 'met' else 'missed' end);
  end loop;
  return v_out;
end $fn$;
revoke execute on function public.fn_ceo_path_month_result(bigint, date) from public, anon, authenticated;

create or replace function public.fn_seat_takes_ceo_month_directive(p_id bigint)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare a public.agent_actions;
begin
  select * into a from public.agent_actions where id = p_id and kind = 'handoff';
  if not found then raise exception 'no handoff %', p_id; end if;
  return jsonb_build_object('accepted', true, 'seat', a.agent, 'month', a.detail->>'month', 'targets', a.detail->'targets', 'actions', a.detail->'actions',
    'waiting', 'the CEO reads each target daily and closes this at month end, met or missed');
end $fn$;
revoke execute on function public.fn_seat_takes_ceo_month_directive(bigint) from public, anon, authenticated;

create or replace function public.fn_ceo_month_plan(p_at timestamptz default now())
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_m0 date := date_trunc('month', p_at at time zone 'Asia/Dubai')::date; v_pm date := (v_m0 - interval '1 month')::date;
  c_id bigint; d public.ceo_seat_directive; r jsonb; x jsonb; v_status text; v_targets jsonb; v_need numeric; v_act numeric;
  v_miss jsonb; v_hid bigint; n_closed int := 0; n_issued int := 0; v_body text; v_facts jsonb; s text; v_cost numeric; v_ceiling numeric;
begin
  select id into c_id from public.target_contract where contract_key = 'FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30' and status = 'active';
  if c_id is null then return jsonb_build_object('month', v_m0, 'contract', null); end if;

  -- 1. close last month's directives, met or missed; a missed target becomes an improvement for the seat
  if exists (select 1 from public.target_path where contract_id = c_id and month = v_pm) then
    r := public.fn_ceo_path_month_result(c_id, v_pm);
    for d in select * from public.ceo_seat_directive where month = v_pm and status = 'issued' loop
      select coalesce(jsonb_agg(e), '[]'::jsonb) into x from jsonb_array_elements(r) e where e->>'owner_seat' = d.seat;
      v_status := case when exists (select 1 from jsonb_array_elements(x) e where e->>'result' = 'missed') then 'missed'
                       when exists (select 1 from jsonb_array_elements(x) e where e->>'result' = 'met') then 'met'
                       else 'not_measurable' end;
      update public.ceo_seat_directive set status = v_status, outcome = x, closed_at = now() where month = d.month and seat = d.seat;
      if d.handoff_id is not null and exists (select 1 from public.agent_actions where id = d.handoff_id and status = 'pending') then
        perform set_config('qd.handoff_closer', 'ceo', true);
        perform public.fn_seat_handoff_complete(d.handoff_id, jsonb_build_object('verified_by', 'ceo', 'month', v_pm, 'result', v_status, 'outcome', x));
        perform set_config('qd.handoff_closer', '', true);
      end if;
      for v_miss in select e from jsonb_array_elements(x) e where e->>'result' = 'missed' loop
        perform public.fn_ceo_improvement_open('month_miss', v_pm || ':' || d.seat || ':' || (v_miss->>'metric'), d.seat,
          format('%s closed %s at %s against a target of %s. Name the root cause and what changes this month.', v_miss->>'metric', to_char(v_pm, 'Mon YYYY'), v_miss->>'actual', v_miss->>'target'),
          v_miss || jsonb_build_object('month', v_pm));
      end loop;
      n_closed := n_closed + 1;
    end loop;

    -- 2. the founder's monthly report, once per month
    if not exists (select 1 from public.ceo_month_report where month = v_pm) then
      select cost_ceiling_aed into v_ceiling from public.ceo_year_plan where month = v_pm;
      v_cost := (select (e->>'actual')::numeric from jsonb_array_elements(r) e where e->>'metric' = 'costs_aed');
      v_facts := jsonb_build_object('month', v_pm, 'metrics', r,
        'directives', (select coalesce(jsonb_object_agg(seat, status), '{}'::jsonb) from public.ceo_seat_directive where month = v_pm),
        'improvements_opened', (select count(*) from public.ceo_improvement where created_at >= v_pm and created_at < v_m0),
        'improvements_closed', (select count(*) from public.ceo_improvement where closed_at >= v_pm and closed_at < v_m0),
        'cost_ceiling_aed', v_ceiling, 'costs_aed', v_cost, 'next_month', (select to_jsonb(y) from public.ceo_year_plan y where y.month = v_m0));
      v_body := format(E'Monthly review, %s.\n\nTargets against the plan:\n', to_char(v_pm, 'FMMonth YYYY'))
        || (select string_agg(format('- %s (%s): %s of %s, %s', e->>'metric', e->>'owner_seat', coalesce(e->>'actual', 'not measurable'),
                                     e->>'target', e->>'result'), E'\n' order by e->>'owner_seat') from jsonb_array_elements(r) e)
        || E'\n\nSeats: ' || coalesce((select string_agg(seat || ' ' || status, ', ' order by seat) from public.ceo_seat_directive where month = v_pm), 'no directives were issued')
        || format(E'\nCosts: AED %s against a ceiling of AED %s.', coalesce(round(v_cost)::text, 'not measurable'), v_ceiling)
        || format(E'\nImprovements: %s opened, %s closed.', v_facts->>'improvements_opened', v_facts->>'improvements_closed')
        || coalesce(format(E'\n\nNext month: %s verified suppliers by month end, %s requests, AED %s of reveal fees.',
                           v_facts->'next_month'->>'verified', v_facts->'next_month'->>'requests', v_facts->'next_month'->>'fee_aed'), '');
      v_hid := public.fn_seat_handoff('ceo', 'customer_support', 'delivery.request', 'ceo_month_report', v_pm::text,
        jsonb_build_object('recipient_role', 'founder', 'event', 'CEO monthly review: ' || to_char(v_pm, 'FMMonth YYYY'), 'detail', left(v_body, 4000),
                           'level', 'info', 'kind', 'founder_brief', 'dedupe_key', 'ceo_month:' || v_pm));
      insert into public.ceo_month_report (month, facts, body, handoff_id) values (v_pm, v_facts, v_body, v_hid);
    end if;
  end if;

  -- 3. this month's directive per seat, from the plan table; a cumulative target carries last month's shortfall
  if exists (select 1 from public.target_path where contract_id = c_id and month = v_m0) then
    foreach s in array array['sales_engineer', 'customer_support', 'marketing', 'accountant', 'it_engineer'] loop
      continue when exists (select 1 from public.ceo_seat_directive where month = v_m0 and seat = s);
      continue when not exists (select 1 from public.org_role where role_id = s and status = 'active');
      v_targets := '[]'::jsonb;
      for x in select to_jsonb(p) from public.target_path p where p.contract_id = c_id and p.month = v_m0 and p.owner_seat = s order by p.metric_key loop
        v_need := null;
        if x->>'kind' = 'cumulative' then
          v_act := public.fn_ambition_measure(x->>'metric_key', v_m0::timestamp at time zone 'Asia/Dubai', p_at);
          v_need := greatest(0, (x->>'value')::numeric - coalesce(v_act, 0));
        end if;
        v_targets := v_targets || jsonb_build_object('metric', x->>'metric_key', 'kind', x->>'kind', 'direction', x->>'direction',
                                                     'target', (x->>'value')::numeric, 'still_needed', v_need);
      end loop;
      insert into public.ceo_seat_directive (month, seat, targets, actions)
      values (v_m0, s, v_targets, coalesce((select array_agg(a.action order by a.id) from public.ceo_plan_action a
                                             where a.seat = s and v_m0 between a.from_month and a.to_month), '{}'::text[]));
      v_hid := public.fn_seat_handoff('ceo', s, 'ceo.month_directive', 'ceo_seat_directive', v_m0 || ':' || s,
        jsonb_build_object('month', v_m0, 'targets', v_targets,
                           'actions', (select to_jsonb(actions) from public.ceo_seat_directive where month = v_m0 and seat = s),
                           'due_at', ((v_m0 + interval '1 month')::timestamp at time zone 'Asia/Dubai')));
      update public.ceo_seat_directive set handoff_id = v_hid where month = v_m0 and seat = s;
      n_issued := n_issued + 1;
    end loop;
  end if;
  return jsonb_build_object('month', v_m0, 'closed', n_closed, 'issued', n_issued,
    'reported', (select handoff_id from public.ceo_month_report where month = v_pm));
end $fn$;
revoke execute on function public.fn_ceo_month_plan(timestamptz) from public, anon, authenticated;
grant execute on function public.fn_ceo_month_plan(timestamptz) to service_role;

-- ═════════════════════════════════════════════════════════════════════════════════════════════════════
-- 5. DAILY: the morning read, the day's priorities, unblocking, the signals, and a note only when it matters
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════
create table if not exists public.ceo_day (
  day             date primary key,
  facts           jsonb not null,
  priorities      jsonb not null,
  matters         text[] not null default '{}',
  note_handoff_id bigint,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
alter table public.ceo_day enable row level security;
drop policy if exists ceo_day_service_role_only on public.ceo_day;
create policy ceo_day_service_role_only on public.ceo_day as permissive for all to public using (false) with check (false);
revoke all on public.ceo_day from anon, authenticated;

create or replace function public.fn_ceo_daily_run(p_at timestamptz default now())
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_day date := (p_at at time zone 'Asia/Dubai')::date; v_m0 date := date_trunc('month', p_at at time zone 'Asia/Dubai')::date;
  v_from timestamptz := v_m0::timestamp at time zone 'Asia/Dubai';
  v_verdict jsonb; v_status jsonb; h record; n_stuck_new int := 0; v_stuck jsonb := '[]'::jsonb; v_prio jsonb := '{}'::jsonb;
  v_signals jsonb; v_matters text[] := '{}'; v_note bigint; s text; v_m jsonb; v_first text; v_task bigint; v_body text;
begin
  -- the morning read: every path metric against today (idempotent: the verdict opens a task once per miss)
  v_verdict := public.fn_ceo_target_daily_verdict(p_at);
  v_status := public.fn_ceo_year_plan_status(p_at);

  -- unblocking: a handoff the receiving seat never answered within twice its reply time (a day when none is set)
  for h in select a.id, a.agent, a.detail->>'type' as type, a.detail->>'from' as from_seat, a.created_at
             from public.agent_actions a
             left join public.seat_handoff_kind k on k.type = a.detail->>'type' and k.from_seat = a.detail->>'from' and k.to_seat = a.agent
            where a.kind = 'handoff' and a.status = 'pending' and a.detail->>'replied_at' is null
              and a.created_at < p_at - coalesce(k.reply_within * 2, interval '1 day') loop
    v_stuck := v_stuck || jsonb_build_object('handoff_id', h.id, 'seat', h.agent, 'type', h.type, 'from', h.from_seat, 'since', h.created_at);
    if not exists (select 1 from public.ceo_task where title = format('Stuck handoff #%s', h.id)) then
      v_task := public.fn_ceo_task_open(format('Stuck handoff #%s', h.id),
        format(E'%s from %s to %s has waited since %s with no answer. The CEO re-runs it (fn_seat_handoff_act) and, if it fails again, the failure is on this task.',
               h.type, h.from_seat, h.agent, h.created_at));
      begin
        perform public.fn_seat_handoff_act(h.id);                    -- the unblock: the receiving seat acts now
        update public.ceo_task set state = 'done', closed_at = now(), evidence = 'Re-run on ' || v_day || ': the seat answered.'
         where task_id = v_task and exists (select 1 from public.agent_actions where id = h.id and (status = 'done' or detail ? 'replied_at'));
      exception when others then
        update public.ceo_task set state = 'blocked', blocked_reason = left('Re-run failed: ' || sqlerrm, 1000) where task_id = v_task;
      end;
      n_stuck_new := n_stuck_new + 1;
    end if;
  end loop;

  -- the experience, cash and incident signals
  v_signals := jsonb_build_object(
    'stranded_registrations', public.fn_ceo_plan_measure('stranded_submissions', p_at - interval '1 day', p_at),
    'bounce_pct_7d', public.fn_ceo_plan_measure('bounce_pct_7d', p_at - interval '7 days', p_at),
    'requests_unquoted_3d', (select count(*) from public.inquiries i join public.customers c on c.id = i.customer_id
                               where i.parent_inquiry_id is null and i.created_at < p_at - interval '3 days' and i.created_at > p_at - interval '30 days'
                                 and not exists (select 1 from public.quotes q where q.inquiry_id = i.id)
                                 and coalesce(i.provenance->>'source', '') not in ('demo_factory', 'e2e')
                                 and not (coalesce(c.is_demo, false) or coalesce(c.full_name, '') ilike 'ZZ DEMO%' or coalesce(c.email, '') ilike '%@example.invalid')),
    'findings_open', (select count(*) from public.it_engineer_finding where closed_at is null),
    'findings_new_today', (select count(*) from public.it_engineer_finding where closed_at is null and started_at > p_at - interval '1 day'),
    'fee_month_aed', public.fn_ambition_measure('fee_aed', v_from, p_at),
    'costs_month_aed', public.fn_ambition_measure('costs_aed', v_from, p_at),
    'cost_ceiling_month_aed', (select cost_ceiling_aed from public.ceo_year_plan where month = v_m0),
    'stale_tasks', (select count(*) from public.ceo_task where state in ('open', 'working', 'blocked') and created_at < p_at - interval '14 days'));

  -- the day's priorities per seat: its worst miss first, then its stuck handoffs, then its open improvements
  foreach s in array array['sales_engineer', 'customer_support', 'marketing', 'accountant', 'it_engineer'] loop
    select e into v_m from jsonb_array_elements(v_status->'metrics') e
     where e->>'owner_seat' = s and e->>'status' in ('miss', 'within_tolerance')
     order by (e->>'status' = 'miss') desc, abs(coalesce((e->>'gap_pct')::numeric, 0)) desc limit 1;
    v_first := case
      when v_m is not null then format('Recover %s: %s against %s today (%s).', v_m->>'metric', coalesce(v_m->>'actual', '?'), v_m->>'expected', v_m->>'status')
      when exists (select 1 from jsonb_array_elements(v_stuck) e where e->>'seat' = s) then 'Answer the handoffs waiting past their reply time.'
      when exists (select 1 from public.ceo_improvement i where i.seat = s and i.status = 'assigned') then
        'Move improvement #' || (select min(id) from public.ceo_improvement i where i.seat = s and i.status = 'assigned') || ' forward.'
      else 'Hold the path: every target of the month is on track.' end;
    v_prio := v_prio || jsonb_build_object(s, jsonb_build_object('first', v_first,
      'misses', (select coalesce(jsonb_agg(e->>'metric'), '[]'::jsonb) from jsonb_array_elements(v_status->'metrics') e where e->>'owner_seat' = s and e->>'status' = 'miss'),
      'stuck_handoffs', (select count(*) from jsonb_array_elements(v_stuck) e where e->>'seat' = s),
      'improvements_open', (select count(*) from public.ceo_improvement i where i.seat = s and i.status in ('open', 'assigned'))));
  end loop;

  -- what matters enough for the founder's daily note (otherwise he gets nothing today)
  if coalesce((v_verdict->>'tasks_opened')::int, 0) > 0 then v_matters := v_matters || format('%s target(s) fell behind the path today', v_verdict->>'tasks_opened'); end if;
  if n_stuck_new > 0 then v_matters := v_matters || format('%s handoff(s) were stuck and re-run', n_stuck_new); end if;
  if coalesce((v_signals->>'stranded_registrations')::numeric, 0) > 0 then v_matters := v_matters || format('%s supplier registration(s) waited over 24 hours', v_signals->>'stranded_registrations'); end if;
  if coalesce((v_signals->>'bounce_pct_7d')::numeric, 0) >= 5 then v_matters := v_matters || format('email bounces at %s %% over 7 days', v_signals->>'bounce_pct_7d'); end if;
  if coalesce((v_signals->>'requests_unquoted_3d')::int, 0) > 0 then v_matters := v_matters || format('%s request(s) have no quote after 3 days', v_signals->>'requests_unquoted_3d'); end if;
  if coalesce((v_signals->>'costs_month_aed')::numeric, 0) > coalesce((v_signals->>'cost_ceiling_month_aed')::numeric, 1e12) then
    v_matters := v_matters || format('costs this month AED %s are over the ceiling of AED %s', round((v_signals->>'costs_month_aed')::numeric), v_signals->>'cost_ceiling_month_aed');
  end if;

  insert into public.ceo_day (day, facts, priorities, matters)
  values (v_day, jsonb_build_object('verdict', v_verdict, 'plan', v_status, 'signals', v_signals, 'stuck', v_stuck), v_prio, v_matters)
  on conflict (day) do update set facts = excluded.facts, priorities = excluded.priorities,
    matters = (select array_agg(distinct m) from unnest(ceo_day.matters || excluded.matters) m), updated_at = now();

  select note_handoff_id into v_note from public.ceo_day where day = v_day;
  if cardinality(v_matters) > 0 and v_note is null then
    v_body := 'Today, ' || to_char(v_day, 'Dy DD Mon') || E':\n- ' || array_to_string(v_matters, E'\n- ')
      || E'\n\nWhat the seats do about it:\n' || (select string_agg(format('- %s: %s', k, v->>'first'), E'\n' order by k) from jsonb_each(v_prio) x(k, v));
    v_note := public.fn_seat_handoff('ceo', 'customer_support', 'delivery.request', 'ceo_day', v_day::text,
      jsonb_build_object('recipient_role', 'founder', 'event', 'CEO daily note: ' || to_char(v_day, 'Dy DD Mon'), 'detail', left(v_body, 4000),
                         'level', 'info', 'kind', 'founder_brief', 'dedupe_key', 'ceo_day:' || v_day));
    update public.ceo_day set note_handoff_id = v_note where day = v_day;
  end if;
  return jsonb_build_object('day', v_day, 'misses', v_verdict->'misses', 'stuck_new', n_stuck_new, 'matters', to_jsonb(v_matters),
                            'note_handoff_id', v_note, 'priorities', v_prio);
end $fn$;
revoke execute on function public.fn_ceo_daily_run(timestamptz) from public, anon, authenticated;
grant execute on function public.fn_ceo_daily_run(timestamptz) to service_role;

-- the duty runner calls a routine with no argument
create or replace function public.fn_ceo_daily_run_now()
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_ceo_daily_run(now()) $fn$;
revoke execute on function public.fn_ceo_daily_run_now() from public, anon, authenticated;
grant execute on function public.fn_ceo_daily_run_now() to service_role;
create or replace function public.fn_ceo_month_plan_now()
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_ceo_month_plan(now()) $fn$;
revoke execute on function public.fn_ceo_month_plan_now() from public, anon, authenticated;
grant execute on function public.fn_ceo_month_plan_now() to service_role;

-- ═════════════════════════════════════════════════════════════════════════════════════════════════════
-- 6. THE CONVERSATIONS, THE DUTIES AND THE SEAT'S OWN RECORD
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════
insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, originator_closes, owner_file)
select k.type, 'ceo', s, k.meaning, k.handler, interval '1 day', true,
       'scripts/sql/the_ceo_runs_the_company_on_the_founders_year_one_targets.sql'
  from unnest(array['sales_engineer', 'customer_support', 'marketing', 'accountant', 'it_engineer']) s
  cross join (values
    ('ceo.month_directive', 'The seat''s month from the year-one plan: its targets (a cumulative one carries last month''s shortfall) and its actions. The CEO closes it at month end, met or missed.', 'fn_seat_takes_ceo_month_directive'),
    ('ceo.improvement', 'An improvement the CEO assigns from a recurring miss, a lesson or a recurring finding. The CEO closes it when its source shows it worked.', 'fn_seat_takes_ceo_improvement')) k(type, meaning, handler)
on conflict (type, from_seat, to_seat) do update set meaning = excluded.meaning, handler = excluded.handler, owner_file = excluded.owner_file;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('ceo.daily_run', 'ceo', interval '1 day', 'fn_ceo_daily_run_now',
   'The morning read against the year-one path, the day''s priorities per seat, stuck handoffs re-run, the signals, and a founder note only when something matters.',
   'scripts/sql/the_ceo_runs_the_company_on_the_founders_year_one_targets.sql'),
  ('ceo.month_plan', 'ceo', interval '1 day', 'fn_ceo_month_plan_now',
   'Once a month: last month closed per seat, the monthly review to the founder, and each seat''s directive for the new month from the plan table.',
   'scripts/sql/the_ceo_runs_the_company_on_the_founders_year_one_targets.sql'),
  ('ceo.improvement', 'ceo', interval '7 days', 'fn_ceo_improvement_sweep',
   'Recurring misses, lessons and recurring findings become improvements assigned to a seat, closed when their source recovers.',
   'scripts/sql/the_ceo_runs_the_company_on_the_founders_year_one_targets.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

update public.org_agents
   set role = 'Chief Executive: runs the company on the founder''s year-one targets (50 suppliers by 8 Oct 2026, 200 by 30 Nov, 300 by 31 Dec, about 500 by Aug 2027) within his cost ceilings, and directs every seat to them',
       improvement_plan = 'Daily against public.target_path (ceo_day), weekly in the management review and the improvement sweep (ceo_improvement), monthly by each seat''s directive closed met or missed (ceo_seat_directive) and the founder''s monthly review (ceo_month_report).'
 where agent_key = 'ceo';

-- ═════════════════════════════════════════════════════════════════════════════════════════════════════
-- 6b. THE WEEKLY SUMMARY EMAIL CARRIES PLAN AGAINST ACTUAL FOR EVERY METRIC (founder, 24 Sep 2026)
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════
-- Per metric of the path, at the end of the reported week: the target by then, the actual, the gap, the owning seat
-- and the action being taken. The target by then is the verdict's own line (a month metric pro-rated to the day, a
-- cumulative one from last month's target, a level or rate as set, a ceiling the whole month's). The action is the
-- owning seat's open target-miss task (its root cause and corrective action once answered), otherwise the first action
-- of the seat's month directive. Code only.
create or replace function public.fn_ceo_week_plan_vs_actual(p_week_end date)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare c_id bigint; v_m0 date := date_trunc('month', p_week_end)::date; v_from timestamptz := v_m0::timestamp at time zone 'Asia/Dubai';
  v_to timestamptz := (p_week_end + 1)::timestamp at time zone 'Asia/Dubai';
  v_frac numeric := extract(day from p_week_end) / extract(day from (v_m0 + interval '1 month - 1 day'));
  p record; v_prev numeric; v_exp numeric; v_act numeric; v_gap numeric; v_res text; v_action text; v_rows jsonb := '[]'::jsonb; v_text text;
begin
  select id into c_id from public.target_contract where contract_key = 'FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30' and status = 'active';
  if c_id is null or not exists (select 1 from public.target_path where contract_id = c_id and month = v_m0) then
    return jsonb_build_object('rows', '[]'::jsonb, 'text', 'PLAN AGAINST ACTUAL' || E'\n' || '  No year-one path for ' || to_char(v_m0, 'FMMonth YYYY') || ' (the path runs October 2026 to September 2027).');
  end if;
  for p in select * from public.target_path where contract_id = c_id and month = v_m0 order by owner_seat, metric_key loop
    if p.kind = 'cumulative' then
      select coalesce(max(value), 0) into v_prev from public.target_path where contract_id = c_id and metric_key = p.metric_key and month < v_m0;
      v_exp := round(v_prev + (p.value - v_prev) * v_frac, 1);
    elsif p.kind = 'month' and p.direction = 'min' then v_exp := round(p.value * v_frac, 1);
    else v_exp := p.value; end if;
    v_act := public.fn_ambition_measure(p.metric_key, v_from, v_to);
    v_gap := case when v_act is not null then round(v_act - v_exp, 1) end;
    v_res := case when v_act is null then 'not measurable'
                  when p.direction = 'max' then case when v_act <= v_exp then 'within the ceiling' else 'OVER the ceiling' end
                  when v_act >= v_exp then 'on plan' else 'BEHIND' end;
    select coalesce(nullif(substring(t.evidence from 'Corrective action: ([^\n]*)'), '?'), 'root cause asked of ' || p.owner_seat || ' (task #' || t.task_id || ')')
      into v_action from public.ceo_task t
     where t.title like 'Target miss: ' || p.metric_key || ' (' || p.owner_seat || ')%' and t.state in ('open', 'working', 'blocked')
     order by t.task_id desc limit 1;
    if v_action is null then
      select d.actions[1] into v_action from public.ceo_seat_directive d where d.month = v_m0 and d.seat = p.owner_seat;
      v_action := coalesce(v_action, (select a.action from public.ceo_plan_action a where a.seat = p.owner_seat and v_m0 between a.from_month and a.to_month order by a.id limit 1),
                           'the CEO''s own routine: the daily read, the weekly review and the month plan');
    end if;
    v_rows := v_rows || jsonb_build_object('metric', p.metric_key, 'owner_seat', p.owner_seat, 'target', v_exp, 'month_target', p.value,
                                           'actual', v_act, 'gap', v_gap, 'result', v_res, 'action', v_action);
  end loop;
  v_text := 'PLAN AGAINST ACTUAL, month to ' || to_char(p_week_end, 'DD Mon YYYY') || E' (the founder''s year-one path)\n'
    || (select string_agg(format(E'  %s (%s): target %s, actual %s, gap %s, %s\n    Action: %s',
                                 r->>'metric', r->>'owner_seat', r->>'target', coalesce(r->>'actual', 'not measurable'),
                                 coalesce(r->>'gap', 'n/a'), r->>'result', r->>'action'), E'\n' order by r->>'owner_seat', r->>'metric')
          from jsonb_array_elements(v_rows) r);
  return jsonb_build_object('rows', v_rows, 'text', v_text);
end $fn$;
revoke execute on function public.fn_ceo_week_plan_vs_actual(date) from public, anon, authenticated;
grant execute on function public.fn_ceo_week_plan_vs_actual(date) to service_role;

-- Every weekly report the CEO writes carries the section, above the money figures; the plan rows go in its figures.
-- A trigger rather than a second copy of fn_ceo_weekly_report: the report's own writer stays the one canonical file.
create or replace function public.fn_ceo_weekly_report_carries_the_plan()
returns trigger
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v jsonb;
begin
  if new.body is null or position('PLAN AGAINST ACTUAL' in new.body) > 0 then return new; end if;
  v := public.fn_ceo_week_plan_vs_actual(new.week_end);
  new.body := case when position('MONEY' in new.body) > 0
                   then overlay(new.body placing (v->>'text') || E'\n\n' || '--------------------------------------------------' || E'\n' from position('MONEY' in new.body) for 0)
                   else new.body || E'\n\n' || (v->>'text') end;
  new.figures := coalesce(new.figures, '{}'::jsonb) || jsonb_build_object('plan_vs_actual', v->'rows');
  return new;
end $fn$;
revoke execute on function public.fn_ceo_weekly_report_carries_the_plan() from public, anon, authenticated;
drop trigger if exists ceo_weekly_report_carries_the_plan on public.ceo_weekly_report;
create trigger ceo_weekly_report_carries_the_plan before insert or update of body on public.ceo_weekly_report
  for each row execute function public.fn_ceo_weekly_report_carries_the_plan();

-- ═════════════════════════════════════════════════════════════════════════════════════════════════════
-- 7. THE VERDICT (reads only; the behaviour is proved in scripts/checks/the_ceo_year_one_plan_follows_the_founder_targets.test.mjs)
-- ═════════════════════════════════════════════════════════════════════════════════════════════════════
select case
  when (select count(*) from public.ceo_year_plan where month between date '2026-10-01' and date '2027-09-01') <> 12 then 'PROBE FAILED: the year plan is not 12 months'
  when (select verified from public.ceo_year_plan where month = date '2026-11-01') <> 200
    or (select verified from public.ceo_year_plan where month = date '2026-12-01') <> 300
    or (select verified from public.ceo_year_plan where month = date '2027-08-01') <> 500 then 'PROBE FAILED: a founder milestone is off the path'
  when (select sum(requests + reveals + fee_aed) from public.ceo_year_plan where month < date '2027-01-01') <> 0 then 'PROBE FAILED: customer activity before the January launch'
  when (select sum(cost_ceiling_aed) from public.ceo_year_plan) >= 250000 then 'PROBE FAILED: the cost ceilings exceed AED 250,000 a year'
  when exists (select 1 from public.target_contract where contract_key in ('REVEAL_FEES_BASE_PATH_BY_2027_08_31', 'REVENUE_AED_1M_BY_2027_10_01', 'SUPPLIERS_1000_BY_2027_10_01') and status = 'active')
    then 'PROBE FAILED: a replaced target is still active'
  when (select count(*) from public.target_path p join public.target_contract c on c.id = p.contract_id
         where c.contract_key = 'FOUNDER_TARGETS_YEAR_ONE_TO_2027_09_30') <> 192 then 'PROBE FAILED: the path is not 16 metrics x 12 months'
  when (select count(*) from public.seat_duty where duty in ('ceo.daily_run', 'ceo.month_plan', 'ceo.improvement')) <> 3 then 'PROBE FAILED: a CEO routine has no clock'
  else 'PROBE OK' end as verdict;
