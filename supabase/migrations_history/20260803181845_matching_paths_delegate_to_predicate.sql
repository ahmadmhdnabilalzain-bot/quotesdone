-- AUDIT §3 part 2. The three matching paths now delegate to fn_is_matchable and contain no
-- eligibility logic of their own. Scope logic (trades, authorities, keywords, embeddings, project
-- size) stays where it belongs — that is what each path is FOR. Eligibility is not.

-- ---------------------------------------------------------------------------------------------
-- Vector path. Was the only path with a non-empty pool (516) and the most permissive gate: it
-- checked neither banned nor verified nor permanently_closed, so the first customer enquiry would
-- have been answered with scraped businesses that never signed up.
-- Ranking bonuses for `claimed` and approval_status='approved' are removed: both are implied by
-- `verified`, so across a uniformly verified pool they were constants adding 0.05 to every row.
CREATE OR REPLACE FUNCTION public.match_suppliers(query_embedding vector, match_count integer DEFAULT 10, p_emirate text DEFAULT NULL::text, p_role text DEFAULT NULL::text, p_product text DEFAULT NULL::text, p_min_rating numeric DEFAULT NULL::numeric)
 RETURNS TABLE(id bigint, company_name text, emirate text, business_role text, products text, services text, phone text, email text, whatsapp text, website text, rating numeric, reviews integer, capability_summary text, similarity double precision)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select l.id, l.company_name, l.emirate, l.business_role, l.products, l.services,
         l.phone, l.email, l.whatsapp, l.website, l.rating, l.reviews, l.capability_summary,
         1 - (l.embedding_gte <=> query_embedding) as similarity
  from public.leads l
  left join public.supplier_perf sp on sp.supplier_id = l.id
  where l.embedding_gte is not null
    and public.fn_is_matchable(l.verified, l.banned, l.matching_blocked,
                               l.approval_status, l.permanently_closed, l.chat_strikes)
    and (p_emirate is null or l.emirate ilike p_emirate)
    and (p_role    is null or l.business_role = p_role)
    and (p_product is null or l.products ilike '%'||p_product||'%' or l.capability_summary ilike '%'||p_product||'%')
    and (p_min_rating is null or l.rating >= p_min_rating)
  order by ( (1 - (l.embedding_gte <=> query_embedding))
             + 0.05 * coalesce(sp.perf_score,0) ) desc
  limit match_count;
$function$;

-- ---------------------------------------------------------------------------------------------
-- Keyword path. Two changes beyond delegation:
--   * the registration clause (registration_submitted_at is not null or source='self_registered'
--     or approval_status='approved') is removed. It was a fourth, private definition of "is this a
--     real supplier", and `verified` subsumes it — you cannot be verified without having registered
--     and been approved. It was also the reason this path's pool was 0.
--   * the `+2 if verified` scoring bonus is removed. Verification is now a gate, so the bonus was
--     about to become a constant added to every row. A ranking signal that never varies is not a
--     ranking signal. THIS was the trap: `verified` appeared in this function and looked like
--     enforcement, and it was arithmetic.
CREATE OR REPLACE FUNCTION public.match_suppliers_kw(p_keywords text[] DEFAULT '{}'::text[], p_category text DEFAULT NULL::text, p_emirate text DEFAULT NULL::text, p_role text DEFAULT NULL::text, p_min_rating numeric DEFAULT NULL::numeric, p_limit integer DEFAULT 8, p_multi boolean DEFAULT false)
 RETURNS TABLE(id bigint, company_name text, emirate text, business_role text, products text, services text, phone text, email text, whatsapp text, website text, rating numeric, reviews integer, capability_summary text, match_score integer, in_emirate boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with base as (
    select l.id, l.company_name, l.emirate, l.business_role, l.products, l.services,
           l.phone, l.email, l.whatsapp, l.website, l.rating, l.reviews, l.capability_summary,
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
      and (p_min_rating is null or l.rating>=p_min_rating)
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
  order by in_emirate desc, match_score desc, rating desc nulls last, reviews desc nulls last
  limit coalesce(p_limit,8);
$function$;

-- ---------------------------------------------------------------------------------------------
-- Capability path. Eligibility gates replaced by the predicate; the approval_status='approved'
-- check it used (stricter than the other three) is subsumed — verified implies approved, and the
-- predicate additionally rejects a supplier whose documents have since expired into
-- 'action_required', which '=approved' would have caught but banned/blocked alone would not.
-- Scope gates are untouched.
CREATE OR REPLACE FUNCTION public.fn_match_capability(p_trades text[], p_need text DEFAULT 'executes'::text, p_products text[] DEFAULT '{}'::text[], p_brands text[] DEFAULT '{}'::text[], p_project_type text DEFAULT NULL::text, p_value numeric DEFAULT NULL::numeric, p_emirate text DEFAULT NULL::text, p_limit integer DEFAULT 12)
 RETURNS TABLE(supplier_id bigint, company_name text, score numeric, trades text[], roles text[], product_hits integer, brand_hit boolean, ptype_hit boolean, track numeric, why text)
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
with w as (
  select coalesce((select value::text::numeric from decision_policy where key='score_w_product'),40)      as w_prod,
         coalesce((select value::text::numeric from decision_policy where key='score_w_brand'),20)        as w_brand,
         coalesce((select value::text::numeric from decision_policy where key='score_w_project_type'),15) as w_ptype,
         coalesce((select value::text::numeric from decision_policy where key='score_w_track_record'),15) as w_track,
         coalesce((select value::text::numeric from decision_policy where key='score_w_size_fit'),10)     as w_size
),
req_auth as (   -- authorities legally mandated by the requested trades
  select coalesce(array_agg(distinct a),'{}') as codes
  from public.taxonomy_trade t, unnest(t.authority_required) a
  where t.code = any(p_trades)
),
cand as (
  select sc.supplier_id, sc.trades, sc.roles, sc.products_norm, sc.brands, sc.project_types,
         sc.min_project_value, sc.max_project_value,
         l.company_name,
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
    + w.w_size  * (case when s.size_known then 1 else 0.5 end)   -- unknown range is neutral, not punished
  , 1) as score,
  s.trades, s.roles, s.product_hits, s.brand_hit, s.ptype_hit, round(s.track,3) as track,
  concat_ws(' · ',
    'trades ' || array_to_string(array(select unnest(s.trades) intersect select unnest(p_trades)), '+'),
    case when s.product_hits > 0 then s.product_hits||'/'||cardinality(p_products)||' products' end,
    case when s.brand_hit then 'brand match' end,
    case when s.ptype_hit then 'project type' end
  ) as why
from scored s, w
order by score desc, s.track desc, s.supplier_id
limit greatest(1, p_limit);
$function$;;
