-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260727004408   name: bi_innovation_simulation_evolution_collaboration
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ============ 12. BUSINESS INTELLIGENCE ============
create table if not exists public.metric_definition (
  metric_key  text primary key,
  label       text not null,
  domain      text not null check (domain in ('demand','supply','liquidity','revenue','quality','cost','ops')),
  definition  text not null,
  measure_sql text not null,
  target       numeric,
  direction   text not null default 'up' check (direction in ('up','down')),
  owner_dept  text,
  active      boolean not null default true
);

insert into public.metric_definition (metric_key, label, domain, definition, measure_sql, target, direction, owner_dept) values
('inquiries_7d','Inquiries received (7d)','demand','Buyer briefs submitted in the last 7 days. The top of the funnel; everything downstream is a fraction of it.','select count(*) from inquiries where created_at > now() - interval ''7 days''', 50, 'up','marketing'),
('rfq_ready_pct','RFQ-ready rate','quality','Share of inquiries complete enough to fan out to suppliers without a scoping call.','select round(100.0*count(*) filter (where rfq_ready)/nullif(count(*),0),1) from inquiries where created_at > now() - interval ''30 days''', 70, 'up','knowledge'),
('quotes_per_inquiry','Quotes per inquiry (30d)','liquidity','Average number of supplier quotes an inquiry attracts. Below 3 the buyer has no real comparison and the reveal fee is hard to justify.','select round(avg(q)::numeric,2) from (select i.id, count(qt.id) q from inquiries i left join quotes qt on qt.inquiry_id=i.id where i.created_at > now() - interval ''30 days'' group by i.id) s', 3, 'up','supplier_success'),
('verified_suppliers','Verified suppliers','supply','Suppliers with a recorded, unexpired trade licence. The only supplier count that means anything.','select count(*) from leads where verified', 2000, 'up','supplier_success'),
('supplier_response_rate','Supplier response rate (30d)','supply','Share of fanned-out RFQs that receive a quote. The number that decides whether reveals refund.','select round(avg(rv_response_rate)::numeric,1) from leads where rv_reveals > 0', 60, 'up','supplier_success'),
('reveals_30d','Paid reveals (30d)','revenue','Reveals paid for in the last 30 days. The only transaction revenue line.','select count(*) from transactions where revealed_at > now() - interval ''30 days''', 40, 'up','finance'),
('reveal_revenue_30d','Reveal revenue (30d, AED)','revenue','Sum of reveal fees collected in the last 30 days.','select coalesce(sum(reveal_fee),0) from transactions where revealed_at > now() - interval ''30 days''', 20000, 'up','finance'),
('refund_rate','Reveal refund rate','quality','Share of reveals refunded, almost always because the supplier never responded. Directly destroys contribution margin.','select round(100.0*count(*) filter (where refund_status is not null and refund_status <> ''none'')/nullif(count(*),0),1) from transactions where revealed_at is not null', 5, 'down','customer_success'),
('ai_cost_30d','AI cost (30d, AED)','cost','OpenRouter spend in the last 30 days across all functions.','select coalesce(sum(cost_aed),0) from ai_cost_log where occurred_at > now() - interval ''30 days''', 7700, 'down','it'),
('avoidable_ai_pct','Avoidable AI spend','cost','Share of model calls the cost governor flagged as doable more cheaply or deterministically.','select round(100.0*count(*) filter (where could_be_cheaper)/nullif(count(*),0),1) from ai_cost_log where occurred_at > now() - interval ''30 days''', 10, 'down','it'),
('categories_live','Categories with real liquidity','liquidity','Categories that have both an inquiry and a responsive supplier in the last 30 days. The honest measure of how much of the catalogue actually works.','select count(*) from v_marketplace_liquidity where coalesce(inquiries_30d,0) > 0 and coalesce(responsive_suppliers,0) > 0', 10, 'up','exec'),
('knowledge_compliance_pct','Knowledge compliance','quality','Share of the 84 catalogue categories whose employee holds all 14 expert modules.','select round(100.0*count(*) filter (where coverage=''COMPLIANT'')/nullif(count(*),0),1) from v_category_coverage', 100, 'up','knowledge'),
('failed_runs_24h','Failed scheduled runs (24h)','ops','Scheduled jobs that errored in the last day. Anything above zero is an unattended failure.','select count(*) from agent_runs where ok = false and started_at > now() - interval ''24 hours''', 0, 'down','it'),
('open_p1','Open P1 backlog items','ops','Priority-1 specification items not yet done.','select count(*) from spec_backlog where priority=1 and status <> ''done''', 0, 'down','exec')
on conflict (metric_key) do update set label=excluded.label, definition=excluded.definition,
  measure_sql=excluded.measure_sql, target=excluded.target, direction=excluded.direction, owner_dept=excluded.owner_dept;

