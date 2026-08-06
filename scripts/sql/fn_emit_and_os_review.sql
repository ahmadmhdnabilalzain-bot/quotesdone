-- A CALLABLE EMITTER, AND THE OS HEALTH REVIEW THAT USES IT.
--
-- fn_emit_event is a TRIGGER function: it reads tg_argv and NEW, so no routine can call it. Every
-- one of the eleven programmatic writers therefore hand-rolled its own INSERT into company_event,
-- which is why correlation_id had to be fixed at the column rather than in one place. xos-12 needs
-- six more routines to emit rather than write into another OS's department, so the emitter comes
-- first and they all share it.
create or replace function public.fn_emit(p_event_type text, p_entity_type text, p_entity_id text,
                                          p_actor text default 'system',
                                          p_payload jsonb default '{}'::jsonb)
 returns bigint
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare v_id bigint;
begin
  -- correlation_id and causation_id are deliberately NOT named here. They carry the column
  -- defaults, which read app.correlation_id / app.causation_event_id — so an event emitted inside
  -- fn_event_dispatch's loop joins the chain it came from, and one emitted from a cron starts its
  -- own. Naming them here would override that and silently break the chain.
  insert into company_event (event_type, entity_type, entity_id, actor, payload)
  values (p_event_type, p_entity_type, p_entity_id, coalesce(p_actor,'system'), coalesce(p_payload,'{}'::jsonb))
  returning id into v_id;
  return v_id;
end $function$;

-- ── fn_os_review ───────────────────────────────────────────────────────────────────────────────
-- THREE CHANGES, ALL MEASURED:
--
-- comp-16-*  v_os_health computes open_risks, review_pass_pct, needs_founder_pct and
--            backlog_per_head per OS and HAD ZERO READERS — not one routine, view, cron or edge
--            function. The review already writes os_review.metrics, which fn_exec_meeting and
--            fn_company_snapshot already read, so this is a source swap (v_os_scoreboard ->
--            v_os_health) and four more keys in a jsonb object that is already consumed. Nothing
--            new is computed; something computed nightly stops being thrown away.
--
-- comp-16-health-score  operating_system.health_score was NULL on all 10 rows and last_health_at
--            NULL with it. The green/amber/red verdict was already derived here and discarded
--            after being written as text. health_score is NUMERIC, so the text verdict cannot
--            simply be copied into it — the score below is the finer-grained figure the column's
--            type asks for, and it is defined so that green/amber/red and the number cannot
--            disagree (the same inputs drive both).
--
-- xos-12     "No OS should call another OS directly for business logic." Founder decision of
--            6 Aug 2026: enforce. This routine's violation was NOT the whole insert — an OS
--            creating a task in its OWN department is not a cross-OS call and stays. It was the
--            `coalesce(..., 'exec')` fallback: when the owner agent could not be resolved, the
--            review wrote a task straight into the Executive Office, which belongs to the
--            leadership OS. That path now emits os.health_changed and the bus delivers it —
--            os_interface already declares os.health_changed as a leadership INPUT and a
--            subscription for it already exists, so the work still lands.
create or replace function public.fn_os_review()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare r record; v_period text := to_char(now(),'IYYY-"W"IW');
  v_health text; v_find jsonb; v_act int; v_total int := 0; v_red int := 0; v_amber int := 0;
  v_missed int; v_stale int; v_overspend numeric; v_score numeric; v_dept text; v_dept_os text;
  v_emitted int := 0; v_prev text;
