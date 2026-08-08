-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709093816   name: ai_agent_quality_view
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- per-agent quality (30-day): run reliability + how often the founder rejects the agent's recommendations
create or replace view public.ai_agent_quality as
with runs as (
  select agent, count(*) as runs_30d, count(*) filter (where status in ('error','failed')) as errors
  from agent_runs where started_at >= now()-interval '30 days' group by agent
),
acts as (
  select agent, count(*) as actions_30d,
    count(*) filter (where status in ('pending','needs_review')) as open_escalations,
    count(*) filter (where status='rejected') as rejected,
    count(*) filter (where status in ('approved','done','auto_done')) as accepted
  from agent_actions where created_at >= now()-interval '30 days' group by agent
)
select coalesce(r.agent,a.agent) as agent,
  coalesce(r.runs_30d,0) as runs_30d, coalesce(r.errors,0) as errors,
  round(100.0*(coalesce(r.runs_30d,0)-coalesce(r.errors,0))/nullif(r.runs_30d,0),1) as run_success_pct,
  coalesce(a.actions_30d,0) as actions_30d, coalesce(a.open_escalations,0) as open_escalations,
  coalesce(a.rejected,0) as rejected, coalesce(a.accepted,0) as accepted,
  round(100.0*a.rejected/nullif(a.rejected+a.accepted,0),1) as rejection_rate_pct
from runs r full join acts a on a.agent=r.agent;
revoke all on public.ai_agent_quality from anon, authenticated;

create table if not exists public.ai_trainer_snapshots (
  id bigint generated always as identity primary key,
  snapshot_date date not null default current_date,
  kpis jsonb not null,
  created_at timestamptz not null default now()
);
create unique index if not exists ai_trainer_snap_day on public.ai_trainer_snapshots(snapshot_date);
revoke all on public.ai_trainer_snapshots from anon, authenticated;
