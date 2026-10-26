-- A MISSED KPI OPENS REMEDIATION AND ASSIGNS PRACTICE — the loop closes on "we missed, now what?".
--
-- fn_kpi_review already turned a missed KPI into an advisory org_task and an outcome_record. But the
-- remediation table (agent_remediation) and the training assigner (fn_assign_training) had no caller
-- from here: a miss was recorded and diagnosed, and nothing was ever OPENED against the employee to
-- fix the competency behind it. The component ledger recorded fn_open_remediation as
-- 'DEFERRED_RUNTIME_IMPLEMENTATION -- deployed, no trigger, no cron, no caller'. This wires it.
--
-- Now, for each missed KPI, once per (employee, metric) while a remediation is still open:
--   * fn_open_remediation records the failure against the responsible employee, with the metric,
--     attainment and the goal it serves in the detail, so reputation and the authority gate can see
--     an open remediation exists;
--   * fn_assign_training queues fresh unseen PRACTICE from that employee's own case pool (no
--     competency filter, because KPI metrics do not map one-to-one onto the training taxonomy). This
--     only inserts attempt rows; grading is a separate step and is the only part that needs a model.
--
-- No LLM is called here. This is the plumbing that makes training feed reputation (learning_speed)
-- when the workforce next runs; it does not itself do the remediation.

create or replace function public.fn_kpi_review()
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare r record; v_opened int:=0; v_missed int:=0; v_nodata int:=0; v_title text; v_task bigint;
  v_remediated int:=0; v_trained int:=0; v_rem bigint; v_comp text; v_tr jsonb; v_agent text;
begin
  for r in select * from fn_kpi_scoreboard() loop
    if r.verdict='NO DATA' then v_nodata:=v_nodata+1; continue; end if;
    if r.verdict<>'MISSED' then continue; end if;
    v_missed := v_missed+1;
    v_title := 'KPI missed: '||r.metric||' ('||r.agent_key||')';
    if exists (select 1 from org_tasks where title=v_title and status<>'done') then continue; end if;

    insert into org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class)
    values (coalesce(r.department,'exec'), v_title,
      'Owner: '||r.agent_key||'. Target '||coalesce(r.target::text,'?')||' '||coalesce(r.unit,'')||
      ', actual '||coalesce(r.actual::text,'?')||' ('||coalesce(r.attainment::text,'?')||'% of target), cadence '||coalesce(r.cadence,'?')||
      '. Serves company goal: '||coalesce(r.serves_goal,'unassigned')||
      '. Diagnose the cause and either close the gap or propose a revised target with evidence.',
      'proposed','advisory', false, 'recommend')
    returning id into v_task;

    perform fn_outcome_open(
      p_actor           => r.agent_key,
      p_decision        => 'Close the gap on: '||r.metric,
      p_subject_type    => 'org_task',
      p_subject_id      => v_task::text,
      p_expected_kpi_id => r.kpi_id,
      p_rationale       => 'KPI missed at '||coalesce(r.attainment::text,'?')||'% of target. Opened automatically by the weekly KPI review.',
      p_direction       => case when r.unit='percent_max' then 'down' else 'up' end,
      p_measure_after   => case when r.cadence='weekly' then interval '14 days' else interval '35 days' end
    );

    -- REMEDIATION + PRACTICE. Once per (employee, metric) while a remediation is still open, so a
    -- persistent miss does not open a new remediation every week.
    v_comp := coalesce(nullif(r.serves_goal,''), r.metric);
    -- A remediation can only be opened against a real, active employee: agent_remediation FKs to
    -- org_agents. Some KPIs are owned by a key that resolves to no employee (e.g. a department word);
    -- those still get the task and outcome_record above, but a remediation cannot be opened against
    -- nobody. Resolve the owner through the alias map first, exactly as fn_assign_training does.
    v_agent := coalesce(public.fn_org_agent_resolve(r.agent_key), r.agent_key);
    if exists (select 1 from org_agents o where o.agent_key = v_agent and o.active)
       and not exists (select 1 from agent_remediation ar
                    where ar.agent_key = v_agent and ar.failure_class = 'kpi_miss'
                      and coalesce(ar.detail->>'metric','') = r.metric and ar.status = 'open') then
      v_rem := fn_open_remediation(v_agent, 'kpi_miss', v_comp,
        jsonb_build_object('metric', r.metric, 'kpi_id', r.kpi_id, 'attainment', r.attainment,
                           'target', r.target, 'actual', r.actual, 'serves_goal', r.serves_goal,
                           'org_task_id', v_task, 'owner_key', r.agent_key, 'source', 'fn_kpi_review'));
      v_remediated := v_remediated + 1;
      -- queue unseen practice from the employee's own pool; a no-op if it has no case pool.
      begin
        v_tr := fn_assign_training(v_agent, null, 'practice', 3);
        v_trained := v_trained + coalesce((v_tr->>'assigned')::int, 0);
      exception when others then null;  -- practice is best-effort; a miss must still be remediated
      end;
    end if;

    v_opened := v_opened+1;
  end loop;

  insert into agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('kpi_review', now(), now(), 'ok',
          jsonb_build_object('missed',v_missed,'opened',v_opened,'no_data',v_nodata,
                             'remediations_opened',v_remediated,'practice_assigned',v_trained),
          'Weekly KPI review: '||v_missed||' missing target, '||v_opened||' task(s) + outcome record(s) opened, '
          ||v_remediated||' remediation(s) opened, '||v_trained||' practice case(s) assigned, '||v_nodata||' with no data.');
  return jsonb_build_object('missed',v_missed,'opened',v_opened,'no_data',v_nodata,
                            'remediations_opened',v_remediated,'practice_assigned',v_trained);
end $function$;