create table if not exists public.metric_snapshot (
  id bigserial primary key,
  metric_key text not null references public.metric_definition(metric_key) on delete cascade,
  value numeric,
  error text,
  taken_at timestamptz not null default now()
);
create index if not exists metric_snapshot_key_time_idx on public.metric_snapshot (metric_key, taken_at desc);

-- Executes each metric's own SQL. Deterministic; no model call.
create or replace function public.fn_bi_snapshot() returns table (metric_key text, value numeric, error text)
language plpgsql security definer set search_path = public as $fn$
declare r record; v numeric; e text;
begin
  for r in select m.metric_key, m.measure_sql from metric_definition m where m.active loop
    v := null; e := null;
    begin
      execute r.measure_sql into v;
    exception when others then e := left(sqlerrm, 200);
    end;
    insert into metric_snapshot (metric_key, value, error) values (r.metric_key, v, e);
    metric_key := r.metric_key; value := v; error := e;
    return next;
  end loop;
end; $fn$;

revoke execute on function public.fn_bi_snapshot() from anon, authenticated, public;

create or replace view public.v_bi_scorecard as
with latest as (
  select distinct on (s.metric_key) s.metric_key, s.value, s.error, s.taken_at
  from metric_snapshot s order by s.metric_key, s.taken_at desc
)
select d.metric_key, d.label, d.domain, d.owner_dept, l.value, d.target, d.direction,
       case
         when l.error is not null then 'ERROR'
         when l.value is null or d.target is null then 'UNMEASURED'
         when d.direction='up'   and l.value >= d.target then 'ON_TARGET'
         when d.direction='down' and l.value <= d.target then 'ON_TARGET'
         when d.direction='up'   and l.value >= d.target*0.7 then 'BEHIND'
         when d.direction='down' and l.value <= d.target*1.3 then 'BEHIND'
         else 'OFF_TARGET'
       end as state,
       l.error, l.taken_at, d.definition
from metric_definition d left join latest l on l.metric_key = d.metric_key
where d.active;

-- ============ 11. INNOVATION ENGINE ============
-- Deterministic scoring: value per unit of effort, weighted by confidence. No LLM.
create or replace function public.fn_idea_score(p_value numeric, p_effort text, p_confidence numeric)
returns numeric language sql immutable as $fn$
  select round(
    coalesce(p_value,0)
    * coalesce(p_confidence,0.5)
    / case lower(coalesce(p_effort,'m'))
        when 's' then 1 when 'small' then 1
        when 'm' then 3 when 'medium' then 3
        when 'l' then 8 when 'large' then 8
        when 'xl' then 20 else 3 end
  , 2);
$fn$;

create or replace function public.fn_idea_rescore() returns trigger
language plpgsql as $fn$
begin
  new.score := public.fn_idea_score(new.expected_value_aed, new.effort, new.confidence);
  new.updated_at := now();
  return new;
end; $fn$;

drop trigger if exists trg_idea_score on public.idea;
create trigger trg_idea_score before insert or update on public.idea
for each row execute function public.fn_idea_rescore();

create or replace view public.v_innovation_pipeline as
select i.id, i.title, i.dept_key, i.submitted_by, i.category, i.serves_goal,
       i.expected_value_aed, i.effort, i.confidence, i.score, i.stage, i.outcome, i.created_at
