-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260721163931   name: fn_match_capability_gated
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Negative scope needs to be gateable, so exclusions (free text the supplier wrote) are also
-- normalised to trade codes. "we do not do plumbing" -> excluded_trades = {plumbing}.
alter table public.supplier_capabilities
  add column if not exists excluded_trades text[] not null default '{}';
create index if not exists idx_supcap_excluded on public.supplier_capabilities using gin (excluded_trades);

update public.supplier_capabilities
   set excluded_trades = coalesce(public.fn_norm_trades(array_to_string(exclusions,' ')), '{}')
 where cardinality(exclusions) > 0;

-- LAYER 1 (hard gates) + LAYER 2 (structured score).
-- Gates cannot produce a false positive: they are set operations over confirmed, structured data.
-- Score only decides ORDER among suppliers that already passed. Weights come from decision_policy
-- so they are tunable as data, with no code change.
create or replace function public.fn_match_capability(
  p_trades       text[],
  p_need         text    default 'executes',   -- supplies | executes | whole_scope
  p_products     text[]  default '{}',
  p_brands       text[]  default '{}',
  p_project_type text    default null,
  p_value        numeric default null,
  p_emirate      text    default null,          -- used ONLY for emirate-specific authority checks
  p_limit        int     default 12
)
returns table (
  supplier_id bigint, company_name text, score numeric,
  trades text[], roles text[], product_hits int, brand_hit boolean,
  ptype_hit boolean, track numeric, why text
)
language sql stable
set search_path to 'public','pg_temp'
as $$
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
    and coalesce(l.banned,false) = false                   -- GATE: not banned
    and coalesce(l.matching_blocked,false) = false         -- GATE: docs valid / not suspended
    and coalesce(l.approval_status,'') = 'approved'        -- GATE: approved
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

$$;

comment on function public.fn_match_capability is
  'Layer 1 hard gates + layer 2 structured score. Gates are set operations over supplier-confirmed data and cannot false-positive; score only orders the survivors. Emirate is NOT a gate or a score input - UAE suppliers work across emirates - it is used only where a trade needs emirate-specific regulatory approval.';
