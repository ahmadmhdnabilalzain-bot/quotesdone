-- A BUSY OR PAUSED SUPPLIER IS SKIPPED, AND AN INQUIRY NOBODY CAN REACH GOES TO THE RESCUE.
-- Seat: sales_engineer. 29 Sep 2026, founder ledger 1033 ("Supplier capacity and availability: busy or
-- available"), built under 1018 ("build them once the queue is below 20"), round 3.
--
-- WHAT THE SUPPLIER SAYS. In the portal (Settings, English only) a supplier marks itself
--   available  - the default, and what every supplier with no row here is;
--   busy       - until a date he names: from that date (Dubai) he is available again, with nothing to do;
--   paused     - until he says otherwise.
-- It is stored in public.supplier_availability, one row per supplier, written only through
-- fn_supplier_set_availability (supplier_api action set_availability), never by the browser directly.
--
-- WHAT MATCHING DOES WITH IT. fn_match_capability, the one matcher every dispatch path uses (customer_api
-- create_inquiry through sales_engineer {action:match}, the short-of-quotes widening, the public and intake
-- supplier counts), gains ONE gate in its candidate set: fn_supplier_available(state, busy_until). A busy
-- supplier whose date has come is available at read time, so the expiry is exact even if no clock has run;
-- the duty below also rewrites the row so the portal shows what matching does.
--
-- THE RESCUE. Skipping suppliers must never leave a customer's request with nobody to answer it and nobody
-- knowing. public.stalled_inquiry_rescue is the intake of the stalled-inquiry rescue (founder ledger 1023,
-- "no quotes after 48 hours triggers targeted recruitment and an honest update to the customer"): one row
-- per inquiry that is open, has no live quote, and has ZERO reachable suppliers - none matched, or every
-- matched supplier now busy, paused or no longer matchable. fn_stalled_inquiry_flag decides that for one
-- inquiry and flags it (or clears a flag whose inquiry is reachable again); customer_api calls it the
-- moment a dispatch lands on nobody, and the duty sweeps every open inquiry every 15 minutes, so an
-- inquiry whose suppliers all pause AFTER dispatch is flagged too. The row says why: how many were
-- matched and in what state, how many suppliers of the trade are busy or paused, and the earliest date
-- one of them is back. The flag is a record for the rescue to act on; it sends nothing to anyone.
--
-- MEASURED BEFORE THIS FILE (production, 29 Sep 2026, read-only): no availability, busy or pause column
-- on leads or supplier_capabilities, no routine named for availability or a rescue; inquiries hold 3 rows,
-- all ZZ DEMO (2 quoted, 1 revealed); 1 confirmed capability row (ZZ DEMO Interiors gypsum founderdemo,
-- the only supplier fn_match_capability(['gypsum']) returns). fn_rfq_short_of_quotes_tick widens only an
-- inquiry that was SENT to someone (first_sent is not null), so an inquiry that reached nobody was never
-- seen by any clock - customer_api's coverage_gap action was its only trace.
--
-- Pending: scripts/sql/pending/a_busy_or_paused_supplier_is_skipped_and_an_unreachable_inquiry_goes_to_the_rescue.txt.
-- Proved in one rolled-back transaction on ZZ DEMO data:
--   scripts/sql/a_busy_or_paused_supplier_is_skipped_and_an_unreachable_inquiry_goes_to_the_rescue_probe.sql,
--   run by scripts/checks/a_busy_or_paused_supplier_is_skipped_and_an_unreachable_inquiry_goes_to_the_rescue.test.mjs.

-- ── 1. what the supplier said ───────────────────────────────────────────────────────────────────────────
create table if not exists public.supplier_availability (
  supplier_id bigint primary key references public.leads(id) on delete cascade,
  state text not null default 'available' check (state in ('available', 'busy', 'paused')),
  busy_until date,
  set_at timestamptz not null default now(),
  set_by text not null,
  constraint supplier_availability_busy_names_its_date check ((state = 'busy') = (busy_until is not null))
);
comment on table public.supplier_availability is
  'sales_engineer: a supplier''s own availability (available / busy until a date / paused). No row = available. Written only by fn_supplier_set_availability; read by fn_match_capability through fn_supplier_available.';
alter table public.supplier_availability enable row level security;
drop policy if exists supplier_availability_service_role_only on public.supplier_availability;
create policy supplier_availability_service_role_only on public.supplier_availability
  as permissive for all to public using (false) with check (false);
revoke all on public.supplier_availability from anon, authenticated;

-- One definition of "available now", read by the matcher, the portal and the rescue alike. Busy until D
-- means busy through the day before D (Dubai): on D he is available.
create or replace function public.fn_supplier_available(p_state text, p_busy_until date)
returns boolean
language sql
stable
set search_path to 'public', 'pg_temp'
as $fn$
  select coalesce(p_state, 'available') = 'available'
      or (p_state = 'busy' and p_busy_until <= (now() at time zone 'Asia/Dubai')::date);
$fn$;
revoke execute on function public.fn_supplier_available(text, date) from public, anon, authenticated;
grant execute on function public.fn_supplier_available(text, date) to service_role;

-- What the portal shows: the state as matching reads it (a busy date that has come reads as available).
create or replace function public.fn_supplier_availability_of(p_supplier_id bigint)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select case
    when a.supplier_id is null or public.fn_supplier_available(a.state, a.busy_until)
      then jsonb_build_object('state', 'available', 'busy_until', null, 'set_at', a.set_at, 'matched', true)
    else jsonb_build_object('state', a.state, 'busy_until', a.busy_until, 'set_at', a.set_at, 'matched', false)
  end
  from (select 1) one
  left join public.supplier_availability a on a.supplier_id = p_supplier_id;
$fn$;
revoke execute on function public.fn_supplier_availability_of(bigint) from public, anon, authenticated;
grant execute on function public.fn_supplier_availability_of(bigint) to service_role;

-- The one writer. A busy date must be after today and within a year (a later date is a pause with a typo).
create or replace function public.fn_supplier_set_availability(p_supplier_id bigint, p_state text, p_busy_until date default null, p_by text default 'supplier_api')
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_today date := (now() at time zone 'Asia/Dubai')::date;
begin
  if p_state is null or p_state not in ('available', 'busy', 'paused') then
    return jsonb_build_object('ok', false, 'code', 'bad_state', 'error', 'Choose available, busy or paused.');
  end if;
  if p_state = 'busy' and (p_busy_until is null or p_busy_until <= v_today) then
    return jsonb_build_object('ok', false, 'code', 'busy_date_not_future', 'error', 'Choose the date you are available again: a date after today.');
  end if;
  if p_state = 'busy' and p_busy_until > v_today + 365 then
    return jsonb_build_object('ok', false, 'code', 'busy_date_too_far', 'error', 'A busy date must be within a year. To stop receiving requests for longer, pause instead.');
  end if;
  if not exists (select 1 from public.leads where id = p_supplier_id) then
    return jsonb_build_object('ok', false, 'code', 'no_company', 'error', 'No such supplier.');
  end if;
  insert into public.supplier_availability (supplier_id, state, busy_until, set_at, set_by)
  values (p_supplier_id, p_state, case when p_state = 'busy' then p_busy_until end, now(), coalesce(nullif(btrim(p_by), ''), 'supplier_api'))
  on conflict (supplier_id) do update
     set state = excluded.state, busy_until = excluded.busy_until, set_at = excluded.set_at, set_by = excluded.set_by;
  return jsonb_build_object('ok', true, 'availability', public.fn_supplier_availability_of(p_supplier_id));
end
$fn$;
revoke execute on function public.fn_supplier_set_availability(bigint, text, date, text) from public, anon, authenticated;
grant execute on function public.fn_supplier_set_availability(bigint, text, date, text) to service_role;

-- ── 2. the matcher skips a busy or paused supplier (fn_match_capability: the body of
--    the_sales_engineer_owns_onboarding_performance_and_supply_gaps.sql, MANIFEST 1726, with ONE added gate
--    and the availability join; nothing else changed) ─────────────────────────────────────────────────────
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
  left join public.supplier_availability av on av.supplier_id = sc.supplier_id
  where sc.confirmed_at is not null
    and sc.trades && p_trades
    and not (sc.excluded_trades && p_trades)
    and public.fn_is_matchable(l.verified, l.banned, l.matching_blocked,
                               l.approval_status, l.permanently_closed, l.chat_strikes)
    -- 29 Sep 2026 (ledger 1033): a supplier who said he is busy or paused is not sent a request. No row = available;
    -- a busy date that has come reads as available here, whether or not the duty has rewritten the row yet.
    and public.fn_supplier_available(av.state, av.busy_until)
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

-- ── 3. the rescue's intake ──────────────────────────────────────────────────────────────────────────────
create table if not exists public.stalled_inquiry_rescue (
  inquiry_id uuid primary key references public.inquiries(id) on delete cascade,
  reason text not null check (reason in ('no_reachable_supplier')),
  detail jsonb not null default '{}'::jsonb,
  fixture boolean not null default false,
  flagged_at timestamptz not null default now(),
  flagged_by text not null,
  cleared_at timestamptz,
  cleared_why text
);
comment on table public.stalled_inquiry_rescue is
  'sales_engineer: the stalled-inquiry rescue''s intake (ledger 1023). An open inquiry with no live quote and zero reachable suppliers, flagged by fn_stalled_inquiry_flag; cleared_at set when it is reachable again or closed.';
alter table public.stalled_inquiry_rescue enable row level security;
drop policy if exists stalled_inquiry_rescue_service_role_only on public.stalled_inquiry_rescue;
create policy stalled_inquiry_rescue_service_role_only on public.stalled_inquiry_rescue
  as permissive for all to public using (false) with check (false);
revoke all on public.stalled_inquiry_rescue from anon, authenticated;
create index if not exists stalled_inquiry_rescue_open_idx on public.stalled_inquiry_rescue (flagged_at) where cleared_at is null;

-- One inquiry: flag it when nobody can reach it, clear its flag when somebody can. "Reachable" = a supplier
-- matched to it who is matchable now (fn_is_matchable) and available now (fn_supplier_available). An inquiry
-- with a live quote was reached, whatever its suppliers say today.
create or replace function public.fn_stalled_inquiry_flag(p_inquiry_id uuid, p_by text default 'sales_engineer')
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  i public.inquiries; v_fixture boolean; v_quotes int; v_matched int; v_reach int; v_busy int; v_paused int;
  v_blocked int; v_back date; v_trades text[]; v_trade_busy int; v_trade_paused int; v_trade_back date;
  v_open boolean; v_detail jsonb; v_by text := coalesce(nullif(btrim(p_by), ''), 'sales_engineer');
begin
  select * into i from public.inquiries where id = p_inquiry_id;
  if not found then return jsonb_build_object('ok', false, 'error', 'no such inquiry'); end if;
  v_open := exists (select 1 from public.stalled_inquiry_rescue where inquiry_id = i.id and cleared_at is null);

  select count(*)::int into v_quotes from public.quotes q
   where q.inquiry_id = i.id
     and coalesce(q.status, '') not in ('draft', 'withdrawn', 'rejected', 'expired', 'held', 'cancelled')
     and q.stale_at is null;

  if coalesce(i.status, '') not in ('sent', 'quoted') or v_quotes > 0 then
    if v_open then
      update public.stalled_inquiry_rescue set cleared_at = now(),
             cleared_why = case when v_quotes > 0 then v_quotes || ' live quote(s)' else 'inquiry is ' || coalesce(i.status, 'null') end
       where inquiry_id = i.id and cleared_at is null;
    end if;
    return jsonb_build_object('ok', true, 'inquiry_id', i.id, 'flagged', false, 'cleared', v_open,
                              'why', case when v_quotes > 0 then 'quoted' else 'not open' end);
  end if;

  select count(*)::int,
         count(*) filter (where public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status, l.permanently_closed, l.chat_strikes)
                            and public.fn_supplier_available(av.state, av.busy_until))::int,
         count(*) filter (where not public.fn_supplier_available(av.state, av.busy_until) and av.state = 'busy')::int,
         count(*) filter (where not public.fn_supplier_available(av.state, av.busy_until) and av.state = 'paused')::int,
         count(*) filter (where not public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status, l.permanently_closed, l.chat_strikes))::int,
         min(av.busy_until) filter (where not public.fn_supplier_available(av.state, av.busy_until))
    into v_matched, v_reach, v_busy, v_paused, v_blocked, v_back
    from public.inquiry_matches m
    join public.leads l on l.id = m.supplier_id
    left join public.supplier_availability av on av.supplier_id = m.supplier_id
   where m.inquiry_id = i.id;

  if v_reach > 0 then
    if v_open then
      update public.stalled_inquiry_rescue set cleared_at = now(), cleared_why = v_reach || ' reachable supplier(s)'
       where inquiry_id = i.id and cleared_at is null;
    end if;
    return jsonb_build_object('ok', true, 'inquiry_id', i.id, 'flagged', false, 'cleared', v_open, 'reachable', v_reach);
  end if;

  -- Nobody can reach it. Say why, for the rescue: the matched suppliers' states, and the suppliers of its
  -- trades who confirmed their scope and are matchable but said busy or paused (the trade gate only: role,
  -- authority, value and emirate are the matcher's, not repeated here).
  v_trades := public.fn_taxonomy_trades_for(case when coalesce(cardinality(i.trades), 0) > 0 then i.trades
                                                 else array[coalesce(i.category, '')] end);
  select count(*) filter (where av.state = 'busy')::int, count(*) filter (where av.state = 'paused')::int, min(av.busy_until)
    into v_trade_busy, v_trade_paused, v_trade_back
    from public.supplier_capabilities sc
    join public.leads l on l.id = sc.supplier_id
    join public.supplier_availability av on av.supplier_id = sc.supplier_id
   where sc.confirmed_at is not null
     and sc.trades && coalesce(v_trades, '{}'::text[])
     and not (sc.excluded_trades && coalesce(v_trades, '{}'::text[]))
     and public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status, l.permanently_closed, l.chat_strikes)
     and not public.fn_supplier_available(av.state, av.busy_until);

  select public.fn_seat_clock_customer_is_fixture(c) into v_fixture from public.customers c where c.id = i.customer_id;
  v_detail := jsonb_build_object(
    'matched', v_matched, 'reachable', 0, 'matched_busy', v_busy, 'matched_paused', v_paused, 'matched_not_matchable', v_blocked,
    'earliest_back', v_back, 'trades', to_jsonb(v_trades), 'category', i.category, 'emirate', i.emirate,
    'in_trade_busy', coalesce(v_trade_busy, 0), 'in_trade_paused', coalesce(v_trade_paused, 0), 'in_trade_earliest_back', v_trade_back,
    'matcher_unavailable', coalesce((i.routing->>'matcher_unavailable')::boolean, false), 'at', now());

  insert into public.stalled_inquiry_rescue (inquiry_id, reason, detail, fixture, flagged_at, flagged_by)
  values (i.id, 'no_reachable_supplier', v_detail, coalesce(v_fixture, false), now(), v_by)
  on conflict (inquiry_id) do update
     set detail = excluded.detail, fixture = excluded.fixture,
         -- an open flag keeps the time it was first raised; a cleared one is raised again from now
         flagged_at = case when stalled_inquiry_rescue.cleared_at is null then stalled_inquiry_rescue.flagged_at else excluded.flagged_at end,
         flagged_by = case when stalled_inquiry_rescue.cleared_at is null then stalled_inquiry_rescue.flagged_by else excluded.flagged_by end,
         cleared_at = null, cleared_why = null;
  return jsonb_build_object('ok', true, 'inquiry_id', i.id, 'flagged', true, 'new', not v_open, 'detail', v_detail);
