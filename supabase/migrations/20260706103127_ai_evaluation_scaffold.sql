-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706103127   name: ai_evaluation_scaffold
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ============ AI EVALUATION FRAMEWORK (scaffold) ============
create table if not exists public.agent_evals(
  id bigserial primary key,
  snapshot_at timestamptz default now(),
  window_days int default 30,
  kpis jsonb not null);
alter table public.agent_evals enable row level security;
revoke all on public.agent_evals from anon, authenticated;

create or replace function public.fn_eval_snapshot(p_days int default 30)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  intake_total int; intake_complete int;
  q_total int; q_scored int; q_pass numeric; q_avg numeric;
  inq_matched int; inq_all int;
  inq_done int; inq_open int;
  esc_pending int; esc_total int;
  lat_avg numeric;
  k jsonb;
begin
  -- intake completeness: inquiries in window with spec AND (budget or trades)
  select count(*) filter (where created_at > now()-(p_days||' days')::interval),
         count(*) filter (where created_at > now()-(p_days||' days')::interval
                          and coalesce(spec::text,'') not in ('','null','{}')
                          and (budget is not null or coalesce(array_length(trades,1),0) > 0))
    into intake_total, intake_complete from inquiries;

  -- quote gate: pass rate = quality.score >= 60
  select count(*) filter (where created_at > now()-(p_days||' days')::interval),
         count(*) filter (where created_at > now()-(p_days||' days')::interval and quality is not null),
         avg(nullif(quality->>'score','')::numeric) filter (where created_at > now()-(p_days||' days')::interval),
         count(*) filter (where created_at > now()-(p_days||' days')::interval
                          and nullif(quality->>'score','')::numeric >= 60)
    into q_total, q_scored, q_avg, q_pass from quotes;

  -- match coverage: inquiries with >=1 match
  select count(*) filter (where i.created_at > now()-(p_days||' days')::interval),
         count(*) filter (where i.created_at > now()-(p_days||' days')::interval
                          and exists(select 1 from inquiry_matches m where m.inquiry_id=i.id))
    into inq_all, inq_matched from inquiries i;

  -- resolution: completed vs open (window)
  select count(*) filter (where created_at > now()-(p_days||' days')::interval
                          and (status in ('completed','accepted','closed') or completed_at is not null)),
         count(*) filter (where created_at > now()-(p_days||' days')::interval)
    into inq_done, inq_open from inquiries;

  -- escalation proxy: pending agent_actions vs all (window)
  begin
    select count(*) filter (where created_at > now()-(p_days||' days')::interval and status='pending'),
           count(*) filter (where created_at > now()-(p_days||' days')::interval)
      into esc_pending, esc_total from agent_actions;
  exception when others then esc_pending:=0; esc_total:=0; end;

  -- latency: avg agent_runs seconds (window)
  begin
    select round(avg(extract(epoch from (finished_at-started_at)))::numeric,1)
      into lat_avg from agent_runs
      where started_at > now()-(p_days||' days')::interval and finished_at is not null;
  exception when others then lat_avg:=null; end;

  k := jsonb_build_object(
    'window_days', p_days,
    'rfq_completeness_pct', case when intake_total=0 then null else round(intake_complete::numeric/intake_total*100,1) end,
    'quote_gate_pass_pct',  case when q_scored=0 then null else round(q_pass::numeric/q_scored*100,1) end,
    'quote_quality_avg',    round(coalesce(q_avg,0),1),
    'match_coverage_pct',   case when inq_all=0 then null else round(inq_matched::numeric/inq_all*100,1) end,
    'resolution_pct',       case when inq_open=0 then null else round(inq_done::numeric/inq_open*100,1) end,
    'escalation_rate_pct',  case when esc_total=0 then null else round(esc_pending::numeric/esc_total*100,1) end,
    'agent_latency_sec_avg',lat_avg,
    -- require labelled eval sets / surveys; scaffolded null until instrumented
    'clarification_efficiency', null,
    'hallucination_rate_pct',   null,
    'customer_satisfaction',    null,
    'samples', jsonb_build_object('inquiries',intake_total,'quotes',q_total,'agent_actions',esc_total));
  return k;
end $$;

create or replace function public.fn_eval_run() returns void
language plpgsql security definer set search_path=public,pg_temp as $$
declare k jsonb;
begin
  k := public.fn_eval_snapshot(30);
  insert into public.agent_evals(window_days,kpis) values (30,k);
end $$;

select public.fn_eval_run();
select jsonb_pretty(kpis) from public.agent_evals order by id desc limit 1;
