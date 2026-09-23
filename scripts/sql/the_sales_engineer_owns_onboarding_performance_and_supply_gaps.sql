-- THE SALES ENGINEER OWNS A SUPPLIER FROM INVITATION TO FIRST QUOTE, SCORES HOW HE PERFORMS, AND NAMES WHERE SUPPLY IS SHORT.
-- Seat: sales_engineer. 23 Sep 2026, founder_instruction 898 (no new agents) and the seat-duties plan (886-898):
-- "SUPPLIER ONBOARDING OWNER (invite → mandatory six → first quote); SUPPLIER PERFORMANCE SCORE feeding matching;
-- SUPPLY-GAP RECRUITMENT per trade/emirate (hands targeting to marketing)".
-- Needs every_seat_duty_has_an_owner_a_clock_and_a_check.sql (public.seat_duty, fn_seat_duty_reason,
-- fn_seat_duty_cross_review). Marketing's half (the funnel that recruits into these gaps, and reputation) is
-- marketing_recruits_where_supply_is_short_and_keeps_the_companys_reputation.sql.
--
-- WHAT WAS MEASURED (production, 23 Sep 2026)
--   * Onboarding: invitation (enqueue_supplier_invites), the day-2/day-6 registration reminders and the 14-day
--     registration window (fn_sales_engineer_supplier_documents_tick) all exist. Nothing follows an APPROVED supplier
--     to his first quote: 2 approved, 171 invited, and no record anywhere of which stage each supplier is at.
--   * Performance: fn_supplier_score_refresh computes reliability / quality per supplier (supplier_score, 20,465 rows)
--     and HAS NO CALLER; fn_match_capability ranks on supplier_perf (a view: quote_rate, perf_score) and never reads
--     supplier_score. So the score existed and did not feed matching.
--   * Supply: fn_supplier_invite_candidates ranks never-invited leads by under-activated catalogue domain. Nothing
--     measures supply against DEMAND per trade and emirate, and nothing tells marketing where to recruit.
--
-- WHAT THIS ADDS — three duties (owner sales_engineer, a clock each, checked by
-- scripts/checks/sales_engineer_and_marketing_duties_act.test.mjs and fn_seat_duty_health):
--   sales_engineer.supplier_onboarding (1 day): every invited or registered supplier's stage — invited, clicked,
--     registering, action_required, approved, matched, quoting — in public.supplier_onboarding. The stages before
--     approval already have their reminders and are only recorded. An approved supplier matched to open requests who
--     has not quoted 3 days after his first match is told, through customer_support, how many requests wait for him —
--     at most twice, a week apart. Deterministic: dates and counts.
--   sales_engineer.supplier_performance (1 day): runs fn_supplier_score_refresh, then writes one 0..1 score per
--     supplier (public.supplier_performance) from what the platform MEASURED — reliability, the customers' rating,
--     the dispute rate — weighted over the parts that exist; NULL when nothing was measured (unmeasured is not bad).
--     fn_match_capability's track-record term now reads it first.
--   sales_engineer.supply_gap (1 day): per active trade (UAE-wide) and per trade × emirate with demand in 90 days,
--     matchable suppliers against pricing_config.category_open_min_suppliers, the requests short of quotes, and the
--     lead pool (public.supply_gap). A customer already waiting (a short request or demand) is recruited for AT ONCE
--     by rule. A gap nobody is waiting on is a judgement — recruit now or defer — REASONED by the sales engineer (at
--     most ten a day, stakes high); a recruit decision is a seat-to-seat handoff to marketing and opens a
--     cross-family review. A gap that reached the minimum closes.
--
-- WHAT THIS DOES NOT DO: no invitation is sent from here (the invitation machine keeps its gates, the founder's go
-- and its daily cap); recruitment targets only change WHICH eligible leads it invites first. Nothing is matched by a
-- word: trades are taxonomy codes compared for equality, emirates are the seven names.

