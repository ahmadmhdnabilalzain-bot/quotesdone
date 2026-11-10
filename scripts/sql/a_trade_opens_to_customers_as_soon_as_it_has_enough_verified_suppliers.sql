-- A TRADE OPENS TO CUSTOMERS AS SOON AS IT HAS ENOUGH VERIFIED SUPPLIERS; A CUSTOMER IN A TRADE THAT IS NOT OPEN YET IS
-- TOLD THE TRUTH, KEPT ON A WAITING LIST AND TOLD WHEN IT OPENS.
--
-- Assigned: ceo (the opening rule, the launch gate it replaces, the tuning) with sales_engineer (the intake doors that
-- read it) and customer_support (the notice when a trade opens). 10 Nov 2026. Founder ledger 1614 (standing): "launch to
-- customers TRADE BY TRADE - a trade opens to customers as soon as it has enough verified suppliers; customers in a
-- not-yet-open trade are told suppliers are being onboarded and notified when it opens." It supersedes the CEO launch
-- rule that needed all 223 trades at 10 suppliers. Proposal P1 of docs/reports/2026-11-10-seat-qualification-audit.md.
--
-- == MEASURED, 10 Nov 2026, production read-only ====================================================================
--   * THE ALL-TRADES GATE: fn_ceo_launch_readiness (scripts/sql/the_ceo_decides_whether_january_holds_on_supply_coverage.sql,
--     live md5 1b7e10e7...) decides 'ready' only when trades_ready = trades_total, "Customers launch only when every trade
--     is covered": 223 active trades x pricing_config.category_open_min_suppliers 10 = 2,230 suppliers before the first
--     customer. ceo_launch_gate 2026-11-09: 0 of 223 ready. That gate is replaced below.
--   * NOTHING AT THE DOOR READ COVERAGE: category_open_min_suppliers is read by six routines (supply gap target, the fact
--     packs, the weekly review), none of them on the customer path. customer_api create_inquiry posts a request in any
--     trade, with no supplier, and the matcher simply finds nobody. The WhatsApp interview advises in any trade.
--   * COVERAGE TODAY: supply_gap UAE reads 4 matchable slots (aluminium 2, gypsum 1, painting 1), and every one of them is
--     the single ZZ DEMO supplier: 0 real leads pass fn_is_matchable. No trade is open under any threshold.
--
-- == THE THRESHOLD AND WHY ==========================================================================================
--   The product promise is the T&C comparison: "the best 3 technical quotes vs the rest". A trade is worth opening when a
--   request in it can expect 3 quotes. With n verified suppliers each quoting with probability p, P(at least 3) is
--   1 - sum_{k=0..2} C(n,k) p^k (1-p)^(n-k). No quote has been measured yet (inquiry_matches 3 rows, all demo), so p is
--   ASSUMED at 0.40 (a B2B RFQ response rate; stated as an assumption, not a measurement):
--     * OPEN AT 10 (the start): P(>=3 | 10, 0.40) = 0.833. It is also the level the platform already names for opening
--       (pricing_config.category_open_min_suppliers = 10, the audit's measured need). The CEO tunes it (below).
--     * HARD FLOOR 5, in the schema: even at a strong p = 0.60, P(>=3 | 5) = 0.683 and P(>=3 | 4) = 0.475. Below 5 the
--       comparison the customer pays to act on is a coin toss, and a request with no answer in 3 working days is the
--       non-response refund the T&C promise. The floor is a CHECK constraint: the CEO cannot write under it; only a
--       reviewed schema change can.
--     * THE CEO TUNES IT WEEKLY (fn_ceo_trade_opening_tune): once 30 or more supplier invitations to quote exist in the
--       last 90 days of real requests, p is MEASURED (quotes / invitations) and the threshold becomes the smallest n in
--       [5, 25] with P(>=3 | n, p) >= 0.80. Below 30 invitations it does not move (a rate on a handful is noise).
--   Hysteresis: a trade OPENS at the threshold and CLOSES only below the floor, so a customer half-way through a request
--   is not stranded because one supplier was paused.
--
-- == WHAT THIS ADDS ================================================================================================
--   trade_opening_rule        one row: open_at_suppliers (CEO-tuned, 5..25), floor 5, the basis of the last change.
--   trade_customer_opening    per active trade: verified suppliers, open or not, when it opened or closed.
--   customer_trade_waitlist   one row per (customer or WhatsApp number, trade) while waiting; notified when it opens.
--   fn_trade_customer_gate(slugs)       the intake doors' question: open / not_open / unclassified, with the trades short.
--   fn_trade_waitlist_join(...)         records the waiting customer and returns the honest message, EN and AR.
--   fn_trade_reveal_allowed(inquiry)    a paid reveal is refused while any of the request's trades is under the floor.
--   fn_ceo_trade_opening_tick()         hourly (ceo.trade_opening): re-measures, opens and closes, and tells the waiting.
--   fn_ceo_trade_opening_tune(at)       weekly (ceo.trade_opening_tune): the threshold from the measured quote rate.
--   fn_ceo_launch_readiness             REWRITTEN: the week's open trades, not "every trade". It no longer mails the
--                                       founder anything (ledger 1616: he is told in his daily brief only).
--
-- THE DEMO HARNESS: ZZ DEMO suppliers count only for a ZZ DEMO customer (fn_customer_is_demo, fn_inquiry_is_demo,
-- fn_is_demo_phone: the markers the estate already uses), and for such a customer a trade is open at the floor of 5, so
-- scripts/e2e/evidence_pack.mjs (five ZZ DEMO suppliers per journey) and the walks run while no real trade is open. A real
-- customer is never served, and never charged a reveal, on the strength of a demo supplier; the hourly state table counts
-- real suppliers only. Measured 10 Nov 2026: 3 ZZ DEMO suppliers are matchable (aluminium 2, gypsum 1, painting 1).
--
-- NOT CHANGED: pricing_config (category_open_min_suppliers stays the sales engineer's recruitment target per trade),
-- fn_sales_engineer_supply_gap, the matcher, any campaign switch or cap. A request with no taxonomy trade at all
-- ('general', the intake's own "no listed trade fits") posts as before: there is no trade to count coverage on, and
-- refusing it would invent a rule ledger 1614 did not make. Said here so nobody reads it as an oversight.
--
-- prevented by: scripts/checks/a_trade_opens_to_customers_as_soon_as_it_has_enough_verified_suppliers.test.mjs
-- Pending: scripts/sql/pending/a_trade_opens_to_customers_as_soon_as_it_has_enough_verified_suppliers.txt

create table if not exists public.trade_opening_rule (
  id                  smallint primary key default 1 check (id = 1),
  -- THE HARD FLOOR IS THE SCHEMA: 5 (see the header). The CEO may set anything from 5 to 25 and nothing else.
  open_at_suppliers   integer not null check (open_at_suppliers between 5 and 25),
  floor_suppliers     integer not null default 5 check (floor_suppliers = 5),
  target_quotes       integer not null default 3 check (target_quotes = 3),
  assumed_quote_rate  numeric not null default 0.40 check (assumed_quote_rate > 0 and assumed_quote_rate <= 1),
  measured_quote_rate numeric check (measured_quote_rate is null or (measured_quote_rate >= 0 and measured_quote_rate <= 1)),
  measured_invitations integer,
  set_by              text not null check (set_by in ('session', 'ceo')),
  reason              text not null check (length(btrim(reason)) > 0),
  updated_at          timestamptz not null default now()
);
alter table public.trade_opening_rule enable row level security;
drop policy if exists trade_opening_rule_service_role_only on public.trade_opening_rule;
create policy trade_opening_rule_service_role_only on public.trade_opening_rule as permissive for all to public using (false) with check (false);
revoke all on public.trade_opening_rule from anon, authenticated;
insert into public.trade_opening_rule (id, open_at_suppliers, set_by, reason)
values (1, 10, 'session', 'Start: P(>=3 quotes | 10 suppliers, assumed 40% quote rate) = 0.833; the platform''s own opening level (pricing_config.category_open_min_suppliers 10). Ledger 1614.')
on conflict (id) do nothing;

create table if not exists public.trade_customer_opening (
  trade               text primary key references public.taxonomy_trade(code) on delete cascade,
  verified_suppliers  integer not null,
  open_at             integer not null,
  is_open             boolean not null default false,
  opened_at           timestamptz,
  closed_at           timestamptz,
  measured_at         timestamptz not null default now()
);
alter table public.trade_customer_opening enable row level security;
drop policy if exists trade_customer_opening_service_role_only on public.trade_customer_opening;
create policy trade_customer_opening_service_role_only on public.trade_customer_opening as permissive for all to public using (false) with check (false);
revoke all on public.trade_customer_opening from anon, authenticated;

create table if not exists public.customer_trade_waitlist (
  id           bigint generated always as identity primary key,
  -- no foreign key to customers on purpose: creating one takes a SHARE ROW EXCLUSIVE lock on the table every sign-in
  -- writes to (memory: an apply can lock sign-in); a waiting row of a deleted customer is simply never sendable
  customer_id  uuid,
  phone        text,
  channel      text not null check (channel in ('portal', 'whatsapp')),
  trade        text not null references public.taxonomy_trade(code) on delete cascade,
  intake_id    uuid,
  lang         text not null default 'en' check (lang in ('en', 'ar')),
  status       text not null default 'waiting' check (status in ('waiting', 'notified', 'withdrawn')),
  created_at   timestamptz not null default now(),
  notified_at  timestamptz,
  notice       jsonb,
  constraint customer_trade_waitlist_has_someone check (customer_id is not null or nullif(btrim(phone), '') is not null)
);
create unique index if not exists customer_trade_waitlist_one_waiting
  on public.customer_trade_waitlist (coalesce(customer_id::text, phone), trade) where status = 'waiting';
alter table public.customer_trade_waitlist enable row level security;
drop policy if exists customer_trade_waitlist_service_role_only on public.customer_trade_waitlist;
create policy customer_trade_waitlist_service_role_only on public.customer_trade_waitlist as permissive for all to public using (false) with check (false);
revoke all on public.customer_trade_waitlist from anon, authenticated;

-- Verified, matchable suppliers of one trade, UAE-wide: the predicate fn_sales_engineer_supply_gap counts on (a confirmed
-- capability row and fn_is_matchable), with one difference that matters: A DEMO SUPPLIER NEVER COUNTS. Measured 10 Nov 2026:
-- supply_gap's "4 matchable" are all one ZZ DEMO supplier; real verified, matchable suppliers number 0.
-- THE DEMO HARNESS (coordinator review, 10 Nov 2026): ZZ DEMO suppliers count ONLY for a ZZ DEMO customer (p_with_fixtures,
-- set by the callers from fn_customer_is_demo / fn_inquiry_is_demo / fn_is_demo_phone, the markers the estate already uses),
-- so scripts/e2e/evidence_pack.mjs and the walks (five ZZ DEMO suppliers per journey) are not waitlisted while 0 real
-- trades are open, and a real customer is never served on the strength of a demo supplier.
-- THE PROBE SEAM: qd.trade_opening_fixture_counts, a session setting holding {"<trade>": n} for the real count and
-- {"<trade>@fixture": n} for the count a demo customer sees, replaces the count for the trades it names. Only this file's
-- probe sets it, inside its own rolled-back transaction (set_config(..., true)); it is never stored, and a verified
-- supplier cannot be faked for a probe (fn_supplier_mandatory_six wants real documents).
create or replace function public.fn_trade_verified_suppliers(p_trade text, p_with_fixtures boolean default false)
returns integer language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce(
    (nullif(current_setting('qd.trade_opening_fixture_counts', true), '')::jsonb ->> (p_trade || case when p_with_fixtures then '@fixture' else '' end))::int,
    (select count(distinct sc.supplier_id)::int
       from public.supplier_capabilities sc join public.leads l on l.id = sc.supplier_id
      where sc.confirmed_at is not null and p_trade = any(sc.trades)
        and (not coalesce(l.is_demo, false) or p_with_fixtures)
        and public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status, l.permanently_closed, l.chat_strikes)))
$fn$;
revoke execute on function public.fn_trade_verified_suppliers(text, boolean) from public, anon, authenticated;
grant execute on function public.fn_trade_verified_suppliers(text, boolean) to service_role;

-- The taxonomy trades a request names: fn_taxonomy_trades_for (the resolver dispatch uses), kept to ACTIVE taxonomy codes
-- only, so an intake slug that is not itself a trade ('general', 'combined') never counts as one.
create or replace function public.fn_trade_codes_of(p_slugs text[])
returns text[] language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select coalesce(array_agg(distinct c order by c), '{}'::text[])
    from unnest(public.fn_taxonomy_trades_for(p_slugs)) c
   where exists (select 1 from public.taxonomy_trade t where t.code = c and t.active)
$fn$;
revoke execute on function public.fn_trade_codes_of(text[]) from public, anon, authenticated;
grant execute on function public.fn_trade_codes_of(text[]) to service_role;

-- Is this trade open to customers now? The tick's state when it holds one (hysteresis: open until under the floor), and a
-- live count for a trade that crossed the threshold since the last tick, so a door never refuses a trade that is ready.
-- A ZZ DEMO customer (p_fixture): the trade is open at the floor of 5, counting demo suppliers with the real ones. The
-- harness proves the journey, not the coverage rule; the real threshold and its hysteresis are untouched and tested apart.
create or replace function public.fn_trade_is_open(p_trade text, p_fixture boolean default false)
returns boolean language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  with r as (select open_at_suppliers, floor_suppliers from public.trade_opening_rule where id = 1),
       n as (select public.fn_trade_verified_suppliers(p_trade, p_fixture) as v)
  select case when p_fixture then (select n.v >= r.floor_suppliers from n, r)
              when exists (select 1 from public.trade_customer_opening o where o.trade = p_trade and o.is_open)
              then (select n.v >= r.floor_suppliers from n, r)
              else (select n.v >= r.open_at_suppliers from n, r) end
$fn$;
revoke execute on function public.fn_trade_is_open(text, boolean) from public, anon, authenticated;
grant execute on function public.fn_trade_is_open(text, boolean) to service_role;

-- The honest words, in one place, both languages. p_kind: 'waiting' (said at the door) or 'opened' (the notice).
create or replace function public.fn_trade_waitlist_message(p_kind text, p_lang text, p_trades text[], p_link text default null)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_ar boolean := p_lang = 'ar'; v_names text;
begin
  select string_agg(case when v_ar then coalesce(t.label_ar, t.label) else t.label end, case when v_ar then '، ' else ', ' end order by t.label)
    into v_names from public.taxonomy_trade t where t.code = any(p_trades);
  v_names := coalesce(v_names, array_to_string(p_trades, ', '));
  if p_kind = 'waiting_visitor' then
    -- a WhatsApp number with no account: we may not write first later, so the honest words ask them to register
    return jsonb_build_object('subject', null, 'body', case when v_ar then
      'شكرًا لكم. نعمل حاليًا على تسجيل موردين معتمدين في تخصص ' || v_names || '، لذلك لم نفتح الطلبات فيه بعد. سجّلوا حسابكم عبر الرابط التالي لنبلغكم فور فتح التخصص: '
      || coalesce(p_link, 'https://quotesdone.com/ar/me?new=1')
    else
      'Thank you. We are onboarding verified suppliers for ' || v_names || ' right now, so requests in this trade are not open yet. Register here and we will let you know the moment it opens: '
      || coalesce(p_link, 'https://quotesdone.com/me?new=1')
    end);
  end if;
  if p_kind = 'waiting' then
    return jsonb_build_object('subject', null, 'body', case when v_ar then
      'شكرًا لكم. نعمل حاليًا على تسجيل موردين معتمدين في تخصص ' || v_names || '، لذلك لم نفتح الطلبات فيه بعد. حفظنا طلبكم، وسنبلغكم فور فتح التخصص لتتمكنوا من إرساله مباشرة.'
    else
      'Thank you. We are onboarding verified suppliers for ' || v_names || ' right now, so requests in this trade are not open yet. Your request is saved, and we will let you know as soon as the trade opens so you can send it straight away.'
    end);
  end if;
  return jsonb_build_object(
    'subject', case when v_ar then 'فتحنا الطلبات في تخصص ' || v_names else 'Requests are now open for ' || v_names end,
    'body', case when v_ar then
      'يسعدنا إبلاغكم بأن لدينا الآن موردين معتمدين بعدد كافٍ في تخصص ' || v_names || '، وأصبح بإمكانكم إرسال طلبكم فيه. طلبكم المحفوظ بانتظاركم في حسابكم: '
      || coalesce(p_link, 'https://quotesdone.com/ar/me')
    else
      'Good news: we now have enough verified suppliers for ' || v_names || ', so requests in this trade are open. Your saved request is waiting in your account: '
      || coalesce(p_link, 'https://quotesdone.com/me')
    end);
end $fn$;
revoke execute on function public.fn_trade_waitlist_message(text, text, text[], text) from public, anon, authenticated;
grant execute on function public.fn_trade_waitlist_message(text, text, text[], text) to service_role;

-- THE DOORS' QUESTION. state: 'open' (every trade the request names is open: it proceeds as today), 'not_open' (at least
-- one is not: the request waits), 'unclassified' (it names no taxonomy trade: it proceeds as before, see the header).
create or replace function public.fn_trade_customer_gate(p_slugs text[], p_lang text default 'en', p_fixture boolean default false)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_codes text[] := public.fn_trade_codes_of(p_slugs); v_closed text[]; v_detail jsonb; r public.trade_opening_rule;
begin
  select * into r from public.trade_opening_rule where id = 1;
  if cardinality(v_codes) = 0 then
    return jsonb_build_object('state', 'unclassified', 'codes', '[]'::jsonb, 'closed', '[]'::jsonb);
  end if;
  select coalesce(array_agg(c order by c), '{}'::text[]) into v_closed from unnest(v_codes) c where not public.fn_trade_is_open(c, p_fixture);
  select coalesce(jsonb_agg(jsonb_build_object('code', c, 'verified', public.fn_trade_verified_suppliers(c, p_fixture),
           'open_at', case when p_fixture then r.floor_suppliers else r.open_at_suppliers end) order by c), '[]'::jsonb)
    into v_detail from unnest(v_closed) c;
  return jsonb_build_object('state', case when cardinality(v_closed) = 0 then 'open' else 'not_open' end,
    'codes', to_jsonb(v_codes), 'closed', v_detail, 'fixture', p_fixture,
    -- the caller's language, and both: a portal refusal carries message AND message_ar (portalText errText renders them)
    'message', case when cardinality(v_closed) > 0 then public.fn_trade_waitlist_message('waiting', p_lang, v_closed)->>'body' end,
    'message_en', case when cardinality(v_closed) > 0 then public.fn_trade_waitlist_message('waiting', 'en', v_closed)->>'body' end,
    'message_ar', case when cardinality(v_closed) > 0 then public.fn_trade_waitlist_message('waiting', 'ar', v_closed)->>'body' end);
end $fn$;
revoke execute on function public.fn_trade_customer_gate(text[], text, boolean) from public, anon, authenticated;
grant execute on function public.fn_trade_customer_gate(text[], text, boolean) to service_role;

-- THE DOOR RECORDS THE WAITING CUSTOMER. One waiting row per (customer or number, trade); asking again is not a second row.
create or replace function public.fn_trade_waitlist_join(p_slugs text[], p_channel text, p_customer uuid default null,
  p_phone text default null, p_lang text default 'en', p_intake uuid default null)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare g jsonb; v_lang text := case when p_lang = 'ar' then 'ar' else 'en' end; v_n int;
  v_customer uuid := p_customer; v_closed text[]; v_fixture boolean;
begin
  -- a WhatsApp number that belongs to an account is that customer: the notice then goes to the account (and its confirmed number)
  if v_customer is null and nullif(btrim(coalesce(p_phone, '')), '') is not null then
    select c.id into v_customer from public.customers c
     where not coalesce(c.banned, false) and c.merged_into is null
       and (regexp_replace(coalesce(c.whatsapp_phone, ''), '[^0-9]', '', 'g') = regexp_replace(p_phone, '[^0-9]', '', 'g')
            or regexp_replace(coalesce(c.phone, ''), '[^0-9]', '', 'g') = regexp_replace(p_phone, '[^0-9]', '', 'g'))
     order by c.created_at limit 1;
  end if;
  -- the estate's own demo markers: a ZZ DEMO customer (customers.is_demo, generated from the name and @example.invalid)
  -- or the reserved fixture mobile block; nothing else makes a door count demo suppliers
  v_fixture := (v_customer is not null and public.fn_customer_is_demo(v_customer))
               or (p_phone is not null and public.fn_is_demo_phone(p_phone));
  g := public.fn_trade_customer_gate(p_slugs, p_lang, v_fixture);
  if g->>'state' <> 'not_open' then return g || jsonb_build_object('waitlisted', false); end if;
  if v_customer is null and p_channel = 'whatsapp' then
    select array_agg(e->>'code') into v_closed from jsonb_array_elements(g->'closed') e;
    g := g || jsonb_build_object('message', public.fn_trade_waitlist_message('waiting_visitor', v_lang, v_closed,
           coalesce((select value from public.app_secrets where key = 'public_site_url'), 'https://quotesdone.com') || case when v_lang = 'ar' then '/ar/me?new=1' else '/me?new=1' end)->>'body');
  end if;
  if v_customer is null and nullif(btrim(coalesce(p_phone, '')), '') is null then
    return g || jsonb_build_object('waitlisted', false, 'why', 'nobody to tell');
  end if;
  insert into public.customer_trade_waitlist (customer_id, phone, channel, trade, intake_id, lang)
  select v_customer, nullif(btrim(p_phone), ''), case when p_channel = 'whatsapp' then 'whatsapp' else 'portal' end, e->>'code', p_intake, v_lang
    from jsonb_array_elements(g->'closed') e
  on conflict (coalesce(customer_id::text, phone), trade) where status = 'waiting'
  do update set intake_id = coalesce(excluded.intake_id, customer_trade_waitlist.intake_id), lang = excluded.lang;
  get diagnostics v_n = row_count;
  return g || jsonb_build_object('waitlisted', true, 'rows', v_n, 'customer_id', v_customer);
end $fn$;
revoke execute on function public.fn_trade_waitlist_join(text[], text, uuid, text, text, uuid) from public, anon, authenticated;
grant execute on function public.fn_trade_waitlist_join(text[], text, uuid, text, text, uuid) to service_role;

-- NEVER A PAID REVEAL UNDER THE FLOOR (ledger 1614, this build's rule): every taxonomy trade of the request must hold at
-- least floor_suppliers verified suppliers at the moment the customer would pay. _shared/reveal_guard.ts canReveal asks
-- this before any charge, on every reveal door. A request with no taxonomy trade is not gated (see the header).
create or replace function public.fn_trade_reveal_allowed(p_inquiry uuid)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare i public.inquiries; v_codes text[]; v_floor int := (select floor_suppliers from public.trade_opening_rule where id = 1); v_short jsonb; v_fixture boolean;
begin
  select * into i from public.inquiries where id = p_inquiry;
  if not found then return jsonb_build_object('allowed', false, 'why', 'no such request'); end if;
  -- a ZZ DEMO request (fn_inquiry_is_demo: the customer, the run tag, the fixture brief) counts demo suppliers; a real one never
  v_fixture := public.fn_inquiry_is_demo(i.id);
  v_codes := public.fn_trade_codes_of(array_remove(array[i.category] || coalesce(i.trades, '{}'::text[]), null));
  select coalesce(jsonb_agg(jsonb_build_object('code', c, 'verified', n)), '[]'::jsonb) into v_short
    from (select c, public.fn_trade_verified_suppliers(c, v_fixture) n from unnest(v_codes) c) x where n < v_floor;
  return jsonb_build_object('allowed', jsonb_array_length(v_short) = 0, 'floor', v_floor, 'codes', to_jsonb(v_codes), 'below_floor', v_short, 'fixture', v_fixture);
end $fn$;
revoke execute on function public.fn_trade_reveal_allowed(uuid) from public, anon, authenticated;
grant execute on function public.fn_trade_reveal_allowed(uuid) to service_role;

-- HOURLY (ceo.trade_opening): re-measure every active trade, open at the threshold, close under the floor, and tell every
-- waiting customer whose trade is open. A fixture customer or a demo number is marked told WITHOUT a message: a probe of
-- this routine cannot reach a person (skill: organised-like-an-auditor §8).
create or replace function public.fn_ceo_trade_opening_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare r public.trade_opening_rule; v_opened int := 0; v_closed int := 0; v_told int := 0; v_fixture int := 0; v_unreachable int := 0; w record; m jsonb;
  v_email text; v_sent jsonb; v_link text; v_base text := coalesce((select value from public.app_secrets where key = 'public_site_url'), 'https://quotesdone.com');
begin
  select * into r from public.trade_opening_rule where id = 1;
  -- one pass over the suppliers for all 223 trades (the per-trade routine made a tick ~5 s; this is the same predicate,
  -- fn_trade_verified_suppliers', set-based, with the same probe seam)
  with s as materialized (
    select sc.supplier_id, sc.trades from public.supplier_capabilities sc join public.leads l on l.id = sc.supplier_id
     where sc.confirmed_at is not null and not coalesce(l.is_demo, false)
       and public.fn_is_matchable(l.verified, l.banned, l.matching_blocked, l.approval_status, l.permanently_closed, l.chat_strikes)),
  n as (select t.code, coalesce((nullif(current_setting('qd.trade_opening_fixture_counts', true), '')::jsonb ->> t.code)::int,
                                (select count(distinct s.supplier_id) from s where t.code = any(s.trades)))::int v
          from public.taxonomy_trade t where t.active)
  insert into public.trade_customer_opening as o (trade, verified_suppliers, open_at, is_open, opened_at, measured_at)
  select n.code, n.v, r.open_at_suppliers, n.v >= r.open_at_suppliers, case when n.v >= r.open_at_suppliers then now() end, now() from n
  on conflict (trade) do update set verified_suppliers = excluded.verified_suppliers, open_at = excluded.open_at, measured_at = now(),
    is_open = case when o.is_open then excluded.verified_suppliers >= r.floor_suppliers else excluded.verified_suppliers >= excluded.open_at end,
    opened_at = case when not o.is_open and excluded.verified_suppliers >= excluded.open_at then now() else o.opened_at end,
    closed_at = case when o.is_open and excluded.verified_suppliers < r.floor_suppliers then now() else o.closed_at end;
  -- now() is the transaction's instant, so "= now()" is exactly the rows this run opened or closed
  select count(*) filter (where opened_at = now()), count(*) filter (where closed_at = now())
    into v_opened, v_closed from public.trade_customer_opening;

  for w in
    select q.*, c.email, c.locale from public.customer_trade_waitlist q
      join public.trade_customer_opening o on o.trade = q.trade and o.is_open
      left join public.customers c on c.id = q.customer_id
     where q.status = 'waiting' order by q.created_at limit 200
  loop
    if (w.customer_id is not null and public.fn_customer_is_demo(w.customer_id)) or (w.phone is not null and public.fn_is_demo_phone(w.phone)) then
      update public.customer_trade_waitlist set status = 'notified', notified_at = now(), notice = jsonb_build_object('fixture', true) where id = w.id;
      v_fixture := v_fixture + 1; continue;
    end if;
    v_link := v_base || case when w.lang = 'ar' then '/ar/me' else '/me' end || case when w.intake_id is null then '?new=1' else '' end;
    m := public.fn_trade_waitlist_message('opened', w.lang, array[w.trade], v_link);
    v_email := lower(nullif(btrim(coalesce(w.email, '')), ''));
    if v_email is not null then
      -- the customer_support door every duty mail goes through: suppression, dedupe and the outbox
      v_sent := public.fn_customer_support_duty_send('trade_open.notice', w.id::text, 'customer', v_email, w.lang, m->>'subject', m->>'body', w.customer_id, null, null);
    else
      -- A WHATSAPP NUMBER WITH NO ACCOUNT. The platform writes first on WhatsApp only to a CONFIRMED number
      -- (a03_notifications_whatsapp_goes_to_a_confirmed_number skips anything else, and Meta's rules agree), so there is no
      -- door to tell this person on. Said, not faked: the row is withdrawn with the reason, the waiting message told them to
      -- register for the notice (fn_trade_waitlist_message 'waiting_visitor'), and the next time they write the door is open.
      update public.customer_trade_waitlist set status = 'withdrawn', notified_at = now(),
             notice = jsonb_build_object('sent', false, 'why', 'no account and no confirmed WhatsApp number: the platform may not write first; the trade is open when they next write')
       where id = w.id;
      v_unreachable := v_unreachable + 1; continue;
    end if;
    update public.customer_trade_waitlist set status = 'notified', notified_at = now(), notice = coalesce(v_sent, '{}'::jsonb) where id = w.id;
    v_told := v_told + 1;
  end loop;
  return jsonb_build_object('open_at', r.open_at_suppliers, 'floor', r.floor_suppliers,
    'open', (select count(*) from public.trade_customer_opening where is_open), 'opened', v_opened, 'closed', v_closed,
    'told', v_told, 'fixtures_marked', v_fixture, 'unreachable', v_unreachable, 'waiting', (select count(*) from public.customer_trade_waitlist where status = 'waiting'));
end $fn$;
revoke execute on function public.fn_ceo_trade_opening_tick() from public, anon, authenticated;
grant execute on function public.fn_ceo_trade_opening_tick() to service_role;

-- P(at least k quotes | n suppliers, rate p): the binomial tail the threshold is chosen on.
create or replace function public.fn_trade_quote_odds(p_n integer, p_rate numeric, p_k integer default 3)
returns numeric language sql immutable security definer set search_path to 'public', 'pg_temp' as $fn$
  select round(1 - coalesce(sum((factorial(p_n) / (factorial(j) * factorial(p_n - j))) * power(p_rate, j) * power(1 - p_rate, p_n - j)), 0), 4)
    from generate_series(0, least(p_k - 1, p_n)) j
$fn$;
revoke execute on function public.fn_trade_quote_odds(integer, numeric, integer) from public, anon, authenticated;
grant execute on function public.fn_trade_quote_odds(integer, numeric, integer) to service_role;

-- WEEKLY (ceo.trade_opening_tune): the CEO's own call, inside the floor. Measured quote rate over 90 days of real requests
-- (inquiry_matches = invitations to quote, quotes = answers); under 30 invitations nothing moves.
create or replace function public.fn_ceo_trade_opening_tune(p_at timestamptz default now())
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_inv int; v_q int; v_p numeric; v_n int; r public.trade_opening_rule;
begin
  select * into r from public.trade_opening_rule where id = 1;
  select count(*), count(*) filter (where exists (select 1 from public.quotes q where q.inquiry_id = m.inquiry_id and q.supplier_id = m.supplier_id))
    into v_inv, v_q
    from public.inquiry_matches m
   where m.sent_at > p_at - interval '90 days' and not public.fn_inquiry_is_demo(m.inquiry_id);
  if v_inv < 30 then
    return jsonb_build_object('changed', false, 'open_at', r.open_at_suppliers, 'invitations', v_inv, 'why', 'fewer than 30 invitations to quote in 90 days: the rate is not measurable yet');
  end if;
  v_p := round(v_q::numeric / v_inv, 4);
  select min(n) into v_n from generate_series(5, 25) n where public.fn_trade_quote_odds(n, greatest(v_p, 0.0001)) >= 0.80;
  v_n := coalesce(v_n, 25);
  update public.trade_opening_rule set measured_quote_rate = v_p, measured_invitations = v_inv,
    open_at_suppliers = v_n, set_by = 'ceo', updated_at = now(),
    reason = format('CEO %s: measured quote rate %s (%s of %s invitations, 90 days); %s suppliers give P(>=3 quotes) %s', (p_at at time zone 'Asia/Dubai')::date, v_p, v_q, v_inv, v_n, public.fn_trade_quote_odds(v_n, greatest(v_p, 0.0001)))
   where id = 1 and (open_at_suppliers is distinct from v_n or measured_quote_rate is distinct from v_p);
  return jsonb_build_object('changed', v_n <> r.open_at_suppliers, 'from', r.open_at_suppliers, 'open_at', v_n, 'quote_rate', v_p, 'invitations', v_inv);
end $fn$;
revoke execute on function public.fn_ceo_trade_opening_tune(timestamptz) from public, anon, authenticated;
grant execute on function public.fn_ceo_trade_opening_tune(timestamptz) to service_role;
create or replace function public.fn_ceo_trade_opening_tune_now()
returns jsonb language sql security definer set search_path to 'public', 'pg_temp' as $fn$ select public.fn_ceo_trade_opening_tune(now()) $fn$;
revoke execute on function public.fn_ceo_trade_opening_tune_now() from public, anon, authenticated;
grant execute on function public.fn_ceo_trade_opening_tune_now() to service_role;

-- THE ALL-TRADES GATE IS REPLACED (ledger 1614). The weekly row now records how many trades are OPEN to customers and the
-- ten nearest to opening; 'ready' means at least one trade is open (customers can be served there), never "every trade".
-- The decision column keeps its two words for history: 'january_holds' = a trade is open on the decision day, so the
-- customer launch starts there; 'launch_waits' = none is open yet. No founder mail (ledger 1616: the daily brief only).
create or replace function public.fn_ceo_launch_readiness(p_at timestamptz default now())
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_day date := (p_at at time zone 'Asia/Dubai')::date; v_week date := date_trunc('week', p_at at time zone 'Asia/Dubai')::date;
  v_total int; v_open int; v_gaps jsonb; v_measured timestamptz; v_verdict text; v_decision text; v_decide boolean; v_tick jsonb;
begin
  v_tick := public.fn_ceo_trade_opening_tick();
  select count(*), count(*) filter (where o.is_open), max(o.measured_at) into v_total, v_open, v_measured
    from public.taxonomy_trade t left join public.trade_customer_opening o on o.trade = t.code where t.active;
  select coalesce(jsonb_agg(jsonb_build_object('trade', x.code, 'label', x.label, 'matchable', x.v, 'target', x.open_at) order by x.short, x.code), '[]'::jsonb)
    into v_gaps
    from (select t.code, t.label, coalesce(o.verified_suppliers, 0) v, coalesce(o.open_at, 0) open_at, coalesce(o.open_at, 0) - coalesce(o.verified_suppliers, 0) short
            from public.taxonomy_trade t left join public.trade_customer_opening o on o.trade = t.code
           where t.active and not coalesce(o.is_open, false)
           order by short, t.code limit 10) x;
  v_verdict := case when v_total = 0 or v_measured is null or v_measured < p_at - interval '8 days' then 'not_measurable'
                    when v_open > 0 then 'ready' else 'not_ready' end;
  v_decide := (v_day >= date '2026-12-01' and v_day < date '2027-02-01')
              or (v_day >= date '2027-02-01'
                  and not exists (select 1 from public.ceo_launch_gate g where g.decided_on >= date_trunc('quarter', v_day)::date));
  v_decision := case when not v_decide then null when v_verdict = 'ready' then 'january_holds' else 'launch_waits' end;
  insert into public.ceo_launch_gate (week, trades_total, trades_ready, coverage_pct, widest_gaps, measured_at, verdict, decision, decided_on)
  values (v_week, v_total, v_open, case when v_total > 0 then round(100.0 * v_open / v_total, 1) else 0 end, v_gaps, v_measured, v_verdict, v_decision,
          case when v_decision is not null then v_day end)
  on conflict (week) do update set trades_total = excluded.trades_total, trades_ready = excluded.trades_ready,
    coverage_pct = excluded.coverage_pct, widest_gaps = excluded.widest_gaps, measured_at = excluded.measured_at, verdict = excluded.verdict,
    decision = coalesce(excluded.decision, ceo_launch_gate.decision), decided_on = coalesce(excluded.decided_on, ceo_launch_gate.decided_on);
  return jsonb_build_object('week', v_week, 'trades_total', v_total, 'trades_open', v_open, 'verdict', v_verdict, 'decision', v_decision,
    'rule', 'trade by trade (ledger 1614)', 'tick', v_tick);
end $fn$;
-- CREATE OR REPLACE keeps the routine's ACL; stated again so the file reads as closed on its own
revoke execute on function public.fn_ceo_launch_readiness(timestamptz) from public, anon, authenticated;
grant execute on function public.fn_ceo_launch_readiness(timestamptz) to service_role;

insert into public.seat_duty (duty, owner_seat, every, routine, what, owner_file) values
  ('ceo.trade_opening', 'ceo', interval '1 hour', 'fn_ceo_trade_opening_tick',
   'Every hour, each trade''s verified suppliers: a trade opens to customers at the CEO''s threshold and closes only under the floor of 5; every waiting customer of a trade that opened is told (ledger 1614).',
   'scripts/sql/a_trade_opens_to_customers_as_soon_as_it_has_enough_verified_suppliers.sql'),
  ('ceo.trade_opening_tune', 'ceo', interval '7 days', 'fn_ceo_trade_opening_tune_now',
   'Every week, the opening threshold from the measured quote rate: the fewest suppliers (5 to 25) that give a request an 80% chance of 3 quotes; unchanged under 30 invitations.',
   'scripts/sql/a_trade_opens_to_customers_as_soon_as_it_has_enough_verified_suppliers.sql'),
  ('ceo.launch_readiness', 'ceo', interval '7 days', 'fn_ceo_launch_readiness_now',
   'Every week, the trades open to customers (ledger 1614: trade by trade, never "every trade") and the ten nearest to opening; from 1 Dec 2026 and each quarter, whether the customer launch has started somewhere. The founder reads it in his daily brief.',
   'scripts/sql/a_trade_opens_to_customers_as_soon_as_it_has_enough_verified_suppliers.sql')
on conflict (duty) do update set every = excluded.every, routine = excluded.routine, what = excluded.what, owner_file = excluded.owner_file;
