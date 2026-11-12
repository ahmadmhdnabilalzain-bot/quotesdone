-- A PARTNER SERVICE IS MATCHED KNOWINGLY (12 Nov 2026, sales_engineer; built by it_engineer).
-- Seat: sales_engineer. Founder ruling 1647 ("a decoration company ... pools through a subcontractor"; "if this step is
-- done wrong everything after it goes wrong") and 1628 (matching is code over confirmed keys). Design: analysis
-- services/REPORT.md 3.7, slice 5.
--
-- MEASURED (analysis, 12 hard profiles, 12 Nov 2026): every service a profile said goes through a partner was dropped
-- (22 of 22), because there was nowhere to say it. Slice 4 stores it: supplier_capabilities.services_partner, the subset
-- of his confirmed services he delivers through a partner. Without this file the matcher cannot tell the two apart: a
-- decorator who subcontracts pools would rank beside a pool builder for "build a pool".
--
-- WHAT THIS CHANGES:
--   1. supplier_capabilities.services_partner text[] not null default '{}'. THE SAME COLUMN, SAME DEFINITION, is added by
--      the slice 4 file (the question cards and services_partner storage); `add column if not exists` here makes the two
--      files independent of each other's order (whichever is applied first adds it; the second is a no-op).
--   2. fn_match_capability:
--      * a new output column partner_hits text[]: the named services he holds ONLY through his partner services (a key
--        reached from an own-team service, or by a curated implication of his trade, is his own);
--      * ORDERING: a supplier every one of whose named-service hits is through a partner is ordered after every other
--        supplier the gates admitted (own team first); with p_limit the partner-only ones are the first to drop off;
--      * why: 'through a partner: <keys>'. THAT SEGMENT IS INTERNAL: _shared/partner_match.ts withoutPartnerWhy removes
--        it before a reason is stored in inquiry_matches.match_reason (which a customer reads after reveal) or returned by
--        customer_api discovery (analysis recommendation adopted: the customer is not told a quote uses a partner);
--      * the GATES DO NOT CHANGE: a partner service still admits him (he can take a job whole); a key in services_partner
--        that is not in services is not confirmed and matches nothing; with no service named nothing changes at all.
--      NOBODY IS HELD BACK: every supplier returned is invited (founder ruling of 24 Sep 2026, any number may quote, which
--      outranks the hold-back proposed in REPORT.md 3.7); the partner-only one is simply invited last in this order.
--   3. THE RETURN TYPE CHANGES, so this is DROP + CREATE, not CREATE OR REPLACE (Postgres refuses a changed result
--      row type). CREATE grants EXECUTE to PUBLIC: the revoke below closes it again, and EXECUTE is granted to
--      service_role only, as before. ONE overload exists, fn_match_capability(text[],text,text[],text[],text,numeric,text,
--      integer,text[]) (pg_proc, 12 Nov 2026); the arguments are unchanged, so no overload is left behind. No view or
--      routine depends on it in pg_depend; its two SQL callers (fn_rfq_short_of_quotes_tick, fn_it_engineer_load_test)
--      read named columns or count(*), so a new last column changes nothing for them. Stays SECURITY INVOKER with its
--      search_path pinned. The body is otherwise a_suppliers_own_words_reach_every_customer_who_asks_for_the_same_work.sql's.
--
-- APPLY WITH: node scripts/apply_sql.mjs scripts/sql/a_partner_service_is_matched_knowingly.sql --apply --ddl
--   (--ddl is required: apply_sql.mjs recognises only `create or replace`, so without it this DROP + CREATE file prints
--   "nothing to do", exits 0 and applies nothing; with it the routine read-back is skipped, so the verdict below reads the
--   live routine back itself: partner_hits among its result columns and this version's marker line in its body).
-- LOCKS: the ALTER takes ACCESS EXCLUSIVE on supplier_capabilities. Queued behind a long reader it would block every
--   matcher call (PostgREST roles time out at 8 s), so the file starts with lock_timeout 3 s: it fails fast instead, and is
--   simply applied again.
-- APPLY with no function deploy before it (the callers read partner_hits as absent = none); deploy sales_engineer and
-- customer_api after it so the stored reasons lose the partner segment.
-- prevented by: scripts/sql/a_partner_service_is_matched_knowingly_probe.sql (on production, rolled back, ZZ DEMO only),
--               scripts/checks/a_partner_service_is_matched_knowingly.test.mjs, supabase/functions/_shared/partner_match.test.ts.

set local lock_timeout = '3s';

alter table public.supplier_capabilities add column if not exists services_partner text[] not null default '{}';
comment on column public.supplier_capabilities.services_partner is
  'sales_engineer: the confirmed services (a subset of services) he delivers through a partner, not his own team; matched after own-team suppliers (fn_match_capability partner_hits).';

drop function if exists public.fn_match_capability(text[], text, text[], text[], text, numeric, text, integer, text[]);
create function public.fn_match_capability(p_trades text[], p_need text default 'executes',
  p_products text[] default '{}', p_brands text[] default '{}', p_project_type text default null,
  p_value numeric default null, p_emirate text default null, p_limit integer default 12, p_services text[] default '{}')
returns table(supplier_id bigint, company_name text, score numeric, trades text[], roles text[], product_hits integer,
  brand_hit boolean, ptype_hit boolean, track numeric, why text, service_hits text[], via_implication text[], partner_hits text[])
set search_path to 'public', 'pg_temp'
language sql
stable
as $function$
-- version: a_partner_service_is_matched_knowingly (12 Nov 2026), partner_hits and own team first
with w as (
  select coalesce((select value::text::numeric from decision_policy where key='score_w_product'),40)      as w_prod,
         coalesce((select value::text::numeric from decision_policy where key='score_w_brand'),20)        as w_brand,
         coalesce((select value::text::numeric from decision_policy where key='score_w_project_type'),15) as w_ptype,
         coalesce((select value::text::numeric from decision_policy where key='score_w_track_record'),15) as w_track,
         coalesce((select value::text::numeric from decision_policy where key='score_w_size_fit'),10)     as w_size,
         -- 10 Nov 2026: RANKING ONLY (see the header); absent = 0 = off.
         coalesce((select value::text::numeric from decision_policy where key='score_w_service_similarity'),0) as w_sim
),
-- EXACT (23 Sep 2026, decision point 25): the request's terms and the supplier's, each lower-cased and
-- trimmed, then compared for equality. A substring is not a match: "door" is not "door closer".
q as (
  select array(select distinct lower(btrim(x)) from unnest(coalesce(p_products, '{}'::text[])) x where nullif(btrim(x), '') is not null) as products,
         array(select distinct lower(btrim(x)) from unnest(coalesce(p_brands, '{}'::text[])) x where nullif(btrim(x), '') is not null) as brands,
         nullif(lower(btrim(coalesce(p_project_type, ''))), '') as ptype,
         nullif(lower(btrim(coalesce(p_emirate, ''))), '') as emirate
),
named as (
  select distinct s as key, split_part(s, '.', 1) as tr
  from unnest(coalesce(p_services, '{}'::text[])) s
  where position('.' in s) > 0
    and exists (select 1 from public.taxonomy_trade_service ts
                where ts.active and ts.trade_code || '.' || ts.code = s)
),
n as (select count(*)::int as k from named),
-- THE REACH (10 Nov 2026, founder ledger 1573/1579/1586). With no service named it is the request's trades, exactly as
-- before. With a service named it adds the trade that service belongs to (a code the request itself named) and the
-- curated adjacent trades of either (public.taxonomy_trade_adjacent), ONE level: an adjacent trade's own neighbours are
-- not followed. A supplier found only through the reach must hold a named service (scored, below).
asked as (
  select distinct t from (select unnest(coalesce(p_trades, '{}'::text[])) as t union select tr from named) x where t is not null
),
reach as (
  select coalesce(array_agg(distinct c), '{}'::text[]) as codes from (
    select t as c from asked
    union
    select case when j.a_code = a.t then j.b_code else j.a_code end
      from asked a join public.taxonomy_trade_adjacent j on j.active and (j.a_code = a.t or j.b_code = a.t)
     where (select k from n) > 0
  ) r
),
req_auth as (
  select coalesce(array_agg(distinct a),'{}') as codes
  from public.taxonomy_trade t, unnest(t.authority_required) a
  where t.code = any(p_trades) or t.code in (select tr from named)
),
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
         -- 12 Nov 2026: the services he does THROUGH A PARTNER (a subset of services; a key here that is not in
         -- services is not confirmed and matches nothing).
         coalesce(sc.services_partner, '{}'::text[]) as services_partner,
         l.company_name, l.emirate as lead_emirate,
         -- 23 Sep 2026 (sales_engineer.supplier_performance): the measured score comes first; the view's quote rate
         -- and perf_score remain the fallback for a supplier the platform has not measured yet.
         least(1, greatest(0, coalesce(pf.score, sp.quote_rate, sp.perf_score, 0))) as track,
         ((select emirate from q) is not null and (select emirate from q) = any(loc.stated)) as in_emirate,
         cardinality(loc.stated) as stated_n,
         -- the request's own trade (the trade-level pass applies to these only)
         coalesce(sc.trades && p_trades, false) as direct
  from public.supplier_capabilities sc
  join public.leads l on l.id = sc.supplier_id
  join loc on loc.supplier_id = sc.supplier_id
  left join public.supplier_perf sp on sp.supplier_id = sc.supplier_id
  left join public.supplier_performance pf on pf.lead_id = sc.supplier_id
  left join public.supplier_availability av on av.supplier_id = sc.supplier_id
  where sc.confirmed_at is not null
    and sc.trades && (select codes from reach)
    and not (sc.excluded_trades && p_trades)
    and not (sc.excluded_trades && array(select tr from named))
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
              else public.fn_services_effective(c.services, c.trades, c.services_removed) end as eff_services,
         -- the same, from what he does with his own team only (his services minus his partner services)
         case when (select k from n) = 0 or cardinality(c.services_partner) = 0 then null::text[]
              else public.fn_services_effective(array(select unnest(coalesce(c.services, '{}'::text[])) except select unnest(c.services_partner)),
                                                c.trades, c.services_removed) end as own_services
  from cand c
),
svc as (
  select e.*,
    array(select unnest(e.eff_services) intersect select key from named) as service_hits,
    -- THROUGH A PARTNER (12 Nov 2026, services/REPORT.md 3.7): a named service he holds only through his partner services.
    case when e.own_services is null then '{}'::text[]
         else array(select unnest(e.eff_services) intersect select key from named except select unnest(e.own_services) order by 1) end as partner_hits,
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
    (p_value is not null and c.min_project_value is not null and c.max_project_value is not null) as size_known,
    -- THE SIMILARITY SIGNAL (ranking only): the best cosine between a named service and a service this supplier stated,
    -- over the stored gte-small vectors. 1 for an exact hit; 0 when either side has no vector or the weight is 0.
    case when (select k from n) = 0 or (select w_sim from w) = 0 then 0::numeric else coalesce((
      select max(greatest(0, least(1, 1 - (a.embedding_gte <=> b.embedding_gte))))::numeric
        from public.taxonomy_trade_service a
        join named nm on a.trade_code || '.' || a.code = nm.key
        join public.taxonomy_trade_service b on b.active and b.trade_code || '.' || b.code = any(coalesce(c.services, '{}'::text[]))
       where a.embedding_gte is not null and b.embedding_gte is not null), 0) end as sim
  from svc c
  -- THE GATE. A supplier of the request's own trades passes at trade level when the request names no service of his
  -- trades (founder 857); one reached only through a named service's trade or an adjacent trade must hold a named
  -- service. The similarity above is computed for those already through and decides nothing here.
  where (select k from n) = 0
     or cardinality(c.service_hits) > 0
     or (c.never_asked and c.direct)
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
      + w.w_sim   * s.sim
    , 1) as score_v
  from scored s, w
)
select r.supplier_id, r.company_name, r.score_v as score,
  r.trades, r.roles, r.product_hits, r.brand_hit, r.ptype_hit, round(r.track,3) as track,
  concat_ws(' · ',
    case when r.direct then 'trades ' || array_to_string(array(select unnest(r.trades) intersect select unnest(p_trades)), '+') end,
    case when not r.direct then 'reached through '
      || array_to_string(array(select unnest(r.trades) intersect select unnest((select codes from reach))), '+')
      || ' (the named service''s trade or a curated adjacent trade)' end,
    case when cardinality(r.service_hits) > 0 then cardinality(r.service_hits)||'/'||(select k from n)||' services' end,
    case when (select k from n) > 0 and r.never_asked and cardinality(r.service_hits) = 0
           then 'trade level (no service named in this supplier''s trades)' end,
    case when cardinality(r.via_implication) > 0 then 'implied: ' || array_to_string(r.via_implication, ', ') end,
    -- internal only: _shared/partner_match.ts withoutPartnerWhy strips this segment before a reason is stored or shown
    case when cardinality(r.partner_hits) > 0 then 'through a partner: ' || array_to_string(r.partner_hits, ', ') end,
    case when r.product_hits > 0 then r.product_hits||'/'||cardinality((select products from q))||' products' end,
    case when r.brand_hit then 'brand match' end,
    case when r.ptype_hit then 'project type' end,
    case when r.sim > 0 and r.sim < 1 then 'service similarity ' || round(r.sim, 2) end,
    case when p_emirate is not null then
      case when r.in_emirate then 'in ' || p_emirate else 'UAE-wide (no stated limit)' end end
  ) as why,
  r.service_hits, r.via_implication, r.partner_hits
