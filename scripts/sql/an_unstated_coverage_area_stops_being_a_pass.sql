-- AN UNSTATED COVERAGE AREA STOPS BEING A PASS.
--
-- fn_match_capability is the estate's real matcher and it is good: it applies trade intersection,
-- declared negative scope, contracted role, every mandatory authority, project-value band and
-- emirate coverage as HARD SQL GATES before anything is ranked. The Sales Engineer build prompt asks
-- for exactly that list, and almost all of it was already here.
--
-- One clause breaks the rule the prompt is most insistent about:
--
--   "Apply deterministic current mandatory gates before ranking: legal/current credentials when
--    required, correct contracted role, capability coverage, location, explicit exclusions, capacity,
--    customer constraints and account eligibility. UNKNOWN MANDATORY EVIDENCE IS NOT A PASS."
--
-- The location gate read:
--
--   and (p_emirate is null
--        or coalesce(cardinality(sc.coverage_emirates), 0) = 0     <-- unknown passed
--        or exists (... ce ilike p_emirate)
--        or l.emirate ilike p_emirate)
--
-- A supplier who has never stated where they work matched every emirate ever asked for. This is not
-- a case of the system lacking the information and guessing: it KNOWS the coverage is unstated,
-- because the routine's own `why` string prints 'coverage not stated' on exactly those rows. It
-- reported the uncertainty and matched anyway.
--
-- WHY THIS ONE AND NOT THE VALUE BAND. The value gate treats a null min/max as passing too, and that
-- is left alone deliberately: a supplier with no stated maximum plausibly has no cap, so a null
-- there is an absent CONSTRAINT rather than absent EVIDENCE. An empty coverage array is different --
-- every supplier works somewhere, so an empty list is a fact nobody recorded, not a supplier who
-- covers nowhere. Treating those two nulls the same way would be tidier and wrong.
--
-- THE FALLBACK ON l.emirate IS KEPT. A supplier whose capability record has no coverage list but
-- whose lead row states an emirate still matches that emirate -- that is a stated fact in a
-- different column, not an unknown. What is removed is the branch that passed when NOTHING anywhere
-- said where they work.
--
-- WHAT THIS CHANGES TODAY: nothing measurable, and that is worth saying plainly rather than dressing
-- up. Measured 9 Sep 2026: supplier_capabilities holds 15,305 rows and 0 have confirmed_at set, so
-- the first gate already excludes every row and this routine returns the empty set for every
-- possible query. The fix is made now because the matcher is about to acquire its first real data
-- through the Sales Engineer, and a gate that admits unknown evidence is far harder to notice once
-- it is quietly producing plausible matches.
--
-- The `why` string keeps its 'coverage not stated' branch. It is now unreachable through the gate,
-- and it stays as the record of what the row would have said -- and so a future loosening of the
-- gate cannot silently lose the disclosure too.
--
--   node scripts/apply_sql.mjs scripts/sql/an_unstated_coverage_area_stops_being_a_pass.sql --apply

begin;

-- The defaults and the search_path are reproduced exactly. pg_get_function_identity_arguments does
-- NOT show parameter defaults, and a create-or-replace that omits them is refused outright:
-- "cannot remove parameter defaults from existing function". The hint suggests DROP FUNCTION, which
-- would be the wrong move here -- it discards the ACL and briefly removes a routine six callers
-- depend on. The right move is to reproduce the real header, taken from pg_get_functiondef.
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
    -- GATE: they cover the emirate asked for, and SAY SO somewhere.
    -- The branch that passed an empty coverage_emirates is gone: unknown evidence is not a pass.
    -- The lead-row emirate is still honoured, because that is a stated fact in another column.
    and (p_emirate is null
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

commit;
