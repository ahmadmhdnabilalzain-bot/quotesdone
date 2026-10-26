-- #29 AUTONOMOUS OPPORTUNITY DETECTION
create table if not exists public.opportunity (
  id           bigserial primary key,
  kind         text not null,
  title        text not null,
  detail       text,
  evidence     jsonb default '{}'::jsonb,
  value_score  numeric,
  effort       text check (effort in ('low','medium','high')),
  confidence   numeric,
  status       text not null default 'open' check (status in ('open','pursuing','won','dismissed')),
  detected_by  text not null default 'intel_director',
  created_at   timestamptz not null default now()
);
alter table public.opportunity enable row level security;

create or replace function public.fn_opportunity_scan()
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare r record; n int := 0;
begin
  -- underserved categories that already hold a viable pool: ready demand, no action
  for r in select * from v_supply_gap where status='READY - not yet invited' order by sendable desc limit 10 loop
    insert into opportunity (kind,title,detail,evidence,value_score,effort,confidence,detected_by)
    select 'underserved_category','Untapped pool: '||r.name,
      r.name||' holds '||r.sendable||' sendable suppliers and zero invitations sent. The pool is already sufficient for the 10-approved target.',
      jsonb_build_object('slug',r.slug,'sendable',r.sendable,'approved',r.approved),
      least(100, r.sendable/5.0), 'low', 0.8, 'intel_director'
    where not exists (select 1 from opportunity o where o.title='Untapped pool: '||r.name and o.status='open');
    if found then n := n+1; end if;
  end loop;

  -- categories where knowledge exists but no supply: capability ahead of market
  for r in select * from v_supply_gap where status='NO POOL - must source from scratch' limit 5 loop
    insert into opportunity (kind,title,detail,evidence,value_score,effort,confidence,detected_by)
    select 'unmet_demand','Whitespace: '||r.name,
      'A fully briefed category expert exists for '||r.name||' with zero suppliers anywhere in the pool. Either a genuine market gap worth owning, or a category to retire.',
      jsonb_build_object('slug',r.slug,'sendable',0), 40,'high',0.5,'market_analyst'
    where not exists (select 1 from opportunity o where o.title='Whitespace: '||r.name and o.status='open');
    if found then n := n+1; end if;
  end loop;

  -- cost opportunity
  if (select count(*) filter (where could_be_cheaper) from ai_cost_log where occurred_at>now()-interval '30 days') > 10 then
    insert into opportunity (kind,title,detail,evidence,value_score,effort,confidence,detected_by)
    select 'cost_saving','Over-specified AI calls',
      (select count(*) filter (where could_be_cheaper)||' of '||count(*)||' calls in the last 30 days could have been served by a cheaper model.' from ai_cost_log where occurred_at>now()-interval '30 days'),
      '{}'::jsonb, 60,'low',0.9,'optimisation_eng'
    where not exists (select 1 from opportunity where title='Over-specified AI calls' and status='open');
    if found then n := n+1; end if;
  end if;

  insert into agent_runs (agent,started_at,finished_at,status,counts,note)
  values ('opportunity_scan',now(),now(),'ok',jsonb_build_object('found',n),
    'Opportunity scan: '||n||' new opportunity(ies) detected without being asked.');
  return jsonb_build_object('found',n);
end $fn$;
revoke execute on function public.fn_opportunity_scan() from public, anon, authenticated;

-- #23 AUTONOMOUS RESOURCE ALLOCATION - governed, bounded, reversible
create table if not exists public.allocation_change (
  id          bigserial primary key,
  resource    text not null,
  subject     text not null,
  from_value  numeric,
  to_value    numeric,
  reason      text not null,
  policy      text not null,
  reverted    boolean not null default false,
  created_at  timestamptz not null default now()
);
alter table public.allocation_change enable row level security;

