-- THE CEO TRACKS THE SUPPLIER TARGET BY TRADE AND EMIRATE, AND PAID MARKETING WAITS UNTIL EVERY TRADE HAS TEN.
--
-- Assigned: ceo. 28 Sep 2026. Seat audit ceo.md gap 2 ("Supplier acquisition plan per trade and emirate toward 300
-- by Dec: partial; no per-trade gap plan; 0/195 trades ready") and marketing.md P1. Founder rulings: the year-one
-- plan is 50 verified suppliers by 12 Oct 2026, 200 by 30 Nov, 300 by 31 Dec (the AED 1M and 1,000/1,000 targets
-- are withdrawn and are not graded here); ledger 1004: marketing is ORGANIC ONLY until every category has >= 10
-- registered suppliers.
--
-- ══ MEASURED, 28 Sep 2026 (read-only, production) ═════════════════════════════════════════════════════
--   * 213 active trades in taxonomy_trade (the audit's "195" is older); pricing_config.category_open_min_suppliers 10.
--   * Matchable suppliers (confirmed supplier_capabilities + fn_is_matchable): 1, and it is a demo row; 0 real.
--     leads.verified and not is_demo: 0.
--   * No routine reads the supplier count against the 50 / 200 / 300 milestones; target_verdict carries
--     `metrics: []`. ceo_year_plan holds month-end figures (125 by Oct end), not the 12 Oct milestone.
--   * fn_ads_autospend_state() is the single gate every paid path reads: the ad_decision guard trigger (refuses
--     real spend unless live_allowed), fn_ads_manage (returns early), fn_ad_spend_daily_ceiling (0 when not
--     allowed). It knew nothing of supplier coverage: with the founder's go, token and cap it would allow spend
--     while 0 of 213 trades had ten suppliers.
--
-- ══ WHAT THIS ADDS ════════════════════════════════════════════════════════════════════════════════════
--   fn_supplier_target_by_trade_emirate(p_demo): per active trade x ('UAE' + the seven emirates) the registered
--     suppliers (confirmed capabilities) and the verified ones. "Verified" is the SAME definition the sales
--     engineer's supply_gap and ceo.launch_readiness count (confirmed capability + fn_is_matchable; a supplier
--     who states no emirate covers all of them), computed live instead of from the weekly snapshot. Demo rows
--     (leads.is_demo) are excluded; p_demo = true counts ONLY demo rows, so a probe can prove it in isolation.
--   fn_every_category_has_ten_suppliers(p_demo, p_trades): the gate boolean plus every category below 10
--     verified suppliers UAE-wide. Verified (not merely registered) is the launch_readiness definition and is
--     the stricter reading of "registered", so the gate can only open later, never earlier.
--   fn_ceo_supplier_target_status(p_at, p_demo): verified total against the next milestone, the linear path
--     from the previous one, the shortfall and the pace required per day.
--   ceo.supplier_target (daily, fn_ceo_supplier_target_now): when behind the path it opens ONE ceo_task per Dubai
--     day (the CEO's task list, which ceo.daily_run already reads), carrying the shortfall, the pace and the
--     per-emirate counts. Idempotent: a second run the same day opens nothing.
--   fn_ads_autospend_state(): live_allowed now also requires the gate; the reason names the categories short.
--     This supersedes the definition in ad_spend_needs_the_founders_cap_and_go.sql (identical otherwise).
--
-- NOT CHANGED: fn_sales_engineer_supply_gap and supply_gap (the sales engineer owns recruitment), launch_readiness,
-- the founder's go switch, token and cap, organic posting (marketing_campaign stays organic_only). No model is
-- called; nothing here writes to a person.
--
-- Pending: scripts/sql/pending/the_ceo_tracks_the_supplier_target_by_trade_and_emirate.txt.

create or replace function public.fn_supplier_target_by_trade_emirate(p_demo boolean default false)
returns table (trade text, label text, emirate text, registered integer, verified integer)
language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with sup as materialized (
    select sc.trades,
           public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status, l.permanently_closed, l.chat_strikes) as ok,
           array(select distinct lower(btrim(e)) from unnest(coalesce(sc.coverage_emirates, '{}'::text[]) || coalesce(l.service_emirates, '{}'::text[])) e
                  where nullif(btrim(e), '') is not null) as stated
      from public.supplier_capabilities sc join public.leads l on l.id = sc.supplier_id
     where sc.confirmed_at is not null and coalesce(l.is_demo, false) = p_demo
  ), em(emirate) as (
    values ('UAE'), ('Abu Dhabi'), ('Dubai'), ('Sharjah'), ('Ajman'), ('Umm Al Quwain'), ('Ras Al Khaimah'), ('Fujairah')
  )
  select t.code, t.label, em.emirate,
         count(s.trades)::int,
         (count(s.trades) filter (where s.ok))::int
    from public.taxonomy_trade t cross join em
    left join sup s on t.code = any(s.trades)
                   and (em.emirate = 'UAE' or cardinality(s.stated) = 0 or lower(em.emirate) = any(s.stated))
   where t.active
   group by t.code, t.label, em.emirate
$fn$;
revoke execute on function public.fn_supplier_target_by_trade_emirate(boolean) from public, anon, authenticated;
grant execute on function public.fn_supplier_target_by_trade_emirate(boolean) to service_role;

-- Ledger 1004. p_trades narrows the set only for a probe; the paid path always calls it with no arguments.
create or replace function public.fn_every_category_has_ten_suppliers(p_demo boolean default false, p_trades text[] default null)
returns jsonb language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with c as (
    select * from public.fn_supplier_target_by_trade_emirate(p_demo)
     where emirate = 'UAE' and (p_trades is null or trade = any(p_trades))
  )
  select jsonb_build_object(
    'gate', count(*) > 0 and count(*) filter (where verified < 10) = 0,
    'categories', count(*),
    'below_ten', count(*) filter (where verified < 10),
    'short', coalesce(jsonb_agg(jsonb_build_object('trade', trade, 'label', label, 'verified', verified)
                                order by verified, trade) filter (where verified < 10), '[]'::jsonb))
  from c
$fn$;
revoke execute on function public.fn_every_category_has_ten_suppliers(boolean, text[]) from public, anon, authenticated;
grant execute on function public.fn_every_category_has_ten_suppliers(boolean, text[]) to service_role;

create or replace function public.fn_ceo_supplier_target_status(p_at timestamptz default now(), p_demo boolean default false)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_day date := (p_at at time zone 'Asia/Dubai')::date; v_verified int; v_registered int;
  m record; v_expected numeric; v_short int; v_days int; v_emirates jsonb;
begin
  select coalesce(sum(verified), 0), coalesce(sum(registered), 0) into v_verified, v_registered
    from (select count(*) filter (where public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status, l.permanently_closed, l.chat_strikes)) as verified,
                 count(*) as registered
            from public.supplier_capabilities sc join public.leads l on l.id = sc.supplier_id
           where sc.confirmed_at is not null and coalesce(l.is_demo, false) = p_demo) x;
  -- The founder's year-one milestones (24 Sep 2026, restated 28 Sep). The path starts at 0 on 28 Sep 2026.
  select * into m from (values
      (date '2026-10-12',  50, date '2026-09-28',   0),
      (date '2026-11-30', 200, date '2026-10-12',  50),
      (date '2026-12-31', 300, date '2026-11-30', 200)) v(due, target, prev_due, prev_target)
   where v.due >= v_day order by v.due limit 1;
  if m.due is null then
    return jsonb_build_object('day', v_day, 'verified', v_verified, 'registered', v_registered, 'milestone', null, 'behind', false);
  end if;
  v_expected := m.prev_target + (m.target - m.prev_target) * greatest(0, least(1, (v_day - m.prev_due)::numeric / (m.due - m.prev_due)));
  v_short := greatest(0, m.target - v_verified);
  v_days := greatest(1, m.due - v_day);
  select jsonb_object_agg(emirate, verified) into v_emirates
    from (select emirate, count(distinct trade) filter (where verified >= 10) as verified
            from public.fn_supplier_target_by_trade_emirate(p_demo) group by emirate) e;
  return jsonb_build_object('day', v_day, 'verified', v_verified, 'registered', v_registered,
    'milestone', m.due, 'target', m.target, 'expected_today', floor(v_expected)::int,
    'behind_path', greatest(0, floor(v_expected)::int - v_verified), 'shortfall', v_short,
    'days_left', m.due - v_day, 'pace_per_day', round(v_short::numeric / v_days, 1),
    'behind', v_verified < floor(v_expected), 'trades_at_ten_by_emirate', v_emirates);
