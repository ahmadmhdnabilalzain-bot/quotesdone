-- #32 AI REPUTATION: earned, not assigned. High reputation widens autonomy within governance.
create table if not exists public.agent_reputation (
  agent_key      text primary key,
  correctness    numeric,
  reliability    numeric,
  cost_efficiency numeric,
  learning_speed numeric,
  collaboration  numeric,
  score          numeric,
  tier           text check (tier in ('probation','standard','trusted','senior_trusted')),
  computed_at    timestamptz not null default now()
);
alter table public.agent_reputation enable row level security;

create or replace function public.fn_reputation_recompute()
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare r record; n int := 0; v_score numeric; v_tier text;
  v_corr numeric; v_rel numeric; v_cost numeric; v_learn numeric; v_collab numeric;
begin
  for r in select agent_key from org_agents where active loop
    -- correctness: graded improvements that moved the metric the right way
    select coalesce(round(100.0*count(*) filter (where verdict='improved')
             /nullif(count(*) filter (where verdict in ('improved','no_change','worse')),0),1), null)
      into v_corr from outcome_record where actor = r.agent_key;
    -- reliability: runs that did not error
    select coalesce(round(100.0*count(*) filter (where status<>'error')/nullif(count(*),0),1), null)
      into v_rel from agent_runs where agent = r.agent_key and started_at > now()-interval '30 days';
    -- cost efficiency: share of calls a cheaper model could NOT have served
    select coalesce(round(100.0*count(*) filter (where not coalesce(could_be_cheaper,false))/nullif(count(*),0),1), null)
      into v_cost from ai_cost_log where agent_key = r.agent_key and occurred_at > now()-interval '30 days';
    -- learning speed: knowledge this agent owns that is validated
    select coalesce(round(100.0*count(*) filter (where validation_status not in ('unvalidated','unreviewed'))
             /nullif(count(*),0),1), null)
      into v_learn from agent_knowledge where owner_agent = r.agent_key;
    -- collaboration: reviews it took part in that reached approval
    select coalesce(round(100.0*count(*) filter (where decision='approve')/nullif(count(*),0),1), null)
      into v_collab from review_chain where author_agent = r.agent_key or reviewer_agent = r.agent_key;

    v_score := round((coalesce(v_corr,50)*0.30 + coalesce(v_rel,50)*0.30 + coalesce(v_cost,50)*0.15
                    + coalesce(v_learn,50)*0.15 + coalesce(v_collab,50)*0.10), 1);
    v_tier := case when v_score >= 85 then 'senior_trusted'
                   when v_score >= 70 then 'trusted'
                   when v_score >= 50 then 'standard' else 'probation' end;

    insert into agent_reputation (agent_key,correctness,reliability,cost_efficiency,learning_speed,collaboration,score,tier,computed_at)
    values (r.agent_key,v_corr,v_rel,v_cost,v_learn,v_collab,v_score,v_tier,now())
    on conflict (agent_key) do update set correctness=excluded.correctness, reliability=excluded.reliability,
      cost_efficiency=excluded.cost_efficiency, learning_speed=excluded.learning_speed,
      collaboration=excluded.collaboration, score=excluded.score, tier=excluded.tier, computed_at=now();
    n := n + 1;
  end loop;

  -- probation is a real consequence: any agent below the floor loses autonomous authority
  update employee_authority a set max_tier='gated'
   from agent_reputation p
  where p.agent_key=a.agent_key and p.tier='probation' and a.max_tier='autonomous';

  insert into agent_runs (agent,started_at,finished_at,status,counts,note)
  values ('reputation',now(),now(),'ok',jsonb_build_object('scored',n),
    'Reputation recomputed for '||n||' employee(s). Probation demotes autonomous authority to gated.');
  return jsonb_build_object('scored',n);
end $fn$;
revoke execute on function public.fn_reputation_recompute() from public, anon, authenticated;

-- #40 COMPANY MATURITY INDEX + #31 ORGANIZATIONAL ENERGY + #30 MARKETPLACE HEALTH
create table if not exists public.company_index (
  id          bigserial primary key,
  measured_on date not null,
  index_name  text not null,
  dimensions  jsonb not null,
  score       numeric not null,
  band        text,
  created_at  timestamptz not null default now(),
  unique (measured_on, index_name)
);
alter table public.company_index enable row level security;

create or replace function public.fn_company_indices()
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare
  d_auto numeric; d_know numeric; d_dec numeric; d_fin numeric; d_cust numeric;
  d_supp numeric; d_sec numeric; d_res numeric; d_inno numeric; d_strat numeric; v_mat numeric;
  e_vel numeric; e_backlog numeric; e_collab numeric; e_knowcreate numeric; e_autorate numeric; v_energy numeric;
  m_quality numeric; m_speed numeric; m_completion numeric; m_fraud numeric; m_conf numeric; v_mh numeric;
