-- correct the institutional_memory write to the real column set
create or replace function public.fn_outcome_evaluate()
returns jsonb
language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare
  r record; v_now numeric; v_delta numeric; v_verdict text; v_lesson text;
  n_improved int := 0; n_worse int := 0; n_flat int := 0; n_unmeasurable int := 0;
begin
  for r in
    select o.*, k.measure_sql
    from outcome_record o
    left join employee_kpi k on k.id = o.expected_kpi_id
    where o.verdict = 'pending' and o.due_at <= now()
  loop
    v_now := null;
    begin
      if r.measure_sql is not null then execute r.measure_sql into v_now; end if;
    exception when others then v_now := null; end;

    if v_now is null or r.baseline_value is null then
      v_verdict := 'unmeasurable'; v_delta := null;
      v_lesson := 'Could not be graded: no measurable KPI attached, or no reading in the window. A change nobody can measure cannot be proven to have helped.';
      n_unmeasurable := n_unmeasurable + 1;
    else
      v_delta := v_now - r.baseline_value;
      if r.expected_direction = 'down' then v_delta := -v_delta; end if;
      if v_delta > 0 then
        v_verdict := 'improved';
        v_lesson := r.decision||' -> '||coalesce(r.expected_metric,'metric')||' moved '||r.baseline_value||' to '||v_now||' as predicted. Promote to standard practice.';
        n_improved := n_improved + 1;
      elsif v_delta < 0 then
        v_verdict := 'worse';
        v_lesson := r.decision||' -> '||coalesce(r.expected_metric,'metric')||' moved the WRONG WAY, '||r.baseline_value||' to '||v_now||'. Reverse this change and do not repeat it.';
        n_worse := n_worse + 1;
      else
        v_verdict := 'no_change';
        v_lesson := r.decision||' -> '||coalesce(r.expected_metric,'metric')||' unchanged at '||v_now||'. The action was not the lever. Look elsewhere before spending more here.';
        n_flat := n_flat + 1;
      end if;
    end if;

    update outcome_record
       set observed_value=v_now, observed_at=now(), delta=v_delta, verdict=v_verdict, lesson=v_lesson,
           promoted=(v_verdict='improved'),
           rollback_reason=case when v_verdict='worse' then 'Graded worse than baseline on '||to_char(now(),'DD Mon YYYY') else null end,
           closed_at=now()
     where id = r.id;

    begin
      insert into institutional_memory (kind, subject_type, subject_id, headline, detail, outcome,
                                        learned_by, confidence, evidence_ref, occurred_at)
      values ('outcome', r.subject_type, r.subject_id,
              left(coalesce(r.expected_metric, r.decision), 120), v_lesson, v_verdict,
              r.actor, case v_verdict when 'improved' then 0.9 when 'worse' then 0.9 else 0.6 end,
              'outcome_record#'||r.id, now());
    exception when others then null; end;

    if v_verdict = 'worse' then
      begin
        insert into org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class)
        select coalesce(r.dept_key,'exec'), 'ROLL BACK: '||left(r.decision,90),
               'Outcome record #'||r.id||' graded WORSE. '||v_lesson||' Reverse the change, confirm the metric recovers, then close.',
               'proposed','gated', false, 'incident_fix'
        where not exists (select 1 from org_tasks where title='ROLL BACK: '||left(r.decision,90) and status<>'done');
      exception when others then null; end;
    end if;
  end loop;

  insert into agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('outcome_evaluate', now(), now(), 'ok',
          jsonb_build_object('improved',n_improved,'worse',n_worse,'no_change',n_flat,'unmeasurable',n_unmeasurable),
          'Graded due outcomes: '||n_improved||' improved, '||n_worse||' worse (rollback opened), '||n_flat||' no change, '||n_unmeasurable||' unmeasurable.');

  return jsonb_build_object('improved',n_improved,'worse',n_worse,'no_change',n_flat,'unmeasurable',n_unmeasurable);
end $fn$;

revoke execute on function public.fn_outcome_evaluate() from public, anon, authenticated;

-- WIRE IT UP: every KPI-miss task now opens an outcome record with the baseline captured,
-- so the fix is graded against the number it promised to move.
create or replace function public.fn_kpi_review()
returns jsonb
language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare r record; v_opened int:=0; v_missed int:=0; v_nodata int:=0; v_title text; v_task bigint;
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

    v_opened := v_opened+1;
  end loop;

  insert into agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('kpi_review', now(), now(), 'ok',
          jsonb_build_object('missed',v_missed,'opened',v_opened,'no_data',v_nodata),
          'Weekly KPI review: '||v_missed||' missing target, '||v_opened||' task(s) + outcome record(s) opened, '||v_nodata||' with no data.');
  return jsonb_build_object('missed',v_missed,'opened',v_opened,'no_data',v_nodata);
end $fn$;

revoke execute on function public.fn_kpi_review() from public, anon, authenticated;