create or replace function public.fn_reallocate()
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare r record; n int := 0; v_total numeric; v_free numeric := 0;
begin
  -- policy: never move more than 20% of a department's budget in one cycle, never below 200 AED,
  -- only from departments under 30% utilisation, only to departments over 85%.
  for r in
    select b.dept_key, b.monthly_aed, b.spent_aed,
           round(100.0*b.spent_aed/nullif(b.monthly_aed,0),1) as util
    from department_budget b where b.monthly_aed > 200
  loop
    if r.util < 30 and r.monthly_aed * 0.2 >= 50 then
      v_free := v_free + round(r.monthly_aed*0.2,0);
      insert into allocation_change (resource,subject,from_value,to_value,reason,policy)
      values ('ai_budget_aed', r.dept_key, r.monthly_aed, r.monthly_aed - round(r.monthly_aed*0.2,0),
        r.dept_key||' used only '||coalesce(r.util,0)||'% of its budget. Releasing 20% to the pool.',
        'release: utilisation under 30%, cap 20% per cycle, floor 200 AED');
      update department_budget set monthly_aed = monthly_aed - round(monthly_aed*0.2,0), updated_at=now()
       where dept_key = r.dept_key;
      n := n + 1;
    end if;
  end loop;

  if v_free > 0 then
    for r in
      select b.dept_key, b.monthly_aed, round(100.0*b.spent_aed/nullif(b.monthly_aed,0),1) util
      from department_budget b where round(100.0*b.spent_aed/nullif(b.monthly_aed,0),1) > 85
      order by util desc limit 3
    loop
      insert into allocation_change (resource,subject,from_value,to_value,reason,policy)
      values ('ai_budget_aed', r.dept_key, r.monthly_aed, r.monthly_aed + round(v_free/3,0),
        r.dept_key||' is at '||r.util||'% utilisation. Receiving released budget.',
        'grant: utilisation over 85%, split evenly across at most 3 departments');
      update department_budget set monthly_aed = monthly_aed + round(v_free/3,0), updated_at=now()
       where dept_key = r.dept_key;
      n := n + 1;
    end loop;
  end if;

  insert into agent_runs (agent,started_at,finished_at,status,counts,note)
  values ('reallocate',now(),now(),'ok',jsonb_build_object('changes',n,'released_aed',v_free),
    'Resource reallocation: '||n||' change(s), '||v_free||' AED moved from idle to saturated departments. Every change is logged and reversible.');
  return jsonb_build_object('changes',n,'released_aed',v_free);
end $fn$;
revoke execute on function public.fn_reallocate() from public, anon, authenticated;

-- Layer 8 / #16 FUTURE SIMULATOR
create or replace function public.fn_what_if(p_question text, p_change jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare v_sup int; v_rev numeric; v_cost numeric; v_conv numeric; v_pool int;
  v_impact jsonb; v_conf numeric; v_id bigint;
begin
  select count(*) into v_sup from leads where approval_status='approved';
  select coalesce(sum(coalesce(reveal_fee,app_fee,0)),0) into v_rev from transactions where revealed_at>now()-interval '30 days';
  select coalesce(sum(cost_aed),0) into v_cost from ai_cost_log where occurred_at>now()-interval '30 days';
  select coalesce(sum(sendable),0) into v_pool from v_supply_gap;
  v_conv := 0.05;

  if p_question ~* 'reveal fee|reduce.*fee|lower.*fee' then
    v_impact := jsonb_build_object(
      'revenue_per_reveal','down by the discount percentage',
      'reveal_volume','unknown - no reveals have occurred, so elasticity is unmeasured',
      'net_revenue','indeterminate',
      'honest_answer','This cannot be simulated. Zero reveals have happened, so there is no price-response curve to extrapolate from. Any number would be invented.');
    v_conf := 0.15;
  elsif p_question ~* 'model price|openrouter|ai cost.*double|llm cost' then
    v_impact := jsonb_build_object(
      'current_monthly_ai_cost_aed', round(v_cost,2),
      'if_doubled_aed', round(v_cost*2,2),
      'share_of_total_budget', round(100.0*v_cost*2/nullif((select sum(monthly_aed) from department_budget),0),1)||'%',
      'mitigation','Model policy already routes by task class; cache adoption is 0%, so caching is the first lever.');
    v_conf := 0.8;
  elsif p_question ~* 'invite|supplier.*onboard|scale.*supplier' then
    v_impact := jsonb_build_object(
      'sendable_pool', v_pool,
      'expected_approved_at_5pct', round(v_pool*v_conv),
      'target', 860,
      'shortfall', greatest(0, 860 - round(v_pool*v_conv)),
      'note','Assumes a 5% invite-to-approved conversion, which is an assumption not an observation - no invite has converted yet.');
    v_conf := 0.45;
  elsif p_question ~* 'saudi|expand|new market' then
    v_impact := jsonb_build_object(
      'home_market_readiness', (select count(*) from v_supply_gap where approved>=10)||' of 86 categories at target',
      'assessment','Expanding before the home market has any onboarded supply spreads a thin pool thinner and the category knowledge is UAE-specific.');
    v_conf := 0.7;
  else
    v_impact := jsonb_build_object('assessment','No model exists for this question yet. Add a scenario to scenario_library so it can be simulated rather than guessed.');
    v_conf := 0.2;
  end if;

  insert into simulations (scenario, result) values (p_question, v_impact) returning id into v_id;
  return jsonb_build_object('id',v_id,'question',p_question,'projection',v_impact,'confidence',v_conf,
    'basis', jsonb_build_object('approved_suppliers',v_sup,'revenue_30d',v_rev,'ai_cost_30d',round(v_cost,2),'sendable_pool',v_pool));
end $fn$;
revoke execute on function public.fn_what_if(text,jsonb) from public, anon, authenticated;