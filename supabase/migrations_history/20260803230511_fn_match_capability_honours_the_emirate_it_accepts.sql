-- fn_match_capability accepted p_emirate and never referenced it. Every other parameter in this
-- function is a GATE - confirmed scope, trade intersection, declared negative scope, matchability,
-- role capability, mandatory authorities, job size - and the emirate silently was not one, so a
-- Dubai customer could be matched to a Fujairah-only supplier and the response would carry no hint
-- that geography had been ignored.
--
-- A parameter a function accepts and does not read is worse than one it does not accept: the caller
-- believes a constraint is being applied. Both other matchers do apply it - match_suppliers hard
-- filters on `l.emirate ilike p_emirate`, match_suppliers_kw carries it as a ranking signal - so this
-- was the odd one out rather than a deliberate design.
--
-- WHICH FIELD. supplier_capabilities.coverage_emirates is the supplier's OWN confirmed coverage,
-- which is the right source for a function whose premise is confirmed capability. leads.emirate is
-- accepted as well, because a supplier registered in the emirate plainly serves it.
--
-- UNDECLARED COVERAGE DOES NOT EXCLUDE. An empty coverage_emirates means the supplier has stated no
-- restriction, and this function already treats every other unstated limit that way -
-- min/max_project_value are skipped when null rather than assumed to be zero. Treating silence as
-- "serves nowhere" would empty the marketplace on a field most suppliers have not filled in yet.
--
-- SAFE TO APPLY NOW. supplier_capabilities has 0 rows, so this function returns nothing today
-- regardless. The bug is latent and this closes it before the first registration rather than after.
create or replace function public.fn_match_capability(
  p_trades text[], p_need text default 'executes', p_products text[] default '{}',
  p_brands text[] default '{}', p_project_type text default null, p_value numeric default null,
  p_emirate text default null, p_limit integer default 12)
returns table(supplier_id bigint, company_name text, score numeric, trades text[], roles text[],
              product_hits integer, brand_hit boolean, ptype_hit boolean, track numeric, why text)
language sql stable set search_path to 'public', 'pg_temp'
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
    and (p_emirate is null or                               -- GATE: they cover the emirate asked for
         coalesce(cardinality(sc.coverage_emirates), 0) = 0
      or exists (select 1 from unnest(sc.coverage_emirates) ce where ce ilike p_emirate)
      or l.emirate ilike p_emirate)
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
      case when coalesce(cardinality(s.coverage_emirates),0) = 0 then 'coverage not stated'
           else 'covers ' || p_emirate end end
  ) as why
from scored s, w
order by score desc, s.track desc, s.supplier_id
limit greatest(1, p_limit);
$function$;

do $$
declare n int;
begin
  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'fn_match_capability';
  if n <> 1 then raise exception 'fn_match_capability must have exactly one signature, found %', n; end if;

  -- The invariant: every parameter this function accepts is referenced by its body. A silently
  -- ignored parameter is a constraint the caller believes is being applied and is not.
  if exists (select 1 from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
              where ns.nspname='public' and p.proname='fn_match_capability'
                and p.prosrc not like '%p_emirate%') then
    raise exception 'fn_match_capability still ignores p_emirate';
  end if;
end $$;;