from idea i
order by case i.stage when 'proposed' then 1 when 'assessing' then 2 when 'approved' then 3
                      when 'building' then 4 when 'shipped' then 5 else 6 end,
         i.score desc nulls last;

-- ============ 10. SIMULATION ============
-- Deterministic marketplace model. Answers "what happens if we change X" without a model call.
create or replace function public.fn_simulate_growth(
  p_invites_per_day integer,
  p_invite_accept_rate numeric,
  p_verification_rate numeric,
  p_months integer default 24,
  p_target_verified integer default 2000
) returns jsonb
language plpgsql immutable as $fn$
declare
  v_per_month numeric := p_invites_per_day * 30.0;
  v_verified_per_month numeric := v_per_month * coalesce(p_invite_accept_rate,0) * coalesce(p_verification_rate,0);
  v_months_to_target numeric;
  v_at_horizon numeric;
begin
  if v_verified_per_month <= 0 then
    return jsonb_build_object(
      'verified_per_month', 0,
      'months_to_target', null,
      'verified_at_horizon', 0,
      'verdict', 'UNREACHABLE: no supplier is verified at these rates');
  end if;
  v_months_to_target := ceil(p_target_verified / v_verified_per_month);
  v_at_horizon := round(v_verified_per_month * p_months);
  return jsonb_build_object(
    'invites_per_day', p_invites_per_day,
    'invite_accept_rate', p_invite_accept_rate,
    'verification_rate', p_verification_rate,
    'verified_per_month', round(v_verified_per_month,1),
    'months_to_target', v_months_to_target,
    'years_to_target', round(v_months_to_target/12.0, 2),
    'verified_at_horizon', v_at_horizon,
    'horizon_months', p_months,
    'target_verified', p_target_verified,
    'verdict', case when v_months_to_target <= p_months then 'REACHABLE within horizon'
                    else 'MISSES horizon by ' || (v_months_to_target - p_months) || ' months' end);
end; $fn$;

-- ============ 16. SELF-EVOLUTION ============
create table if not exists public.evolution_proposal (
  id           bigserial primary key,
  trigger_kind text not null check (trigger_kind in ('repeated_failure','metric_off_target','cost_anomaly','manual','audit_gap','review_rejection')),
  subject      text not null,
  observation  text not null,
  evidence     jsonb default '{}'::jsonb,
  proposal     text not null,
  change_class text not null default 'process' check (change_class in ('knowledge','process','code','policy','model_routing','org')),
  status       text not null default 'proposed' check (status in ('proposed','accepted','rejected','implemented')),
  decided_by   text,
  created_at   timestamptz not null default now()
);
create unique index if not exists evolution_proposal_dedupe_idx
  on public.evolution_proposal (trigger_kind, subject, change_class) where status = 'proposed';

-- Detects its own failure patterns and proposes a change. Deterministic detection.
create or replace function public.fn_evolution_scan() returns integer
language plpgsql security definer set search_path = public as $fn$
declare n integer := 0;
begin
  -- Any scheduled function failing 3+ times in 7 days is a process defect, not bad luck.
  insert into evolution_proposal (trigger_kind, subject, observation, evidence, proposal, change_class)
  select 'repeated_failure', r.fn,
         format('%s failed %s times in the last 7 days.', r.fn, r.fails),
         jsonb_build_object('failures_7d', r.fails),
         format('Root-cause %s rather than retry it. If the failure is external, add a documented fallback to continuity_plan; if it is a parsing or contract failure, fix the contract and add a regression test.', r.fn),
         'code'
  from (select fn, count(*) fails from agent_runs
        where ok = false and started_at > now() - interval '7 days' group by fn having count(*) >= 3) r
  on conflict do nothing;
  get diagnostics n = row_count;

  -- Metrics sitting off target are a strategy signal, not a dashboard colour.
  insert into evolution_proposal (trigger_kind, subject, observation, evidence, proposal, change_class)
  select 'metric_off_target', s.metric_key,
         format('%s is %s against a target of %s.', s.label, coalesce(s.value::text,'unmeasured'), s.target),
         jsonb_build_object('value', s.value, 'target', s.target, 'owner', s.owner_dept),
         format('%s owns this. Either the target is wrong and should be restated, or the operating approach behind it is wrong and should change. Do not carry it as-is for another period.', coalesce(s.owner_dept,'exec')),
         'process'
  from v_bi_scorecard s where s.state = 'OFF_TARGET'
  on conflict do nothing;

  -- Model spend that deterministic code could have handled.
  insert into evolution_proposal (trigger_kind, subject, observation, evidence, proposal, change_class)
  select 'cost_anomaly', c.fn,
         format('%s made %s model calls in 30 days that the cost governor flagged as avoidable.', c.fn, c.n),
         jsonb_build_object('avoidable_calls', c.n, 'cost_aed', c.cost),
         format('Replace the flagged path in %s with a rule, a lookup or SQL, or drop it to the small tier.', c.fn),
         'model_routing'
  from (select fn, count(*) n, round(sum(cost_aed),2) cost from ai_cost_log
        where could_be_cheaper and occurred_at > now() - interval '30 days'
        group by fn having count(*) >= 5) c
  on conflict do nothing;

  return (select count(*) from evolution_proposal where status='proposed');
