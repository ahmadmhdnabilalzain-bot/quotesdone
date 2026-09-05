-- THE ORG_TASK LANE RENDERS FROM THE TASK'S FACTS AND RUNS THE TASK'S EXECUTOR (MASTER_PLAN A1 / §4.2, §4.3), 6 Sep 2026.
--
-- MEASURED on production 5 Sep 2026 by an adversarial audit of the lane (every number by hand):
--   * of 610 org_tasks closed since 12:00 UTC through fn_org_task_deterministic_done, the deliverables
--     were 50 standing playbook texts stamped by cosine match: 242 distinct of 610, one text shared by
--     39 tasks. 609 of 610 read "Event X raised on a Y ... subscribes because ..."; 0 mention the
--     employee_kpi row the task is about; decided_by on the trace read 'fn_apply_playbook'.
--   * the lane's close PASTED the playbook. It read nothing from the task: not the event it was minted
--     from, not the KPI row, not the department's numbers, not the prior attempts. Two tasks with
--     different facts produced the same deliverable. That is documentation, not determination
--     (the-deterministic-close-documents-rather-than-performs).
--   * a task whose action_class has a deterministic executor (recommend -> fn_recommend_deterministic,
--     exec_review -> fn_exec_review_deterministic, knowledge_fill_gap -> fn_knowledge_gap_deterministic,
--     registered 5 Sep) closed without the executor ever being called: 0 action_execution rows for
--     any org_task close, ever.
--   * result.review carried fn_task_review's chain verdict ('published') beside a review_queue row
--     that is 'pending' until an independent reviewer decides; nothing distinguished the two, so a
--     reader took a pending queue row for a published review.
--
-- WHAT CHANGES, all deterministic, no model call anywhere, every guard kept:
--   1. fn_org_task_facts(task_id, step_run_id) reads the TASK's own facts: the row (title, detail,
--      class, tier, priority, owner, attempts, age), its department_objective, the company_event rows it
--      was minted from (event_delivery -> company_event, with payload), the entity those name, the
--      employee_kpi row a "KPI missed" task is about (live value, target, attainment, previous value,
--      14-day verdicts), the department's live numbers (employee_kpi verdicts and v_bi_scorecard by
--      owner_dept through the org_departments crosswalk), the prior attempts and reviews on the row,
--      and — where the lane's run has a step_run — fn_workflow_step_facts of that step. It DERIVES the
--      band, the attainment, the cause class, the recurrence and the department's attainment, and
--      counts facts_bound.
--   2. fn_org_task_render(facts, record, executor) renders the matched record's structured_data
--      AGAINST those facts (a keyed map resolved at the band, the cause, the action class, the event
--      type, the entity type, the tier, the department), prints the facts it decided from first, the
--      executor's output next, and the record last. Different facts -> different deliverable; the
--      same facts -> the same deliverable.
--   3. fn_org_task_deterministic_done INVOKES the task's executor when org_action_executor maps the
--      task's action_class to a deterministic rpc (kind rpc, zero required args, low/advisory_safe/
--      reversible, notifies nobody, not founder-reserved, fn_executor_needs_model false). The call is
--      recorded as a succeeded/failed action_execution (idempotency_key org_task:<id>:det:<ts>) and its
--      output is in the deliverable — that is the work. A failing executor refuses the close with the
--      error recorded. A model-backed executor is not invoked and the close says so
--      (disposition advisory_held_model). No executor mapped -> rendered from facts.
--   4. The review is labelled truthfully: result.review.chain_outcome is fn_task_review's verdict on
--      the deliverable; result.review.queue_status is the review_queue row's status ('pending' until
--      an independent reviewer decides) with its id. The row is never auto-decided here.
--   5. The disposition is EARNED, never a literal: determined (facts bound, deterministic executor or
--      none), advisory_held_model (facts bound, executor needs the held model), needs_narrative
--      (no fact bound). used_llm is MEASURED from llm_attempt + ai_cost_log by workflow_dispatch since
--      the step was claimed. 'deterministic_low_confidence' is no longer written by this lane.
--   6. Guards UNCHANGED: playbook must be a current runtime-eligible actionable record; cosine >= 0.85;
--      corroboration >= 2 terms and >= 30%; the caller's deliverable >= 300 chars; RESULT: line; the
--      KPI-miss root cause; the terminal verdict paths (escalate -> escalated, else blocked) and the
--      agent_runs row for the employee on every path.
--
--   node scripts/apply_sql.mjs scripts/sql/org_task_close_renders_from_the_tasks_facts_2026_09_06.sql --apply --ddl

begin;

-- ---------------------------------------------------------------------------------------------------
-- 1. THE TASK'S OWN FACTS. Scalars throughout: a SELECT INTO that finds no row nulls every target.
-- ---------------------------------------------------------------------------------------------------
create or replace function public.fn_org_task_facts(p_task_id bigint, p_step_run_id bigint default null)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  t record;
  v_bound int := 0;
  v_obj jsonb := null;
  v_events jsonb := '[]'::jsonb; v_deliveries int := 0;
  v_entity_type text; v_entity_id text; v_event_type text;
  v_kpi jsonb := null; v_kpi_metric text; v_kpi_owner text;
  k record; v_prev numeric; v_prev_on date; v_missed14 int := 0; v_met14 int := 0;
  v_att numeric; v_band text; v_cause text; v_cause_why text; v_att_source text;
  v_depts text[]; v_dept jsonb := null;
  v_kpi_rows int := 0; v_kpi_measured int := 0; v_kpi_met int := 0; v_kpi_missed int := 0; v_worst jsonb;
  v_sc_rows int := 0; v_sc_off int := 0; v_sc_list jsonb;
  v_hist jsonb; v_rq jsonb; v_rc_n int := 0; v_rc_last text; v_dt_n int := 0;
  v_step jsonb := null; v_step_bound int := 0;
  v_derived jsonb;