begin
  -- BOTH views, joined, and not one or the other. v_os_health projects only a SUBSET of
  -- v_os_scoreboard: it carries open_risks/review_pass_pct/needs_founder_pct/backlog_per_head but
  -- drops kpis, kpis_unmeasurable and departments. Swapping the source outright would have
  -- compiled, deployed, reported success and then failed at call time on r.kpis — the exact class
  -- of bug that only a fixture catches.
  for r in select h.*, s.kpis, s.kpis_unmeasurable, s.departments
             from v_os_health h join v_os_scoreboard s on s.os_key = h.os_key loop
    v_find := '[]'::jsonb; v_act := 0;

    v_missed    := coalesce(r.kpi_gaps, 0);
    v_stale     := coalesce(r.stale_tasks, 0);
    v_overspend := coalesce(r.budget_pct, 0);

    if r.employees = 0 then
      v_find := v_find || jsonb_build_array(jsonb_build_object('issue','no employees','detail','This operating system has no staff.'));
    end if;
    if r.kpis = 0 then
      v_find := v_find || jsonb_build_array(jsonb_build_object('issue','no KPIs','detail','This operating system cannot be held to account.'));
    end if;
    if r.kpis_unmeasurable > 0 then
      v_find := v_find || jsonb_build_array(jsonb_build_object('issue','unmeasurable KPIs','detail',r.kpis_unmeasurable||' KPI(s) have no measure.'));
    end if;
    if v_missed > 0 then
      v_find := v_find || jsonb_build_array(jsonb_build_object('issue','KPIs missing target','detail',v_missed||' unclosed KPI gap(s).'));
    end if;
    if v_stale > 0 then
      v_find := v_find || jsonb_build_array(jsonb_build_object('issue','stale work','detail',v_stale||' task(s) open more than 14 days.'));
    end if;
    if coalesce(r.open_risks,0) > 0 then
      v_find := v_find || jsonb_build_array(jsonb_build_object('issue','open risks','detail',r.open_risks||' risk(s) owned inside this OS.'));
    end if;
    if v_overspend >= 95 then
      v_find := v_find || jsonb_build_array(jsonb_build_object('issue','budget halt','detail',v_overspend||'% of monthly AI budget spent.'));
    elsif v_overspend >= 70 then
      v_find := v_find || jsonb_build_array(jsonb_build_object('issue','budget degrade','detail',v_overspend||'% of monthly AI budget spent.'));
    end if;

    v_health := case
      when r.employees = 0 or r.kpis = 0 or v_overspend >= 95 then 'red'
      when jsonb_array_length(v_find) > 0 then 'amber'
      else 'green' end;

    -- The two verdicts are driven by the same inputs on purpose. A green OS scores at least 85 and
    -- a red one at most 60, so "green with a score of 40" is not a state this can produce — a text
    -- verdict and a number that can disagree is worse than either alone.
    v_score := greatest(0, 100
      - (case when r.employees = 0 then 40 else 0 end)
      - (case when r.kpis = 0 then 40 else 0 end)
      - least(20, coalesce(r.kpis_unmeasurable,0) * 4)
      - least(15, v_missed * 3)
      - least(15, v_stale * 2)
      - least(10, coalesce(r.open_risks,0) * 3)
      - (case when v_overspend >= 95 then 25 when v_overspend >= 70 then 10 else 0 end));

    select os.health_score::text into v_prev from operating_system os where os.os_key = r.os_key;

    update operating_system
       set health_score = v_score, last_health_at = now()
     where os_key = r.os_key;

    -- xos-12 / comp-07. Own OS -> a task, which is not a cross-OS call. Anything else -> the bus.
    select coalesce(a.department, null) into v_dept from org_agents a where a.agent_key = r.owner_agent;
    select od.os_key into v_dept_os from os_department od where od.dept_key = v_dept;

    if v_health <> 'green' then
      if v_dept is not null and v_dept_os is not distinct from r.os_key then
        insert into org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class)
        select v_dept,
               'OS review ['||v_health||']: '||r.name,
               'Owner: '||coalesce(r.owner_agent,'unassigned')||'. Week '||v_period||'. Findings: '||v_find::text
               ||'. Close each finding or bring evidence the standard is wrong.',
               'proposed','advisory', false, 'exec_review'
        where not exists (select 1 from org_tasks t2 where t2.title like 'OS review [%]: '||r.name and t2.status <> 'done');
        get diagnostics v_act = row_count;
      else
        -- The old code wrote this into 'exec' — a different OS — which is exactly what xos-12
        -- forbids. Emitting means leadership receives it through the bus it already subscribes to.
        perform public.fn_emit('os.health_changed', 'operating_system', r.os_key, 'fn_os_review',
                 jsonb_build_object('os_key', r.os_key, 'health', v_health, 'score', v_score,
                                    'period', v_period, 'findings', v_find,
                                    'reason', 'owner agent resolves to no department inside this OS'));
        v_emitted := v_emitted + 1;
      end if;
    end if;

    -- comp-07 / xos-13. os.health_changed was DECLARED by leadership and had never once fired.
    -- Emitted on a real transition only: emitting every week whether or not anything moved is how
    -- an event stream becomes noise nobody subscribes to.
    if v_prev is distinct from v_score::text then
      perform public.fn_emit('os.health_changed', 'operating_system', r.os_key, 'fn_os_review',
               jsonb_build_object('os_key', r.os_key, 'health', v_health, 'score', v_score,
                                  'previous_score', v_prev, 'period', v_period));
      v_emitted := v_emitted + 1;
    end if;

    insert into os_review (os_key, period, owner_agent, health, metrics, findings, actions)
    values (r.os_key, v_period, r.owner_agent, v_health,
            jsonb_build_object('departments',r.departments,'employees',r.employees,'open_tasks',r.open_tasks,
                               'kpis',r.kpis,'kpis_unmeasurable',r.kpis_unmeasurable,
                               'budget_pct',v_overspend,'kpi_gaps',v_missed,'stale_tasks',v_stale,
                               -- the four v_os_health columns that had no reader at all
                               'health_score',v_score,
                               'open_risks',coalesce(r.open_risks,0),
                               'review_pass_pct',r.review_pass_pct,
                               'needs_founder_pct',r.needs_founder_pct,
                               'backlog_per_head',r.backlog_per_head,
                               -- comp-16-capacity. resource_pool is `committed` against
                               -- `capacity`; there is no `used` column, and guessing one would
                               -- have deployed and failed at call time.
                               'capacity_pct',(select round(100.0*sum(rp.committed)/nullif(sum(rp.capacity),0),1)
                                                 from resource_pool rp where rp.os_key = r.os_key)),
            v_find, v_act)
    on conflict (os_key, period) do update
      set health=excluded.health, metrics=excluded.metrics, findings=excluded.findings,
          actions=excluded.actions, created_at=now();

    v_total := v_total + 1;
    if v_health='red' then v_red := v_red+1; elsif v_health='amber' then v_amber := v_amber+1; end if;
  end loop;

  insert into agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('os_review', now(), now(), case when v_red>0 then 'error' else 'ok' end,
          jsonb_build_object('reviewed',v_total,'red',v_red,'amber',v_amber,'green',v_total-v_red-v_amber,'emitted',v_emitted),
          'Operating system review, week '||v_period||': '||(v_total-v_red-v_amber)||' green, '||v_amber||' amber, '||v_red||' red.');

  return jsonb_build_object('reviewed',v_total,'red',v_red,'amber',v_amber,'green',v_total-v_red-v_amber,
                            'events_emitted',v_emitted);
end $function$;
