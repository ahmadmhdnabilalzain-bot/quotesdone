-- OUTCOME GRADING RESUMES, AND RESPECTS THE HOLD (org audit E16).
--
-- MEASURED. fn_outcome_evaluate grades due outcome_record rows correctly, but its cron
-- (outcome_evaluate_daily) is active=false and 49 outcomes sit ungraded (9 past due), so the
-- correctness axis fn_reputation_recompute reads is frozen. The cron was disabled because grading opens
-- a 'ROLL BACK' org_task on a 'worse' outcome — work — and the founder stood the workforce down.
--
-- THIS FILE makes outcome grading behave exactly like reputation and promotion: it SELF-PAUSES on the
-- founder stand-down (so it opens no corrective work while the hold is open). The self-pause is the fix.
-- The daily cron stays DISABLED (see the footer): fn_outcome_evaluate opens corrective ROLL BACK work, so
-- it is a state-changing cron component that kernel_boards_are_green requires be classified in
-- phase_c_source_cutover and wrapped through fn_kernel_cron_exec before it may run — Phase C kernel work
-- deliberately not done in this pass. Once it is classified and wrapped, enabling it is safe: during the
-- hold it self-pauses, and when the hold lifts it grades the due backlog and the correctness signal flows.
--
-- decision_log.confidence/sources are already a live column pair the action gate populates when the
-- producing agent states them; their sparsity is the model's recording habit (an unfunded, model-side
-- concern), not a schema gap, so nothing here changes them.
--
--   node scripts/apply_sql.mjs scripts/sql/outcome_grading_resumes_and_respects_the_hold.sql --apply --ddl

begin;

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
$function$;

-- The daily cron is LEFT DISABLED. fn_outcome_evaluate is a state-changing cron component (it opens
-- ROLL BACK org_tasks), and kernel_boards_are_green requires such a component to be classified in
-- phase_c_source_cutover and wrapped through fn_kernel_cron_exec before it runs. fn_outcome_evaluate now
-- self-pauses on the founder hold, so an enabled cron would do NOTHING during the stand-down anyway —
-- the self-pause is the real fix here, making it safe to enable once it is classified and wrapped as a
-- kernel cron component (Phase C kernel work, deliberately not done in this change).
-- Ensure it stays disabled regardless of prior state:
select cron.alter_job((select jobid from cron.job where jobname='outcome_evaluate_daily'), active := false);

commit;