-- ── 1. onboarding: every supplier's stage, and the nudge from approval to the first quote ─────────────────────
create table if not exists public.supplier_onboarding (
  lead_id         bigint primary key references public.leads (id) on delete cascade,
  stage           text not null check (stage in ('invited', 'clicked', 'registering', 'action_required', 'approved', 'matched', 'quoting', 'closed')),
  stage_since     timestamptz not null default now(),
  first_match_at  timestamptz,
  first_quote_at  timestamptz,
  open_matches    integer not null default 0,
  nudges          integer not null default 0,
  last_nudge_at   timestamptz,
  updated_at      timestamptz not null default now()
);
alter table public.supplier_onboarding enable row level security;
drop policy if exists supplier_onboarding_service_role_only on public.supplier_onboarding;
create policy supplier_onboarding_service_role_only on public.supplier_onboarding as permissive for all to public using (false) with check (false);
revoke all on public.supplier_onboarding from anon, authenticated;

create or replace function public.fn_sales_engineer_supplier_onboarding()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r record; v_nudged int := 0; v_to text; v_ar boolean; v_stages jsonb;
begin
  -- THE STAGE, from what the rows say happened (never from a status someone typed).
  with m as (
    select im.supplier_id, min(im.sent_at) as first_match_at,
           count(*) filter (where i.status not in ('revealed', 'closed', 'cancelled', 'completed', 'expired', 'lost')
                              and not exists (select 1 from public.quotes q where q.inquiry_id = im.inquiry_id and q.supplier_id = im.supplier_id)) as open_matches
      from public.inquiry_matches im join public.inquiries i on i.id = im.inquiry_id
     group by im.supplier_id
  ), q as (
    select supplier_id, min(created_at) as first_quote_at from public.quotes group by supplier_id
  ), s as (
    select l.id,
           case when coalesce(l.banned, false) or coalesce(l.permanently_closed, false) or l.approval_status = 'rejected' then 'closed'
                when q.first_quote_at is not null then 'quoting'
                when l.approval_status = 'approved' and m.first_match_at is not null then 'matched'
                when l.approval_status = 'approved' then 'approved'
                when l.approval_status = 'action_required' then 'action_required'
                when l.registration_submitted_at is not null or coalesce(l.claimed, false) then 'registering'
                when l.invite_clicked_at is not null then 'clicked'
                else 'invited' end as stage,
           m.first_match_at, q.first_quote_at, coalesce(m.open_matches, 0) as open_matches
      from public.leads l
      left join m on m.supplier_id = l.id
      left join q on q.supplier_id = l.id
     where l.invited_at is not null or coalesce(l.claimed, false) or l.approval_status is not null
  )
  insert into public.supplier_onboarding as o (lead_id, stage, first_match_at, first_quote_at, open_matches)
  select id, stage, first_match_at, first_quote_at, open_matches from s
  on conflict (lead_id) do update set
    stage_since    = case when o.stage is distinct from excluded.stage then now() else o.stage_since end,
    stage          = excluded.stage,
    first_match_at = excluded.first_match_at, first_quote_at = excluded.first_quote_at,
    open_matches   = excluded.open_matches, updated_at = now();

  -- THE NUDGE. Before approval the invitation reminders and the 14-day window already act; from approval to the
  -- first quote nothing did. Matched, requests open for him, not quoted 3 days after the first match: told, at
  -- most twice, a week apart, in his language, through customer_support.
  for r in
    select o.lead_id, o.open_matches, l.company_name, l.locale, lower(nullif(btrim(coalesce(l.claimed_by, l.email)), '')) as to_email
      from public.supplier_onboarding o join public.leads l on l.id = o.lead_id
     where o.stage = 'matched' and o.open_matches > 0 and o.first_match_at < now() - interval '3 days'
       and o.nudges < 2 and (o.last_nudge_at is null or o.last_nudge_at < now() - interval '7 days')
     order by o.first_match_at
     limit 50
  loop
    continue when r.to_email is null;
    v_ar := r.locale = 'ar';
    perform public.fn_customer_support_takes_delivery(jsonb_build_array(jsonb_build_object(
      'type', 'supplier_first_quote_nudge', 'requested_by', 'sales_engineer', 'channel', 'email',
      'to_email', r.to_email, 'to_role', 'supplier', 'lead_id', r.lead_id, 'lang', case when v_ar then 'ar' else 'en' end,
      'dedupe_key', 'first_quote_nudge:' || r.lead_id || ':' || (select nudges from public.supplier_onboarding where lead_id = r.lead_id),
      'subject', case when v_ar then 'طلبات عملاء بانتظار عروض أسعاركم في QuotesDone'
                      else 'Customer requests are waiting for your quotation' end,
      'body', case when v_ar then
          'السادة/ ' || coalesce(r.company_name, 'المورّد') || ' المحترمين،' || chr(10) || 'تحية طيبة وبعد،' || chr(10) || chr(10)
          || 'لديكم ' || r.open_matches || ' من طلبات العملاء المطابقة لتخصصكم لم تُقدَّم لها عروض أسعار حتى الآن. '
          || 'يمكنكم الاطلاع عليها وتقديم عروضكم من بوابة المورّدين: https://quotesdone.com/ar/portal' || chr(10) || chr(10)
          || 'وتفضلوا بقبول فائق الاحترام والتقدير،'
        else
          'Dear ' || coalesce(r.company_name, 'supplier') || ',' || chr(10) || chr(10)
          || r.open_matches || ' customer request(s) matched to your trade are open and have no quotation from you yet. '
          || 'You can read them and quote in your supplier portal: https://quotesdone.com/portal' || chr(10) || chr(10)
          || 'QuotesDone' end)));
    update public.supplier_onboarding set nudges = nudges + 1, last_nudge_at = now() where lead_id = r.lead_id;
    v_nudged := v_nudged + 1;
  end loop;

  select coalesce(jsonb_object_agg(stage, n), '{}'::jsonb) into v_stages
    from (select stage, count(*) n from public.supplier_onboarding group by stage) x;
  return jsonb_build_object('stages', v_stages, 'nudged', v_nudged);