begin
  -- MATURITY: ten dimensions, 0-100
  select coalesce(100 - round(100.0*count(*) filter (where needs_founder)/nullif(count(*),0),1),100)
    into d_auto from org_tasks where status<>'done';
  select coalesce(round(100.0*count(*) filter (where validation_status not in ('unvalidated','unreviewed'))/nullif(count(*),0),1),0)
    into d_know from agent_knowledge;
  select coalesce(round(100.0*count(*) filter (where verdict='improved')
           /nullif(count(*) filter (where verdict in ('improved','no_change','worse')),0),1),50)
    into d_dec from outcome_record;
  select case when coalesce(sum(coalesce(reveal_fee,app_fee,0)),0) > 0 then 60 else 10 end
    into d_fin from transactions where revealed_at > now()-interval '90 days';
  select case when count(*) > 0 then 50 else 10 end into d_cust from customers;
  select least(100, round(100.0*(select count(*) from v_supply_gap where approved>=10)/86.0,1))
    into d_supp;
  select coalesce(round(100.0*count(*) filter (where ok)/nullif(count(*),0),1),50)
    into d_sec from health_checks where check_kind='http' and created_at > now()-interval '7 days';
  select round(100.0*count(*) filter (where last_tested is not null)/nullif(count(*),0),1)
    into d_res from continuity_plan;
  select least(100, (select count(*) from evolution_proposal)*5) into d_inno;
  select coalesce(round(100.0*count(*) filter (where verdict in ('MET','NEAR'))
           /nullif(count(*) filter (where verdict<>'NO DATA'),0),1),0)
    into d_strat from fn_kpi_scoreboard();

  v_mat := round((d_auto+d_know+d_dec+d_fin+d_cust+d_supp+d_sec+d_res+d_inno+d_strat)/10.0,1);
  insert into company_index (measured_on,index_name,dimensions,score,band)
  values (current_date,'company_maturity',
    jsonb_build_object('automation',d_auto,'knowledge_quality',d_know,'decision_accuracy',d_dec,
      'financial_health',d_fin,'customer_trust',d_cust,'supplier_ecosystem',d_supp,'security',d_sec,
      'operational_resilience',d_res,'innovation',d_inno,'strategic_execution',d_strat), v_mat,
    case when v_mat>=80 then 'mature' when v_mat>=60 then 'developing' when v_mat>=40 then 'early' else 'nascent' end)
  on conflict (measured_on,index_name) do update set dimensions=excluded.dimensions, score=excluded.score, band=excluded.band;

  -- ENERGY: momentum
  select count(*) into e_vel from decision_log where created_at > now()-interval '7 days';
  select coalesce(round(100.0 - 100.0*count(*) filter (where created_at < now()-interval '14 days')/nullif(count(*),0),1),100)
    into e_backlog from org_tasks where status<>'done';
  select coalesce(round(100.0*count(*) filter (where decision='approve')/nullif(count(*),0),1),50)
    into e_collab from review_chain where created_at > now()-interval '30 days';
  select least(100, count(*)) into e_knowcreate from agent_knowledge where updated_at > now()-interval '7 days';
  select coalesce(100 - round(100.0*count(*) filter (where needs_founder)/nullif(count(*),0),1),100)
    into e_autorate from org_tasks where status<>'done';
  v_energy := round((least(100,e_vel)+e_backlog+e_collab+e_knowcreate+e_autorate)/5.0,1);
  insert into company_index (measured_on,index_name,dimensions,score,band)
  values (current_date,'organizational_energy',
    jsonb_build_object('decision_velocity_7d',e_vel,'backlog_freshness',e_backlog,
      'collaboration_efficiency',e_collab,'knowledge_creation_7d',e_knowcreate,'automation_rate',e_autorate),
    v_energy, case when v_energy>=75 then 'high' when v_energy>=50 then 'steady' else 'slowing' end)
  on conflict (measured_on,index_name) do update set dimensions=excluded.dimensions, score=excluded.score, band=excluded.band;

  -- MARKETPLACE HEALTH: replaces the single-column stub
  select coalesce(round(avg(reliability),1),0) into m_quality from supplier_score where reliability is not null;
  select coalesce(round(100.0*count(*) filter (where sent_at is not null and sent_at-created_at < interval '24 hours')
           /nullif(count(*),0),1),0) into m_speed from notifications where created_at > now()-interval '30 days';
  select coalesce(round(100.0*count(*) filter (where exists(select 1 from quotes q where q.inquiry_id=i.id))
           /nullif(count(*),0),1),0) into m_completion from inquiries i where i.created_at > now()-interval '30 days';
  select coalesce(100 - least(100,count(*)*5),100) into m_fraud from fraud_flags;
  select coalesce(round(avg(confidence)*100,1),50) into m_conf from decision_log where confidence is not null;
  v_mh := round((m_quality+m_speed+coalesce(m_completion,0)+m_fraud+m_conf)/5.0,1);
  insert into company_index (measured_on,index_name,dimensions,score,band)
  values (current_date,'marketplace_health',
    jsonb_build_object('supplier_quality',m_quality,'quote_speed',m_speed,'rfq_completion',m_completion,
      'fraud_clean',m_fraud,'ai_confidence',m_conf), v_mh,
    case when v_mh>=75 then 'healthy' when v_mh>=50 then 'fragile' else 'unhealthy' end)
  on conflict (measured_on,index_name) do update set dimensions=excluded.dimensions, score=excluded.score, band=excluded.band;

  insert into agent_runs (agent,started_at,finished_at,status,counts,note)
  values ('company_indices',now(),now(),'ok',
    jsonb_build_object('maturity',v_mat,'energy',v_energy,'marketplace_health',v_mh),
    'Company indices: maturity '||v_mat||', energy '||v_energy||', marketplace health '||v_mh||'.');
  return jsonb_build_object('maturity',v_mat,'energy',v_energy,'marketplace_health',v_mh);
end $fn$;
revoke execute on function public.fn_company_indices() from public, anon, authenticated;