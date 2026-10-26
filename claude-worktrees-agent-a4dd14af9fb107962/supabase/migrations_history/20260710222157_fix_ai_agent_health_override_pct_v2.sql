-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260710222157   name: fix_ai_agent_health_override_pct_v2
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace view public.v_ai_agent_health as
with runs as (
  select agent,
    count(*) filter (where started_at > now()-interval '30 days') as runs_30d,
    count(*) filter (where started_at > now()-interval '30 days' and status='error') as errors_30d,
    max(started_at) as last_run
  from public.agent_runs group by agent
),
acts as (
  select agent,
    count(*) filter (where created_at>now()-interval '30 days') as actions_30d,
    count(*) filter (where created_at>now()-interval '30 days' and decided_at is not null) as decided_30d,
    count(*) filter (where created_at>now()-interval '30 days' and lower(coalesce(status,'')) in ('rejected','dismissed','declined','overridden')) as rejected_30d,
    round(avg(confidence) filter (where created_at>now()-interval '30 days'),1) as avg_confidence
  from public.agent_actions group by agent
)
select coalesce(r.agent,a.agent) as agent,
  coalesce(r.runs_30d,0) as runs_30d, coalesce(r.errors_30d,0) as errors_30d, r.last_run,
  coalesce(a.decided_30d,0) as decided_30d, coalesce(a.rejected_30d,0) as rejected_30d,
  round(case when a.actions_30d>0 then a.rejected_30d::numeric/a.actions_30d*100 else null end,1) as override_pct,
  a.avg_confidence,
  coalesce(a.actions_30d,0) as actions_30d
from runs r full outer join acts a on a.agent=r.agent
order by override_pct desc nulls last, runs_30d desc;
revoke all on public.v_ai_agent_health from anon, authenticated;
