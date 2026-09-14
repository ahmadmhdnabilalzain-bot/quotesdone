-- EVERY UAE SUPPLIER IS MATCHED ACROSS THE WHOLE COUNTRY.
--
-- Founder, 14 Sep 2026: "and its not only the customer emirate. all suppliers in UAE do full coverage
-- of UAE." The customer's emirate stays a fact about the job. It stops deciding who is invited.
--
-- WHAT WAS MEASURED (read-only, 14 Sep 2026, project htdblwldjkcgjvmqkbeh):
--
--   fn_match_capability, the matcher that dispatch (sales_engineer `match`), inquiry_intake's
--   supplier count, public_site route_brief and customer_api discover all call, carried a HARD gate:
--
--     and (p_emirate is null
--       or coalesce(cardinality(sc.coverage_emirates), 0) = 0
--       or exists (select 1 from unnest(sc.coverage_emirates) ce where ce ilike p_emirate)
--       or l.emirate ilike p_emirate
--       or l.license_city ilike p_emirate)
--
--   A supplier who had stated any coverage list, or whose lead row named another emirate, was
--   dropped before ranking. Counted over supplier_capabilities, applying only this gate and the trade:
--
--     trade        emirate   passes the gate today   passes with no emirate gate
--     electrical   Dubai      615                    1194
--     electrical   Sharjah    204                    1194
--     hvac         Dubai      316                     492
--     hvac         Sharjah     51                     492
--     plumbing     Dubai      234                     487
--     plumbing     Sharjah    101                     487
--
--   The live, fully gated count is 0 before and 0 after for all six, because 0 of 15,305 capability
--   rows have confirmed_at set and fn_is_matchable passes no lead yet. The change is made now, before
--   the first confirmed scope arrives, so that Sharjah requests are not quietly shown a quarter of
--   the electrical suppliers that Dubai requests see.
--
--   match_suppliers_kw (customer_api's keyword fallback) never excluded on emirate, but it sorted
--   `in_emirate desc` BEFORE match_score, so with p_limit 8 an in-emirate supplier with one keyword
--   hit outranked an out-of-emirate supplier with six. That is an exclusion in practice at a cap of 8.
--
-- WHAT CHANGES:
--   1. fn_match_capability: the coverage gate is removed. Being in the job's emirate (stated
--      coverage, lead emirate or licence city) becomes a tie-break after the score, before the track
--      record. The `why` string says 'in <emirate>' or 'UAE-wide'. Signature, defaults, return type,
--      volatility and search_path are reproduced from pg_get_functiondef, so CREATE OR REPLACE keeps
--      the existing ACL.
--   2. match_suppliers_kw: ORDER BY puts match_score first and in_emirate second. Nothing else moves.
--
-- NOT CHANGED, and why: fn_supplier_opportunities scores location as 30 of a supplier's fit points
-- and fn_customer_decision_support counts `suppliers_covering` through coverage_emirates. Neither
-- decides who is invited; both are reported alongside this file as the next place the rule lands.
--
--   node scripts/apply_sql.mjs scripts/sql/every_uae_supplier_is_matched_across_the_whole_country.sql --apply --ddl

begin;

create or replace function public.fn_match_capability(
  p_trades text[],
  p_need text default 'executes'::text,
  p_products text[] default '{}'::text[],
  p_brands text[] default '{}'::text[],
  p_project_type text default null::text,
  p_value numeric default null::numeric,
  p_emirate text default null::text,
  p_limit integer default 12)
returns table(supplier_id bigint, company_name text, score numeric, trades text[], roles text[],
              product_hits integer, brand_hit boolean, ptype_hit boolean, track numeric, why text)
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
cand as (
  select sc.supplier_id, sc.trades, sc.roles, sc.products_norm, sc.brands, sc.project_types,
         sc.min_project_value, sc.max_project_value, sc.coverage_emirates,
         l.company_name, l.emirate as lead_emirate,
         least(1, greatest(0, coalesce(sp.quote_rate, sp.perf_score, 0))) as track,
         -- TIE-BREAK ONLY. Every UAE supplier covers the whole country (founder, 14 Sep 2026), so the
         -- job's emirate never removes a candidate; it only orders two equal scores.
         (p_emirate is not null and (
              exists (select 1 from unnest(sc.coverage_emirates) ce where ce ilike p_emirate)
           or l.emirate ilike p_emirate
           or l.license_city ilike p_emirate)) as in_emirate
  from public.supplier_capabilities sc
  join public.leads l on l.id = sc.supplier_id
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
  from cand c
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
    case when r.product_hits > 0 then r.product_hits||'/'||cardinality(p_products)||' products' end,
    case when r.brand_hit then 'brand match' end,
    case when r.ptype_hit then 'project type' end,
    case when p_emirate is not null then
      case when r.in_emirate then 'in ' || p_emirate else 'UAE-wide' end end
  ) as why