end; $fn$;

revoke execute on function public.fn_evolution_scan() from anon, authenticated, public;

-- ============ LAYER 22. CROSS-DEPARTMENT COLLABORATION ============
create table if not exists public.collaboration_rule (
  id            bigserial primary key,
  situation     text not null unique,
  owner_dept    text not null,
  must_involve  text[] not null default '{}',
  must_review   text[] not null default '{}',
  may_challenge text[] not null default '{}',
  reason        text not null,
  blocking      boolean not null default true
);

insert into public.collaboration_rule (situation, owner_dept, must_involve, must_review, may_challenge, reason, blocking) values
('Changing the reveal fee or any pricing parameter','finance', array['exec','analytics'], array['exec'], array['customer_success','supplier_success'],'Pricing is the business model. Analytics supplies the elasticity evidence, the founder signs it off.', true),
('Approving a supplier whose documents are incomplete','supplier_success', array['legal'], array['legal'], array['it'],'An unverified supplier reaching a buyer costs trust, which is the whole product.', true),
('Publishing anything externally','marketing', array['legal'], array['exec'], array['knowledge'],'Published claims are commitments. Legal checks claims, knowledge checks technical accuracy.', true),
('Issuing a refund above the automatic threshold','finance', array['customer_success'], array['exec'], array[]::text[],'Refunds are both a cost and a customer signal; the reason matters as much as the money.', true),
('Adding or removing a supplier category','knowledge', array['analytics','supplier_success'], array['exec'], array['marketing'],'A category with no supply is a broken promise to buyers; a category with no demand is wasted acquisition.', true),
('Changing a model or routing rule','it', array['finance'], array['exec'], array['knowledge'],'Model choice is a cost decision and a quality decision at the same time.', true),
('Responding to a security incident','it', array['legal','exec'], array['exec'], array[]::text[],'Disclosure obligations and technical response must move together.', true),
('Banning a supplier or buyer','legal', array['supplier_success','customer_success'], array['exec'], array[]::text[],'Irreversible and reputational. Never a single-employee decision.', true),
('Setting or revising a department budget','finance', array['exec'], array['exec'], array[]::text[],'Budgets are the mechanism that stops AI spend growing quietly.', true),
('Changing knowledge that employees rely on','knowledge', array[]::text[], array['exec'], array['analytics','supplier_success','customer_success'],'Knowledge changes propagate to every quote and every answer. Anyone may challenge a module they believe is wrong.', false)
on conflict (situation) do update set must_involve=excluded.must_involve, must_review=excluded.must_review,
  may_challenge=excluded.may_challenge, reason=excluded.reason, blocking=excluded.blocking;

alter table public.metric_definition enable row level security;
alter table public.metric_snapshot enable row level security;
alter table public.evolution_proposal enable row level security;
alter table public.collaboration_rule enable row level security;
