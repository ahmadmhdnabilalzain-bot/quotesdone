-- A SUPPLIER WHO LIMITS ITS EMIRATES IS MATCHED ONLY THERE. National is the default.
-- Seat: sales_engineer. 21 Sep 2026. Audit of 21 Sep 2026, finding 25.
--
-- MEASURED (read-only, 21 Sep 2026, project htdblwldjkcgjvmqkbeh):
--   * Lead 126512 "ZZ DEMO Interiors gypsum founderdemo": leads.service_emirates = {Dubai, Abu Dhabi},
--     supplier_capabilities.coverage_emirates = {Dubai}, trades {gypsum, painting}, confirmed.
--   * A Sharjah painting inquiry (a179ea8d…, rfq_no 151769) reached it. The supplier Profile copy says
--     the emirates a supplier selects decide what reaches it. It did not.
--   * The live fn_match_capability is the 9-argument one from
--     scripts/sql/a_supplier_describes_its_services_in_its_own_words_and_the_sales_engineer_rewrites_them.sql
--     (MANIFEST line 1462 -- NOT every_uae_supplier_is_matched_across_the_whole_country.sql at line 1358,
--     which the brief named; that one is the 8-argument body the 18 Sep file DROPPED and re-created with
--     p_services). Its location logic is a TIE-BREAK only (`in_emirate` orders equal scores).
--
-- WRONG, twice:
--   (a) scripts/e2e/founder_demo_tour.mjs wrote inquiry_matches directly ("founder demo: direct
--       invitation") for jobs in Abu Dhabi and Sharjah, never asking the matcher. Fixed in that file.
--   (b) The matcher itself: a real Sharjah request would also reach a supplier who said "Dubai only".
--
-- THE TWO RULINGS, reconciled here:
--   9 Sep 2026:  "we can get the emirate from the trade license. and ALL UAE SUPPLIERS COVER ALL EMIRATES."
--                Read as the DEFAULT in a_uae_supplier_covers_the_whole_country_unless_it_says_otherwise.sql:
--                "A supplier who HAS stated coverage and does not list the emirate asked for is still
--                excluded -- they limited themselves and that limit is honoured."
--   14 Sep 2026: "and its not only the customer emirate. all suppliers in UAE do full coverage of UAE."
--                Applied in every_uae_supplier_is_matched_across_the_whole_country.sql as: no gate at all.
--   Decision: national BY DEFAULT (a supplier who stated nothing is matched everywhere); a supplier who
--   EXPLICITLY limited itself is matched only inside its stated emirates. The 14 Sep words describe the
--   market default; the Profile page promises the limit is honoured; both hold at once this way.
--
-- CHANGES (only the location logic; every other gate, the scoring and the ordering are byte-for-byte):
--   1. stated := the distinct non-empty union of sc.coverage_emirates and leads.service_emirates.
--   2. GATE: p_emirate is null, or stated is empty, or p_emirate is in stated (ilike).
--   3. in_emirate stays the tie-break. `why` says 'in <emirate>' or 'UAE-wide (no stated limit)'.
--   Signature, defaults, return type, language, volatility and search_path are copied from the 1462
--   file, so CREATE OR REPLACE keeps the existing ACL (revoked from public/anon/authenticated there);
--   no revoke is repeated here. leads.emirate / license_city are no longer a location claim: a scraped
--   HQ emirate is not a coverage statement, and the 9 Sep file's own counts show license_city is 0 populated.
--
-- NOT CHANGED: match_suppliers_kw. It is the retired keyword path (customer_api's fallback), reads
-- leads.emirate only, and never decided an invitation; it stays as the every_uae file left it.
--
--   node scripts/apply_sql.mjs scripts/sql/a_supplier_who_limits_its_emirates_is_matched_only_there.sql --apply

begin;

create or replace function public.fn_match_capability(
  p_trades text[],
  p_need text default 'executes'::text,
  p_products text[] default '{}'::text[],
  p_brands text[] default '{}'::text[],
  p_project_type text default null::text,
  p_value numeric default null::numeric,
  p_emirate text default null::text,
  p_limit integer default 12,
  p_services text[] default '{}'::text[]
)
 returns table(supplier_id bigint, company_name text, score numeric, trades text[], roles text[],
               product_hits integer, brand_hit boolean, ptype_hit boolean, track numeric, why text,
               service_hits text[], via_implication text[])
 language sql
 stable
 set search_path to 'public', 'pg_temp'
as $function$
with w as (
  select coalesce((select value::text::numeric from decision_policy where key='score_w_product'),40)      as w_prod,
         coalesce((select value::text::numeric from decision_policy where key='score_w_brand'),20)        as w_brand,
         coalesce((select value::text::numeric from decision_policy where key='score_w_project_type'),15) as w_ptype,
         coalesce((select value::text::numeric from decision_policy where key='score_w_track_record'),15) as w_track,
         coalesce((select value::text::numeric from decision_policy where key='score_w_size_fit'),10)     as w_size
),
req_auth as (
  select coalesce(array_agg(distinct a),'{}') as codes
  from public.taxonomy_trade t, unnest(t.authority_required) a
  where t.code = any(p_trades)
),
-- LOCATION. What the supplier itself STATED: the confirmed capability's coverage list and the
-- registration's service_emirates, as one distinct list with blanks dropped. Empty = no self-imposed
-- limit = the whole UAE (founder, 9 and 14 Sep 2026). Non-empty = the limit is honoured (finding 25).
loc as (
  select sc.supplier_id,
         array(select distinct e from unnest(coalesce(sc.coverage_emirates, '{}'::text[])
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
         least(1, greatest(0, coalesce(sp.quote_rate, sp.perf_score, 0))) as track,
         -- TIE-BREAK between equal scores: the job's emirate is one the supplier named.
         (p_emirate is not null and exists (select 1 from unnest(loc.stated) e where e ilike p_emirate)) as in_emirate,
         cardinality(loc.stated) as stated_n
  from public.supplier_capabilities sc
  join public.leads l on l.id = sc.supplier_id
  join loc on loc.supplier_id = sc.supplier_id
  left join public.supplier_perf sp on sp.supplier_id = sc.supplier_id
  where sc.confirmed_at is not null                        -- GATE: supplier confirmed their own scope
    and sc.trades && p_trades                              -- GATE: trade intersection
    and not (sc.excluded_trades && p_trades)               -- GATE: declared negative scope
    and public.fn_is_matchable(l.verified, l.banned, l.matching_blocked,
                               l.approval_status, l.permanently_closed, l.chat_strikes)
    and exists (                                            -- GATE: role can actually do this kind of work
      select 1 from public.taxonomy_role r
      where r.code = any(sc.roles)
        and case p_need when 'supplies'    then r.supplies
                        when 'whole_scope' then r.whole_scope
                        else r.executes end
    )
    and not exists (                                        -- GATE: every mandatory authority held
      select 1 from unnest((select codes from req_auth)) a
      where not (sc.authority_approvals ? a)
    )
    and (p_value is null or (                               -- GATE: job size inside their range
          (sc.min_project_value is null or p_value >= sc.min_project_value)
      and (sc.max_project_value is null or p_value <= sc.max_project_value)))
    and (p_emirate is null                                  -- GATE: a stated limit is honoured; none = UAE-wide
      or cardinality(loc.stated) = 0
      or exists (select 1 from unnest(loc.stated) e where e ilike p_emirate))
),
-- GATE: the services the inquiry names, at SERVICE level. Stated + one level of the curated
-- implication map - what the supplier removed. Empty p_services leaves every candidate through.
--
-- ONE DEFINITION OF COVERAGE. eff_services is computed once per candidate by fn_services_effective,
-- and BOTH the hit list and the attribution are derived from it. An earlier draft re-derived the
-- attribution from c.services directly (database review, 18 Sep 2026): a service code the supplier
-- still stores but taxonomy_trade_service no longer marks active was rejected by fn_services_effective
-- and accepted by the attribution, so `why` could name a curated rule that never actually fired.
eff as (
  select c.*,
         case when cardinality(p_services) = 0 then '{}'::text[]
              else public.fn_services_effective(c.services, c.trades, c.services_removed) end as eff_services
  from cand c
),
svc as (
  select e.*,
    array(select unnest(e.eff_services) intersect select unnest(p_services)) as service_hits,
    -- ponytail: one scan of service_implication per candidate. At 113 curated rows against a
    -- candidate set the gates above have already cut down, this is not measurable; batch it with a
    -- single unnest+join if the map or the candidate count grows an order of magnitude.
    array(
      select distinct i.from_code || ' -> ' || i.implies_trade || '.' || i.implies_code
      from public.service_implication i
      where i.active
        and (i.implies_trade || '.' || i.implies_code) = any(e.eff_services)   -- it really is covered
        and (i.implies_trade || '.' || i.implies_code) = any(p_services)       -- and the inquiry asked
        and not ((i.implies_trade || '.' || i.implies_code) = any(coalesce(e.services, '{}'::text[])))
        and (i.from_code = any(coalesce(e.trades, '{}'::text[]))
          or i.from_code = any(coalesce(e.services, '{}'::text[])))
      order by 1) as via_implication
  from eff e
),
scored as (
  select c.*,
    (select count(distinct pq) from unnest(p_products) pq
      where exists (select 1 from unnest(c.products_norm) pp
                    where pp ilike '%'||pq||'%' or pq ilike '%'||pp||'%'))::int as product_hits,
    (cardinality(p_brands) > 0 and exists (
       select 1 from unnest(p_brands) bq join unnest(c.brands) bb on bb ilike '%'||bq||'%' or bq ilike '%'||bb||'%'
     )) as brand_hit,
    (p_project_type is not null and exists (
       select 1 from unnest(c.project_types) pt
       where pt ilike '%'||p_project_type||'%' or p_project_type ilike '%'||pt||'%'
     )) as ptype_hit,
    (p_value is not null and c.min_project_value is not null and c.max_project_value is not null) as size_known
  from svc c
  where cardinality(p_services) = 0 or cardinality(c.service_hits) > 0
),
ranked as (
  select s.*,
    round(
        w.w_prod  * (case when cardinality(p_products) > 0
                          then s.product_hits::numeric / cardinality(p_products) else 0 end)
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
    case when cardinality(r.service_hits) > 0 then cardinality(r.service_hits)||'/'||cardinality(p_services)||' services' end,
    case when cardinality(r.via_implication) > 0 then 'implied: ' || array_to_string(r.via_implication, ', ') end,
    case when r.product_hits > 0 then r.product_hits||'/'||cardinality(p_products)||' products' end,
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

comment on function public.fn_match_capability(text[], text, text[], text[], text, numeric, text, integer, text[]) is
  'The structured matcher. Gates: confirmed scope, trade intersection, negative scope, matchability, role, mandatory authority, job value, a stated emirate limit (coverage_emirates + service_emirates; empty = UAE-wide, founder 9/14 Sep 2026), and -- when the inquiry names services -- service coverage through fn_services_effective. service_hits and via_implication say which services matched and which curated implication rule produced each one the supplier did not state itself. Exact codes only; no nearest, no fuzzy (founder, 14 Sep 2026).';

commit;
