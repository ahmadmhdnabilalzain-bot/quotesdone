-- comp-16: the seven health dimensions had a writer and no reader.
--
-- fn_os_review computes eight per-OS figures out of v_os_health and lands them in
-- os_review.metrics. Nothing then opened them: os_review is selected by fn_exec_meeting
-- (health, owner_agent, findings) and fn_company_snapshot (health) only, so open_risks,
-- kpi_gaps, capacity_pct, stale_tasks, backlog_per_head, review_pass_pct, budget_pct and
-- needs_founder_pct travelled from one store into another and stopped. That is the exact
-- pathology spec file #2 exists to catch, and it is a real gap, not a scoring artefact.
--
-- The reader is the person accountable for the OS. fn_agent_context puts agent_memory rows
-- with importance >= 5 into LAYER 4 of the employee prompt, so writing one brief per OS to
-- operating_system.owner_agent is the shortest path from the figure to the human who can act
-- on it. One row per owner, replaced each week, so this cannot accumulate.
create or replace function public.fn_os_health_brief()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare r record; v_period text; v_n int := 0;
begin
  select max(period) into v_period from os_review;
  if v_period is null then
    return jsonb_build_object('written', 0, 'reason', 'os_review is empty');
  end if;

  -- Only active OSes with an ACTIVE owner: a brief addressed to a departed employee is another
  -- write with no reader, which is the defect this function exists to close.
  for r in
    select o.os_key, o.name, o.owner_agent, rv.health, rv.metrics
      from operating_system o
      join os_review rv  on rv.os_key = o.os_key and rv.period = v_period
      join org_agents  a on a.agent_key = o.owner_agent and a.active
     where o.active
     order by o.num
  loop
    -- Scoped to this function's own rows by source, so it can never touch a memory it did not
    -- write. This is what makes the weekly run idempotent instead of cumulative.
    delete from agent_memory
     where agent_key = r.owner_agent and source = 'fn_os_health_brief';

    -- ->> everywhere, never ->. text || jsonb resolves to jsonb || jsonb and silently builds an
    -- array instead of a sentence; that has already cost this project two call-time failures.
    insert into agent_memory (agent_key, kind, content, source, importance, horizon)
    values (r.owner_agent, 'os_health',
      'OS HEALTH, week ' || v_period || ' - ' || r.name || ' (' || r.os_key || '), which you own. '
      || 'HEALTH SCORE ' || coalesce(r.metrics->>'health_score', '?') || '/100 ('
        || coalesce(r.health, 'unrated') || '). '
      || 'RISK: open_risks ' || coalesce(r.metrics->>'open_risks', '0') || '. '
      || 'PERFORMANCE: kpi_gaps ' || coalesce(r.metrics->>'kpi_gaps', '0') || ' against '
        || coalesce(r.metrics->>'kpis', '0') || ' KPI(s). '
      || 'CAPACITY: capacity_pct ' || coalesce(r.metrics->>'capacity_pct', 'unmeasured') || '%. '
      || 'BACKLOG: ' || coalesce(r.metrics->>'open_tasks', '0') || ' open, stale_tasks '
        || coalesce(r.metrics->>'stale_tasks', '0') || ', backlog_per_head '
        || coalesce(r.metrics->>'backlog_per_head', '0') || '. '
      || 'QUALITY: review_pass_pct ' || coalesce(r.metrics->>'review_pass_pct', 'unmeasured') || '%. '
      || 'COST: budget_pct ' || coalesce(r.metrics->>'budget_pct', '0') || '% of the AI budget. '
      || 'AUTOMATION: needs_founder_pct ' || coalesce(r.metrics->>'needs_founder_pct', '0')
        || '% of open work still needs the founder. '
      || 'Act on the worst figure before it becomes a finding.',
      'fn_os_health_brief', 7, 'short');

    v_n := v_n + 1;
  end loop;

  return jsonb_build_object('period', v_period, 'written', v_n);
end
$function$;

-- Weekly, five minutes after os_review_weekly (45 4 * * 1) writes the figures and fifteen
-- minutes before exec_meeting_weekly, so the owner reads this week's numbers, not last week's.
select cron.schedule('os_health_brief_weekly', '50 4 * * 1',
                     'select public.fn_os_health_brief();');

-- Seed the first run on both projects. Waiting for Monday would mean deploying a reader and
-- verifying nothing, and the figures for 2026-W32 already exist. The function replaces its own
-- rows by source, so running it here and again on the cron produces the same ten memories.
select public.fn_os_health_brief();