from ranked r
order by r.score_v desc, r.in_emirate desc, r.track desc, r.supplier_id
limit greatest(1, p_limit);
$function$;

create or replace function public.match_suppliers_kw(
  p_keywords text[] default '{}'::text[],
  p_category text default null::text,
  p_emirate text default null::text,
  p_role text default null::text,
  p_min_rating numeric default null::numeric,
  p_limit integer default 8,
  p_multi boolean default false)
returns table(id bigint, company_name text, emirate text, business_role text, products text, services text,
              phone text, email text, whatsapp text, website text, rating numeric, reviews integer,
              capability_summary text, match_score integer, in_emirate boolean)
language sql
stable
set search_path to 'public', 'pg_temp'
as $function$
  with base as (
    select l.id, l.company_name, l.emirate, l.business_role, l.products, l.services,
           l.phone, l.email, l.whatsapp, l.website, l.app_rating as rating, l.app_reviews as reviews, l.capability_summary,
           (select count(*) from unnest(p_keywords) k
              where l.products ilike '%'||k||'%' or l.services ilike '%'||k||'%'
                 or l.categories ilike '%'||k||'%' or l.capability_summary ilike '%'||k||'%') as strong_hits,
           (select count(*) from unnest(p_keywords) k where l.company_name ilike '%'||k||'%') as name_hits,
           (p_category is not null and l.sector = p_category) as cat_match,
           (p_multi and (
                 l.sector='fitout'
                 or l.business_role ilike '%turnkey%' or l.business_role ilike '%contract%' or l.business_role ilike '%fit%out%' or l.business_role ilike '%interior%'
                 or l.capability_summary ilike '%turnkey%' or l.capability_summary ilike '%fit-out%' or l.capability_summary ilike '%fit out%' or l.capability_summary ilike '%fitout%' or l.capability_summary ilike '%renovation%' or l.capability_summary ilike '%general contract%' or l.capability_summary ilike '%main contract%'
                 or l.services ilike '%turnkey%' or l.services ilike '%fit-out%' or l.services ilike '%fit out%' or l.services ilike '%renovation%'
               )) as turnkey_match,
           (coalesce(l.app_reviews,0) > 0) as has_app_rev,
           coalesce(p_emirate is not null and l.emirate ilike p_emirate, false) as in_emirate
    from public.leads l
    where public.fn_is_matchable(l.verified, l.banned, l.matching_blocked,
                                 l.approval_status, l.permanently_closed, l.chat_strikes)
      and (p_role is null or l.business_role=p_role)
      and (p_min_rating is null or l.app_rating>=p_min_rating)
      and (
            (p_category is not null and l.sector=p_category)
         or exists (select 1 from unnest(p_keywords) k
              where l.products ilike '%'||k||'%' or l.services ilike '%'||k||'%'
                 or l.categories ilike '%'||k||'%' or l.capability_summary ilike '%'||k||'%' or l.company_name ilike '%'||k||'%')
         or (p_multi and (l.sector='fitout' or l.business_role ilike '%turnkey%' or l.business_role ilike '%contract%' or l.business_role ilike '%interior%' or l.capability_summary ilike '%turnkey%' or l.capability_summary ilike '%fit-out%' or l.capability_summary ilike '%fitout%' or l.capability_summary ilike '%renovation%'))
      )
  )
  select id, company_name, emirate, business_role, products, services, phone, email, whatsapp,
         website, rating, reviews, capability_summary,
         ( least(strong_hits,6)*2 + least(name_hits,2)
           + case when cat_match then 3 else 0 end
           + case when turnkey_match then 5 else 0 end
           + case when has_app_rev then 1 else 0 end )::int as match_score,
         in_emirate
  from base
  where cat_match or strong_hits > 0 or turnkey_match
  -- Fit first. The job's emirate only breaks a tie between equal scores (founder, 14 Sep 2026).
  order by match_score desc, in_emirate desc, rating desc nulls last, reviews desc nulls last
  limit coalesce(p_limit,8);
$function$;

commit;