begin
  select o.id, o.dept_key, o.title, o.detail, o.action_class, o.tier, o.priority, o.status, o.assigned_agent,
         coalesce(o.attempts, 0) as attempts, o.created_at, o.updated_at, o.root_cause, o.needs_founder,
         o.objective_id, coalesce(o.result, '{}'::jsonb) as result, o.decided_by
    into t from public.org_tasks o where o.id = p_task_id;
  if not found then return null; end if;

  -- THE OBJECTIVE the task serves
  if t.objective_id is not null then
    select jsonb_strip_nulls(jsonb_build_object('id', d.id, 'objective', d.objective, 'goal_key', d.goal_key,
             'horizon', d.horizon, 'status', d.status, 'target_value', d.target_value, 'unit', d.unit,
             'actual_value', d.actual_value, 'measured_at', d.measured_at))
      into v_obj from public.department_objective d where d.id = t.objective_id;
    if v_obj is not null then v_bound := v_bound + 1; end if;
  end if;

  -- THE EVENTS it was minted from (event_delivery is the provenance; decided_by is overwritten at close)
  select count(*) into v_deliveries from public.event_delivery ed where ed.task_id = t.id;
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
           'event_id', ce.id, 'event_type', ce.event_type, 'entity_type', ce.entity_type, 'entity_id', ce.entity_id,
           'actor', ce.actor, 'occurred_at', ce.occurred_at, 'delivered_to', ed.agent_key,
           'payload', coalesce(ce.payload, '{}'::jsonb))) order by ce.occurred_at desc), '[]'::jsonb)
    into v_events
    from (select * from public.event_delivery ed where ed.task_id = t.id order by ed.delivered_at desc limit 5) ed
    join public.company_event ce on ce.id = ed.event_id;
  v_bound := v_bound + jsonb_array_length(v_events)
             + (select count(*) from jsonb_array_elements(v_events) e, jsonb_each(e->'payload') p
                 where jsonb_typeof(p.value) in ('string','number','boolean'))::int;

  -- THE ENTITY it is about: the newest event's, else parsed from the bus title "<type> on <entity_type> <id>"
  if jsonb_array_length(v_events) > 0 then
    v_event_type  := v_events->0->>'event_type';
    v_entity_type := v_events->0->>'entity_type';
    v_entity_id   := v_events->0->>'entity_id';
  else
    v_event_type  := substring(t.title from '^(?:ZZ DEMO\s*[—-]?\s*)?([a-z_]+\.[a-z_]+) on ');
    v_entity_type := substring(t.title from ' on ([a-z_]+) ');
    v_entity_id   := substring(t.title from ' on [a-z_]+ (\S+)\s*$');
  end if;

  -- THE KPI ROW a "KPI missed: <metric> (<owner>)" task is about, live
  if t.title ~* 'KPI missed: ' then
    v_kpi_metric := substring(t.title from 'KPI missed: (.+) \([a-z0-9_]+\)\s*$');
    v_kpi_owner  := substring(t.title from 'KPI missed: .+ \(([a-z0-9_]+)\)\s*$');
    select e.id, e.metric, e.target_value, e.actual_value, e.unit, e.cadence, e.serves_goal, e.measured_at,
           e.no_measure_reason, e.kpi_class
      into k
      from public.employee_kpi e
     where e.agent_key = v_kpi_owner and e.metric = v_kpi_metric
     order by e.active desc, e.measured_at desc nulls last limit 1;
    if found then
      select h.actual_value, h.measured_on into v_prev, v_prev_on
        from public.employee_kpi_history h
       where h.kpi_id = k.id and (k.measured_at is null or h.measured_at < k.measured_at - interval '1 hour')
       order by h.measured_at desc limit 1;
      select count(*) filter (where h.verdict = 'MISSED'), count(*) filter (where h.verdict = 'MET')
        into v_missed14, v_met14
        from public.employee_kpi_history h
       where h.kpi_id = k.id and h.measured_on >= current_date - 14;
      v_att := case when k.actual_value is null or k.target_value is null then null
                    when k.unit in ('percent_max', 'minutes') or k.unit ilike '%max%' then
                         case when k.actual_value > 0 then round(100 * k.target_value / k.actual_value, 1) else 100 end
                    when k.target_value > 0 then round(100 * k.actual_value / k.target_value, 1)
                    when k.actual_value <= 0 then 100 else null end;
      v_att_source := 'employee_kpi live (' || coalesce(k.measured_at::text, 'never measured') || ')';
      v_kpi := jsonb_strip_nulls(jsonb_build_object(
                 'kpi_id', k.id, 'owner', v_kpi_owner, 'metric', k.metric, 'target', k.target_value, 'actual', k.actual_value,
                 'unit', k.unit, 'cadence', k.cadence, 'serves_goal', k.serves_goal, 'measured_at', k.measured_at,
                 'no_measure_reason', k.no_measure_reason, 'kpi_class', k.kpi_class,
                 'previous_value', v_prev, 'previous_on', v_prev_on,
                 'missed_verdicts_14d', v_missed14, 'met_verdicts_14d', v_met14, 'attainment_pct', v_att));
      v_bound := v_bound + (k.actual_value is not null)::int + (k.target_value is not null)::int
                 + (v_prev is not null)::int + ((v_missed14 + v_met14) > 0)::int;
    end if;
    if v_att is null then
      -- the minter wrote "actual X (Y% of target)" into the detail; it is a fact of the task even without a live row
      v_att := nullif(substring(coalesce(t.detail,'') from '\(([0-9]+(?:\.[0-9]+)?)% of target\)'), '')::numeric;
      if v_att is not null then
        v_att_source := 'task detail as written by fn_kpi_review';
        v_bound := v_bound + 1;
      end if;
    end if;
    v_band := case when v_att is null then 'UNMEASURED'
                   when v_att >= 100 then 'ON_TARGET'
                   when v_att >= 70 then 'BEHIND'
                   else 'OFF_TARGET' end;
    if k.no_measure_reason is not null then
      v_cause := 'INSTRUMENT'; v_cause_why := 'employee_kpi.no_measure_reason: ' || k.no_measure_reason;
    elsif v_att is null then
      v_cause := 'INSTRUMENT'; v_cause_why := 'no attainment figure on the row or in the task: the variance class cannot be read';
    elsif v_att >= 100 then
      v_cause := 'NONE'; v_cause_why := 'attainment ' || v_att || '% is at or above target, so the miss is in how the metric is measured or dated, not in the work';
    elsif v_att < 5 then
      v_cause := 'EXECUTION'; v_cause_why := 'no throughput: attainment ' || v_att || '% means the input that feeds this metric has not started, not that it under-performed';
    elsif v_att < 50 then
      v_cause := 'EXECUTION'; v_cause_why := 'capacity or conversion shortfall: attainment ' || v_att || '% is real activity falling well short of the target';
    elsif v_met14 = 0 and v_missed14 >= 3 then
      v_cause := 'TARGET_MIS_SET'; v_cause_why := 'near-miss at ' || v_att || '% with ' || v_missed14 || ' MISSED and 0 MET verdicts in 14 days: the target sits above what the process currently reaches';
    else
      v_cause := 'EXECUTION'; v_cause_why := 'near-miss at ' || v_att || '% (' || v_missed14 || ' MISSED / ' || v_met14 || ' MET verdicts in 14 days): execution against a target the process has reached before';
    end if;
  end if;

  -- THE DEPARTMENT'S LIVE NUMBERS (the same sources fn_workflow_step_facts / fn_recommend_deterministic read)
  select coalesce(array_agg(d.dept_key), array[t.dept_key]) into v_depts
    from public.org_departments d where d.merged_into = t.dept_key or d.dept_key = t.dept_key;
  with kp as (
    select e.id, e.agent_key, e.metric, e.target_value, e.actual_value, e.unit,
           (select h.verdict from public.employee_kpi_history h where h.kpi_id = e.id order by h.measured_at desc limit 1) verdict,
           (select h.attainment from public.employee_kpi_history h where h.kpi_id = e.id order by h.measured_at desc limit 1) attainment
      from public.employee_kpi e join public.org_agents a on a.agent_key = e.agent_key
     where e.active and a.department = t.dept_key)
  select count(*), count(*) filter (where actual_value is not null),
         count(*) filter (where verdict = 'MET'), count(*) filter (where verdict = 'MISSED'),
         (select jsonb_agg(jsonb_build_object('owner', agent_key, 'metric', metric, 'actual', actual_value, 'target', target_value,
                                              'unit', unit, 'attainment_pct', attainment))
            from (select * from kp where verdict = 'MISSED' and attainment is not null order by attainment asc limit 3) w)
    into v_kpi_rows, v_kpi_measured, v_kpi_met, v_kpi_missed, v_worst
    from kp;
  select count(*), count(*) filter (where sc.state is distinct from 'ON_TARGET'),
         (select jsonb_agg(jsonb_build_object('label', s2.label, 'metric_key', s2.metric_key, 'value', s2.value, 'target', s2.target,
                                              'state', s2.state, 'error', s2.error) order by s2.state, s2.label)
            from (select * from public.v_bi_scorecard s2 where s2.owner_dept = any(v_depts) and s2.state is distinct from 'ON_TARGET'
                  order by s2.state, s2.label limit 6) s2)
    into v_sc_rows, v_sc_off, v_sc_list
    from public.v_bi_scorecard sc where sc.owner_dept = any(v_depts);
  v_dept := jsonb_strip_nulls(jsonb_build_object(
              'dept_key', t.dept_key, 'crosswalk', to_jsonb(v_depts),
              'kpi_rows', v_kpi_rows, 'kpi_measured', v_kpi_measured, 'kpi_met', v_kpi_met, 'kpi_missed', v_kpi_missed,
              'worst_missed', v_worst,
              'scorecard_rows', v_sc_rows, 'scorecard_off_target', v_sc_off, 'scorecard_off_target_list', v_sc_list));
  v_bound := v_bound + (v_kpi_measured > 0)::int + (v_sc_rows > 0)::int;

  -- PRIOR ATTEMPTS AND REVIEWS on this row
  select coalesce(jsonb_agg(jsonb_build_object('id', q.id, 'kind', q.kind, 'status', q.status, 'decided_by', q.decided_by,
                                               'created_at', q.created_at) order by q.created_at desc), '[]'::jsonb)
    into v_rq
    from (select * from public.review_queue q where q.payload->>'org_task_id' = t.id::text order by q.created_at desc limit 5) q;
  select count(*), max(rc.stage || '/' || rc.decision || ' by ' || rc.reviewer_agent) into v_rc_n, v_rc_last
    from public.review_chain rc where rc.subject_type = 'org_task' and rc.subject_id = t.id::text;
  select count(*) into v_dt_n from public.decision_trace d where d.entity_type = 'org_task' and d.entity_id = t.id::text;
  v_hist := jsonb_strip_nulls(jsonb_build_object(
              'attempts', t.attempts, 'decided_by_before', t.decided_by, 'root_cause_before', t.root_cause,
              'parked', t.result->'parked', 'previously_parked', t.result->'previously_parked',
              'held', t.result->'held', 'escalated', t.result->'escalated',
              'prior_review_chain_outcome', t.result->'review'->>'outcome',
              'review_queue_rows', v_rq, 'review_chain_rows', v_rc_n, 'review_chain_last', v_rc_last,
              'decision_traces', v_dt_n));
  v_bound := v_bound + (t.attempts > 0)::int + (v_rc_n > 0)::int + (jsonb_array_length(v_rq) > 0)::int;

  -- THE STEP'S FACTS when the lane's run has a step_run (a trigger event and its metric, when any)
  if p_step_run_id is not null then
    v_step := public.fn_workflow_step_facts(p_step_run_id);
    if v_step is not null then
      v_step_bound := coalesce((v_step->>'facts_bound')::int, 0);
      v_step := v_step - 'context' - 'read_at';
      v_bound := v_bound + v_step_bound;
      if v_band is null and v_step#>>'{derived,band}' is not null then
        v_band := v_step#>>'{derived,band}'; v_cause := v_step#>>'{derived,cause}'; v_cause_why := v_step#>>'{derived,cause_evidence}';
      end if;
    end if;
  end if;

  v_derived := jsonb_strip_nulls(jsonb_build_object(
    'band', v_band, 'attainment_pct', v_att, 'attainment_source', v_att_source,
    'cause', v_cause, 'cause_evidence', v_cause_why,
    'event_type', v_event_type, 'entity_type', v_entity_type, 'entity_id', v_entity_id,
    'recurrence', v_deliveries, 'days_open', round(extract(epoch from (now() - t.created_at)) / 86400.0, 1),
    'dept_kpi_attainment_pct', case when v_kpi_met + v_kpi_missed > 0 then round(100.0 * v_kpi_met / (v_kpi_met + v_kpi_missed), 1) end,
    'dept_scorecard_off_target', v_sc_off));

  return jsonb_strip_nulls(jsonb_build_object(
    'task', jsonb_build_object('id', t.id, 'dept_key', t.dept_key, 'title', t.title, 'detail', left(coalesce(t.detail,''), 2000),
                               'action_class', t.action_class, 'tier', t.tier, 'priority', t.priority, 'status', t.status,
                               'assigned_agent', t.assigned_agent, 'needs_founder', t.needs_founder, 'created_at', t.created_at),
    'objective', v_obj,
    'events', v_events, 'deliveries_total', v_deliveries,
    'entity', case when v_entity_type is null then null else jsonb_build_object('type', v_entity_type, 'id', v_entity_id) end,
    'kpi', v_kpi,
    'department', v_dept,
    'history', v_hist,
    'step_facts', v_step,
    'derived', v_derived,
    'facts_bound', v_bound,
    'read_at', now()));