end $fn$;
revoke execute on function public.fn_ceo_supplier_target_status(timestamptz, boolean) from public, anon, authenticated;
grant execute on function public.fn_ceo_supplier_target_status(timestamptz, boolean) to service_role;

-- The daily duty: behind the path = one CEO task per Dubai day, nothing when on track.
create or replace function public.fn_ceo_supplier_target(p_at timestamptz default now(), p_demo boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare s jsonb := public.fn_ceo_supplier_target_status(p_at, p_demo); g jsonb := public.fn_every_category_has_ten_suppliers(p_demo);
  v_title text; v_task bigint;
begin
  if (s->>'behind')::boolean then
    v_title := format('Supplier target behind on %s%s', s->>'day', case when p_demo then ' (demo)' else '' end);
    if not exists (select 1 from public.ceo_task where title = v_title) then
      v_task := public.fn_ceo_task_open(v_title, format(
        E'%s verified suppliers against %s expected on the path to %s by %s. Shortfall %s in %s days: %s a day needed.\n'
        || E'Registered (capabilities confirmed): %s. Categories below 10 verified: %s of %s, so paid marketing stays closed (ledger 1004).\n'
        || 'Trades with 10+ verified, by emirate: %s. Direct the sales engineer and marketing to the widest trades.',
        s->>'verified', s->>'expected_today', s->>'target', s->>'milestone', s->>'shortfall', s->>'days_left', s->>'pace_per_day',
        s->>'registered', g->>'below_ten', g->>'categories', s->'trades_at_ten_by_emirate'));
    end if;
  end if;
  return s || jsonb_build_object('task_id', v_task, 'gate', g->'gate', 'below_ten', g->'below_ten');
end $fn$;
revoke execute on function public.fn_ceo_supplier_target(timestamptz, boolean) from public, anon, authenticated;
grant execute on function public.fn_ceo_supplier_target(timestamptz, boolean) to service_role;

create or replace function public.fn_ceo_supplier_target_now()
returns jsonb language sql security definer set search_path to 'public', 'pg_temp'
as $fn$ select public.fn_ceo_supplier_target(now(), false) $fn$;
revoke execute on function public.fn_ceo_supplier_target_now() from public, anon, authenticated;
grant execute on function public.fn_ceo_supplier_target_now() to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('ceo.supplier_target', 'ceo', interval '1 day', 'fn_ceo_supplier_target_now',
   'Every day, verified suppliers against the 50 / 200 / 300 milestones, per trade and emirate; when behind the path, one CEO task with the shortfall and the pace needed.',
   'scripts/sql/the_ceo_tracks_the_supplier_target_by_trade_and_emirate.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;

-- THE PAID PATH (supersedes ad_spend_needs_the_founders_cap_and_go.sql). Every paid route reads live_allowed:
-- the ad_decision guard trigger, fn_ads_manage and fn_ad_spend_daily_ceiling. Ledger 1004 is checked FIRST, so
-- no switch the founder flips opens paid spend while any category is below ten.
create or replace function public.fn_ads_autospend_state()
returns jsonb language sql stable set search_path to 'public' as $function$
  with s as (
    select
      coalesce((select lower(trim(value)) from public.app_secrets where key = 'meta_autospend_golive'), 'false') = 'true' as golive,
      coalesce((select length(trim(value)) >= 24 from public.app_secrets where key = 'meta_access_token'), false)        as token_present,
      (select case when trim(value) ~ '^[0-9]+(\.[0-9]+)?$' and trim(value)::numeric > 0 then trim(value)::numeric end
         from public.app_secrets where key = 'meta_daily_budget_cap_aed')                                               as cap_aed,
      public.fn_every_category_has_ten_suppliers()                                                                      as ten
  )
  select jsonb_build_object(
    'golive', golive,
    'token_present', token_present,
    'cap_aed', cap_aed,
    'every_category_has_ten', (ten->>'gate')::boolean,
    'live_allowed', (ten->>'gate')::boolean and golive and token_present and cap_aed is not null,
    'reason', case
      when not (ten->>'gate')::boolean then format('organic only (ledger 1004): %s of %s categories have fewer than 10 verified suppliers', ten->>'below_ten', ten->>'categories')
      when not golive then 'meta_autospend_golive is not ''true'''
      when not token_present then 'meta_access_token is absent'
      when cap_aed is null then 'meta_daily_budget_cap_aed is not a positive number'
      else 'live spend allowed under ' || cap_aed || ' AED/day' end)
  from s;
$function$;
revoke execute on function public.fn_ads_autospend_state() from public, anon, authenticated;
grant execute on function public.fn_ads_autospend_state() to service_role;
