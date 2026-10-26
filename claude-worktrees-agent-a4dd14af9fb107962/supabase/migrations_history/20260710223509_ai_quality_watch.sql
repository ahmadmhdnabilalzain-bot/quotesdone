-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260710223509   name: ai_quality_watch
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create table if not exists public.ai_quality_snapshots(
  at timestamptz not null default now(), agent text, override_pct numeric, actions_30d int);
alter table public.ai_quality_snapshots enable row level security;

create or replace function public.fn_ai_quality_watch()
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp' as $$
declare v_regs int:=0; v_spikes int:=0; v_detail jsonb; v_open int; v_owner text;
begin
  -- 1. snapshot current per-agent override rate (builds history for spike detection)
  insert into public.ai_quality_snapshots(agent,override_pct,actions_30d)
    select agent, override_pct, actions_30d from public.v_ai_agent_health where override_pct is not null;

  -- 2. eval regressions: latest run worse than previous, or below 70 absolute
  with ranked as (
    select prompt_key, score, created_at,
           row_number() over(partition by prompt_key order by created_at desc) rn
    from public.prompt_eval_runs
  ),
  reg as (
    select c.prompt_key, c.score cur, p.score prev
    from ranked c join ranked p on p.prompt_key=c.prompt_key and p.rn=2
    where c.rn=1 and (c.score < p.score - 5 or c.score < 70)
  ),
  ins as (
    insert into public.security_events(kind,severity,source,subject,detail)
    select 'eval_regression', case when cur<70 then 'high' else 'medium' end, 'ai_quality_watch', prompt_key,
           jsonb_build_object('current',cur,'previous',prev)
    from reg returning 1
  )
  select count(*) into v_regs from ins;

  -- 3. override spikes: human-facing agents whose override jumped >20pts above their trailing average
  with cur as (
    select agent, override_pct, actions_30d from public.v_ai_agent_health
    where override_pct is not null and actions_30d>=5 and agent not in ('security','onboarding','email')
  ),
  hist as (
    select agent, avg(override_pct) avg_prev, count(*) n
    from public.ai_quality_snapshots where at < now()-interval '12 hours' group by agent
  ),
  spike as (
    select c.agent, c.override_pct, round(h.avg_prev,1) avg_prev
    from cur c join hist h on h.agent=c.agent
    where h.n>=1 and c.override_pct > coalesce(h.avg_prev,0)+20
  ),
  ins2 as (
    insert into public.security_events(kind,severity,source,subject,detail)
    select 'override_spike','medium','ai_quality_watch', agent,
           jsonb_build_object('override_pct',override_pct,'trailing_avg',avg_prev)
    from spike returning 1
  )
  select count(*) into v_spikes from ins2;

  v_detail := jsonb_build_object('eval_regressions',v_regs,'override_spikes',v_spikes);

  -- 4. surface + email the founder (deduped, mirrors fn_backup_watch), only if something fired
  if v_regs+v_spikes > 0 then
    select count(*) into v_open from public.agent_actions
      where kind='ai_quality_alert' and coalesce(status,'') in ('pending','needs_review')
        and created_at > now()-interval '24 hours';
    if v_open = 0 then
      insert into public.agent_actions(agent,kind,status,risk,title,recommendation,target_table,detail)
      values('ai_trainer','ai_quality_alert','pending','medium',
        'AI quality alert: '||v_regs||' eval regression(s), '||v_spikes||' override spike(s)',
        'Open the AI Observability dashboard and review security_events of kind eval_regression / override_spike. Consider rolling back the regressed prompt version, or investigating why a human-facing agent''s suggestions are being rejected.',
        'security_events', v_detail);
      select split_part(coalesce(value,'management@quotesdone.com'),',',1) into v_owner
        from public.app_secrets where key='admin_emails';
      insert into public.notifications(type,to_email,to_role,channel,subject,body,status)
      values('ai_quality_alert', v_owner,'admin','email','QuotesDone: AI quality alert',
        'The AI quality watch flagged '||v_regs||' eval regression(s) and '||v_spikes||' override spike(s). Open the AI Observability dashboard and check security_events (kind eval_regression / override_spike).','queued');
    end if;
  end if;
  return v_detail;
end $$;

select cron.schedule('ai_quality_watch_daily','40 3 * * *', $$select public.fn_ai_quality_watch();$$);
select public.fn_ai_quality_watch() as first_run;
