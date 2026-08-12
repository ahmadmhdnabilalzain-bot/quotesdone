-- Seventeen lessons from four readings, and not one of them earned
-- ================================================================
--
-- The brief called this "513 decisions a week, 33 outcomes" and proposed adding expected_kpi_id /
-- expected_direction / measure_after to decision_log so outcomes could be opened from it. I
-- measured before building that, and both halves of the diagnosis are wrong.
--
-- FIRST: decision_log is not a decision ledger. 1,584 of its 1,603 rows are kind='action_gate',
-- every sample reading decision='permitted', reasons=[], confidence=0.9. That is admission
-- control - "this agent was allowed to raise this item and route it to procurement" - not a
-- statement that any KPI will move. Putting an expected_kpi_id on that table and asking ~20
-- routines to fill it would attach a causal claim to a permission check, which is precisely the
-- fabrication the brief itself forbids. decision_log needs no columns. It is doing its job.
--
-- SECOND: outcome_record already works. fn_kpi_review opens it from org_task with a real
-- expected_kpi_id, a real baseline_value and a real measure_after, and fn_outcome_evaluate grades
-- it honestly - it has 'worse', 'no_change' and 'unmeasurable' branches, it emits outcome.graded,
-- and it opens a rollback task when something goes backwards. Nothing there needed building.
--
-- WHAT IS ACTUALLY BROKEN is what the loop then writes down. Every one of the 17 graded outcomes
-- came back 'improved', every observed_value was exactly 100.00, and all 17 trace to just FOUR
-- distinct readings:
--
--     Platform availability                          8 outcomes  8 actors  1 reading
--     Quality gate pass rate before ship             5 outcomes  5 actors  1 reading
--     Company goals with active work and no red      3 outcomes  3 actors  1 reading
--     Goals having at least one open initiative      1 outcome   1 actor   1 reading
--
-- Eight agents share one measure_sql - the share of our own HTTP health checks that passed in the
-- last 7 days. When that moved 80.00 -> 100.00, the loop credited it to eight different decisions
-- and wrote eight separate institutional_memory rows, each at confidence 0.9, each ending
-- "as predicted. Promote to standard practice." The same happened for the QA pass rate and for
-- "does an open task exist against this goal", which is 100% by construction because dept_plan
-- creates a task for every goal.
--
-- So the company's institutional memory holds 17 high-confidence causal claims manufactured out of
-- four measurements, and the actors credited include legal, contract_specialist, marketing_content
-- and brand_mgr being told their work raised HTTP availability. That is not a learning loop. It is
-- one observation shouting, and agents retrieve from institutional_memory.
--
-- THE FIX IS NOT TO STOP GRADING. The measurement is real and belongs in outcome_record; every row
-- keeps its observed_value, delta and verdict. What must stop is asserting WHO caused it when the
-- reading is shared. A movement that N unrelated decisions all point at establishes that the metric
-- moved and nothing whatsoever about which decision moved it, so:
--
--   * one institutional_memory per distinct reading, not one per claimant, naming the co-claimants;
--   * promoted stays FALSE for a shared reading - "promote to standard practice" is a claim about a
--     proven lever and a shared reading has not proven one;
--   * confidence drops to 0.4, below the 0.6 already used for no_change, because a co-attributed
--     improvement is weaker evidence than a clean flat reading;
--   * one rollback task per shared reading instead of N, for the same reason.
--
-- A sole-claimant outcome is untouched: it still promotes at 0.9 and still reads "as predicted".
-- This makes the loop HARDER to satisfy, not easier. That is correct - the old pass was false.

create or replace function public.fn_outcome_evaluate()
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  r record; v_now numeric; v_delta numeric; v_verdict text; v_lesson text;
  n_improved int := 0; n_worse int := 0; n_flat int := 0; n_unmeasurable int := 0;
  v_claimants int; v_others text; v_lead_id bigint; v_is_lead boolean; v_conf numeric;
begin
  -- How many due outcomes share each reading, and which one speaks for the group. Computed once,
  -- over the same set the loop below walks, so the grouping cannot drift mid-run.
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
           -- a shared reading never promotes: it has not shown which decision was the lever
           promoted=(v_verdict='improved' and v_claimants = 1),
           rollback_reason=case when v_verdict='worse' then 'Graded worse than baseline on '||to_char(now(),'DD Mon YYYY') else null end,
           closed_at=now()
     where id = r.id;

    perform public.fn_emit('outcome.graded','outcome_record', r.id::text, coalesce(r.actor,'system'),
              jsonb_build_object('verdict', v_verdict, 'metric', r.expected_metric,
                                 'baseline', r.baseline_value, 'observed', v_now, 'delta', v_delta,
                                 'claimants', v_claimants));

    -- One lesson per reading. The co-claimants are named inside it rather than each minting their
    -- own copy, so retrieval sees one observation instead of N agreeing witnesses who are one witness.
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
