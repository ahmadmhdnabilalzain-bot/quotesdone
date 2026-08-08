-- Grades every due outcome against its own claim, writes the lesson into organisational
-- memory, and flags anything that made things worse for reversal. This is the half of the
-- loop that did not exist: measure -> compare to baseline -> promote or roll back -> learn.
create or replace function public.fn_outcome_evaluate()
returns jsonb
language plpgsql security definer set search_path to 'public','pg_temp'
as $fn$
declare
  r record; v_sql text; v_now numeric; v_delta numeric; v_verdict text; v_lesson text;
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
      v_lesson := 'Could not be graded: no measurable KPI attached, or no reading available in the window. '
               || 'A change nobody can measure cannot be proven to have helped.';
      n_unmeasurable := n_unmeasurable + 1;
    else
      v_delta := v_now - r.baseline_value;
      if r.expected_direction = 'down' then v_delta := -v_delta; end if;

      if v_delta > 0 then
        v_verdict := 'improved';
        v_lesson := r.decision || ' -> ' || r.expected_metric || ' moved from ' || r.baseline_value
                 || ' to ' || v_now || ' as predicted. Promote to standard practice.';
        n_improved := n_improved + 1;
      elsif v_delta < 0 then
        v_verdict := 'worse';
        v_lesson := r.decision || ' -> ' || r.expected_metric || ' moved the WRONG WAY, from '
                 || r.baseline_value || ' to ' || v_now || '. Reverse this change and do not repeat it.';
        n_worse := n_worse + 1;
      else
        v_verdict := 'no_change';
        v_lesson := r.decision || ' -> ' || r.expected_metric || ' unchanged at ' || v_now
                 || '. The action was not the lever. Look elsewhere before spending more on this.';
        n_flat := n_flat + 1;
      end if;
    end if;

    update outcome_record
       set observed_value = v_now, observed_at = now(), delta = v_delta,
           verdict = v_verdict, lesson = v_lesson,
           promoted = (v_verdict = 'improved'),
           rollback_reason = case when v_verdict = 'worse'
                                  then 'Graded worse than baseline on ' || to_char(now(),'DD Mon YYYY')
                                  else null end,
           closed_at = now()
     where id = r.id;

    -- Every graded outcome becomes organisational memory, not just the successes.
    begin
      insert into institutional_memory (topic, lesson, source, dept_key, created_at)
      values ('outcome:' || coalesce(r.expected_metric, r.subject_type),
              v_lesson, 'outcome_record#' || r.id, r.dept_key, now());
    exception when others then null; end;

    -- A change that made things worse becomes work, immediately.
    if v_verdict = 'worse' then
      begin
        insert into org_tasks (dept_key, title, detail, status, tier, needs_founder, action_class)
        select coalesce(r.dept_key,'exec'),
               'ROLL BACK: ' || left(r.decision, 90),
               'Outcome record #' || r.id || ' graded WORSE. ' || v_lesson
               || ' Reverse the change, confirm the metric recovers, then close.',
               'proposed','gated', false, 'incident_fix'
        where not exists (select 1 from org_tasks where title = 'ROLL BACK: ' || left(r.decision, 90) and status <> 'done');
      exception when others then null; end;
    end if;
  end loop;

  insert into agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('outcome_evaluate', now(), now(), 'ok',
          jsonb_build_object('improved',n_improved,'worse',n_worse,'no_change',n_flat,'unmeasurable',n_unmeasurable),
          'Graded due outcomes: ' || n_improved || ' improved (promoted), ' || n_worse
          || ' worse (rollback task opened), ' || n_flat || ' no change, ' || n_unmeasurable || ' unmeasurable.');

  return jsonb_build_object('improved',n_improved,'worse',n_worse,'no_change',n_flat,'unmeasurable',n_unmeasurable);
end $fn$;

revoke execute on function public.fn_outcome_evaluate() from public, anon, authenticated;