end $fn$;
revoke execute on function public.fn_sales_engineer_supplier_onboarding() from public, anon, authenticated;
grant execute on function public.fn_sales_engineer_supplier_onboarding() to service_role;

-- ── 2. performance: one measured score per supplier, read by matching ─────────────────────────────────────
create table if not exists public.supplier_performance (
  lead_id      bigint primary key references public.leads (id) on delete cascade,
  score        numeric check (score is null or (score >= 0 and score <= 1)),
  components   jsonb not null default '{}'::jsonb,
  computed_at  timestamptz not null default now()
);
alter table public.supplier_performance enable row level security;
drop policy if exists supplier_performance_service_role_only on public.supplier_performance;
create policy supplier_performance_service_role_only on public.supplier_performance as permissive for all to public using (false) with check (false);
revoke all on public.supplier_performance from anon, authenticated;

create or replace function public.fn_sales_engineer_supplier_performance()
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_refreshed int; v_scored int; v_null int;
begin
  v_refreshed := public.fn_supplier_score_refresh();
  -- WEIGHTED OVER WHAT WAS MEASURED: reliability 0.5, the customers' rating 0.3, disputes 0.2 (only once a customer
  -- has reviewed him). A part that does not exist is left out of both sides of the average, never counted as zero.
  with parts as (
    select s.lead_id,
           case when s.reliability is not null then least(1, greatest(0, s.reliability / 100.0)) end as rel,
           case when s.quality_rating is not null then least(1, greatest(0, s.quality_rating / 100.0)) end as qual,
           case when coalesce(r.review_count, 0) > 0 then 1 - least(1, greatest(0, coalesce(r.dispute_rate_pct, 0) / 100.0)) end as disp
      from public.supplier_score s
      left join public.supplier_reputation r on r.supplier_id = s.lead_id
     where s.reliability is not null or s.quality_rating is not null or coalesce(r.review_count, 0) > 0
  )
  insert into public.supplier_performance as p (lead_id, score, components, computed_at)
  select lead_id,
         round((coalesce(0.5 * rel, 0) + coalesce(0.3 * qual, 0) + coalesce(0.2 * disp, 0))
               / nullif((case when rel is not null then 0.5 else 0 end) + (case when qual is not null then 0.3 else 0 end)
                        + (case when disp is not null then 0.2 else 0 end), 0), 3),
         jsonb_build_object('reliability', rel, 'rating', qual, 'disputes', disp), now()
    from parts
  on conflict (lead_id) do update set score = excluded.score, components = excluded.components, computed_at = now();
  get diagnostics v_scored = row_count;
  -- a supplier who lost every measurement is unmeasured again, not scored on stale numbers
  delete from public.supplier_performance p where p.computed_at < now() - interval '1 minute';
  get diagnostics v_null = row_count;
  return jsonb_build_object('score_rows_refreshed', v_refreshed, 'scored', v_scored, 'dropped_unmeasured', v_null);