end
$function$;

-- ---------------------------------------------------------------------------------------------------
-- 2. RENDER the record against the facts. Same selection rule as fn_workflow_step_render: an
--    object-valued key in structured_data is resolved at the derived band, cause, action class, event
--    type, entity type, tier and department. What is selected is what was decided.
-- ---------------------------------------------------------------------------------------------------
create or replace function public.fn_org_task_render(p_facts jsonb, p_title text, p_record_type text, p_content text,
                                                     p_structured jsonb, p_executor_status text default null,
                                                     p_executor_output text default null)
returns text
language plpgsql
immutable
set search_path to 'public', 'pg_temp'
as $function$
declare
  f jsonb := coalesce(p_facts, '{}'::jsonb);
  d jsonb := coalesce(p_facts->'derived', '{}'::jsonb);
  tk jsonb := coalesce(p_facts->'task', '{}'::jsonb);
  kp jsonb := p_facts->'kpi';
  dp jsonb := p_facts->'department';
  h jsonb := coalesce(p_facts->'history', '{}'::jsonb);
  t text := '';
  sel text[]; k text; v jsonb; s text; x jsonb; n int := 0; lines text := '';
begin
  t := 'DETERMINATION — QuotesDone org_task #' || coalesce(tk->>'id', '?') || ' (' || coalesce(tk->>'dept_key', '?') || ', '
       || coalesce(tk->>'action_class', '?') || ', tier ' || coalesce(tk->>'tier', '?') || '): ' || coalesce(tk->>'title', '') || E'\n'
       || 'Decided by ' || coalesce(tk->>'assigned_agent', tk->>'dept_key', '?') || ' at ' || coalesce(f->>'read_at', '') || ' from '
       || coalesce(f->>'facts_bound', '0') || ' bound fact(s); no model call.' || E'\n\n';

  t := t || E'FACTS THIS TASK DECIDED FROM\n';
  t := t || '- the task: ' || coalesce(tk->>'detail', '(no detail)') || E'\n';
  t := t || '- open ' || coalesce(d->>'days_open', '?') || ' day(s), attempts before this one ' || coalesce(h->>'attempts', '0')
       || ', priority ' || coalesce(tk->>'priority', 'none') || E'\n';
  if f ? 'objective' then
    t := t || '- objective served: "' || coalesce(f#>>'{objective,objective}', '?') || '" (goal ' || coalesce(f#>>'{objective,goal_key}', 'none')
         || ', ' || coalesce(f#>>'{objective,status}', '?') || ', target ' || coalesce(f#>>'{objective,target_value}', 'null') || ' '
         || coalesce(f#>>'{objective,unit}', '') || ', actual ' || coalesce(f#>>'{objective,actual_value}', 'null')
         || case when f#>>'{objective,measured_at}' is not null then ' measured ' || (f#>>'{objective,measured_at}') else '' end || ')' || E'\n';
  else
    t := t || E'- objective served: none linked on the row\n';
  end if;
  if jsonb_typeof(f->'events') = 'array' and jsonb_array_length(f->'events') > 0 then
    t := t || '- minted from ' || coalesce(f->>'deliveries_total', '?') || ' event delivery(ies); newest first:' || E'\n';
    for x in select * from jsonb_array_elements(f->'events') loop
      t := t || '    · ' || coalesce(x->>'event_type', '?') || ' on ' || coalesce(x->>'entity_type', '?') || ' ' || coalesce(x->>'entity_id', '?')
           || ' by ' || coalesce(x->>'actor', 'system') || ' at ' || coalesce(x->>'occurred_at', '?') || ' (event ' || coalesce(x->>'event_id', '?')
           || ') payload ' || left(coalesce((x->'payload')::text, '{}'), 700) || E'\n';
    end loop;
  elsif f ? 'entity' then
    t := t || '- about ' || coalesce(f#>>'{entity,type}', '?') || ' ' || coalesce(f#>>'{entity,id}', '?') || ' (from the title; no event_delivery row links this task to a company_event)' || E'\n';
  else
    t := t || E'- minted from: no company_event delivery on this task\n';
  end if;
  if kp is not null then
    t := t || '- the KPI: "' || coalesce(kp->>'metric', '?') || '" owned by ' || coalesce(kp->>'owner', '?') || ' (employee_kpi ' || coalesce(kp->>'kpi_id', '?')
         || '): actual ' || coalesce(kp->>'actual', 'null') || ' ' || coalesce(kp->>'unit', '') || ' against target ' || coalesce(kp->>'target', 'null')
         || ', cadence ' || coalesce(kp->>'cadence', '?') || ', serves ' || coalesce(kp->>'serves_goal', 'no goal')
         || ', measured ' || coalesce(kp->>'measured_at', 'never')
         || case when kp ? 'previous_value' then '; previous ' || (kp->>'previous_value') || ' on ' || coalesce(kp->>'previous_on', '?') else '; no earlier measurement' end
         || '; last 14 days ' || coalesce(kp->>'missed_verdicts_14d', '0') || ' MISSED / ' || coalesce(kp->>'met_verdicts_14d', '0') || ' MET'
         || case when kp ? 'no_measure_reason' then '; no_measure_reason: ' || (kp->>'no_measure_reason') else '' end || E'\n';
  elsif (tk->>'title') ~* 'KPI missed' then
    t := t || E'- the KPI: no employee_kpi row matches the owner and metric in the title; the task''s own numbers are used\n';
  end if;
  if dp is not null then
    t := t || '- the department ' || coalesce(dp->>'dept_key', '?') || ': ' || coalesce(dp->>'kpi_rows', '0') || ' active KPI(s), '
         || coalesce(dp->>'kpi_measured', '0') || ' measured, ' || coalesce(dp->>'kpi_met', '0') || ' MET / ' || coalesce(dp->>'kpi_missed', '0') || ' MISSED at the latest verdict'
         || case when d ? 'dept_kpi_attainment_pct' then ' (' || (d->>'dept_kpi_attainment_pct') || '% of verdicts met)' else '' end
         || '; scorecard ' || coalesce(dp->>'scorecard_rows', '0') || ' metric(s), ' || coalesce(dp->>'scorecard_off_target', '0') || ' not on target' || E'\n';
    if jsonb_typeof(dp->'worst_missed') = 'array' then
      for x in select * from jsonb_array_elements(dp->'worst_missed') loop
        t := t || '    · worst missed: ' || coalesce(x->>'metric', '?') || ' (' || coalesce(x->>'owner', '?') || ') ' || coalesce(x->>'actual', 'null')
             || '/' || coalesce(x->>'target', 'null') || ' ' || coalesce(x->>'unit', '') || ' = ' || coalesce(x->>'attainment_pct', '?') || '%' || E'\n';
      end loop;
    end if;
    if jsonb_typeof(dp->'scorecard_off_target_list') = 'array' then
      for x in select * from jsonb_array_elements(dp->'scorecard_off_target_list') loop
        t := t || '    · scorecard ' || coalesce(x->>'state', '?') || ': ' || coalesce(x->>'label', '?') || ' [' || coalesce(x->>'metric_key', '?') || '] value='
             || coalesce(x->>'value', 'null') || ' target=' || coalesce(x->>'target', 'null')
             || case when (x->>'error') is not null then ' ERROR=' || (x->>'error') else '' end || E'\n';
      end loop;
    end if;
  end if;
  if h ? 'review_chain_rows' and (h->>'review_chain_rows')::int > 0 then
    t := t || '- prior review: ' || (h->>'review_chain_rows') || ' review_chain row(s), last ' || coalesce(h->>'review_chain_last', '?')
         || '; ' || coalesce(jsonb_array_length(h->'review_queue_rows')::text, '0') || ' review_queue row(s); ' || coalesce(h->>'decision_traces', '0') || ' decision trace(s)' || E'\n';
  end if;
  if h ? 'parked' or h ? 'previously_parked' then
    t := t || '- previously parked: ' || left(coalesce((h->'parked')::text, (h->'previously_parked')::text), 400) || E'\n';
  end if;
  if h ? 'held' then t := t || '- previously held: ' || left((h->'held')::text, 300) || E'\n'; end if;
  if h ? 'escalated' then t := t || '- previously escalated: ' || left((h->'escalated')::text, 300) || E'\n'; end if;
  if f ? 'step_facts' and (f#>'{step_facts,trigger}') is not null then
    t := t || '- the run''s trigger: ' || coalesce(f#>>'{step_facts,trigger,event_type}', '?') || ' on ' || coalesce(f#>>'{step_facts,trigger,entity_type}', '?')
         || ' ' || coalesce(f#>>'{step_facts,trigger,entity_id}', '?') || ' payload ' || left(coalesce((f#>'{step_facts,trigger,payload}')::text, '{}'), 400) || E'\n';
  end if;
  if f ? 'step_facts' and (f#>'{step_facts,metric}') is not null then
    t := t || '- the run''s metric: ' || left((f#>'{step_facts,metric}')::text, 600) || E'\n';
  end if;

  t := t || E'\nDETERMINED\n';
  if d ? 'band' then
    t := t || '- variance: ' || coalesce(kp->>'metric', f#>>'{step_facts,metric,label}', tk->>'title') || ' is ' || (d->>'band')
         || case when d ? 'attainment_pct' then ' at ' || (d->>'attainment_pct') || '% attainment (' || coalesce(d->>'attainment_source', '?') || ')' else '' end || E'\n'
         || '- cause class: ' || coalesce(d->>'cause', 'not established') || ' — ' || coalesce(d->>'cause_evidence', '') || E'\n';
  end if;
  if coalesce((d->>'recurrence')::int, 0) > 1 then
    t := t || '- recurrence: ' || (d->>'recurrence') || ' deliveries of the same event landed on this one task; the condition is standing, not new' || E'\n';
  end if;
  t := t || '- executor: ' || coalesce(p_executor_status, 'none: no active executor is mapped to this action class') || E'\n';

  -- resolve keyed maps in structured_data at the facts
  sel := array_remove(array[d->>'band', d->>'cause', tk->>'action_class', d->>'event_type', d->>'entity_type', tk->>'tier', tk->>'dept_key',
                            lower(d->>'band'), lower(d->>'cause')], null);
  if p_structured is not null and jsonb_typeof(p_structured) = 'object' then
    for k, v in select * from jsonb_each(p_structured) loop
      if jsonb_typeof(v) = 'object' then
        foreach s in array coalesce(sel, '{}'::text[]) loop
          if v ? s then
            n := n + 1;
            lines := lines || '- ' || k || '[' || s || '] → ' || case when jsonb_typeof(v->s) = 'string' then v->>s else (v->s)::text end || E'\n';
          end if;
        end loop;
      end if;
    end loop;
  end if;
  if n > 0 then
    t := t || 'Selected from "' || coalesce(p_title, '?') || '" at the facts above (' || n || ' rule(s)):' || E'\n' || lines;
  else
    t := t || 'No keyed rule in "' || coalesce(p_title, '?') || '" resolves at these facts; the record applies as written below.' || E'\n';
  end if;

  if p_executor_output is not null then
    t := t || E'\nEXECUTOR OUTPUT (the work performed for this task)\n' || p_executor_output || E'\n';
  end if;

  t := t || E'\nAPPLIED RECORD: ' || coalesce(p_record_type, '?') || ' "' || coalesce(p_title, '?') || E'"\n' || coalesce(p_content, '');
  if p_structured is not null and p_structured <> '{}'::jsonb then
    t := t || E'\n\nSTRUCTURED DATA OF THE RECORD:\n' || jsonb_pretty(p_structured);
  end if;
  return t;
end
$function$;

revoke execute on function public.fn_org_task_facts(bigint, bigint) from public;
revoke execute on function public.fn_org_task_render(jsonb, text, text, text, jsonb, text, text) from public;

-- ---------------------------------------------------------------------------------------------------
-- 3. THE CLOSE. Guards, review, terminal paths and agent_runs rows as before; the deliverable is now a
--    function of the task's facts and the executor's output, and the review is labelled truthfully.
-- ---------------------------------------------------------------------------------------------------
create or replace function public.fn_org_task_deterministic_done(p_task_id bigint, p_step_run_id bigint, p_output jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  t            record;
  v_floor      numeric := 0.85;      -- fn_apply_playbook's floor; a caller cannot lower it here
  v_sim        numeric;
  v_terms      int;
  v_total      int;
  v_deliv      text;
  v_outcome    text;
  v_employee   text;
  v_review     jsonb;
  v_verdict    text;
  v_trace      uuid;
  v_queue      bigint;
  v_rc         text;
  v_known      int;
  -- the record applied
  v_pb_id text; v_pb_title text; v_pb_type text; v_pb_content text; v_pb_sd jsonb;
  -- facts + rendering
  v_facts jsonb; v_bound int; v_disp text; v_mode text; v_source text := 'task_facts_rendered';
  -- executor
  ex record; v_needs_model boolean := false; v_exec_status text; v_exec_id uuid; v_exec_result jsonb; v_exec_text text;
  v_req_args int; v_argnames text[]; v_kind text := null; v_target text; v_err text; x jsonb;
  -- measurement
  v_step_started timestamptz; v_llm int := 0; v_cost int := 0; v_used_llm boolean; v_llm_basis text;
begin
  select o.id, o.dept_key, o.title, o.detail, o.action_class, o.tier, o.status, o.assigned_agent
    into t from public.org_tasks o where o.id = p_task_id;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'no such org_task ' || p_task_id);
  end if;
  if t.status not in ('assigned','in_progress') then
    return jsonb_build_object('ok', false, 'reason', 'org_task ' || p_task_id || ' is ' || t.status || ', not open work');
  end if;

  v_deliv   := coalesce(p_output->>'deliverable', '');
  v_sim     := nullif(p_output->>'similarity', '')::numeric;
  v_terms   := coalesce(nullif(p_output->>'terms_matched','')::int, 0);
  v_total   := coalesce(nullif(p_output->>'terms_total','')::int, 0);
  v_employee := coalesce(nullif(p_output->>'employee',''), t.assigned_agent, t.dept_key);

  -- FALSE-SUCCESS GUARDS, UNCHANGED. Nothing below runs unless the match has substance.
  if coalesce(p_output->>'playbook_record_id','') = '' then
    return jsonb_build_object('ok', false, 'reason', 'no playbook_record_id: a determination must cite the company knowledge it applied');
  end if;
  select k.record_id, k.title, k.record_type, k.content, coalesce(k.structured_data, '{}'::jsonb)
    into v_pb_id, v_pb_title, v_pb_type, v_pb_content, v_pb_sd
    from public.ops_knowledge k
   where k.record_id = p_output->>'playbook_record_id'
     and k.runtime_eligible and k.supersession_state = 'current'
     and k.record_type in ('decision_playbook','decision_rule','standard_operating_procedure','exception_playbook');
  if v_pb_id is null then
    return jsonb_build_object('ok', false, 'reason', 'playbook ' || (p_output->>'playbook_record_id')
             || ' is not a current, runtime-eligible, ACTIONABLE ops_knowledge record');
  end if;
  if v_sim is null or v_sim < v_floor then
    return jsonb_build_object('ok', false, 'reason', 'similarity ' || coalesce(v_sim::text,'null') || ' is below the apply floor ' || v_floor);
  end if;
  if v_terms < 2 or v_total < 1 or (v_terms::numeric / v_total) < 0.30 then
    return jsonb_build_object('ok', false, 'reason', 'corroboration ' || v_terms || ' of ' || v_total
             || ' task terms is under the 2-and-30% bar the applier demands');
  end if;
  if length(v_deliv) < 300 then
    return jsonb_build_object('ok', false, 'reason', 'deliverable shorter than 300 characters is not a determination');
  end if;

  -- THE FACTS, then the deliverable AS A FUNCTION OF THEM.
  v_facts := public.fn_org_task_facts(p_task_id, p_step_run_id);
  v_bound := coalesce((v_facts->>'facts_bound')::int, 0);

  -- THE EXECUTOR of the task's action class. Read the registry row and decide from it, in words.
  select e.action_class, e.kind, e.target, e.risk_tier, e.advisory_safe, e.reversible, e.notifies_human, e.required_authority
    into ex
    from public.org_action_executor e
   where e.action_class = t.action_class and e.active
   order by (e.kind = 'rpc') desc, e.kind limit 1;
  if not found then
    v_exec_status := 'none: no active executor is mapped to action_class ' || coalesce(t.action_class, '(null)') || '; rendered from the task''s facts';
  else
    v_kind := ex.kind; v_target := ex.target;
    v_needs_model := public.fn_executor_needs_model(ex.target);
    if v_needs_model then
      v_exec_status := 'held: ' || ex.target || ' is routed to a model task class by fn_task_class and the paid provider is held; not invoked — this close is advisory';
    elsif coalesce(ex.required_authority, '') = 'founder' then
      v_exec_status := 'withheld: ' || ex.target || ' is reserved to the founder';
    elsif ex.notifies_human then
      v_exec_status := 'withheld: ' || ex.target || ' notifies a human (org_action_executor.notifies_human); the deterministic close never sends';
    elsif not (ex.risk_tier = 'low' and ex.advisory_safe and ex.reversible) then
      v_exec_status := format('withheld: %s is risk_tier=%s advisory_safe=%s reversible=%s; the close invokes low/advisory_safe/reversible only',
                              ex.target, ex.risk_tier, ex.advisory_safe, ex.reversible);
    elsif ex.kind <> 'rpc' then
      -- ponytail: an edge executor needs the HTTP invoker and a step left running for the sweep to settle;
      -- the task lane closes the run with the task, so it invokes rpc inline only. Upgrade path: queue an
      -- action_execution here and let fn_workflow_step_sweep close the task when it settles.
      v_exec_status := 'withheld: ' || ex.target || ' is a ' || ex.kind || ' executor; the org_task lane invokes rpc executors inline only';
    else
      select coalesce(p.pronargs - p.pronargdefaults, -1), p.proargnames into v_req_args, v_argnames
        from pg_proc p where p.proname = ex.target and p.pronamespace = 'public'::regnamespace
       order by p.pronargs limit 1;
      if v_req_args is null then
        v_exec_status := 'failed: public.' || ex.target || '() does not exist';
      elsif v_req_args > 0 then
        v_exec_status := 'withheld: public.' || ex.target || '() requires ' || v_req_args || ' argument(s) an org_task cannot supply';
      else
        v_exec_id := gen_random_uuid();
        begin
          if p_step_run_id is not null and 'p_step_run_id' = any(coalesce(v_argnames, '{}'::text[])) then
            execute format('select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) from public.%I(p_step_run_id => $1) t', ex.target)
               into v_exec_result using p_step_run_id;
          else
            execute format('select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) from public.%I() t', ex.target) into v_exec_result;
          end if;
          insert into public.action_execution(id, correlation_id, workflow_step_run_id, action_class, executor, idempotency_key,
                                              risk_tier, reversible, request, response, status, attempts, started_at, finished_at)
          values (v_exec_id, gen_random_uuid(), p_step_run_id, t.action_class, ex.target,
                  'org_task:' || p_task_id || ':det:' || to_char(now(), 'YYYYMMDDHH24MISSMS'),
                  ex.risk_tier, ex.reversible,
                  jsonb_build_object('org_task_id', p_task_id, 'workflow_step_run_id', p_step_run_id, 'dept_key', t.dept_key,
                                     'actor', v_employee, 'source', 'fn_org_task_deterministic_done', 'kind', 'rpc'),
                  jsonb_build_object('invoker', 'succeeded', 'at', now(), 'kind', 'rpc', 'inline', true,
                                     'result_rows', coalesce(jsonb_array_length(v_exec_result), 0),
                                     'result', case when pg_column_size(v_exec_result) > 20000 then to_jsonb(left(v_exec_result::text, 20000)) else v_exec_result end),
                  'succeeded', 1, now(), now());
          v_exec_status := 'ran: public.' || ex.target || '(' || case when p_step_run_id is not null and 'p_step_run_id' = any(coalesce(v_argnames, '{}'::text[]))
                                                                      then 'p_step_run_id => ' || p_step_run_id else '' end
                           || ') inline, ' || coalesce(jsonb_array_length(v_exec_result), 0) || ' row(s), action_execution ' || v_exec_id;
          v_source := 'executor:' || ex.target;
          -- the executor's own words into the deliverable
          v_exec_text := '';
          for x in select * from jsonb_array_elements(v_exec_result) loop
            if x ? 'deliverable' or x ? 'determination' or x ? 'outcome' then
              v_exec_text := v_exec_text
                || case when x ? 'determination' then 'determination: ' || (x->>'determination') || E'\n' else '' end
                || case when x ? 'outcome' then 'outcome: ' || (x->>'outcome') || E'\n' else '' end
                || case when x ? 'deliverable' then (x->>'deliverable') || E'\n' else '' end;
            else
              v_exec_text := v_exec_text || left(x::text, 1500) || E'\n';
            end if;
            exit when length(v_exec_text) > 8000;
          end loop;
          v_exec_text := left(coalesce(nullif(v_exec_text, ''), '(the executor returned no rows)'), 8000);
        exception when others then
          v_err := sqlstate || ' ' || left(sqlerrm, 400);
          -- the failure is a fact: record it and refuse the close, so the step is released with the reason
          insert into public.action_execution(id, correlation_id, workflow_step_run_id, action_class, executor, idempotency_key,
                                              risk_tier, reversible, request, response, status, attempts, started_at, finished_at)
          values (v_exec_id, gen_random_uuid(), p_step_run_id, t.action_class, ex.target,
                  'org_task:' || p_task_id || ':det:' || to_char(now(), 'YYYYMMDDHH24MISSMS'),
                  ex.risk_tier, ex.reversible,
                  jsonb_build_object('org_task_id', p_task_id, 'workflow_step_run_id', p_step_run_id, 'dept_key', t.dept_key,
                                     'actor', v_employee, 'source', 'fn_org_task_deterministic_done', 'kind', 'rpc'),
                  jsonb_build_object('invoker', 'failed', 'at', now(), 'kind', 'rpc', 'inline', true, 'error', v_err),
                  'failed', 1, now(), now());
          return jsonb_build_object('ok', false, 'reason', 'executor public.' || ex.target || '() failed: ' || v_err,
                                    'action_execution_id', v_exec_id);
        end;
      end if;
    end if;
  end if;

  -- THE DELIVERABLE, rendered from the facts, with the executor's output. RESULT: is the org_task
  -- quality standard's major criterion; the outcome sentence is it.
  v_disp := case when v_bound = 0 then 'needs_narrative'
                 when v_needs_model then 'advisory_held_model'
                 else 'determined' end;
  v_mode := case when v_disp = 'determined' then 'determined' else 'advisory' end;
  v_outcome := case when v_disp = 'needs_narrative'
                    then 'No fact was bound for org_task ' || p_task_id || ' (no event, objective, KPI row, department number or prior review); the record "'
                         || v_pb_title || '" applies as written and the task needs narrative from a reviewer.'
                    else coalesce(nullif(v_facts#>>'{derived,band}', '') || ' '
                                  || coalesce(v_facts#>>'{kpi,metric}', v_facts#>>'{derived,event_type}', t.action_class) || ': ', '')
                         || 'applied ' || v_pb_type || ' "' || v_pb_title || '" to ' || v_bound || ' bound fact(s) of org_task ' || p_task_id
                         || case when v_facts#>>'{derived,cause}' is not null then '; cause ' || (v_facts#>>'{derived,cause}') else '' end
                         || '; executor ' || split_part(coalesce(v_exec_status, 'none'), ':', 1) end;
  v_deliv := public.fn_org_task_render(v_facts, v_pb_title, v_pb_type, v_pb_content, v_pb_sd, v_exec_status, v_exec_text);
  if v_deliv !~* '(^|\n)\s*RESULT:' then
    v_deliv := v_deliv || E'\n\nRESULT: ' || left(v_outcome, 300);
  end if;

  -- A KPI-miss task cannot close without a root cause (trg_org_task_root_cause). The cause class and
  -- its evidence come from the facts (the live employee_kpi row, else the task's own numbers).
  if t.title ilike 'KPI missed%' or t.title ~* 'KPI missed: ' then
    v_rc := left('Root cause (deterministic, no model call): ' || coalesce(v_facts#>>'{derived,cause}', 'not established')
              || ' — ' || coalesce(v_facts#>>'{derived,cause_evidence}', 'no attainment figure available')
              || '. Closing action taken from company playbook "' || coalesce(v_pb_title,'') || '" ('
              || v_pb_id || ', cosine ' || v_sim || ', corroborated ' || v_terms || '/' || v_total || ')'
              || case when v_source like 'executor:%' then '; executor ' || v_target || ' ran' else '' end || '.', 500);
  end if;

  -- used_llm IS A MEASUREMENT: the provider ledgers since the dispatcher claimed the step.
  if p_step_run_id is not null then
    select s.started_at into v_step_started from public.workflow_step_run s where s.id = p_step_run_id;
  end if;
  v_step_started := coalesce(v_step_started, now() - interval '10 minutes');
  select count(*) into v_llm  from public.llm_attempt a where a.fn = 'workflow_dispatch' and a.created_at >= v_step_started;
  select count(*) into v_cost from public.ai_cost_log c where c.fn = 'workflow_dispatch' and c.occurred_at >= v_step_started;
  v_used_llm := (v_llm + v_cost) > 0;
  v_llm_basis := 'measured at close: ' || v_llm || ' llm_attempt + ' || v_cost || ' ai_cost_log row(s) by workflow_dispatch since '
                 || v_step_started || case when p_step_run_id is null then ' (no step_run id: a 10-minute window)' else ' (the step was claimed)' end;

  -- The deliverable must be ON THE ROW before the review: fn_task_review reads it off org_tasks, and
  -- so does the author derivation (result.employee).
  update public.org_tasks
     set result = jsonb_build_object(
                    'deliverable', left(v_deliv, 20000),
                    'summary',     left(v_outcome, 300),
                    'mode',        v_mode,
                    'disposition', v_disp,
                    'determination_source', v_source,
                    'executor_status', v_exec_status,
                    'executor_kind', v_kind,
                    'action_execution_id', v_exec_id,
                    'facts_bound', v_bound,
                    'facts',       v_facts,
                    'used_llm',    v_used_llm,
                    'used_llm_basis', v_llm_basis,
                    'lane',        'org_task',
                    'worked_by',   'workflow_dispatch',
                    'employee',    v_employee,
                    'playbook_record_id',   v_pb_id,
                    'playbook_title',       v_pb_title,
                    'playbook_record_type', v_pb_type,
                    'similarity',   v_sim,
                    'terms_matched', v_terms,
                    'terms_total',   v_total,
                    'workflow_step_run_id', p_step_run_id,
                    'at', now())
                  || case when coalesce(result,'{}'::jsonb) ? 'parked'
                          then jsonb_build_object('previously_parked', result->'parked') else '{}'::jsonb end,
         root_cause  = coalesce(v_rc, root_cause),
         decided_by  = 'workflow_dispatch',
         last_run_at = now(),
         attempts    = coalesce(attempts, 0) + 1,
         updated_at  = now()
   where id = p_task_id;

  -- THE PUBLISHER. Department head -> Chief of Staff -> ownership -> cross-department challenge.
  v_review  := public.fn_task_review(p_task_id);
  v_verdict := coalesce(v_review->>'outcome', 'unknown');
  -- result.review: the chain's verdict, labelled as the chain's; queue_status is added once a queue row exists.
  v_review := v_review || jsonb_build_object('chain_outcome', v_verdict, 'chain_by', 'fn_task_review',
                'note', 'chain_outcome is fn_task_review''s verdict on the deliverable (head, chief of staff, ownership, challenge). '
                     || 'queue_status is the review_queue row an independent reviewer has yet to decide. They are not the same thing.');

  -- A VERDICT THAT IS NOT A CLOSE IS A RESTING STATE, NOT A RETRY. The determination is a pure
  -- function of (task facts, executor, playbook), so the same verdict comes back every tick; the task
  -- moves to the state the verdict actually means and fn_workflow_step_claim stops picking it.
  if v_verdict not in ('published','approve') then
    if v_verdict = 'escalate' then
      update public.org_tasks
         set status = 'escalated', updated_at = now(),
             result = coalesce(result,'{}'::jsonb) || jsonb_build_object(
               'review', v_review || jsonb_build_object('queue_status', 'no queue row: the close did not complete'),
               'escalated', jsonb_build_object('at', now(), 'by', 'workflow_dispatch (org_task lane)',
                 'reason', coalesce(v_review->>'reason', 'the review chain could not resolve an available approver'),
                 'note', 'The determination was produced and stored; it is the REVIEW that could not '
                      || 'complete, because this department has no approver independent of the author. '
                      || 'That is an org finding, not a work failure, and it rests here rather than '
                      || 'being retried against the same chain every ten minutes.'))
       where id = p_task_id;
    else
      v_known := public.fn_org_task_lane_knowledge(t.dept_key);
      update public.org_tasks
         set status = 'blocked', updated_at = now(),
             result = coalesce(result,'{}'::jsonb) || jsonb_build_object(
               'review', v_review || jsonb_build_object('queue_status', 'no queue row: the close did not complete'),
               'parked', jsonb_build_object('at', now(), 'by', 'workflow_dispatch (org_task lane)',
                 'reason', 'the review returned ' || v_verdict,
                 'violations', coalesce(v_review->'violations','[]'::jsonb),
                 'knowledge_at_park', v_known,
                 'note', 'The deterministic determination did not meet the org_task quality standard. '
                      || 'The determination is a pure function of this task''s facts and the playbook applied, so '
                      || 'another attempt returns the same verdict; what has to change is the KNOWLEDGE or the facts. '
                      || 'fn_org_task_promote re-opens this when the department holds more actionable '
                      || 'in-scope knowledge than the ' || v_known || ' records it held here.'))
       where id = p_task_id;
    end if;

    -- THE RUN IS THE EMPLOYEE'S: 'ok' when the verdict is an org finding (escalate: no approver),
    -- 'rejected' when the determination itself failed review. Never 'error': fn_watch_failed_runs pages
    -- the founder on error rows and nothing here is an outage.
    insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
    values (v_employee, now(), now(), case when v_verdict = 'escalate' then 'ok' else 'rejected' end,
            jsonb_build_object('org_task_id', p_task_id, 'lane', 'org_task', 'review_outcome', v_verdict,
                               'workflow_step_run_id', p_step_run_id, 'used_llm', v_used_llm,
                               'disposition', v_disp, 'executor_status', v_exec_status, 'action_execution_id', v_exec_id),
            left('org_task ' || p_task_id || ' determined from ' || v_bound || ' fact(s) and playbook ' || coalesce(v_pb_title,'')
                 || '; review returned ' || v_verdict || ' and the task rests as '
                 || case when v_verdict = 'escalate' then 'escalated' else 'blocked' end, 500));

    return jsonb_build_object('ok', false, 'terminal', true, 'review_outcome', v_verdict,
             'reason', 'review returned ' || v_verdict
               || coalesce(': ' || left((v_review->'violations')::text, 300), '')
               || '; the org_task now rests as '
               || case when v_verdict = 'escalate' then 'escalated' else 'blocked' end
               || ' and is not retried',
             'review', v_review, 'disposition', v_disp, 'executor_status', v_exec_status, 'action_execution_id', v_exec_id);
  end if;

  -- The sealed record of what was decided, on what, by which rule, with what confidence.
  insert into public.decision_trace(
      correlation_id, entity_type, entity_id, decision_type,
      proposed_by, decided_by, policy_keys, knowledge_refs, evidence_refs, alternatives,
      assumptions, risk, confidence, authority_result,
      decision, outcome_status, agent_key, department_id, task_class,
      knowledge_versions, source_freshness, tools_requested, tools_executed, tool_result_refs,
      uncertainty, escalation_decision, proposed_action, expected_outcome,
      model, provider, input_tokens, output_tokens, estimated_cost_aed, final_status, sealed_at)
  values (
      gen_random_uuid(), 'org_task', p_task_id::text, 'deterministic_playbook_application',
      v_employee, 'fn_org_task_deterministic_done', array['deterministic_first','org_task_lane']::text[],
      jsonb_build_array(jsonb_build_object('record_id', v_pb_id, 'title', v_pb_title, 'record_type', v_pb_type,
                                           'similarity', v_sim, 'terms_matched', v_terms, 'terms_total', v_total)),
      jsonb_build_array(jsonb_build_object('org_task_id', p_task_id, 'dept_key', t.dept_key,
                                           'title', t.title, 'action_class', t.action_class,
                                           'workflow_step_run_id', p_step_run_id,
                                           'facts', v_facts, 'review', v_review)),
      coalesce(p_output->'candidates', '[]'::jsonb),
      jsonb_build_array('the nearest CORROBORATED actionable company record is the applicable one for this task',
                        'the facts read at close time are the facts the task is about'),
      jsonb_build_object('level', 'low', 'note', case when v_source like 'executor:%'
                                                      then 'a low-risk, advisory-safe, reversible executor was invoked; moves no money, sends nothing, approves nobody'
                                                      else 'determination only; moves no money, sends nothing, approves nobody' end),
      v_sim,
      jsonb_build_object('mode', v_mode, 'tier', t.tier, 'paid_provider', 'held', 'executor', v_exec_status),
      jsonb_build_object('determination', left(v_deliv, 8000), 'outcome', left(v_outcome, 400), 'disposition', v_disp,
                         'determination_source', v_source, 'basis', 'facts of the task rendered against the corroborated record; no model call'),
      'pending', v_employee, t.dept_key, 'org_task',
      '{}'::jsonb, jsonb_build_object('ops_knowledge', 'live at decision time', 'facts_read_at', v_facts->>'read_at'),
      case when v_target is not null then array[v_target] else '{}'::text[] end,
      case when v_source like 'executor:%' then array[v_target] else '{}'::text[] end,
      case when v_exec_id is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('action_execution_id', v_exec_id)) end,
      case v_disp when 'determined' then 'determined from ' || v_bound || ' bound fact(s); queued for review'
                  when 'advisory_held_model' then 'determined from ' || v_bound || ' bound fact(s), but the task''s executor needs the held model; advisory until the hold lifts'
                  else 'no fact bound: the record applies as written; narrative is needed' end,
      'review_queued', 'close the org_task with disposition ' || v_disp,
      'the mirroring employee_task run closes with it; a reviewer can overturn the determination',
      'none', 'deterministic', 0, 0, 0, 'auto_done', now())
  returning id into v_trace;

  insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
  values (v_employee, now(), now(), 'ok',
          jsonb_build_object('org_task_id', p_task_id, 'lane', 'org_task', 'review_outcome', v_verdict,
                             'decision_trace_id', v_trace, 'workflow_step_run_id', p_step_run_id,
                             'playbook_record_id', v_pb_id, 'similarity', v_sim, 'used_llm', v_used_llm,
                             'disposition', v_disp, 'facts_bound', v_bound, 'executor_status', v_exec_status,
                             'action_execution_id', v_exec_id),
          left('org_task ' || p_task_id || ' determined from ' || v_bound || ' fact(s) and playbook ' || coalesce(v_pb_title,'')
               || ' (cosine ' || v_sim || ', corroborated ' || v_terms || '/' || v_total || '); executor '
               || split_part(coalesce(v_exec_status,'none'), ':', 1) || '; review chain ' || v_verdict, 500));

  -- Never a silent pass: the determination is queued for an independent reviewer, with everything
  -- needed to overturn it. The row is NOT decided here.
  insert into public.review_queue(kind, dept_key, title, summary, payload, status)
  values ('deterministic_org_task', t.dept_key,
          left(initcap(replace(v_disp, '_', ' ')) || ': org_task ' || p_task_id || ' — ' || coalesce(t.title,''), 240),
          left(v_outcome, 600),
          jsonb_build_object('org_task_id', p_task_id, 'dept_key', t.dept_key,
                             'workflow_step_run_id', p_step_run_id,
                             'employee', v_employee,
                             'playbook_record_id', v_pb_id, 'playbook_title', v_pb_title,
                             'similarity', v_sim, 'terms_matched', v_terms, 'terms_total', v_total,
                             'decision_trace_id', v_trace, 'review_chain', v_review,
                             'disposition', v_disp, 'determination_source', v_source,
                             'executor_status', v_exec_status, 'action_execution_id', v_exec_id,
                             'facts_bound', v_bound, 'used_llm', v_used_llm),
          'pending')
  returning id into v_queue;

  update public.org_tasks
     set status     = 'done',
         updated_at = now(),
         result     = coalesce(result,'{}'::jsonb) || jsonb_build_object(
                        'review', v_review || jsonb_build_object('queue_status', 'pending', 'review_queue_id', v_queue),
                        'decision_trace_id', v_trace,
                        'review_queue_id', v_queue,
                        'review_queue_status', 'pending',
                        'disposition', v_disp)
   where id = p_task_id;

  return jsonb_build_object('ok', true, 'org_task_id', p_task_id, 'review_outcome', v_verdict,
                            'review', jsonb_build_object('chain_outcome', v_verdict, 'queue_status', 'pending', 'review_queue_id', v_queue),
                            'decision_trace_id', v_trace, 'review_queue_id', v_queue,
                            'disposition', v_disp, 'determination_source', v_source,
                            'executor_status', v_exec_status, 'action_execution_id', v_exec_id,
                            'facts_bound', v_bound, 'used_llm', v_used_llm, 'root_cause', v_rc);
end
$function$;

-- Read back what was applied: the lane renders from the task's facts and no longer writes the literal.
do $$
declare v_src text;
begin
  select pg_get_functiondef(p.oid) into v_src from pg_proc p
   where p.proname = 'fn_org_task_deterministic_done' and p.pronamespace = 'public'::regnamespace;
  if v_src not like '%fn_org_task_facts(%' or v_src not like '%fn_org_task_render(%' then
    raise exception 'fn_org_task_deterministic_done does not render from the task''s facts';
  end if;
  if v_src like '%deterministic_low_confidence%' then
    raise exception 'fn_org_task_deterministic_done still writes the literal disposition';
  end if;
  if v_src not like '%chain_outcome%' or v_src not like '%queue_status%' then
    raise exception 'fn_org_task_deterministic_done does not label the two reviews distinctly';
  end if;
end $$;

commit;
