-- ai_cost_log recorded 132 calls with agent_key and dept_key NULL on every row, so
-- department_budget (with degrade_at_pct / halt_at_pct already designed) could never fire.
-- fn_llm_log accepts p_dept and p_agent; callers pass null. Rather than wait for every
-- call site to be edited, derive the department from the function name - as data, not code.

create table if not exists public.ai_cost_fn_map (
  fn        text primary key,
  dept_key  text not null,
  agent_key text,
  note      text
);
alter table public.ai_cost_fn_map enable row level security;

insert into ai_cost_fn_map (fn, dept_key, agent_key, note) values
  ('agent_brain','exec','ceo','employee runtime'),
  ('agents','exec','ceo','agent roster runtime'),
  ('cos_execute','exec','brief','chief of staff execution'),
  ('dept_plan','exec','brief','daily department planning'),
  ('exec_agents','exec','ceo','executive agents'),
  ('canon_eval','knowledge','knowledge_curator','canon evaluation'),
  ('dept_learn','knowledge','knowledge_curator','daily learning'),
  ('gen_category_knowledge','knowledge','knowledge_curator','category knowledge generation'),
  ('knowledge_exam','knowledge','ai_trainer','auto-learning exams'),
  ('category_provision','knowledge','knowledge_curator','category provisioning'),
  ('enrich_capability','procurement','onboarding','supplier capability enrichment')
on conflict (fn) do nothing;

-- Attribute on the way in, so no call site has to change.
create or replace function public.trg_ai_cost_attribute()
returns trigger
language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare m record;
begin
  if new.dept_key is null or new.agent_key is null then
    select * into m from ai_cost_fn_map where fn = new.fn;
    if found then
      new.dept_key  := coalesce(new.dept_key,  m.dept_key);
      new.agent_key := coalesce(new.agent_key, m.agent_key);
    end if;
  end if;
  return new;
exception when others then return new;
end $fn$;

drop trigger if exists trg_ai_cost_attribute on public.ai_cost_log;
create trigger trg_ai_cost_attribute before insert on public.ai_cost_log
  for each row execute function public.trg_ai_cost_attribute();

-- Backfill the 132 unattributed rows.
update ai_cost_log c set dept_key = m.dept_key, agent_key = coalesce(c.agent_key, m.agent_key)
from ai_cost_fn_map m where c.fn = m.fn and c.dept_key is null;

-- Roll spend into the budget and let the degrade/halt thresholds actually fire.
create or replace function public.fn_budget_rollup()
returns jsonb
language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare v_period text := to_char(current_date,'YYYY-MM'); n int := 0; v_degraded int := 0; v_halted int := 0; r record;
begin
  update department_budget b
     set spent_aed = coalesce(s.total,0), period_label = v_period, updated_at = now()
  from (
    select dept_key, sum(cost_aed) total
    from ai_cost_log
    where dept_key is not null and occurred_at >= date_trunc('month', now())
    group by dept_key
  ) s
  where b.dept_key = s.dept_key;
  get diagnostics n = row_count;

  for r in
    select dept_key, monthly_aed, spent_aed, degrade_at_pct, halt_at_pct,
           round(100.0*spent_aed/nullif(monthly_aed,0),1) as pct
    from department_budget
    where monthly_aed > 0 and spent_aed is not null
  loop
    if r.pct >= r.halt_at_pct then
      v_halted := v_halted + 1;
      insert into founder_alerts (level, event, detail, channel)
      select 'high','ai_budget_halt', r.dept_key||' has spent '||r.pct||'% of its monthly AI budget ('||r.spent_aed||' of '||r.monthly_aed||' AED). Halt threshold '||r.halt_at_pct||'% reached.','email'
      where not exists (select 1 from founder_alerts where event='ai_budget_halt' and detail like r.dept_key||'%' and created_at > now()-interval '24 hours');
    elsif r.pct >= r.degrade_at_pct then
      v_degraded := v_degraded + 1;
      insert into org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class)
      select r.dept_key, 'AI budget degrade threshold: '||r.dept_key,
             r.dept_key||' has spent '||r.pct||'% of its monthly AI budget. Move non-critical work to the cheaper model tier and enable response caching before the halt threshold at '||r.halt_at_pct||'%.',
             'proposed','gated', false, 'recommend'
      where not exists (select 1 from org_tasks where title='AI budget degrade threshold: '||r.dept_key and status<>'done');
    end if;
  end loop;

  insert into agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('budget_rollup', now(), now(), 'ok',
          jsonb_build_object('depts_updated',n,'degraded',v_degraded,'halted',v_halted),
          'AI spend rolled into department budgets: '||n||' departments, '||v_degraded||' past degrade threshold, '||v_halted||' past halt.');
  return jsonb_build_object('updated',n,'degraded',v_degraded,'halted',v_halted);
end $fn$;

revoke execute on function public.fn_budget_rollup() from public, anon, authenticated;