end $fn$;
revoke execute on function public.fn_sales_engineer_supplier_performance() from public, anon, authenticated;
grant execute on function public.fn_sales_engineer_supplier_performance() to service_role;

-- ── 3. supply gaps: where a customer is (or would be) short of suppliers ──────────────────────────────────
create table if not exists public.supply_gap (
  trade          text not null,
  emirate        text not null,           -- 'UAE' for the trade country-wide, else one of the seven
  matchable      integer not null default 0,
  target         integer not null,
  demand_90d     integer not null default 0,
  short_open     integer not null default 0,
  uninvited_pool integer not null default 0,
  status         text not null default 'open' check (status in ('open', 'deciding', 'recruit', 'deferred', 'closed')),
  decided_by     text,
  decided_at     timestamptz,
  held_id        bigint,
  review         jsonb,
  measured_at    timestamptz not null default now(),
  opened_at      timestamptz not null default now(),
  closed_at      timestamptz,
  primary key (trade, emirate)
);
alter table public.supply_gap enable row level security;
drop policy if exists supply_gap_service_role_only on public.supply_gap;
create policy supply_gap_service_role_only on public.supply_gap as permissive for all to public using (false) with check (false);
revoke all on public.supply_gap from anon, authenticated;

create or replace function public.fn_sales_engineer_supply_gap(p_reason_limit integer default 10)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_target int := coalesce((select category_open_min_suppliers from public.pricing_config order by id limit 1), 10);
  g record; v_filed int := 0; v_rule int; v_closed int; v_reopened int; v_month text := to_char(now(), 'YYYY-MM');
  v_emirates text[] := array['Abu Dhabi', 'Dubai', 'Sharjah', 'Ajman', 'Umm Al Quwain', 'Ras Al Khaimah', 'Fujairah'];
