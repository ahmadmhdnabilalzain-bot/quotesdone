-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260710221819   name: ai_observability_and_security_selfaudit
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Per-agent health (runs, errors, override rate, confidence) over 30 days.
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
    count(*) filter (where created_at>now()-interval '30 days' and decided_at is not null) as decided_30d,
    count(*) filter (where created_at>now()-interval '30 days' and lower(coalesce(status,'')) in ('rejected','dismissed','declined','overridden')) as rejected_30d,
    round(avg(confidence) filter (where created_at>now()-interval '30 days'),1) as avg_confidence
  from public.agent_actions group by agent
)
select coalesce(r.agent,a.agent) as agent,
  coalesce(r.runs_30d,0) as runs_30d, coalesce(r.errors_30d,0) as errors_30d, r.last_run,
  coalesce(a.decided_30d,0) as decided_30d, coalesce(a.rejected_30d,0) as rejected_30d,
  round(case when a.decided_30d>0 then a.rejected_30d::numeric/a.decided_30d*100 else null end,1) as override_pct,
  a.avg_confidence
from runs r full outer join acts a on a.agent=r.agent
order by override_pct desc nulls last, runs_30d desc;
revoke all on public.v_ai_agent_health from anon, authenticated;

-- One-row global AI observability summary (unifies the scattered signals).
create or replace view public.v_ai_observability as
select
  (select count(*) from public.agent_runs where started_at>now()-interval '24 hours') as runs_24h,
  (select count(*) from public.agent_runs where started_at>now()-interval '24 hours' and status='error') as errors_24h,
  (select count(*) from public.agent_actions where lower(coalesce(status,'')) in ('pending','needs_review')) as open_approvals,
  (select round(avg(override_pct),1) from public.v_ai_agent_health where override_pct is not null) as avg_override_pct,
  (select round(avg(score)::numeric,1) from public.v_eval_latest) as avg_eval_score,
  (select round(avg(confidence),1) from public.v_kb_confidence) as kb_avg_confidence,
  (select count(*) from public.v_kb_review_due) as kb_review_due,
  (select count(*) from public.kb_chunks where embedding_gte is not null) as kb_embedded,
  (select count(*) from public.kb_chunks) as kb_total,
  (select count(*) from public.kb_usage_log where created_at>now()-interval '7 days') as kb_queries_7d;
revoke all on public.v_ai_observability from anon, authenticated;

-- Security self-audit: tracks the advisor classes over time (free, cron-able), alerts on RLS-off public tables.
create table if not exists public.security_selfaudit_snapshots (
  at timestamptz not null default now(),
  rls_disabled_tables int, rls_no_policy int, secdef_views int, secdef_fns_anon int
);
alter table public.security_selfaudit_snapshots enable row level security;

create or replace function public.fn_security_selfaudit()
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare v_rls_off int; v_no_pol int; v_secviews int; v_secfns int;
begin
  select count(*) into v_rls_off from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='r' and not c.relrowsecurity;
  select count(*) into v_no_pol from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='r' and c.relrowsecurity
      and not exists (select 1 from pg_policy p where p.polrelid=c.oid);
  select count(*) into v_secviews from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='v'
      and not (coalesce(c.reloptions,'{}') @> array['security_invoker=on'] or coalesce(c.reloptions,'{}') @> array['security_invoker=true']);
  select count(*) into v_secfns from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prosecdef and has_function_privilege('anon', p.oid, 'EXECUTE');
  insert into public.security_selfaudit_snapshots(rls_disabled_tables,rls_no_policy,secdef_views,secdef_fns_anon)
    values (v_rls_off, v_no_pol, v_secviews, v_secfns);
  if v_rls_off > 0 then
    insert into public.security_events(kind,severity,source,subject,detail)
    values ('rls_disabled_tables','high','selfaudit','public schema',
            jsonb_build_object('count',v_rls_off,'note','public tables with RLS disabled - deny-by-default violation'));
  end if;
  return jsonb_build_object('rls_disabled_tables',v_rls_off,'rls_no_policy',v_no_pol,'secdef_views',v_secviews,'secdef_fns_anon',v_secfns);
end $$;

select cron.schedule('security_selfaudit_daily','20 3 * * *', $$select public.fn_security_selfaudit();$$);
select public.fn_security_selfaudit() as first_snapshot;
