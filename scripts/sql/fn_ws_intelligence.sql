-- fn_ws_intelligence — the Intelligence Centre's server side.
--
-- Row #3 of the executive-UI spec asks for ONE screen carrying nine intelligence items. Four of
-- them (risks, predictions, forecast, supply coverage) already reach the browser through
-- fn_ws_strategy / fn_ws_finance / fn_ws_analytics and need no server change. This routine exists
-- for the four that are computed every night and reach nothing:
--
--   opportunity           9 open rows, no browser-reachable reader at all
--   competitor            27 rows, read only by fn_company_reflect, which renders nowhere
--   ai_cost_log           1,094 rows in 30 days, read only by fn_ai_route and fn_os_improve
--   company_index         39 measurements across 3 indices, no browser-reachable reader at all
--
-- THE NINTH ITEM IS DELIBERATELY ABSENT. The spec also asks for customer behaviour. The
-- customer_health view is empty because public.customers holds zero rows — the marketplace has
-- 20,470 supplier leads and 7 inquiries but no registered customers yet. A customer panel would
-- therefore be an empty panel, and an empty panel on an intelligence screen reads as "the company
-- knows nothing about its customers" rather than "the company has none". That item is blocked by
-- business reality, not by code, and is left out until there is a customer to describe.
--
--   node scripts/apply_sql.mjs scripts/sql/fn_ws_intelligence.sql --promote
create or replace function public.fn_ws_intelligence()
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_catalog'
as $function$
  with mat as (
    -- The company maturity index, in measurement order. This is the only series in the estate long
    -- enough to carry a trajectory, and it is rebuilt nightly.
    select measured_on, score from public.company_index
     where index_name = 'company_maturity'
     order by measured_on
  ), steps as (
    select (score - lag(score) over (order by measured_on))::double precision dx from mat
  ), moments as (
    select count(*)::int n,
           avg(dx) mu,
           coalesce(stddev_samp(dx), 0) sd
      from steps where dx is not null
  )
  select jsonb_build_object(

    -- ── OPPORTUNITIES ────────────────────────────────────────────────────────────────────────
    'opportunities', jsonb_build_object(
      'open', (select count(*) from public.opportunity where status = 'open'),
      'total', (select count(*) from public.opportunity),
      'newest', (select max(created_at) from public.opportunity),
      'rows', coalesce((select jsonb_agg(jsonb_build_object(
                 'id', o.id, 'kind', o.kind, 'title', o.title, 'detail', o.detail,
                 'value_score', o.value_score, 'effort', o.effort, 'confidence', o.confidence,
                 'detected_by', o.detected_by, 'created_at', o.created_at)
               order by o.value_score desc nulls last, o.created_at desc)
             from public.opportunity o where o.status = 'open'), '[]'::jsonb)
    ),

    -- ── COMPETITORS ──────────────────────────────────────────────────────────────────────────
    'competitors', jsonb_build_object(
      'total', (select count(*) from public.competitor),
      'by_threat', coalesce((select jsonb_agg(jsonb_build_object('level', t.threat_level, 'n', t.n)
                     order by case t.threat_level when 'high' then 1 when 'medium' then 2 else 3 end)
                   from (select coalesce(nullif(threat_level, ''), 'unrated') threat_level, count(*) n
                           from public.competitor group by 1) t), '[]'::jsonb),
      'anonymity_rivals', (select count(*) from public.competitor where offers_anonymity is true),
      'rows', coalesce((select jsonb_agg(jsonb_build_object(
                 'id', c.id, 'name', c.name, 'url', c.url, 'kind', c.kind,
                 'threat_level', c.threat_level, 'overlap', c.overlap, 'strength', c.strength,
                 'weakness', c.weakness, 'offers_anonymity', c.offers_anonymity,
                 'verified_at', c.verified_at)
               order by case coalesce(c.threat_level, '') when 'high' then 1 when 'medium' then 2 else 3 end, c.name)
             from public.competitor c), '[]'::jsonb),
      'positions', coalesce((select jsonb_agg(jsonb_build_object(
                 'dimension', p.dimension, 'quotesdone', p.quotesdone,
                 'market_norm', p.market_norm, 'verdict', p.verdict) order by p.id)
             from public.competitive_position p), '[]'::jsonb)
    ),

    -- ── AI SPENDING ──────────────────────────────────────────────────────────────────────────
    -- Every model call the company has paid for, in the window the spec's own cost row (#8) uses.
    'ai_spending', jsonb_build_object(
      'window_days', 30,
      'calls_30d', (select count(*) from public.ai_cost_log where occurred_at > now() - interval '30 days'),
      'total_aed', (select round(coalesce(sum(cost_aed), 0), 4) from public.ai_cost_log where occurred_at > now() - interval '30 days'),
      'failed_30d', (select count(*) from public.ai_cost_log where occurred_at > now() - interval '30 days' and ok is false),
      'cache_hits_30d', (select count(*) from public.ai_cost_log where occurred_at > now() - interval '30 days' and cached is true),
      'cheaper_available_30d', (select count(*) from public.ai_cost_log where occurred_at > now() - interval '30 days' and could_be_cheaper is true),
      'by_model', coalesce((select jsonb_agg(jsonb_build_object('model', m.model_used, 'calls', m.calls, 'aed', m.aed)
                    order by m.aed desc)
                  from (select coalesce(nullif(model_used, ''), 'unknown') model_used, count(*) calls,
                               round(coalesce(sum(cost_aed), 0), 4) aed
                          from public.ai_cost_log where occurred_at > now() - interval '30 days'
                         group by 1) m), '[]'::jsonb),
      'by_dept', coalesce((select jsonb_agg(jsonb_build_object('dept', d.dept_key, 'calls', d.calls, 'aed', d.aed)
                    order by d.aed desc)
                  from (select coalesce(nullif(dept_key, ''), 'unattributed') dept_key, count(*) calls,
                               round(coalesce(sum(cost_aed), 0), 4) aed
                          from public.ai_cost_log where occurred_at > now() - interval '30 days'
                         group by 1) d), '[]'::jsonb),
      'daily', coalesce((select jsonb_agg(jsonb_build_object('d', x.d, 'aed', x.aed, 'calls', x.calls) order by x.d)
                  from (select occurred_at::date d, round(coalesce(sum(cost_aed), 0), 4) aed, count(*) calls
                          from public.ai_cost_log where occurred_at > now() - interval '30 days'
                         group by 1) x), '[]'::jsonb)
    ),

    -- ── GROWTH PROBABILITY ───────────────────────────────────────────────────────────────────
    -- Not a point estimate dressed up as a forecast. The company maturity index is measured
    -- nightly; its daily changes give a drift and a volatility, and those give the probability the
    -- index is higher in 30 days than it is today under a random-walk-with-drift model. The
    -- logistic form is the standard approximation to the normal CDF (max error ~0.01), which is far
    -- below the uncertainty in a 13-point sample — and the sample size travels with the number so
    -- nobody can read it as more than it is.
    'growth_probability', (select jsonb_build_object(
        'horizon_days', 30,
        'observations', m.n,
        'index_name', 'company_maturity',
        'index_now', (select score from mat order by measured_on desc limit 1),
        'index_first', (select score from mat order by measured_on limit 1),
        'window_from', (select min(measured_on) from mat),
        'window_to', (select max(measured_on) from mat),
        'drift_per_day', round(m.mu::numeric, 4),
        'volatility_per_day', round(m.sd::numeric, 4),
        'growth_probability_pct', case when m.n < 3 or m.sd = 0 then null
            else round((100.0 / (1 + exp(-1.702 * (m.mu * sqrt(30.0) / m.sd))))::numeric, 1) end,
        'method', 'P(index in 30d > index today), from the measured daily drift and volatility of the company maturity index; random walk with drift, logistic approximation to the normal CDF'
      ) from moments m),

    'generated_at', now()
  );
$function$;
