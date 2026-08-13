-- fn_os_ai_quality — the reader for a table that had none.
--
-- ai_quality_snapshots has been written nightly by fn_ai_quality_watch since 10 Jul 2026. Measured
-- 13 Aug 2026: 1,219 rows, and ZERO readers anywhere in src/. The founder could not see a single
-- number it holds. This is the reader, and os_health action='ai_quality' is its one caller.
--
-- IT AGGREGATES, AND THAT IS NOT DEFENSIVE HABIT. Until this morning the nightly INSERT wrote one
-- row per VIEW agent while a BEFORE INSERT trigger collapsed several of them onto one canonical
-- org_agents key, so a single night could hold 52 rows carrying 37 distinct agents (see
-- a_snapshot_whose_grain_was_not_one_row_per_agent.sql). The writer now aggregates before
-- inserting, but the 1,219 historical rows still carry the old shape and are deliberately NOT
-- rewritten — back-dating them would make a rule look like it always held. Grouping here is what
-- lets one screen read both eras without double-counting fifteen agents on every earlier night.
--
-- WEIGHTED BY ACTIONS, NEVER A MEAN OF PERCENTAGES. An override rate is rejected/actions. Averaging
-- those ratios across agents with one action and agents with a hundred and sixty is not the rate,
-- and it is how a quiet agent comes to dominate a headline number.
--
-- WHAT `override_pct` MEANS, because a number on a screen with no definition becomes whatever the
-- reader assumes: it is the share of that agent's agent_actions in the last 30 days that a HUMAN
-- rejected, dismissed, declined or overrode. High is bad — it means the agent's suggestions are
-- being thrown away. NULL actions mean the agent proposed nothing, which is not a quality signal
-- and is why those rows never enter the average.
--
--   node scripts/apply_sql.mjs scripts/sql/the_quality_table_nothing_read.sql --promote --ddl

create or replace function public.fn_os_ai_quality()
 returns jsonb
 language sql
 stable
 security definer
 set search_path to 'public'
as $function$
with nights as (
  select at, row_number() over (order by at desc) rn
  from (select distinct at from public.ai_quality_snapshots) d
),
latest_at as (select at from nights where rn = 1),
-- one row per agent for the most recent night, whichever era wrote it
latest as (
  select s.agent,
         round(sum(s.override_pct * greatest(s.actions_30d,1))::numeric
               / nullif(sum(greatest(s.actions_30d,1)),0), 1) as override_pct,
         sum(s.actions_30d)::int as actions_30d
  from public.ai_quality_snapshots s
  where s.at = (select at from latest_at)
  group by s.agent
),
-- the trailing picture, excluding the night we are reporting on
prev as (
  select s.agent,
         round(sum(s.override_pct * greatest(s.actions_30d,1))::numeric
               / nullif(sum(greatest(s.actions_30d,1)),0), 1) as avg_prev,
         count(distinct s.at) as nights
  from public.ai_quality_snapshots s
  where s.at < (select at from latest_at)
  group by s.agent
)
select jsonb_build_object(
  'as_of', (select at from latest_at),
  'nights_held', (select count(*) from nights),
  'agents', (select count(*) from latest),
  -- the one headline, weighted the same way as every row under it
  'override_pct_overall', (select round(sum(override_pct * greatest(actions_30d,1))::numeric
                                        / nullif(sum(greatest(actions_30d,1)),0), 1) from latest),
  'actions_30d_total', (select coalesce(sum(actions_30d),0) from latest),
  'meaning', 'override_pct is the share of that agent''s proposed actions in the last 30 days that a human rejected, dismissed, declined or overrode. Higher is worse.',
  'rows', coalesce((
    select jsonb_agg(r order by r->>'sort_key')
    from (
      select jsonb_build_object(
               'agent', l.agent,
               'override_pct', l.override_pct,
               'actions_30d', l.actions_30d,
               'avg_prev', p.avg_prev,
               'nights_of_history', coalesce(p.nights, 0),
               -- stated only when there IS a history to compare against, so a first-night agent
               -- reads as 'new' rather than as 'no change'
               'delta', case when p.avg_prev is null then null
                             else round(l.override_pct - p.avg_prev, 1) end,
               'sort_key', lpad((1000 - least(999, l.actions_30d))::text, 4, '0') || l.agent
             ) as r
      from latest l left join prev p on p.agent = l.agent
    ) x), '[]'::jsonb)
);
$function$;

revoke execute on function public.fn_os_ai_quality() from public;
revoke execute on function public.fn_os_ai_quality() from anon;
grant execute on function public.fn_os_ai_quality() to service_role;
