-- fn_report_drilldown — click a number in a report and find out why it moved, and who moved it.
--
-- Screen 10: "Clicking a number in a report drills into why it moved and who contributed." The
-- report KPIs were rendered as flat tiles, nothing bound a click to them, and no browser-reachable
-- routine took a metric argument at all — so the question could not be asked, let alone answered.
--
-- Everything below is history the company already keeps:
--
--   metric_snapshot   the metric's own series, and the movement between the last two readings
--   company_index     if the metric names an index, its band and dimension breakdown
--   goal_period       the target it is measured against, and the gap to it
--   decision_log      who decided anything naming this metric in the window, which is the
--                     "who contributed" half of the requirement
--
--   node scripts/apply_sql.mjs scripts/sql/fn_report_drilldown.sql --promote
create or replace function public.fn_report_drilldown(p_metric text, p_days integer default 30)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_catalog'
as $function$
  with b as (select coalesce(nullif(btrim(p_metric), ''), '~none~') m,
                    greatest(coalesce(p_days, 30), 1) d),
  series as (
    select s.taken_at, s.value from public.metric_snapshot s, b
     where s.metric_key ilike '%' || b.m || '%'
       and s.taken_at > now() - (b.d || ' days')::interval
     order by s.taken_at desc limit 60
  )
  select jsonb_build_object(
    'metric', (select m from b), 'window_days', (select d from b),

    -- WHY IT MOVED: the last two readings, and the change between them.
    'series', coalesce((select jsonb_agg(jsonb_build_object('at', taken_at, 'value', value) order by taken_at desc) from series), '[]'::jsonb),
    'latest', (select value from series order by taken_at desc limit 1),
    'previous', (select value from series order by taken_at desc offset 1 limit 1),
    'change', (select (select value from series order by taken_at desc limit 1)
                    - (select value from series order by taken_at desc offset 1 limit 1)),
    'readings', (select count(*) from series),

    'index', (select jsonb_build_object('index_name', c.index_name, 'score', c.score, 'band', c.band,
                'measured_on', c.measured_on, 'dimensions', c.dimensions)
                from public.company_index c, b
               where c.index_name ilike '%' || b.m || '%'
               order by c.measured_on desc limit 1),

    -- THE TARGET it is measured against.
    'target', (select jsonb_build_object('goal_key', g.goal_key, 'horizon', g.horizon,
                 'period_label', g.period_label, 'target_value', g.target_value,
                 'actual_value', g.actual_value, 'status', g.status,
                 'gap', g.target_value - g.actual_value, 'updated_at', g.updated_at)
                from public.goal_period g, b
               where g.goal_key ilike '%' || b.m || '%'
               order by g.updated_at desc limit 1),

    -- WHO CONTRIBUTED: the decisions that named this metric in the window.
    'contributors', coalesce((select jsonb_agg(jsonb_build_object(
          'actor', l.actor, 'os', public.fn_owning_os(l.actor), 'kind', l.kind,
          'decision', l.decision, 'confidence', l.confidence, 'at', l.created_at)
        order by l.created_at desc)
      from (select l.* from public.decision_log l, b
             where l.created_at > now() - (b.d || ' days')::interval
               and (l.decision ilike '%' || b.m || '%' or l.ctx::text ilike '%' || b.m || '%')
             order by l.created_at desc limit 10) l), '[]'::jsonb),
    'generated_at', now()
  );
$function$;