from ranked r
-- OWN TEAM FIRST: a supplier every one of whose named-service hits is through a partner ranks after every other
order by (cardinality(r.service_hits) > 0 and cardinality(r.partner_hits) = cardinality(r.service_hits)), r.score_v desc, cardinality(r.service_hits) desc, r.in_emirate desc, r.track desc, r.supplier_id
limit greatest(1, p_limit);
$function$;
revoke execute on function public.fn_match_capability(text[], text, text[], text[], text, numeric, text, integer, text[]) from public, anon, authenticated;
grant execute on function public.fn_match_capability(text[], text, text[], text[], text, numeric, text, integer, text[]) to service_role;

-- Verdict row (DDL file, so no raise): the column, the new output column, one overload, closed to the public roles.
select case
  when exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'supplier_capabilities'
                 and column_name = 'services_partner' and is_nullable = 'NO')
   and (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'fn_match_capability') = 1
   and (select 'partner_hits' = any(proargnames) from pg_proc where oid = 'public.fn_match_capability(text[],text,text[],text[],text,numeric,text,integer,text[])'::regprocedure)
   and position('-- version: a_partner_service_is_matched_knowingly (12 Nov 2026)' in
         (select prosrc from pg_proc where oid = 'public.fn_match_capability(text[],text,text[],text[],text,numeric,text,integer,text[])'::regprocedure)) > 0
   and not has_function_privilege('anon', 'public.fn_match_capability(text[],text,text[],text[],text,numeric,text,integer,text[])', 'execute')
   and not has_function_privilege('authenticated', 'public.fn_match_capability(text[],text,text[],text[],text,numeric,text,integer,text[])', 'execute')
   and has_function_privilege('service_role', 'public.fn_match_capability(text[],text,text[],text[],text,numeric,text,integer,text[])', 'execute')
  then 'PROBE OK fn_match_capability returns partner_hits, orders own team first and is closed to the public roles'
  else 'PROBE FAILED: the partner column, the output column, the overload count or a grant is wrong' end as verdict;