begin
  with sup as materialized (   -- every matchable supplier with his trades and the emirates he states (none stated = UAE-wide)
    select sc.supplier_id, sc.trades,
           array(select distinct lower(btrim(e)) from unnest(coalesce(sc.coverage_emirates, '{}'::text[]) || coalesce(l.service_emirates, '{}'::text[])) e
                  where nullif(btrim(e), '') is not null) as stated
      from public.supplier_capabilities sc join public.leads l on l.id = sc.supplier_id
     where sc.confirmed_at is not null
       and public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status, l.permanently_closed, l.chat_strikes)
  ), inq as materialized (
    select i.id, i.emirate, i.trades, i.created_at,
           (i.created_at > now() - interval '30 days' and i.status not in ('revealed', 'closed', 'cancelled', 'completed', 'expired', 'lost')
            and (select count(*) from public.quotes q where q.inquiry_id = i.id) < 3) as short
      from public.inquiries i where i.created_at > now() - interval '90 days'
  ), pool as materialized (
    select t, l.emirate, count(*) as n from public.leads l, unnest(l.invite_trades) t
     where l.invite_status is null and not coalesce(l.banned, false) and not coalesce(l.permanently_closed, false)
       and coalesce(l.is_demo, false) = false
     group by t, l.emirate
  ), keys as (
    select tt.code as trade, 'UAE'::text as emirate from public.taxonomy_trade tt where tt.active
    union
    select distinct t, i.emirate from inq i, unnest(i.trades) t
     where i.emirate = any(v_emirates) and t in (select code from public.taxonomy_trade where active)
  ), m as (
    select k.trade, k.emirate,
           (select count(*) from sup s where k.trade = any(s.trades)
             and (k.emirate = 'UAE' or cardinality(s.stated) = 0 or lower(k.emirate) = any(s.stated)))::int as matchable,
           (select count(*) from inq i where k.trade = any(i.trades) and (k.emirate = 'UAE' or i.emirate = k.emirate))::int as demand,
           (select count(*) from inq i where i.short and k.trade = any(i.trades) and (k.emirate = 'UAE' or i.emirate = k.emirate))::int as short,
           (select coalesce(sum(p.n), 0) from pool p where p.t = k.trade and (k.emirate = 'UAE' or p.emirate = k.emirate))::int as pool
      from keys k
  )
  insert into public.supply_gap as sg (trade, emirate, matchable, target, demand_90d, short_open, uninvited_pool, measured_at)
  select trade, emirate, matchable, v_target, demand, short, pool, now() from m
  on conflict (trade, emirate) do update set matchable = excluded.matchable, target = excluded.target,
    demand_90d = excluded.demand_90d, short_open = excluded.short_open, uninvited_pool = excluded.uninvited_pool, measured_at = now();

  update public.supply_gap set status = 'closed', closed_at = now() where status <> 'closed' and matchable >= target;
  get diagnostics v_closed = row_count;
  update public.supply_gap set status = 'open', opened_at = now(), closed_at = null, decided_by = null, decided_at = null, held_id = null
   where (status = 'closed' and matchable < target) or (status = 'deferred' and decided_at < now() - interval '30 days');
  get diagnostics v_reopened = row_count;

  -- A decision whose reasoning failed five times goes back to open, so it is filed again (fn_reason_hold reopens it).
  update public.supply_gap sgp set status = 'open'
   where sgp.status = 'deciding' and exists (select 1 from public.reasoning_held_question h where h.id = sgp.held_id and h.status in ('failed', 'expired'));

  -- A CUSTOMER IS ALREADY WAITING: recruited for at once, by rule. No judgement to make, so nothing waits on one.
  update public.supply_gap set status = 'recruit', decided_by = 'rule:customer_waiting', decided_at = now()
   where status in ('open', 'deciding', 'deferred') and (short_open > 0 or demand_90d > 0);
  get diagnostics v_rule = row_count;

  -- NOBODY IS WAITING: recruit now or defer is a judgement, reasoned by the sales engineer (stakes high).
  for g in
    select s.*, tt.label from public.supply_gap s join public.taxonomy_trade tt on tt.code = s.trade
     where s.status = 'open' order by s.uninvited_pool desc, s.matchable, s.trade limit greatest(0, least(coalesce(p_reason_limit, 10), 50))
  loop
    update public.supply_gap set status = 'deciding', held_id = public.fn_seat_duty_reason('sales_engineer', 'sales_engineer.supply_gap',
      'Supplier supply for one trade is below the level at which we open requests to customers. Nobody is waiting on it '
        || 'today. Decide whether marketing should spend recruitment effort on this trade and area now, or defer it for a month.',
      '[{"id":"recruit","meaning":"recruit suppliers for this trade and area now"},{"id":"defer","meaning":"defer for a month; other gaps matter more"}]'::jsonb,
      jsonb_build_object('trade', g.trade, 'trade_label', g.label, 'area', g.emirate, 'matchable_suppliers', g.matchable,
                         'suppliers_needed_to_open', g.target, 'uninvited_leads_in_pool', g.uninvited_pool, 'requests_90d', g.demand_90d),
      jsonb_build_object('trade', g.trade, 'emirate', g.emirate), 'supply_gap:' || g.trade || ':' || g.emirate || ':' || v_month)
     where trade = g.trade and emirate = g.emirate;
    v_filed := v_filed + 1;
  end loop;

  return jsonb_build_object('target', v_target, 'closed', v_closed, 'reopened', v_reopened, 'recruit_by_rule', v_rule,
    'filed_for_reasoning', v_filed,
    'by_status', (select coalesce(jsonb_object_agg(status, n), '{}'::jsonb) from (select status, count(*) n from public.supply_gap group by status) x));
end $fn$;
revoke execute on function public.fn_sales_engineer_supply_gap(integer) from public, anon, authenticated;
grant execute on function public.fn_sales_engineer_supply_gap(integer) to service_role;

create or replace function public.fn_sales_engineer_duty_supply_gap()
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_sales_engineer_supply_gap(10) $fn$;
revoke execute on function public.fn_sales_engineer_duty_supply_gap() from public, anon, authenticated;
grant execute on function public.fn_sales_engineer_duty_supply_gap() to service_role;

