-- A UAE SUPPLIER COVERS THE WHOLE COUNTRY UNLESS IT SAYS OTHERWISE.
--
-- THIS REVERSES A CHANGE I MADE AN HOUR AGO, and the reversal is the point of the file.
--
-- an_unstated_coverage_area_stops_being_a_pass.sql removed the branch that let a supplier with an
-- empty coverage_emirates match any emirate. The reasoning was the build prompt's rule that
-- "unknown mandatory evidence is not a pass", and it was applied to the wrong kind of fact.
--
-- The founder, 9 Sep 2026: "we can get the emirate from the trade license. and ALL UAE SUPPLIERS
-- COVER ALL EMIRATES."
--
-- That is a fact about this market, and it settles it. An empty coverage list is not a supplier
-- whose coverage is UNKNOWN -- it is a supplier who has not LIMITED themselves. The country is
-- small enough that a contractor in Sharjah quotes Dubai work as a matter of course. So the default
-- is national, and coverage_emirates is a self-imposed RESTRICTION, not a claim requiring evidence.
--
-- The distinction the earlier change missed: "unknown mandatory evidence is not a pass" governs
-- things a supplier must PROVE -- a current licence, a SIRA or Civil Defence approval, a contracted
-- role. Coverage is not proven, it is declared, and its absence has a meaning in this market rather
-- than being a gap. Reading an absent restriction as absent evidence excluded suppliers for failing
-- to state something nobody needs to state.
--
-- Measured before writing this, so the correction rests on numbers rather than on agreement:
--   leads.emirate            21,404 of 22,264 populated
--   coverage_emirates stated 15,268 of 15,305 capability rows
--   license_city             0 populated
--   license_authority        0 populated
--   suppliers matchable      0  (confirmed_at is null on every capability row)
--
-- So no supplier was actually excluded by the earlier change -- the first gate already refuses
-- every row. It would have started excluding them the moment real suppliers arrived, which is
-- precisely when it would have been hardest to notice.
--
-- THE TRADE LICENCE IS THE AUTHORITATIVE SOURCE, AND IT IS WIRED HERE FOR WHEN IT ARRIVES.
-- license_city is read alongside leads.emirate, so once license_extract starts populating it, the
-- emirate a supplier is LICENSED in counts as a stated location without any further change. Both are
-- currently unpopulated for licences and populated for 21,404 scraped emirates, so this widens
-- nothing today and is correct the day it does.
--
-- WHAT REMAINS A REFUSAL. A supplier who HAS stated coverage and does not list the emirate asked for
-- is still excluded -- they limited themselves and that limit is honoured. That was true before both
-- changes and is true now.
--
-- THE EXPLANATION STRING IS CORRECTED TOO. It said 'coverage not stated', which reads as a gap in
-- the record. It now says 'UAE-wide (no stated limit)', which is what the row actually means.
--
--   node scripts/apply_sql.mjs scripts/sql/a_uae_supplier_covers_the_whole_country_unless_it_says_otherwise.sql --apply

begin;

create or replace function public.fn_match_capability(
  p_trades text[],
  p_need text default 'executes'::text,
  p_products text[] default '{}'::text[],
  p_brands text[] default '{}'::text[],
  p_project_type text default null::text,
  p_value numeric default null::numeric,
  p_emirate text default null::text,
  p_limit integer default 12
) returns table(supplier_id bigint, company_name text, score numeric, trades text[], roles text[],
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
         least(1, greatest(0, coalesce(sp.quote_rate, sp.perf_score, 0))) as track
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
    -- GATE: coverage. A UAE supplier covers the whole country unless it says otherwise (founder,
    -- 9 Sep 2026), so an empty coverage_emirates PASSES -- it is an absent restriction, not absent
    -- evidence. A supplier who HAS stated coverage must list the emirate asked for. The emirate on
    -- the lead row and the emirate on the trade licence both count as a stated location; the licence
    -- is the authoritative one and is read here for when license_extract starts populating it.
    and (p_emirate is null
      or coalesce(cardinality(sc.coverage_emirates), 0) = 0
      or exists (select 1 from unnest(sc.coverage_emirates) ce where ce ilike p_emirate)
      or l.emirate ilike p_emirate
      or l.license_city ilike p_emirate)
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
)
select s.supplier_id, s.company_name,
  round(
      w.w_prod  * (case when cardinality(p_products) > 0
                        then s.product_hits::numeric / cardinality(p_products) else 0 end)
    + w.w_brand * (case when s.brand_hit then 1 else 0 end)
    + w.w_ptype * (case when s.ptype_hit then 1 else 0 end)
    + w.w_track * s.track
    + w.w_size  * (case when s.size_known then 1 else 0.5 end)
  , 1) as score,
  s.trades, s.roles, s.product_hits, s.brand_hit, s.ptype_hit, round(s.track,3) as track,
  concat_ws(' · ',
    'trades ' || array_to_string(array(select unnest(s.trades) intersect select unnest(p_trades)), '+'),
    case when s.product_hits > 0 then s.product_hits||'/'||cardinality(p_products)||' products' end,
    case when s.brand_hit then 'brand match' end,
    case when s.ptype_hit then 'project type' end,
    case when p_emirate is not null then
      case when coalesce(cardinality(s.coverage_emirates),0) = 0 then 'UAE-wide (no stated limit)'
           else 'covers ' || p_emirate end end
  ) as why
from scored s, w
order by score desc, s.track desc, s.supplier_id
limit greatest(1, p_limit);
$function$;

commit;