end
$fn$;
revoke execute on function public.fn_stalled_inquiry_flag(uuid, text) from public, anon, authenticated;
grant execute on function public.fn_stalled_inquiry_flag(uuid, text) to service_role;

-- ── 4. the duty: busy dates expire on their day, and every open inquiry is swept ───────────────────────
create or replace function public.fn_sales_engineer_availability_tick(p_include_fixtures boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_expired int; r record; v jsonb; v_swept int := 0; v_flagged int := 0; v_new int := 0; v_cleared int := 0;
begin
  -- A busy date that has come: the supplier is available again, with nothing for him to do.
  with x as (
    update public.supplier_availability
       set state = 'available', busy_until = null, set_at = now(), set_by = 'sales_engineer (busy date reached)'
     where state = 'busy' and busy_until <= (now() at time zone 'Asia/Dubai')::date
    returning 1)
  select count(*)::int into v_expired from x;

  -- ponytail: one call per open inquiry (3 rows today); a set-based pass if open inquiries reach thousands.
  for r in
    select i.id from public.inquiries i
      join public.customers c on c.id = i.customer_id
     where i.status in ('sent', 'quoted')
       and (p_include_fixtures or not public.fn_seat_clock_customer_is_fixture(c))
    union
    select f.inquiry_id from public.stalled_inquiry_rescue f
     where f.cleared_at is null and (p_include_fixtures or not f.fixture)
  loop
    v := public.fn_stalled_inquiry_flag(r.id, 'sales_engineer.supplier_availability');
    v_swept := v_swept + 1;
    if coalesce((v->>'flagged')::boolean, false) then
      v_flagged := v_flagged + 1;
      if coalesce((v->>'new')::boolean, false) then v_new := v_new + 1; end if;
    end if;
    if coalesce((v->>'cleared')::boolean, false) then v_cleared := v_cleared + 1; end if;
  end loop;
  return jsonb_build_object('ok', true, 'busy_expired', v_expired, 'inquiries_swept', v_swept,
                            'unreachable', v_flagged, 'newly_flagged', v_new, 'cleared', v_cleared);
end
$fn$;
revoke execute on function public.fn_sales_engineer_availability_tick(boolean) from public, anon, authenticated;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('sales_engineer.supplier_availability', 'sales_engineer', interval '15 minutes', 'fn_sales_engineer_availability_tick',
   'A supplier''s busy date expires on its day; every open inquiry with no live quote and zero reachable suppliers is flagged to the stalled-inquiry rescue (stalled_inquiry_rescue), and cleared when it is reachable again.',
   'scripts/sql/a_busy_or_paused_supplier_is_skipped_and_an_unreachable_inquiry_goes_to_the_rescue.sql')
on conflict (duty) do update set owner_seat = excluded.owner_seat, every = excluded.every, routine = excluded.routine,
  what = excluded.what, owner_file = excluded.owner_file;

-- Verdict row (DDL file, so no raise): the duty is registered and answers, and the matcher carries the gate.
select case
  when exists (select 1 from public.seat_duty where duty = 'sales_engineer.supplier_availability' and routine = 'fn_sales_engineer_availability_tick')
   and coalesce((public.fn_sales_engineer_availability_tick(false)->>'ok')::boolean, false)
   and position('fn_supplier_available(av.state, av.busy_until)' in pg_get_functiondef(
         'public.fn_match_capability(text[],text,text[],text[],text,numeric,text,integer,text[])'::regprocedure)) > 0
  then 'PROBE OK availability duty registered and answering; fn_match_capability skips busy and paused suppliers'
  else 'PROBE FAILED: the availability duty is missing or failing, or fn_match_capability lacks the availability gate' end as verdict;
