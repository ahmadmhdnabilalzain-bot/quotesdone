-- THE SALES ENGINEER REVIEWS THE WEEK, OWNS LICENCE VALIDITY AND THE REVEAL LADDER, AND KEEPS ENTERPRISE ACCOUNTS.
-- Seat: sales_engineer. 24 Sep 2026, founder_instruction 983 (every gap in the seat audit fixed) against the approved
-- job description, section 2. Builds on every_seat_duty_has_an_owner_a_clock_and_a_check.sql (#901) and
-- the_it_engineer_watches_licences_and_every_seats_knowledge.sql (#903).
--
-- Closes these seat-audit gaps (GAPS.md, "Sales engineer"):
--   4. WRONG-OWNED  resilience_step 'ladder' (reveal chase day 3, CEO final call day 5) was registered to the accountant.
--                   The seat map gives reveals to the sales engineer. The refund execution inside the ladder is still
--                   the accountant's own routine (fn_refund_ladder_sweep calls it); only the step's owner moves.
--   5. WRONG-OWNED  the licence-expiry duty sat on it_engineer. The 9 Sep ruling makes a verification record sales
--                   work. Released as #938's sales_engineer.licence_expiry_watch (no second duty here). The original plan delegated to the existing,
--                   already-tested body (fn_it_engineer_licence_expiry_watch) rather than copying it: one body, and
--                   the IT engineer still sees a finding if an expired supplier stays matchable.
--   6. PARTIAL      no weekly quality review. Added: fn_sales_engineer_weekly_quality_review, a weekly seat_duty.
--                   Deterministic counts (held quotes, hold reasons, match rate, requests with no exact match, time
--                   to fix a hold); every request with no exact match and the week itself go into seat_case_memory
--                   through fn_case_remember, which is how the learning loop recalls them by meaning (instr 887).
--   3. MISSING      enterprise accounts. Added: enterprise_account + enterprise_account_member, a consolidated
--                   report across every member's requests, and a weekly pipeline duty that refreshes each account's
--                   totals and flags an account whose plan has not been reviewed in 90 days. Empty until January
--                   2027; the pipe is built now.
-- No LLM and no word matching here: this is routine work (memory routine-work-is-code-not-llm).

-- ── 4. the ladder belongs to the sales engineer ──────────────────────────────────────────────────────────
update public.resilience_step set owner_seat = 'sales_engineer' where step = 'ladder';

-- ── 5. document validity belongs to the sales engineer ───────────────────────────────────────────────────
-- Released 24 Sep 2026: #938 (each_seat_owns_the_duty_the_founder_gave_it_and_it_measures.sql) already moved this duty to
-- sales_engineer.licence_expiry_watch (fn_sales_engineer_licence_expiry_watch). A second duty here would run the same
-- sweep twice a day, so this file only makes sure the IT row stays gone.
delete from public.seat_duty where duty = 'it_engineer.licence_expiry_watch';

-- ── 6. the weekly quality review ─────────────────────────────────────────────────────────────────────────
-- p_include_demo: false in production so ZZ DEMO traffic never distorts the week; the probe passes true.
create or replace function public.fn_sales_engineer_weekly_quality_review(p_include_demo boolean default false)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_from timestamptz := now() - interval '7 days';
  v_week text := to_char(now() at time zone 'Asia/Dubai', 'IYYY-"W"IW');
  v_inq int; v_matched int; v_held int; v_fixed int; v_fix_hours numeric; v_reasons jsonb; v_nomatch jsonb;
  v_rate numeric; v_top text; r record;
begin
  -- requests of the week (an inquiry older than a day has had its chance to be matched)
  with w as (
    select i.id, i.category, i.summary_masked from public.inquiries i
      left join public.customers c on c.id = i.customer_id
     where i.created_at >= v_from and i.created_at < now() - interval '1 day'
       and (p_include_demo or not coalesce(c.is_demo, false)))
  select count(*), count(*) filter (where exists (select 1 from public.inquiry_matches m where m.inquiry_id = w.id)),
         coalesce(jsonb_agg(jsonb_build_object('inquiry_id', w.id, 'trade', w.category, 'summary', w.summary_masked))
                  filter (where not exists (select 1 from public.inquiry_matches m where m.inquiry_id = w.id)), '[]')
    into v_inq, v_matched, v_nomatch from w;

  -- holds opened this week, and how fast the week's decided holds were fixed
  with h as (
    select sh.* from public.quote_spec_hold sh
      left join public.inquiries i on i.id = sh.inquiry_id left join public.customers c on c.id = i.customer_id
     where sh.opened_at >= v_from and (p_include_demo or not coalesce(c.is_demo, false)))
  select count(*), count(*) filter (where decided_at is not null),
         round(avg(extract(epoch from decided_at - opened_at) / 3600) filter (where decided_at is not null), 1)
    into v_held, v_fixed, v_fix_hours from h;

  select coalesce(jsonb_object_agg(reason, n order by n desc), '{}') into v_reasons from (
    select coalesce(e->>'attr', e #>> '{}') reason, count(*) n
      from public.quote_spec_hold sh
      left join public.inquiries i on i.id = sh.inquiry_id left join public.customers c on c.id = i.customer_id
      cross join lateral jsonb_array_elements(case when jsonb_typeof(sh.missing) = 'array' then sh.missing else '[]' end) e
     where sh.opened_at >= v_from and (p_include_demo or not coalesce(c.is_demo, false))
     group by 1) x;

  v_rate := case when v_inq > 0 then round(100.0 * v_matched / v_inq, 1) end;
  select key into v_top from jsonb_each(v_reasons) order by value::int desc limit 1;

  -- the learning loop: every request with no exact match is a case the seat recalls next time it sees one like it
  for r in select * from jsonb_to_recordset(v_nomatch) as x(inquiry_id uuid, trade text, summary text) loop
    perform public.fn_case_remember('sales_engineer', 'no_exact_match', 'inquiries.no_exact_match', r.inquiry_id::text,
      r.trade, coalesce(r.summary, 'request in ' || coalesce(r.trade, 'an unknown trade') || ' with no exact supplier match'),
      'no supplier confirmed this exact work; recruit for it', null, null, false, '{}', null,
      'Trade ' || coalesce(r.trade, 'unknown') || ' had a request no supplier could quote exactly: recruit for it before the next one.');
  end loop;

  -- the week itself
  perform public.fn_case_remember('sales_engineer', 'weekly_quality_review', 'sales_engineer.weekly_quality_review', v_week,
    null, format('Week %s: %s requests, %s matched (%s%%), %s quotes held, %s fixed (avg %s h), %s with no exact match.',
                 v_week, v_inq, v_matched, coalesce(v_rate::text, 'n/a'), v_held, v_fixed, coalesce(v_fix_hours::text, 'n/a'),
                 jsonb_array_length(v_nomatch)),
    null, null, null, true, '{}', null,
    case when v_top is not null then 'Most frequent reason a quote was held this week: ' || v_top
         || '. Ask for it in the supplier''s first review message.' end);

  return jsonb_build_object('week', v_week, 'requests', v_inq, 'matched', v_matched, 'match_rate_pct', v_rate,
    'held', v_held, 'held_fixed', v_fixed, 'avg_hours_to_fix', v_fix_hours, 'hold_reasons', v_reasons,
    'no_exact_match', jsonb_array_length(v_nomatch));
end $fn$;
revoke execute on function public.fn_sales_engineer_weekly_quality_review(boolean) from public, anon, authenticated;
grant execute on function public.fn_sales_engineer_weekly_quality_review(boolean) to service_role;

-- ── 3. enterprise accounts ───────────────────────────────────────────────────────────────────────────────
create table if not exists public.enterprise_account (
  id bigint generated always as identity primary key,
  name text not null,
  owner_seat text not null default 'sales_engineer' references public.org_agents(agent_key),
  plan text,                               -- the account plan, written by the sales engineer
  plan_reviewed_at timestamptz,
  totals jsonb not null default '{}',      -- consolidated report, refreshed weekly
  totals_at timestamptz,
  created_at timestamptz not null default now()
);
create table if not exists public.enterprise_account_member (
  account_id bigint not null references public.enterprise_account(id) on delete cascade,
  customer_id uuid not null references public.customers(id) on delete cascade,
  role text not null default 'buyer' check (role in ('admin', 'buyer', 'viewer')),
  added_at timestamptz not null default now(),
  primary key (account_id, customer_id),
  unique (customer_id)                     -- a customer belongs to one enterprise account
);
alter table public.enterprise_account enable row level security;
alter table public.enterprise_account_member enable row level security;
drop policy if exists enterprise_account_service_role_only on public.enterprise_account;
create policy enterprise_account_service_role_only on public.enterprise_account as permissive for all to public using (false) with check (false);
drop policy if exists enterprise_account_member_service_role_only on public.enterprise_account_member;
create policy enterprise_account_member_service_role_only on public.enterprise_account_member as permissive for all to public using (false) with check (false);
revoke all on public.enterprise_account, public.enterprise_account_member from anon, authenticated;

-- the consolidated report: one account, every member's requests, quotes and reveals
create or replace function public.fn_enterprise_account_report(p_account_id bigint)
returns jsonb
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select jsonb_build_object(
    'account_id', p_account_id,
    'members', (select count(*) from public.enterprise_account_member where account_id = p_account_id),
    'requests', count(distinct i.id),
    'requests_90d', count(distinct i.id) filter (where i.created_at >= now() - interval '90 days'),
    'quotes', count(distinct q.id),
    'revealed', count(distinct i.id) filter (where i.hired_supplier_id is not null or i.status = 'revealed'),
    'quoted_value_aed', coalesce(sum(q.customer_price), 0))
  from public.enterprise_account_member m
  join public.inquiries i on i.customer_id = m.customer_id
  left join public.quotes q on q.inquiry_id = i.id
  where m.account_id = p_account_id
$fn$;
revoke execute on function public.fn_enterprise_account_report(bigint) from public, anon, authenticated;
grant execute on function public.fn_enterprise_account_report(bigint) to service_role;

create or replace function public.fn_sales_engineer_enterprise_pipeline()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_n int := 0; v_stale jsonb;
begin
  update public.enterprise_account a set totals = public.fn_enterprise_account_report(a.id), totals_at = now();
  get diagnostics v_n = row_count;
  select coalesce(jsonb_agg(jsonb_build_object('account_id', id, 'name', name) order by id), '[]') into v_stale
    from public.enterprise_account
   where plan is null or plan_reviewed_at is null or plan_reviewed_at < now() - interval '90 days';
  return jsonb_build_object('accounts', v_n, 'plan_due', v_stale);
end $fn$;
revoke execute on function public.fn_sales_engineer_enterprise_pipeline() from public, anon, authenticated;
grant execute on function public.fn_sales_engineer_enterprise_pipeline() to service_role;

-- ── the clocks ───────────────────────────────────────────────────────────────────────────────────────────
insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('sales_engineer.weekly_quality_review', 'sales_engineer', interval '7 days', 'fn_sales_engineer_weekly_quality_review',
   'Quotes held and why, match rate, requests with no exact match and time to fix a hold; each lesson into seat_case_memory.',
   'scripts/sql/the_sales_engineer_reviews_the_week_owns_licences_the_ladder_and_enterprise_accounts.sql'),
  ('sales_engineer.enterprise_pipeline', 'sales_engineer', interval '7 days', 'fn_sales_engineer_enterprise_pipeline',
   'Consolidated totals for every enterprise account; an account whose plan is missing or older than 90 days is listed.',
   'scripts/sql/the_sales_engineer_reviews_the_week_owns_licences_the_ladder_and_enterprise_accounts.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;
