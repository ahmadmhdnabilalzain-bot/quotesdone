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
--
-- 6 AUG 2026, ROUND 2 — capacity_pct WAS A CONSTANT, NOT A MEASUREMENT. fn_os_review computes
-- it as sum(committed)/sum(capacity) over resource_pool for the OS. Measured: NO routine, view
-- or cron in the database ever wrote resource_pool, so `committed` was 0 on all ten rows and
-- the ratio was 0.0 wherever it resolved at all; three rows carried a NULL os_key and six of
-- the ten active OSes had no row, so capacity_pct was NULL for them. "10 of 10 OS carry
-- capacity" was a true statement about a key and a false one about a figure.
--
-- resource_pool now has a writer, and it is this function, because this is the weekly job that
-- runs BETWEEN os_review_weekly (45 4 * * 1) and exec_meeting_weekly (0 5 * * 1). It refreshes
-- every committed figure from the system that actually consumes the resource, then re-runs
-- fn_os_review for the current period — the upsert is on (os_key, period), the org_tasks insert
-- is guarded by a not-exists, and fn_emit only fires on a score TRANSITION, so a second run in
-- the same week recomputes the metrics and changes nothing else. The brief, and the exec meeting
-- fifteen minutes later, then read figures whose numerator was measured this morning.
create or replace function public.fn_os_health_brief()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare r record; v_period text; v_n int := 0; v_pool int := 0;
begin
  -- ---------------------------------------------------------------------------------------
  -- 1. ONE CAPACITY ROW PER ACTIVE OS, in the one unit every OS has: its own people's
  -- attention. The seed carried a single company-wide row (550 open tasks, keyed to
  -- leadership), which is why six operating systems reported no capacity at all. Both sides
  -- are measured live — org_agents.max_open_tasks is the declared ceiling, org_tasks the
  -- load — so this figure moves on its own and is falsifiable by looking at the org.
  delete from resource_pool where source_ref = 'org_agents.max_open_tasks';

  insert into resource_pool (resource, kind, owner_dept, unit, capacity, committed,
                             window_label, degrade_at_pct, halt_at_pct, source_ref, note, os_key)
  select 'Employee attention - ' || o.name, 'capacity',
         (select min(od.dept_key) from os_department od where od.os_key = o.os_key),
         'open tasks',
         coalesce((select sum(a.max_open_tasks) from os_department od
                     join org_agents a on a.department = od.dept_key and a.active
                    where od.os_key = o.os_key), 0),
         coalesce((select count(*) from os_department od
                     join org_tasks t on t.dept_key = od.dept_key and t.status <> 'done'
                    where od.os_key = o.os_key), 0),
         'rolling', 80, 100, 'org_agents.max_open_tasks',
         'Open tasks in this OS''s departments against the sum of max_open_tasks for its '
         || 'active staff. Refreshed weekly by fn_os_health_brief.', o.os_key
    from operating_system o where o.active;
  get diagnostics v_pool = row_count;

  -- 2. EVERY OTHER POOLED RESOURCE GETS A MEASURED NUMERATOR TOO. Each expression is the
  -- system of record for that resource; a resource whose consumption nothing records would
  -- otherwise sit at zero for ever and drag the OS's ratio down with it, which is the same
  -- "populated but never measured" defect one level down.
  update resource_pool rp set committed = m.v, updated_at = now()
    from (values
      ('AI token budget - company',
        (select coalesce(sum(cost_aed), 0)::numeric from ai_cost_log
          where occurred_at >= date_trunc('month', now()))),
      ('Supplier invites',
        (select coalesce(sum(sent), 0)::numeric from invite_schedule where day = current_date)),
      ('Outbound email',
        (select count(*)::numeric from notifications
          where coalesce(channel, 'email') = 'email' and created_at > now() - interval '1 day')),
      ('WhatsApp / SMS',
        (select count(*)::numeric from wa_messages where created_at > now() - interval '1 day')
      + (select count(*)::numeric from notifications
          where channel in ('sms', 'whatsapp') and created_at > now() - interval '1 day')),
      -- A FLOOR, NOT A TOTAL: this counts the scheduled invocations, which is every edge call
      -- the database itself can see. Browser and webhook traffic is not in cron.job_run_details.
      ('Edge function invocations',
        (select count(*)::numeric from cron.job_run_details d
           join cron.job j on j.jobid = d.jobid
          where j.command ~* 'net\.http_post' and d.start_time >= date_trunc('month', now()))),
      ('Database storage',
        round(pg_database_size(current_database()) / 1073741824.0, 2)::numeric),
      ('Document storage',
        (select round(coalesce(sum((o.metadata->>'size')::bigint), 0) / 1073741824.0, 2)::numeric
           from storage.objects o)),
      ('Scraping / enrichment',
        (select coalesce(sum(fetched), 0)::numeric from scrape_runs
          where created_at >= date_trunc('month', now()))),
      ('Payment processing',
        (select count(*)::numeric from transactions where revealed_at > now() - interval '1 day'))
    ) as m(resource, v)
   where rp.resource = m.resource;

  -- 3. The report is computed FROM those inputs, so recompute it now that they are current.
  -- Without this the week's capacity_pct would be derived from last Monday's numerator.
  perform fn_os_review();

  -- ---------------------------------------------------------------------------------------
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

  return jsonb_build_object('period', v_period, 'written', v_n, 'capacity_rows', v_pool);
end
$function$;

-- The three orphaned pooled resources. supplier_success is not mapped in os_department, so its
-- three rows (invites, supplier WhatsApp/SMS, supplier enrichment) had a NULL os_key and counted
-- towards no operating system at all. They are Marketplace supply acquisition; everything else
-- resolves through os_department.
update public.resource_pool rp
   set os_key = od.os_key, updated_at = now()
  from public.os_department od
 where rp.os_key is null and od.dept_key = rp.owner_dept;

update public.resource_pool set os_key = 'marketplace', updated_at = now()
 where os_key is null and owner_dept = 'supplier_success';

-- Weekly, five minutes after os_review_weekly (45 4 * * 1) writes the figures and ten minutes
-- before exec_meeting_weekly, so the owner reads this week's numbers, not last week's.
select cron.schedule('os_health_brief_weekly', '50 4 * * 1',
                     'select public.fn_os_health_brief();');

-- Seed the first run on both projects. Waiting for Monday would mean deploying a reader and
-- verifying nothing, and the figures for 2026-W32 already exist. The function replaces its own
-- rows by source, so running it here and again on the cron produces the same ten memories.
select public.fn_os_health_brief();