-- The reasoned call on a gap. A recruit decision hands the gap to marketing — a seat-to-seat judgement, so marketing
-- reviews it on a model of another family (seat_deliberation).
create or replace function public.fn_reason_apply_sales_engineer__supply_gap(p_id bigint, p_result jsonb)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare r public.reasoning_held_question; v_choice text := p_result->'decision'->>'choice'; g public.supply_gap; v_review jsonb;
begin
  select * into r from public.reasoning_held_question where id = p_id;
  if v_choice is null or v_choice not in ('recruit', 'defer') then
    -- Not an answer to the question asked. fn_reason_held_resolve marks a row applied whenever its apply returns, even
    -- null, so this RAISES: the resolve rolls back, the row stays held and is reasoned again on a later replay.
    raise exception 'CHOICE_NOT_AN_OPTION: % is not recruit or defer (held question %)', coalesce(v_choice, 'no choice'), p_id;
  end if;
  select * into g from public.supply_gap where trade = r.subject->>'trade' and emirate = r.subject->>'emirate' for update;
  if not found or g.status <> 'deciding' then return jsonb_build_object('applied', false, 'reason', 'the gap moved on: ' || coalesce(g.status, 'gone')); end if;
  if v_choice = 'recruit' then
    v_review := public.fn_seat_duty_cross_review('sales_engineer.supply_gap', 'sales_engineer', 'marketing',
      'Review the sales engineer''s call on where marketing should recruit suppliers next.',
      jsonb_build_object('trade', g.trade, 'area', g.emirate, 'matchable_suppliers', g.matchable, 'needed', g.target,
                         'uninvited_leads', g.uninvited_pool, 'requests_90d', g.demand_90d),
      jsonb_build_object('call', 'recruit now', 'reasoning', left(coalesce(p_result->>'answer', ''), 2000)),
      p_result, 'supply_gap', g.trade || ':' || g.emirate);
  end if;
  update public.supply_gap set status = case when v_choice = 'recruit' then 'recruit' else 'deferred' end,
         decided_by = 'reasoning', decided_at = now(), review = v_review
   where trade = g.trade and emirate = g.emirate;
  return jsonb_build_object('applied', true, 'trade', g.trade, 'emirate', g.emirate, 'choice', v_choice, 'review', v_review);
