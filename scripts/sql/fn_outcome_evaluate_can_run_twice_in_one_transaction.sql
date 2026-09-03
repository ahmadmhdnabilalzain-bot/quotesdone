-- fn_outcome_evaluate CAN RUN TWICE IN ONE TRANSACTION (4 Sep 2026).
--
-- The evaluator builds a temporary table _due_group ON COMMIT DROP without guarding against a
-- previous call in the same transaction. Until 3 Sep an open stand-down made every first call return
-- PAUSED before the table existed, so the defect never showed; with the stand-down lifted, the
-- connectivity scenario that calls the evaluator, clears the stand-down and calls it again raised
-- 42P07 "relation _due_group already exists". The table is now dropped if a prior call left it.
-- Every other line is the live definition, unchanged.
--
--   node scripts/apply_sql.mjs scripts/sql/fn_outcome_evaluate_can_run_twice_in_one_transaction.sql --apply --ddl
CREATE OR REPLACE FUNCTION public.fn_outcome_evaluate()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  r record; v_now numeric; v_delta numeric; v_verdict text; v_lesson text;
  n_improved int := 0; n_worse int := 0; n_flat int := 0; n_unmeasurable int := 0;
  v_claimants int; v_others text; v_lead_id bigint; v_is_lead boolean; v_conf numeric;
begin
  -- THE FOUNDER STAND-DOWN. Grading opens corrective ROLL BACK work on a 'worse' verdict, so it pauses
  -- with the workforce exactly as fn_reputation_recompute and fn_promotion_review do. It resumes and
  -- grades the due backlog once the hold lifts.
  if exists (select 1 from public.company_stand_down where resumed_at is null) then
    return jsonb_build_object('ok', false, 'status','PAUSED_BY_FOUNDER_STANDDOWN',
      'improved',0,'worse',0,'no_change',0,'unmeasurable',0,
      'note','Outcome grading opens corrective work and pauses with the founder hold; it resumes when the hold lifts.');
  end if;

  -- 4 SEP 2026: a second call in the same transaction (a probe that first sees the routine pause, then
  -- clears the stand-down and calls again) found this table already there and raised 42P07. The
  -- table belongs to this call; drop what an earlier call in the transaction left.
  drop table if exists _due_group;
  create temporary table _due_group on commit drop as
  select o.id,
         count(*)      over w as claimants,
         min(o.id)     over w as lead_id,
         string_agg(o.actor, ', ') over (partition by coalesce(k.measure_sql, 'id:'||o.id::text)) as actors
  from outcome_record o
  left join employee_kpi k on k.id = o.expected_kpi_id
  where o.verdict = 'pending' and o.due_at <= now()
  window w as (partition by coalesce(k.measure_sql, 'id:'||o.id::text));

  for r in
    select o.*, k.measure_sql, g.claimants, g.lead_id, g.actors
    from outcome_record o
    left join employee_kpi k on k.id = o.expected_kpi_id
    join _due_group g on g.id = o.id
    where o.verdict = 'pending' and o.due_at <= now()
  loop
    v_now := null;
    begin
      if r.measure_sql is not null then execute r.measure_sql into v_now; end if;
    exception when others then v_now := null; end;

    v_claimants := coalesce(r.claimants, 1);
    v_is_lead   := (r.id = r.lead_id);
    v_others    := r.actors;

    if v_now is null or r.baseline_value is null then
      v_verdict := 'unmeasurable'; v_delta := null; v_conf := 0.6;
      v_lesson := 'Could not be graded: no measurable KPI attached, or no reading in the window. A change nobody can measure cannot be proven to have helped.';
      n_unmeasurable := n_unmeasurable + 1;
    else
      v_delta := v_now - r.baseline_value;
      if r.expected_direction = 'down' then v_delta := -v_delta; end if;
      if v_delta > 0 then
        v_verdict := 'improved';
        n_improved := n_improved + 1;
        if v_claimants > 1 then
          v_conf := 0.4;
          v_lesson := coalesce(r.expected_metric,'metric')||' moved '||r.baseline_value||' to '||v_now
                    ||', but '||v_claimants||' decisions are claiming the same single reading ('||v_others
                    ||'). The metric moved; which decision moved it is NOT established. Not promoted.'
                    ||' To prove a lever here, give these decisions distinct measures or stagger them.';
        else
          v_conf := 0.9;
          v_lesson := r.decision||' -> '||coalesce(r.expected_metric,'metric')||' moved '||r.baseline_value||' to '||v_now||' as predicted. Promote to standard practice.';
        end if;
      elsif v_delta < 0 then
        v_verdict := 'worse';
        n_worse := n_worse + 1;
        if v_claimants > 1 then
          v_conf := 0.4;
          v_lesson := coalesce(r.expected_metric,'metric')||' moved the WRONG WAY, '||r.baseline_value||' to '||v_now
                    ||'. '||v_claimants||' decisions share this reading ('||v_others||'), so the cause is not isolated.'
                    ||' Investigate together before reversing any one of them.';
        else
          v_conf := 0.9;
          v_lesson := r.decision||' -> '||coalesce(r.expected_metric,'metric')||' moved the WRONG WAY, '||r.baseline_value||' to '||v_now||'. Reverse this change and do not repeat it.';
        end if;
      else
        v_verdict := 'no_change'; v_conf := 0.6;
        v_lesson := r.decision||' -> '||coalesce(r.expected_metric,'metric')||' unchanged at '||v_now||'. The action was not the lever. Look elsewhere before spending more here.';
        n_flat := n_flat + 1;
      end if;
    end if;

    update outcome_record
       set observed_value=v_now, observed_at=now(), delta=v_delta, verdict=v_verdict, lesson=v_lesson,
           promoted=(v_verdict='improved' and v_claimants = 1),
           rollback_reason=case when v_verdict='worse' then 'Graded worse than baseline on '||to_char(now(),'DD Mon YYYY') else null end,
           closed_at=now()
     where id = r.id;

    perform public.fn_emit('outcome.graded','outcome_record', r.id::text, coalesce(r.actor,'system'),
              jsonb_build_object('verdict', v_verdict, 'metric', r.expected_metric,
                                 'baseline', r.baseline_value, 'observed', v_now, 'delta', v_delta,
                                 'claimants', v_claimants));

    if v_is_lead then
      begin
        insert into institutional_memory (kind, subject_type, subject_id, headline, detail, outcome,
                                          learned_by, confidence, evidence_ref, occurred_at)
        values ('outcome', r.subject_type, r.subject_id,
                left(coalesce(r.expected_metric, r.decision), 120), v_lesson, v_verdict,
                case when v_claimants > 1 then left(v_others, 200) else r.actor end,
                v_conf, 'outcome_record#'||r.id, now());
      exception when others then null; end;
    end if;

    if v_verdict = 'worse' and v_is_lead then
      perform public.fn_emit('rollback.required','outcome_record', r.id::text, coalesce(r.actor,'system'),
                jsonb_build_object('decision', r.decision, 'lesson', v_lesson, 'claimants', v_claimants));
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
end
$function$
