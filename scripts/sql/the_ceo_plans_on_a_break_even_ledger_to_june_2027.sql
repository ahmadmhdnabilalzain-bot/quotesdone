-- THE CEO PLANS ON A BREAK-EVEN LEDGER TO 30 JUNE 2027: WHAT THE COMPANY HAS SPENT AND SPENDS, WHAT IT HAS EARNED, THE
-- GAP, THE MONTHS LEFT AND THE MONTHLY TARGETS THAT CLOSE IT; SET PER SEAT, CHECKED WEEKLY, RE-PLANNED WHEN BEHIND.
--
-- Assigned: ceo (the plan and the orders), with accountant (the cost lines are its books). 10 Nov 2026. Founder ledger
-- 1609: "break-even by June 2027 (AED 19,000 spent + running costs)", "the CEO holds a real strategy and turns it into
-- orders". Proposal P2 of docs/reports/2026-11-10-seat-qualification-audit.md.
--
-- == MEASURED, 10 Nov 2026, production read-only ====================================================================
--   * The CEO plans on ceo_year_plan, the 24 Sep investor model (ledger 971): cost ceilings of AED 18,598-25,598 a month
--     (they carry the founder's AED 10k fee and AED 5k of ads, which 1609 does not), 325 verified suppliers in January.
--     No ceo_* table holds a break-even number.
--   * Cost lines, expense_entries (USD x 3.6725), the latest month each vendor billed: Anthropic 775.01 (19 Oct), OpenAI
--     799.00 (subscription, Sep), Supabase 560.42 (Oct; Aug 130.85, Sep 265.74: rising), Vercel 334.79, GoDaddy (M365)
--     93.80, Resend 73.45, GlockApps 65.50, Twilio 36.76, Google 26.99; the Mashreq fee 199 + 9.95 VAT from the statement.
--     Recurring without OpenRouter: AED 2,974.67 a month. OpenRouter, openrouter_day authoritative: AED 1,297.03 in the
--     last 30 days (session evaluation days included), AED 94.78 in the last 7.
--   * Off, by ruling or measurement, so not carried forward: GitHub (AED 2,514.49 in Oct) and Ubicloud (148.11), Actions
--     off by ledger 1564; Namespace (367.25 once, 21 Oct) ASSUMED off with them, not measured; Apify paused until about
--     Feb 2027 (memory); Tasjeel.ae 31.50 a one-off.
--   * Revenue: 1 transaction ever (AED 777.60, 21 Sep), and its customer is ZZ DEMO. Real reveal revenue: AED 0.
--   * Supply funnel: 312 real leads invited, 1 claimed, 0 approved. fn_invite_founder_cap = 50 a day on every day to June.
--
-- == THE LEDGER (fn_break_even_ledger, every day) ===================================================================
--   cost to cover  = the founder's AED 19,000 (his figure, ledger 1609) + monthly cost x months left to 30 Jun 2027
--                    + the trade-licence renewal (AED 1,200 on 24 Jun 2027; last year's price, ASSUMED unchanged);
--   revenue        = net reveal revenue of real paid reveals: 0.9643 x fee - 1.05 (Stripe's 2.9% + 0.5% + AED 1, x1.05
--                    VAT, absorbed: _shared/reveal_fee.ts);
--   targets        = reveals a month = gap / net per reveal / revenue months (customers from 1 Jan 2027); requests =
--                    reveals / reveal rate; open trades = requests / (requests per verified supplier x the opening
--                    threshold); verified suppliers = open trades x threshold; invitations = verified still needed /
--                    invite-to-verified conversion, NEVER above the guardrail capacity (fn_invite_founder_cap x UAE
--                    working days). Each rate is MEASURED once there is enough evidence, else the stated assumption:
--                    average quotation AED 13,000 and reveal rate 15% (the 24 Sep plan's), 0.20 requests per verified
--                    supplier a month (the same plan's demand rule), 3.08% invite-to-verified (the plan's 4.1% x 75%).
--
-- == WHAT THE CEO DOES WITH IT (fn_ceo_break_even_run, duty ceo.break_even, daily) ==================================
--   every day:  the accountant's cost lines refreshed from the books, the ledger re-computed and kept per month;
--   every week: this month's target per seat written from the ledger (ceo_seat_month_target), each measured against
--               its pro-rata share of the month, and, when one is behind, a re-plan recorded (ceo_break_even_replan):
--               the gap re-spread over the months left and the lever the miss points at. It never raises a sending cap
--               or flips a switch: the invitation target is clamped to the guardrail and the shortfall becomes the lever
--               "channels beyond e-mail". The safety-side growth powers of #1903 are untouched.
--   ceo_year_plan is RE-BASED on the ledger as computed on 10 Nov 2026 (the rows below); the 24 Sep rows are kept, not
--   deleted, in ceo_year_plan_archive. The founder's year-one target contract (target_path, ledger 971) is not touched.
--
-- NOT CHANGED: any campaign switch, invite_daily_cap, the warm-up, app_secrets, pricing_config, founder-owned settings.
-- No task, objective or org_task is created: the targets are the CEO's plan rows, not confirmed work items (7 Sep rule).
-- prevented by: scripts/checks/the_ceo_plans_on_a_break_even_ledger_to_june_2027.test.mjs
-- Pending: scripts/sql/pending/the_ceo_plans_on_a_break_even_ledger_to_june_2027.txt

create table if not exists public.break_even_basis (
  id                     smallint primary key default 1 check (id = 1),
  founder_spent_aed      numeric not null check (founder_spent_aed >= 0),
  spent_as_of            date not null,
  target_date            date not null,
  customer_launch        date not null,
  licence_aed            numeric not null,
  licence_due            date not null,
  assumed_quote_aed      numeric not null check (assumed_quote_aed > 0),
  assumed_reveal_rate    numeric not null check (assumed_reveal_rate > 0 and assumed_reveal_rate <= 1),
  assumed_requests_per_supplier_month numeric not null check (assumed_requests_per_supplier_month > 0),
  assumed_invite_to_verified numeric not null check (assumed_invite_to_verified > 0 and assumed_invite_to_verified <= 1),
  usd_aed                numeric not null default 3.6725,
  reason                 text not null,
  updated_at             timestamptz not null default now()
);
alter table public.break_even_basis enable row level security;
drop policy if exists break_even_basis_service_role_only on public.break_even_basis;
create policy break_even_basis_service_role_only on public.break_even_basis as permissive for all to public using (false) with check (false);
revoke all on public.break_even_basis from anon, authenticated;
insert into public.break_even_basis (id, founder_spent_aed, spent_as_of, target_date, customer_launch, licence_aed, licence_due,
  assumed_quote_aed, assumed_reveal_rate, assumed_requests_per_supplier_month, assumed_invite_to_verified, reason)
values (1, 19000, date '2026-11-10', date '2027-06-30', date '2027-01-01', 1200, date '2027-06-24', 13000, 0.15, 0.20, 0.0308,
  'Ledger 1609 (10 Nov 2026): AED 19,000 spent, break-even by 30 Jun 2027. Rates are the 24 Sep plan''s until measured.')
on conflict (id) do nothing;

-- The accountant's cost lines: one per vendor, refreshed from the books. kind 'recurring' is carried every month;
-- 'excluded' is shown with its reason and never counted.
create table if not exists public.break_even_cost_line (
  vendor_key     text primary key,
  label          text not null,
  kind           text not null check (kind in ('recurring', 'excluded')),
  source         text not null check (source in ('expense_entries', 'expense_entries_subscription', 'statement', 'openrouter_day')),
  monthly_aed    numeric not null default 0,
  basis          text not null,
  refreshed_at   timestamptz
);
alter table public.break_even_cost_line enable row level security;
drop policy if exists break_even_cost_line_service_role_only on public.break_even_cost_line;
create policy break_even_cost_line_service_role_only on public.break_even_cost_line as permissive for all to public using (false) with check (false);
revoke all on public.break_even_cost_line from anon, authenticated;
insert into public.break_even_cost_line (vendor_key, label, kind, source, monthly_aed, basis) values
  ('anthropic', 'Anthropic (Claude subscription)', 'recurring', 'expense_entries_subscription', 775.01, 'measured: latest monthly bill'),
  ('openai', 'OpenAI (ChatGPT subscription)', 'recurring', 'expense_entries_subscription', 799.00, 'measured: latest monthly subscription bill'),
  ('supabase', 'Supabase', 'recurring', 'expense_entries', 560.42, 'measured: latest month (rising)'),
  ('vercel', 'Vercel', 'recurring', 'expense_entries', 334.79, 'measured: latest month'),
  ('godaddy', 'GoDaddy (M365 mailbox)', 'recurring', 'expense_entries', 93.80, 'measured: latest month'),
  ('resend', 'Resend', 'recurring', 'expense_entries', 73.45, 'measured: latest month'),
  ('glockapps', 'GlockApps', 'recurring', 'expense_entries', 65.50, 'measured: latest month'),
  ('twilio', 'Twilio (auto-recharge)', 'recurring', 'expense_entries', 36.76, 'measured: latest recharge'),
  ('google', 'Google Play (Dropbox)', 'recurring', 'expense_entries', 26.99, 'measured: latest month'),
  ('mashreq', 'Mashreq account fee + VAT', 'recurring', 'statement', 208.95, 'measured from the bank statement (199 + 9.95)'),
  ('openrouter', 'OpenRouter (model calls)', 'recurring', 'openrouter_day', 1297.03, 'measured: authoritative spend, last 30 days'),
  ('github', 'GitHub Actions', 'excluded', 'expense_entries', 0, 'off: ledger 1564 (Actions off, budget spent)'),
  ('ubicloud', 'Ubicloud runners', 'excluded', 'expense_entries', 0, 'off: ledger 1564'),
  ('namespace', 'Namespace runners', 'excluded', 'expense_entries', 0, 'ASSUMED off with Actions (one bill, 21 Oct; not measured)'),
  ('apify', 'Apify', 'excluded', 'expense_entries', 0, 'paused until about Feb 2027')
on conflict (vendor_key) do nothing;

-- One row per month: the ledger as the CEO last computed it in that month.
create table if not exists public.ceo_break_even_month (
  month              date primary key,
  computed_at        timestamptz not null default now(),
  cost_to_cover_aed  numeric not null,
  monthly_cost_aed   numeric not null,
  revenue_net_aed    numeric not null,
  gap_aed            numeric not null,
  months_left        numeric not null,
  revenue_months_left integer not null,
  targets            jsonb not null,
  measured           jsonb not null,
  assumptions        jsonb not null,
  verdict            text not null check (verdict in ('reachable', 'not_reachable_on_email', 'covered'))
);
alter table public.ceo_break_even_month enable row level security;
drop policy if exists ceo_break_even_month_service_role_only on public.ceo_break_even_month;
create policy ceo_break_even_month_service_role_only on public.ceo_break_even_month as permissive for all to public using (false) with check (false);
revoke all on public.ceo_break_even_month from anon, authenticated;

create table if not exists public.ceo_seat_month_target (
  month       date not null,
  seat        text not null references public.org_role(role_id),
  metric      text not null,
  target      numeric not null,
  measured    numeric,
  status      text not null default 'set' check (status in ('set', 'on_track', 'behind', 'met')),
  basis       text not null,
  checked_at  timestamptz,
  primary key (month, seat, metric)
);
alter table public.ceo_seat_month_target enable row level security;
drop policy if exists ceo_seat_month_target_service_role_only on public.ceo_seat_month_target;
create policy ceo_seat_month_target_service_role_only on public.ceo_seat_month_target as permissive for all to public using (false) with check (false);
revoke all on public.ceo_seat_month_target from anon, authenticated;

create table if not exists public.ceo_break_even_replan (
  id          bigint generated always as identity primary key,
  replanned_at timestamptz not null default now(),
  month       date not null,
  behind      jsonb not null,
  lever       text not null,
  before      jsonb not null,
  after       jsonb not null
);
alter table public.ceo_break_even_replan enable row level security;
drop policy if exists ceo_break_even_replan_service_role_only on public.ceo_break_even_replan;
create policy ceo_break_even_replan_service_role_only on public.ceo_break_even_replan as permissive for all to public using (false) with check (false);
revoke all on public.ceo_break_even_replan from anon, authenticated;

-- The 24 Sep plan, kept (ledger 1609 replaces it as the operating plan; nothing the founder set is deleted).
create table if not exists public.ceo_year_plan_archive (like public.ceo_year_plan including defaults);
alter table public.ceo_year_plan_archive add column if not exists archived_at timestamptz not null default now();
alter table public.ceo_year_plan_archive add column if not exists archived_reason text;
alter table public.ceo_year_plan_archive enable row level security;
drop policy if exists ceo_year_plan_archive_service_role_only on public.ceo_year_plan_archive;
create policy ceo_year_plan_archive_service_role_only on public.ceo_year_plan_archive as permissive for all to public using (false) with check (false);
revoke all on public.ceo_year_plan_archive from anon, authenticated;

-- THE BOOKS INTO THE COST LINES: the latest month each recurring vendor billed (subscription rows only where the vendor also
-- bills usage), OpenRouter from its authoritative day meter. A line with no bill in 75 days keeps its last figure and says so.
create or replace function public.fn_break_even_cost_refresh()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare b public.break_even_basis; v_n int := 0;
begin
  select * into b from public.break_even_basis where id = 1;
  with e as (
    select case when lower(x.vendor) like 'vercel%' then 'vercel' when lower(x.vendor) like 'github%' then 'github' else lower(btrim(x.vendor)) end v,
           x.category, x.charged_on, case when x.currency = 'USD' then x.amount * b.usd_aed else x.amount end aed
      from public.expense_entries x where x.charged_on > current_date - 75 and coalesce(x.category, '') <> 'licence'),
  bill as (
    select l.vendor_key, sum(e.aed) aed, max(e.charged_on) last
      from public.break_even_cost_line l join e on e.v = l.vendor_key
       and (l.source = 'expense_entries' or (l.source = 'expense_entries_subscription' and e.category = 'Subscription'))
       and date_trunc('month', e.charged_on) = (select date_trunc('month', max(e2.charged_on)) from e e2 where e2.v = l.vendor_key
                                                 and (l.source = 'expense_entries' or e2.category = 'Subscription'))
     where l.kind = 'recurring' group by l.vendor_key)
  update public.break_even_cost_line l set monthly_aed = round(bill.aed, 2), refreshed_at = now(),
         basis = 'measured: the ' || to_char(bill.last, 'Mon YYYY') || ' bill'
    from bill where bill.vendor_key = l.vendor_key;
  get diagnostics v_n = row_count;
  update public.break_even_cost_line set refreshed_at = now(),
         monthly_aed = coalesce((select round(sum(d.authoritative_usd) * b.usd_aed * 30.4375 / 30, 2) from public.openrouter_day d where d.day > current_date - 30), monthly_aed),
         basis = 'measured: authoritative spend, last 30 days'
   where vendor_key = 'openrouter';
  return jsonb_build_object('refreshed', v_n + 1, 'monthly_aed', (select sum(monthly_aed) from public.break_even_cost_line where kind = 'recurring'));
end $fn$;
revoke execute on function public.fn_break_even_cost_refresh() from public, anon, authenticated;
grant execute on function public.fn_break_even_cost_refresh() to service_role;

-- UAE working days (Monday to Friday) from p_from to p_to inclusive, and the invitations the guardrail allows on them.
create or replace function public.fn_break_even_invite_capacity(p_from date, p_to date)
returns integer language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce(sum(public.fn_invite_founder_cap(d::date)), 0)::int
    from generate_series(p_from, p_to, interval '1 day') d where extract(isodow from d) between 1 and 5
$fn$;
revoke execute on function public.fn_break_even_invite_capacity(date, date) from public, anon, authenticated;
grant execute on function public.fn_break_even_invite_capacity(date, date) to service_role;

-- THE LEDGER. Pure arithmetic over measured rows and the stated assumptions; kept on ceo_break_even_month for the month.
create or replace function public.fn_break_even_ledger(p_at timestamptz default now())
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare b public.break_even_basis; v_day date := (p_at at time zone 'Asia/Dubai')::date; v_month date := date_trunc('month', (p_at at time zone 'Asia/Dubai'))::date;
  v_monthly numeric; v_months numeric; v_cost numeric; v_rev numeric; v_gap numeric; v_q numeric; v_net numeric; v_rr numeric;
  v_req_n int; v_rev_n int; v_rev_months int; v_reveals_pm int; v_requests_pm int; v_open_at int; v_trades int; v_verified_need int;
  v_verified_now int; v_conv numeric; v_inv_need int; v_cap int; v_invited int; v_registered int; v_targets jsonb; v_measured jsonb; v_assume jsonb; v_verdict text;
begin
  select * into b from public.break_even_basis where id = 1;
  select coalesce(sum(monthly_aed), 0) into v_monthly from public.break_even_cost_line where kind = 'recurring';
  v_months := greatest(0, round((b.target_date - greatest(v_day, b.spent_as_of))::numeric / 30.4375, 2));
  v_cost := b.founder_spent_aed + v_monthly * v_months + case when v_day <= b.licence_due then b.licence_aed else 0 end;
  -- real paid reveals only: a ZZ DEMO customer is never revenue
  select coalesce(sum(0.9643 * t.reveal_fee - 1.05), 0), count(*) into v_rev, v_rev_n
    from public.transactions t join public.customers c on c.id = t.customer_id
   where t.fee_status = 'paid' and not coalesce(c.is_demo, false) and coalesce(t.refund_status, '') not in ('refunded', 'approved');
  v_gap := greatest(0, v_cost - v_rev);
  -- the measured rates, once there is enough of each to be a rate
  select count(*) into v_req_n from public.inquiries i where not public.fn_inquiry_is_demo(i.id) and i.parent_inquiry_id is null;
  v_rr := case when v_req_n >= 20 then greatest(v_rev_n::numeric / v_req_n, 0.01) else b.assumed_reveal_rate end;
  v_q := coalesce((select avg(t.quote_amount) from public.transactions t join public.customers c on c.id = t.customer_id
                    where t.fee_status = 'paid' and not coalesce(c.is_demo, false) having count(*) >= 10), b.assumed_quote_aed);
  v_net := 0.9643 * 0.03 * v_q - 1.05;
  v_rev_months := greatest(1, (extract(year from age(b.target_date + 1, greatest(v_month, b.customer_launch))) * 12
                               + extract(month from age(b.target_date + 1, greatest(v_month, b.customer_launch))))::int);
  v_reveals_pm := ceil(v_gap / v_net / v_rev_months);
  v_requests_pm := ceil(v_reveals_pm / v_rr);
  v_open_at := coalesce((select open_at_suppliers from public.trade_opening_rule where id = 1), 10);
  v_trades := ceil(v_requests_pm / (b.assumed_requests_per_supplier_month * v_open_at));
  v_verified_need := v_trades * v_open_at;
  select count(*) filter (where invite_status is not null), count(*) filter (where approval_status = 'approved')
    into v_invited, v_registered from public.leads where not coalesce(is_demo, false);
  v_verified_now := v_registered;
  v_conv := case when v_registered >= 5 then v_registered::numeric / greatest(v_invited, 1) else b.assumed_invite_to_verified end;
  v_inv_need := ceil(greatest(0, v_verified_need - v_verified_now) / v_conv);
  v_cap := public.fn_break_even_invite_capacity(v_day, b.target_date);
  v_verdict := case when v_gap = 0 then 'covered' when v_inv_need > v_cap then 'not_reachable_on_email' else 'reachable' end;
  v_targets := jsonb_build_object('reveals_per_month', v_reveals_pm, 'requests_per_month', v_requests_pm, 'open_trades', v_trades,
    'verified_suppliers_per_open_trade', v_open_at, 'verified_suppliers', v_verified_need,
    'invitations_needed', v_inv_need, 'invitations_capacity_to_target_date', v_cap, 'invitations_target', least(v_inv_need, v_cap),
    'invitations_this_month', least(ceil(v_inv_need::numeric / greatest(1, (extract(year from age(b.target_date + 1, v_month)) * 12 + extract(month from age(b.target_date + 1, v_month)))::int)),
                                    public.fn_break_even_invite_capacity(greatest(v_month, b.spent_as_of), (v_month + interval '1 month - 1 day')::date)));
  v_measured := jsonb_build_object('monthly_cost_aed', round(v_monthly, 2), 'paid_reveals', v_rev_n, 'requests', v_req_n,
    'leads_invited', v_invited, 'suppliers_verified', v_verified_now,
    'trades_open', (select count(*) from public.trade_customer_opening where is_open),
    'cost_lines', (select jsonb_object_agg(vendor_key, jsonb_build_object('aed', monthly_aed, 'kind', kind, 'basis', basis)) from public.break_even_cost_line));
  v_assume := jsonb_build_object('quote_aed', round(v_q, 2), 'quote_measured', v_q <> b.assumed_quote_aed, 'net_per_reveal_aed', round(v_net, 2),
    'reveal_rate', v_rr, 'reveal_rate_measured', v_req_n >= 20, 'requests_per_supplier_month', b.assumed_requests_per_supplier_month,
    'invite_to_verified', round(v_conv, 4), 'invite_to_verified_measured', v_registered >= 5, 'founder_spent_aed', b.founder_spent_aed,
    'licence', jsonb_build_object('aed', b.licence_aed, 'due', b.licence_due, 'price_assumed_unchanged', true));
  insert into public.ceo_break_even_month as m (month, computed_at, cost_to_cover_aed, monthly_cost_aed, revenue_net_aed, gap_aed, months_left, revenue_months_left, targets, measured, assumptions, verdict)
  values (v_month, now(), round(v_cost, 2), round(v_monthly, 2), round(v_rev, 2), round(v_gap, 2), v_months, v_rev_months, v_targets, v_measured, v_assume, v_verdict)
  on conflict (month) do update set computed_at = now(), cost_to_cover_aed = excluded.cost_to_cover_aed, monthly_cost_aed = excluded.monthly_cost_aed,
    revenue_net_aed = excluded.revenue_net_aed, gap_aed = excluded.gap_aed, months_left = excluded.months_left,
    revenue_months_left = excluded.revenue_months_left, targets = excluded.targets, measured = excluded.measured,
    assumptions = excluded.assumptions, verdict = excluded.verdict;
  return jsonb_build_object('month', v_month, 'cost_to_cover_aed', round(v_cost, 2), 'monthly_cost_aed', round(v_monthly, 2), 'revenue_net_aed', round(v_rev, 2),
    'gap_aed', round(v_gap, 2), 'months_left', v_months, 'revenue_months_left', v_rev_months, 'verdict', v_verdict,
    'targets', v_targets, 'measured', v_measured - 'cost_lines', 'assumptions', v_assume);
end $fn$;
revoke execute on function public.fn_break_even_ledger(timestamptz) from public, anon, authenticated;
grant execute on function public.fn_break_even_ledger(timestamptz) to service_role;

-- THE CEO'S RUN. Daily: books -> ledger. Weekly (no check in the last 6 days): the month's target per seat, measured
-- pro rata, and a re-plan recorded when one is behind. Inside every hard limit: it writes plan rows only.
create or replace function public.fn_ceo_break_even_run(p_at timestamptz default now())
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_month date := date_trunc('month', (p_at at time zone 'Asia/Dubai'))::date; v_end date; l jsonb; v_frac numeric; v_behind jsonb;
  v_prev jsonb; v_lever text; v_weekly boolean; v_launch date; v_n int;
begin
  perform public.fn_break_even_cost_refresh();
  v_prev := (select to_jsonb(m) - 'computed_at' from public.ceo_break_even_month m where m.month = v_month);
  l := public.fn_break_even_ledger(p_at);
  v_weekly := not exists (select 1 from public.ceo_seat_month_target t where t.month = v_month and t.checked_at > p_at - interval '6 days');
  if not v_weekly then return jsonb_build_object('ledger', l, 'weekly', false); end if;
  v_end := (v_month + interval '1 month')::date;
  v_launch := (select customer_launch from public.break_even_basis where id = 1);
  v_frac := least(1, greatest(0.05, extract(epoch from (p_at - (v_month::timestamp at time zone 'Asia/Dubai'))) / extract(epoch from ((v_end::timestamp - v_month::timestamp)))));

  -- the month's orders, from the ledger (customer-side targets start at the launch month)
  insert into public.ceo_seat_month_target as t (month, seat, metric, target, basis) values
    (v_month, 'sales_engineer', 'suppliers_verified', greatest(0, (l#>>'{targets,verified_suppliers}')::int - (l#>>'{measured,suppliers_verified}')::int), 'break-even ledger: verified suppliers still needed'),
    (v_month, 'sales_engineer', 'invitations_sent', (l#>>'{targets,invitations_this_month}')::int, 'break-even ledger, clamped to the warm-up guardrail (fn_invite_founder_cap)'),
    (v_month, 'ceo', 'trades_open', (l#>>'{targets,open_trades}')::int, 'break-even ledger: trades open to customers (ledger 1614)'),
    (v_month, 'ceo', 'reveals', case when v_month >= v_launch then (l#>>'{targets,reveals_per_month}')::int else 0 end, 'break-even ledger: paid reveals a month from the launch'),
    (v_month, 'marketing', 'customer_requests', case when v_month >= v_launch then (l#>>'{targets,requests_per_month}')::int else 0 end, 'break-even ledger: customer requests a month from the launch')
  on conflict (month, seat, metric) do update set target = excluded.target, basis = excluded.basis;

  -- measured this month, real rows only
  update public.ceo_seat_month_target t set checked_at = p_at, measured = x.v   -- the run's own clock, so a replayed day reads as that day
    from (values
      ('sales_engineer', 'suppliers_verified', (select count(*) from public.leads where not coalesce(is_demo, false) and approval_status = 'approved' and approved_at >= v_month and approved_at < v_end)),
      ('sales_engineer', 'invitations_sent', (select count(*) from public.notifications n where n.type = 'supplier_invite' and n.status = 'sent' and n.sent_at >= v_month and n.sent_at < v_end and not public.fn_is_demo_email(n.to_email))),
      ('ceo', 'trades_open', (select count(*) from public.trade_customer_opening where is_open)),
      ('ceo', 'reveals', (select count(*) from public.transactions tx join public.customers c on c.id = tx.customer_id where tx.fee_status = 'paid' and not coalesce(c.is_demo, false) and tx.revealed_at >= v_month and tx.revealed_at < v_end)),
      ('marketing', 'customer_requests', (select count(*) from public.inquiries i where i.parent_inquiry_id is null and i.created_at >= v_month and i.created_at < v_end and not public.fn_inquiry_is_demo(i.id)))
    ) as x(seat, metric, v)
   where t.month = v_month and t.seat = x.seat and t.metric = x.metric;
  update public.ceo_seat_month_target set status = case when measured >= target then 'met' when measured >= target * v_frac then 'on_track' else 'behind' end
   where month = v_month;

  select coalesce(jsonb_agg(jsonb_build_object('seat', seat, 'metric', metric, 'target', target, 'measured', measured)), '[]'::jsonb), count(*)
    into v_behind, v_n from public.ceo_seat_month_target where month = v_month and status = 'behind';
  if v_n > 0 then
    -- THE LEVER THE MISS POINTS AT, decided in code. E-mail is the only working channel and the guardrail is its ceiling:
    -- when the invitations needed exceed what the warm-up allows, more e-mail is not the answer.
    v_lever := case
      when (l#>>'{targets,invitations_needed}')::int > (l#>>'{targets,invitations_capacity_to_target_date}')::int
        then 'channels beyond e-mail: the invitations needed exceed the warm-up guardrail, so supplier referral, WhatsApp opt-ins in live conversations and the founder''s network carry the gap (no cap is raised)'
      when exists (select 1 from public.ceo_seat_month_target where month = v_month and status = 'behind' and metric = 'invitations_sent')
        then 'send what the guardrail already allows: the invitations are behind a cap the warm-up permits (the CEO growth powers decide any change, clamped)'
      when exists (select 1 from public.ceo_seat_month_target where month = v_month and status = 'behind' and metric = 'suppliers_verified')
        then 'conversion: chase every started registration and every reply to submission'
      else 'demand in the open trades: requests and reveals' end;
    insert into public.ceo_break_even_replan (month, behind, lever, before, after)
    values (v_month, v_behind, v_lever, coalesce(v_prev, '{}'::jsonb), l);
  end if;
  return jsonb_build_object('ledger', l, 'weekly', true, 'behind', v_behind, 'lever', v_lever);
end $fn$;
revoke execute on function public.fn_ceo_break_even_run(timestamptz) from public, anon, authenticated;
grant execute on function public.fn_ceo_break_even_run(timestamptz) to service_role;
create or replace function public.fn_ceo_break_even_run_now()
returns jsonb language sql security definer set search_path to 'public', 'pg_temp' as $fn$ select public.fn_ceo_break_even_run(now()) $fn$;
revoke execute on function public.fn_ceo_break_even_run_now() from public, anon, authenticated;
grant execute on function public.fn_ceo_break_even_run_now() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('ceo.break_even', 'ceo', interval '1 day', 'fn_ceo_break_even_run_now',
   'Every day, the break-even ledger to 30 Jun 2027 from the accountant''s books (cost to cover, revenue, gap, months left, targets); every week, the month''s target per seat measured and a re-plan with its lever when one is behind. Never raises a cap or a switch.',
   'scripts/sql/the_ceo_plans_on_a_break_even_ledger_to_june_2027.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

-- THE YEAR PLAN, RE-BASED. The 24 Sep rows are archived once; the operating plan is the ledger as computed on 10 Nov 2026:
-- AED 4,271.70 a month (2,974.67 recurring + 1,297.03 OpenRouter), 7.62 months, cost to cover 52,750.35, revenue 0;
-- net per reveal at AED 13,000 = 375.03, so 141 reveals over January-June = 24 a month, 160 requests at 15%, 80 trades
-- open at 10 suppliers and 0.20 requests per supplier = 800 verified by January. July-September carry June's rate.
-- Columns: month, verified, verified_added, requests, quotes (1.8 a request, the plan's ratio), reveals, fee_aed
-- (AED 390 a reveal at Q 13,000), fee_cum_aed, business_accounts, cost_ceiling_aed (the measured monthly cost; June adds
-- the licence).
insert into public.ceo_year_plan_archive
select y.*, now(), 'ledger 1609: replaced as the CEO''s operating plan by the break-even ledger (the_ceo_plans_on_a_break_even_ledger_to_june_2027.sql)'
  from public.ceo_year_plan y
 where not exists (select 1 from public.ceo_year_plan_archive a where a.month = y.month);
update public.ceo_year_plan y set verified = p.verified, verified_added = p.verified_added, requests = p.requests, quotes = p.quotes,
       reveals = p.reveals, fee_aed = p.fee, fee_cum_aed = p.cum, business_accounts = p.accounts, cost_ceiling_aed = p.cost,
       basis = 'break-even ledger 10 Nov 2026 (ledger 1609): AED 19,000 spent + measured running cost to 30 Jun 2027; see public.ceo_break_even_month'
  from (values
    ('2026-10-01', 0, 0, 0, 0, 0, 0, 0, 0, 4272),
    ('2026-11-01', 400, 400, 0, 0, 0, 0, 0, 0, 4272),
    ('2026-12-01', 800, 400, 0, 0, 0, 0, 0, 0, 4272),
    ('2027-01-01', 800, 0, 160, 288, 24, 9360, 9360, 0, 4272),
    ('2027-02-01', 800, 0, 160, 288, 24, 9360, 18720, 0, 4272),
    ('2027-03-01', 800, 0, 160, 288, 24, 9360, 28080, 0, 4272),
    ('2027-04-01', 800, 0, 160, 288, 24, 9360, 37440, 0, 4272),
    ('2027-05-01', 800, 0, 160, 288, 24, 9360, 46800, 0, 4272),
    ('2027-06-01', 800, 0, 160, 288, 24, 9360, 56160, 0, 5472),
    ('2027-07-01', 800, 0, 160, 288, 24, 9360, 65520, 0, 4272),
    ('2027-08-01', 800, 0, 160, 288, 24, 9360, 74880, 0, 4272),
    ('2027-09-01', 800, 0, 160, 288, 24, 9360, 84240, 0, 4272)
  ) as p(m, verified, verified_added, requests, quotes, reveals, fee, cum, accounts, cost)
 where y.month = p.m::date;