end $fn$;
revoke execute on function public.fn_reason_apply_sales_engineer__supply_gap(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.fn_reason_apply_sales_engineer__supply_gap(bigint, jsonb) to service_role;

insert into public.seat_handoff_kind (type, from_seat, to_seat, meaning, handler, reply_within, owner_file)
values ('deliberation.review', 'sales_engineer', 'marketing',
        'Marketing reviews, on a model of another family, the sales engineer''s call to recruit suppliers for a trade and area.',
        'fn_seat_deliberation_acts_on_handoff', interval '2 days',
        'scripts/sql/the_sales_engineer_owns_onboarding_performance_and_supply_gaps.sql')
on conflict (type, from_seat, to_seat) do nothing;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('sales_engineer.supplier_onboarding', 'sales_engineer', interval '1 day', 'fn_sales_engineer_supplier_onboarding',
   'Every supplier''s stage from invitation to first quote; a matched supplier who has not quoted in 3 days is told (twice at most).',
   'scripts/sql/the_sales_engineer_owns_onboarding_performance_and_supply_gaps.sql'),
  ('sales_engineer.supplier_performance', 'sales_engineer', interval '1 day', 'fn_sales_engineer_supplier_performance',
   'One measured 0..1 score per supplier (reliability, rating, disputes), read by fn_match_capability.',
   'scripts/sql/the_sales_engineer_owns_onboarding_performance_and_supply_gaps.sql'),
  ('sales_engineer.supply_gap', 'sales_engineer', interval '1 day', 'fn_sales_engineer_duty_supply_gap',
   'Supply against demand per trade and emirate; a waiting customer is recruited for by rule, other gaps are reasoned.',
   'scripts/sql/the_sales_engineer_owns_onboarding_performance_and_supply_gaps.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

-- ── matching reads the score (fn_match_capability, otherwise unchanged from
--    trades_categories_and_product_matches_are_reasoned_not_word_matched.sql) ──────────────────────────────
create or replace function public.fn_match_capability(p_trades text[], p_need text default 'executes',
  p_products text[] default '{}', p_brands text[] default '{}', p_project_type text default null,
  p_value numeric default null, p_emirate text default null, p_limit integer default 12, p_services text[] default '{}')
returns table(supplier_id bigint, company_name text, score numeric, trades text[], roles text[], product_hits integer,
  brand_hit boolean, ptype_hit boolean, track numeric, why text, service_hits text[], via_implication text[])
set search_path to 'public', 'pg_temp'
language sql
stable
as $function$
with w as (
  select coalesce((select value::text::numeric from decision_policy where key='score_w_product'),40)      as w_prod,
         coalesce((select value::text::numeric from decision_policy where key='score_w_brand'),20)        as w_brand,
         coalesce((select value::text::numeric from decision_policy where key='score_w_project_type'),15) as w_ptype,
         coalesce((select value::text::numeric from decision_policy where key='score_w_track_record'),15) as w_track,
         coalesce((select value::text::numeric from decision_policy where key='score_w_size_fit'),10)     as w_size
),
-- EXACT (23 Sep 2026, decision point 25): the request's terms and the supplier's, each lower-cased and
-- trimmed, then compared for equality. A substring is not a match: "door" is not "door closer".
q as (
  select array(select distinct lower(btrim(x)) from unnest(coalesce(p_products, '{}'::text[])) x where nullif(btrim(x), '') is not null) as products,
         array(select distinct lower(btrim(x)) from unnest(coalesce(p_brands, '{}'::text[])) x where nullif(btrim(x), '') is not null) as brands,
         nullif(lower(btrim(coalesce(p_project_type, ''))), '') as ptype,
         nullif(lower(btrim(coalesce(p_emirate, ''))), '') as emirate
),
req_auth as (
  select coalesce(array_agg(distinct a),'{}') as codes
  from public.taxonomy_trade t, unnest(t.authority_required) a
  where t.code = any(p_trades)
),
named as (
  select distinct s as key, split_part(s, '.', 1) as tr
  from unnest(coalesce(p_services, '{}'::text[])) s
  where position('.' in s) > 0
    and exists (select 1 from public.taxonomy_trade_service ts
                where ts.active and ts.trade_code || '.' || ts.code = s)
),
n as (select count(*)::int as k from named),
loc as (
  select sc.supplier_id,
         array(select distinct lower(btrim(e)) from unnest(coalesce(sc.coverage_emirates, '{}'::text[])
                                           || coalesce(l.service_emirates, '{}'::text[])) e
                where nullif(btrim(e), '') is not null) as stated
  from public.supplier_capabilities sc
  join public.leads l on l.id = sc.supplier_id
),
cand as (
  select sc.supplier_id, sc.trades, sc.roles, sc.products_norm, sc.brands, sc.project_types,
         sc.min_project_value, sc.max_project_value, sc.coverage_emirates,
         sc.services, sc.services_removed,
         l.company_name, l.emirate as lead_emirate,
         -- 23 Sep 2026 (sales_engineer.supplier_performance): the measured score comes first; the view's quote rate
         -- and perf_score remain the fallback for a supplier the platform has not measured yet.
         least(1, greatest(0, coalesce(pf.score, sp.quote_rate, sp.perf_score, 0))) as track,
         ((select emirate from q) is not null and (select emirate from q) = any(loc.stated)) as in_emirate,
         cardinality(loc.stated) as stated_n
  from public.supplier_capabilities sc
  join public.leads l on l.id = sc.supplier_id
  join loc on loc.supplier_id = sc.supplier_id
  left join public.supplier_perf sp on sp.supplier_id = sc.supplier_id
  left join public.supplier_performance pf on pf.lead_id = sc.supplier_id
  where sc.confirmed_at is not null
    and sc.trades && p_trades
    and not (sc.excluded_trades && p_trades)
    and public.fn_is_matchable(l.verified, l.banned, l.matching_blocked,
                               l.approval_status, l.permanently_closed, l.chat_strikes)
    and exists (
      select 1 from public.taxonomy_role r
      where r.code = any(sc.roles)
        and case p_need when 'supplies'    then r.supplies
                        when 'whole_scope' then r.whole_scope
                        else r.executes end
    )
    and not exists (
      select 1 from unnest((select codes from req_auth)) a
      where not (sc.authority_approvals ? a)
    )
    and (p_value is null or (
          (sc.min_project_value is null or p_value >= sc.min_project_value)
      and (sc.max_project_value is null or p_value <= sc.max_project_value)))
    and ((select emirate from q) is null
      or cardinality(loc.stated) = 0
      or (select emirate from q) = any(loc.stated))
),
eff as (
  select c.*,
         case when (select k from n) = 0 then '{}'::text[]
              else public.fn_services_effective(c.services, c.trades, c.services_removed) end as eff_services
  from cand c
),
svc as (
  select e.*,
    array(select unnest(e.eff_services) intersect select key from named) as service_hits,
    not exists (select 1 from named t where t.tr = any(coalesce(e.trades, '{}'::text[]))) as never_asked,
    -- ponytail: one scan of service_implication per candidate (113 curated rows); batch it with a single
    -- unnest+join if the map or the candidate count grows an order of magnitude.
    array(
      select distinct i.from_code || ' -> ' || i.implies_trade || '.' || i.implies_code
      from public.service_implication i
      where i.active
        and (i.implies_trade || '.' || i.implies_code) = any(e.eff_services)
        and (i.implies_trade || '.' || i.implies_code) in (select key from named)
        and not ((i.implies_trade || '.' || i.implies_code) = any(coalesce(e.services, '{}'::text[])))
        and (i.from_code = any(coalesce(e.trades, '{}'::text[]))
          or i.from_code = any(coalesce(e.services, '{}'::text[])))
      order by 1) as via_implication
  from eff e
),
scored as (
  select c.*,
    -- EXACT: a requested product counts when the supplier declares that same product.
    (select count(*) from unnest((select products from q)) pq
      where pq = any(array(select lower(btrim(pp)) from unnest(coalesce(c.products_norm, '{}'::text[])) pp)))::int as product_hits,
    (cardinality((select brands from q)) > 0 and exists (
       select 1 from unnest(coalesce(c.brands, '{}'::text[])) bb where lower(btrim(bb)) in (select unnest(q.brands) from q)
     )) as brand_hit,
    ((select ptype from q) is not null and exists (
       select 1 from unnest(coalesce(c.project_types, '{}'::text[])) pt where lower(btrim(pt)) = (select ptype from q)
     )) as ptype_hit,
    (p_value is not null and c.min_project_value is not null and c.max_project_value is not null) as size_known
  from svc c
  where (select k from n) = 0
     or cardinality(c.service_hits) > 0
     or c.never_asked
),
ranked as (
  select s.*,
    round(
        w.w_prod  * (case when cardinality((select products from q)) > 0
                          then s.product_hits::numeric / cardinality((select products from q)) else 0 end)
      + w.w_brand * (case when s.brand_hit then 1 else 0 end)
      + w.w_ptype * (case when s.ptype_hit then 1 else 0 end)
      + w.w_track * s.track
      + w.w_size  * (case when s.size_known then 1 else 0.5 end)
    , 1) as score_v
  from scored s, w
)
select r.supplier_id, r.company_name, r.score_v as score,
  r.trades, r.roles, r.product_hits, r.brand_hit, r.ptype_hit, round(r.track,3) as track,
  concat_ws(' · ',
    'trades ' || array_to_string(array(select unnest(r.trades) intersect select unnest(p_trades)), '+'),
    case when cardinality(r.service_hits) > 0 then cardinality(r.service_hits)||'/'||(select k from n)||' services' end,
    case when (select k from n) > 0 and r.never_asked and cardinality(r.service_hits) = 0
           then 'trade level (no service named in this supplier''s trades)' end,
    case when cardinality(r.via_implication) > 0 then 'implied: ' || array_to_string(r.via_implication, ', ') end,
    case when r.product_hits > 0 then r.product_hits||'/'||cardinality((select products from q))||' products' end,
    case when r.brand_hit then 'brand match' end,
    case when r.ptype_hit then 'project type' end,
    case when p_emirate is not null then
      case when r.in_emirate then 'in ' || p_emirate else 'UAE-wide (no stated limit)' end end
  ) as why,
  r.service_hits, r.via_implication
from ranked r
order by r.score_v desc, cardinality(r.service_hits) desc, r.in_emirate desc, r.track desc, r.supplier_id
limit greatest(1, p_limit);
$function$;
revoke execute on function public.fn_match_capability(text[], text, text[], text[], text, numeric, text, integer, text[]) from public, anon, authenticated;
grant execute on function public.fn_match_capability(text[], text, text[], text[], text, numeric, text, integer, text[]) to service_role;
