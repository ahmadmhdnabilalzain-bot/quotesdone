-- EVERY OPEN TASK GETS A REASON OR A RUN, AND THE RUN IS THE EMPLOYEE'S (MASTER_PLAN §4.3), 5 Sep 2026.
--
-- MEASURED on production 5 Sep 2026 18:35–19:10 UTC, before this file:
--   * open org_tasks 538: assigned 453 (53 with an employee_task run, 400 without), escalated 51,
--     proposed 34, blocked 0, in_progress 0. 645 of 652 carried no reason on the row the day before;
--     today 18 of the 51 escalated carry result.escalated (the lane's verdict), 33 do not.
--   * the 33 without a reason were all escalated by cos_execute (decided_by 'cos'), the org_task
--     executor RETIRED on 3 Sep; 30 of them hold the deliverable "I could not reach the AI service just
--     now — please try again in a moment." That is the retired executor's outage, not a verdict.
--   * the 18 with a reason are ALL in exec, author = ceo, "the review chain could not resolve an
--     available approver". fn_org_task_assign gives the ceo tasks like any colleague (least-loaded,
--     max_open_tasks 50: brief 50, ceo 50, cpo 50 open), fn_pick_reviewer correctly refuses to let the
--     head approve its own work, and the ceo has no manager to climb to. 1 in 5 of the lane's exec
--     closes since the 4 Sep author fix has ended this way (5 published : 1–2 escalated per hour).
--   * the 34 proposed are held by fn_task_approve; the reason ("no org_authority row for supply/analysis
--     - defaulting to gated") is in review_chain, not on the task.
--   * v_department_health credits "run success" from agent_runs joined to org_agents BY EMPLOYEE. The
--     lane closed 367 tasks and wrote no agent_runs row for any of them, so five departments read
--     "no runs recorded for its staff" while their staff did the work.
--   * the promoter's `exception when others then null` around fn_workflow_start is the handler that
--     hid the lane for two days (4 Sep); it now records the refusal on the task instead.
--
-- WHAT CHANGES (three routines, full definitions):
--   fn_org_task_deterministic_done — an agent_runs row for the employee on every terminal path
--     ('ok' on published/escalate, 'rejected' when the determination failed review; never 'error').
--   fn_org_task_promote — four standing rules before promotion (see the comment on the function), and
--     only an OWNED task is promoted, because an unowned task's actor resolves to the department head.
--   fn_org_task_assign — the picker is told who it must not select: a head with no manager while a
--     colleague exists. Unworked tasks already on such a head are released first, and so is work held
--     by a colleague who is no longer active or available (10 tasks on 6 deactivated agents, found
--     by the first tick that recorded a promotion refusal instead of swallowing it: "actor owner
--     resolves to no employee").
--
--   node scripts/apply_sql.mjs scripts/sql/every_open_task_gets_a_reason_or_a_run.sql --apply --ddl

begin;

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
  v_att        numeric;
  v_band       text;
  v_known      int;
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
  v_outcome := coalesce(nullif(p_output->>'outcome',''), left(v_deliv, 280));
  v_sim     := nullif(p_output->>'similarity', '')::numeric;
  v_terms   := coalesce(nullif(p_output->>'terms_matched','')::int, 0);
  v_total   := coalesce(nullif(p_output->>'terms_total','')::int, 0);
  v_employee := coalesce(nullif(p_output->>'employee',''), t.assigned_agent, t.dept_key);

  -- FALSE-SUCCESS GUARDS. Nothing below runs unless the determination has substance.
  if coalesce(p_output->>'playbook_record_id','') = '' then
    return jsonb_build_object('ok', false, 'reason', 'no playbook_record_id: a determination must cite the company knowledge it applied');
  end if;
  if not exists (select 1 from public.ops_knowledge k
                  where k.record_id = p_output->>'playbook_record_id'
                    and k.runtime_eligible and k.supersession_state = 'current'
                    and k.record_type in ('decision_playbook','decision_rule','standard_operating_procedure','exception_playbook')) then
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

  -- The org_task quality standard requires a RESULT: line (major severity). The determination is the
  -- playbook's own content, which does not carry one, so the applier's outcome sentence becomes it.
  if v_deliv !~* '(^|\n)\s*RESULT:' then
    v_deliv := v_deliv || E'\n\nRESULT: ' || left(v_outcome, 300);
  end if;

  -- A KPI-miss task cannot close without a root cause (trg_org_task_root_cause). The honest
  -- deterministic diagnosis available without the model is the ATTAINMENT BAND, read from the task's
  -- own numbers, which fn_kpi_review wrote into the detail as "actual X (Y% of target)". A band is a
  -- class of cause, and it says which class it is rather than inventing a specific one.
  if t.title ilike 'KPI missed%' then
    v_att := nullif(substring(coalesce(t.detail,'') from '\(([0-9]+(?:\.[0-9]+)?)% of target\)'), '')::numeric;
    v_band := case
      when v_att is null      then 'unmeasured: the task carries no attainment figure, so the variance class cannot be read from it'
      when v_att < 5          then 'no throughput: attainment ' || v_att || '% means the input that feeds this metric has not started, not that it under-performed'
      when v_att < 50         then 'capacity or conversion shortfall: attainment ' || v_att || '% is real activity falling well short of the target'
      when v_att < 100        then 'target above current capability: attainment ' || v_att || '% is near-miss performance against a target set higher than the process currently reaches'
      else 'measurement: attainment ' || v_att || '% is at or above target, so the miss is in how the metric is measured or dated, not in the work' end;
    v_rc := left('Root cause (deterministic band, no model call): ' || v_band
              || '. Closing action taken from company playbook "' || coalesce(p_output->>'playbook_title','') || '" ('
              || (p_output->>'playbook_record_id') || ', cosine ' || v_sim || ', corroborated ' || v_terms || '/' || v_total || ').', 500);
  end if;

  -- The deliverable must be ON THE ROW before the review: fn_task_review reads it off org_tasks, and
  -- so does the author derivation (result.employee).
  update public.org_tasks
     set result = jsonb_build_object(
                    'deliverable', left(v_deliv, 20000),
                    'summary',     left(v_outcome, 300),
                    'mode',        'determined',
                    'used_llm',    false,
                    'lane',        'org_task',
                    'worked_by',   'workflow_dispatch',
                    'employee',    v_employee,
                    'playbook_record_id',   p_output->>'playbook_record_id',
                    'playbook_title',       p_output->>'playbook_title',
                    'playbook_record_type', p_output->>'playbook_record_type',
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

  -- A VERDICT THAT IS NOT A CLOSE IS A RESTING STATE, NOT A RETRY. The determination is a pure
  -- function of (task, playbook), so the same verdict comes back every tick; the task moves to the
  -- state the verdict actually means and fn_workflow_step_claim stops picking it (it claims only while
  -- the task is open).
  if v_verdict not in ('published','approve') then
    if v_verdict = 'escalate' then
      update public.org_tasks
         set status = 'escalated', updated_at = now(),
             result = coalesce(result,'{}'::jsonb) || jsonb_build_object(
               'review', v_review,
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
               'review', v_review,
               'parked', jsonb_build_object('at', now(), 'by', 'workflow_dispatch (org_task lane)',
                 'reason', 'the review returned ' || v_verdict,
                 'violations', coalesce(v_review->'violations','[]'::jsonb),
                 'knowledge_at_park', v_known,
                 'note', 'The deterministic determination did not meet the org_task quality standard. '
                      || 'The determination is a pure function of this task and the playbook applied, so '
                      || 'another attempt returns the same verdict; what has to change is the KNOWLEDGE. '
                      || 'fn_org_task_promote re-opens this when the department holds more actionable '
                      || 'in-scope knowledge than the ' || v_known || ' records it held here.'))
       where id = p_task_id;
    end if;

    -- THE RUN IS THE EMPLOYEE'S (5 Sep 2026): the work was performed by v_employee whatever the review
    -- said, and v_department_health reads agent_runs BY EMPLOYEE. 'ok' when the verdict is an org finding
    -- (escalate: no approver), 'rejected' when the determination itself failed review. Never 'error':
    -- fn_watch_failed_runs pages the founder on error rows and nothing here is an outage.
    insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
    values (v_employee, now(), now(), case when v_verdict = 'escalate' then 'ok' else 'rejected' end,
            jsonb_build_object('org_task_id', p_task_id, 'lane', 'org_task', 'review_outcome', v_verdict,
                               'workflow_step_run_id', p_step_run_id, 'used_llm', false),
            left('org_task ' || p_task_id || ' determined from playbook ' || coalesce(p_output->>'playbook_title','')
                 || '; review returned ' || v_verdict || ' and the task rests as '
                 || case when v_verdict = 'escalate' then 'escalated' else 'blocked' end, 500));

    return jsonb_build_object('ok', false, 'terminal', true, 'review_outcome', v_verdict,
             'reason', 'review returned ' || v_verdict
               || coalesce(': ' || left((v_review->'violations')::text, 300), '')
               || '; the org_task now rests as '
               || case when v_verdict = 'escalate' then 'escalated' else 'blocked' end
               || ' and is not retried',
             'review', v_review);
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
      v_employee, 'fn_apply_playbook', array['deterministic_first','org_task_lane']::text[],
      jsonb_build_array(jsonb_build_object('record_id', p_output->>'playbook_record_id',
                                           'title', p_output->>'playbook_title',
                                           'similarity', v_sim,
                                           'terms_matched', v_terms, 'terms_total', v_total)),
      jsonb_build_array(jsonb_build_object('org_task_id', p_task_id, 'dept_key', t.dept_key,
                                           'title', t.title, 'action_class', t.action_class,
                                           'workflow_step_run_id', p_step_run_id,
                                           'review', v_review)),
      coalesce(p_output->'candidates', '[]'::jsonb),
      jsonb_build_array('the nearest CORROBORATED actionable company playbook is the applicable one for this task'),
      jsonb_build_object('level', 'low', 'note', 'advisory determination; moves no money, sends nothing, approves nobody'),
      v_sim,
      jsonb_build_object('mode', 'advisory', 'tier', t.tier, 'paid_provider', 'held'),
      jsonb_build_object('determination', left(v_deliv, 8000), 'outcome', left(v_outcome, 400),
                         'basis', 'nearest corroborated company knowledge by meaning; no model call'),
      'pending', v_employee, t.dept_key, 'org_task',
      '{}'::jsonb, jsonb_build_object('ops_knowledge', 'live at decision time'), '{}'::text[], '{}'::text[], '[]'::jsonb,
      'low-confidence deterministic disposition: the corroborated playbook was applied, not reasoned over; queued for review',
      'review_queued', 'close the org_task with a deterministic disposition',
      'the mirroring employee_task run closes with it; a reviewer can overturn the determination',
      'none', 'deterministic', 0, 0, 0, 'auto_done', now())
  returning id into v_trace;

  insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
  values (v_employee, now(), now(), 'ok',
          jsonb_build_object('org_task_id', p_task_id, 'lane', 'org_task', 'review_outcome', v_verdict,
                             'decision_trace_id', v_trace, 'workflow_step_run_id', p_step_run_id,
                             'playbook_record_id', p_output->>'playbook_record_id', 'similarity', v_sim, 'used_llm', false),
          left('org_task ' || p_task_id || ' determined from playbook ' || coalesce(p_output->>'playbook_title','')
               || ' (cosine ' || v_sim || ', corroborated ' || v_terms || '/' || v_total || '); review ' || v_verdict, 500));

  insert into public.review_queue(kind, dept_key, title, summary, payload, status)
  values ('deterministic_org_task', t.dept_key,
          left('Deterministic determination: org_task ' || p_task_id || ' — ' || coalesce(t.title,''), 240),
          left(v_outcome, 600),
          jsonb_build_object('org_task_id', p_task_id, 'dept_key', t.dept_key,
                             'workflow_step_run_id', p_step_run_id,
                             'employee', v_employee,
                             'playbook_record_id', p_output->>'playbook_record_id',
                             'playbook_title', p_output->>'playbook_title',
                             'similarity', v_sim, 'terms_matched', v_terms, 'terms_total', v_total,
                             'decision_trace_id', v_trace, 'review', v_review,
                             'disposition', 'deterministic_low_confidence'),
          'pending')
  returning id into v_queue;

  update public.org_tasks
     set status     = 'done',
         updated_at = now(),
         result     = coalesce(result,'{}'::jsonb) || jsonb_build_object(
                        'review', v_review,
                        'decision_trace_id', v_trace,
                        'review_queue_id', v_queue,
                        'disposition', 'deterministic_low_confidence')
   where id = p_task_id;

  return jsonb_build_object('ok', true, 'org_task_id', p_task_id, 'review_outcome', v_verdict,
                            'decision_trace_id', v_trace, 'review_queue_id', v_queue,
                            'root_cause', v_rc);
end
$function$;

-- ---------------------------------------------------------------------------------------------------
-- fn_org_task_promote: every open task gets a reason or a run. Three resting states are re-examined on
-- every tick, each with a standing rule rather than a one-off sweep:
--   1. BLOCKED on knowledge  -> re-opened when the department has learned (unchanged).
--   2. ESCALATED by the retired executor (decided_by 'cos', no result.escalated): cos_execute parked
--      these when its model call failed — "I could not reach the AI service" is the deliverable on
--      most of them. That is not a verdict on the work; it is the executor's outage. They re-enter the
--      lane once, with the retired executor's attempt count recorded and the lane's own counter at 0.
--   3. ESCALATED by the lane because the review chain had NO approver and the author was the department
--      head with no manager (the ceo). fn_org_task_assign no longer hands that head work while a
--      colleague exists (below), so the task re-enters unowned and the next assign gives it to a
--      colleague the head CAN review.
--   4. PROPOSED and held by fn_task_approve: the hold reason lives in review_chain; it is copied onto
--      the row (result.held) so the backlog itself says why the task is not running. Status is left
--      to fn_task_approve, which re-evaluates hourly.
-- Then the promotion itself, unchanged except that only an OWNED task is promoted: an unowned task's
-- actor resolves to the department, which fn_org_agent_resolve maps to its head — the exact author
-- that rule 3 exists to avoid.
-- ---------------------------------------------------------------------------------------------------
create or replace function public.fn_org_task_promote(p_limit integer default 12, p_in_flight_ceiling integer default 60)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  r record; v_run uuid;
  v_unparked int := 0; v_promoted int := 0; v_in_flight int; v_room int; v_backlog int;
  v_reopened_cos int := 0; v_reopened_head int := 0; v_held int := 0;
begin
  -- 1. a park heals when the company learns something
  for r in
    select t.id, t.dept_key, coalesce((t.result->'parked'->>'knowledge_at_park')::int, 0) was
      from public.org_tasks t
     where t.status = 'blocked' and (t.result ? 'parked')
     order by t.id
     limit 200
  loop
    if public.fn_org_task_lane_knowledge(r.dept_key) > r.was then
      update public.org_tasks
         set status = 'assigned', updated_at = now(),
             result = coalesce(result,'{}'::jsonb) || jsonb_build_object(
               'unparked', jsonb_build_object('at', now(),
                 'knowledge_at_park', r.was,
                 'knowledge_now', public.fn_org_task_lane_knowledge(r.dept_key),
                 'reason', 'the department now holds more actionable in-scope knowledge than when this parked'))
       where id = r.id;
      update public.workflow_step_run sr
         set status = 'ready', attempts = 0, error = null
        from public.workflow_run wr
       where wr.id = sr.workflow_run_id and wr.workflow_key = 'employee_task'
         and wr.context->>'task_id' = r.id::text
         and sr.finished_at is null
         and coalesce(sr.error->>'disposition','') = 'awaiting_model';
      v_unparked := v_unparked + 1;
    end if;
  end loop;

  -- 2. the retired executor's outages are not verdicts
  update public.org_tasks t
     set status = 'assigned', updated_at = now(),
         attempts = 0,
         result = coalesce(t.result,'{}'::jsonb) || jsonb_build_object(
           'reopened', jsonb_build_object('at', now(), 'by', 'fn_org_task_promote',
             'from', 'escalated', 'previous_attempts', coalesce(t.attempts, 0),
             'previous_decided_by', t.decided_by,
             'reason', 'escalated by cos_execute (retired 3 Sep 2026) after its model call failed; '
                    || 'that was the executor''s outage, not a verdict on the task. It re-enters the '
                    || 'deterministic org_task lane, which determines it from company knowledge or parks it with a reason'))
   where t.status = 'escalated'
     and t.decided_by = 'cos'
     and not (coalesce(t.result,'{}'::jsonb) ? 'escalated')
     and not (coalesce(t.result,'{}'::jsonb) ? 'reopened');
  get diagnostics v_reopened_cos = row_count;

  -- 3. no approver because the head authored it: re-enter unowned, a colleague will author it
  update public.org_tasks t
     set status = 'assigned', updated_at = now(), assigned_agent = null,
         result = coalesce(t.result,'{}'::jsonb) || jsonb_build_object(
           'reopened', jsonb_build_object('at', now(), 'by', 'fn_org_task_promote',
             'from', 'escalated', 'previous_author', t.assigned_agent,
             'reason', 'the review chain had no approver because the department head (' || t.assigned_agent
                    || ', who has no manager) authored the work; re-entered unowned so that a colleague the '
                    || 'head can review performs it'))
    from public.org_departments d
   where d.dept_key = t.dept_key
     and t.status = 'escalated'
     and (t.result ? 'escalated')
     -- who AUTHORED it, as the review recorded — a task claimed while unowned resolves to the head too
     and coalesce(t.result->'review'->>'author', t.assigned_agent) = d.lead_agent
     -- once per escalation: a task claimed while it was still on the head can escalate again after
     -- its first re-open, and that later verdict is re-examined too — never a loop, because a task
     -- the assigner has re-homed no longer carries the head as its assignee
     and coalesce((t.result->'reopened'->>'at')::timestamptz, '-infinity'::timestamptz)
         < coalesce((t.result->'escalated'->>'at')::timestamptz, now())
     and not exists (select 1 from public.org_agents h
                      join public.org_agents m on m.agent_key = h.manager_key and m.active
                     where h.agent_key = d.lead_agent)
     and exists (select 1 from public.org_agents b
                  left join public.org_role rb on rb.runtime_agent_key = b.agent_key and rb.status = 'active'
                 where b.active and coalesce(b.available, true) and b.department = d.dept_key
                   and b.agent_key <> d.lead_agent
                   and coalesce(rb.runtime_mode, 'on_demand_specialist') <> 'independent_reviewer');
  get diagnostics v_reopened_head = row_count;

  -- 4. a held proposal says on the row why it is held
  update public.org_tasks t
     set result = coalesce(t.result,'{}'::jsonb) || jsonb_build_object(
           'held', jsonb_build_object('at', now(), 'by', 'fn_task_approve', 'reason', h.reason, 'decided_at', h.created_at))
    from (select distinct on (rc.subject_id) rc.subject_id, rc.reason, rc.created_at
            from public.review_chain rc
           where rc.subject_type = 'org_task' and rc.stage = 'approval' and rc.decision = 'hold'
           order by rc.subject_id, rc.created_at desc) h
   where t.status = 'proposed'
     and h.subject_id = t.id::text
     and coalesce(t.result->'held'->>'reason', '') is distinct from h.reason;
  get diagnostics v_held = row_count;

  select count(*) into v_in_flight
    from public.workflow_run wr where wr.workflow_key = 'employee_task' and wr.status = 'running';
  v_room := greatest(least(coalesce(p_limit, 12), coalesce(p_in_flight_ceiling, 60) - v_in_flight), 0);

  select count(*) into v_backlog
    from public.org_tasks t
   where t.status in ('assigned','in_progress')
     -- a RUNNING run, not any run: a task re-opened after an escalation keeps its earlier (failed) run
     -- and needs a new one — measured 5 Sep: 18 re-opened exec tasks sat unpromoted behind this predicate
     and not exists (select 1 from public.workflow_run wr
                      where wr.workflow_key = 'employee_task' and wr.context->>'task_id' = t.id::text
                        and wr.status = 'running');

  if v_room > 0 then
    for r in
      select t.id, t.dept_key
        from public.org_tasks t
       where t.status in ('assigned','in_progress')
         and coalesce(t.needs_founder, false) = false
         and exists (select 1 from public.org_agents a where a.agent_key = t.assigned_agent and a.active)
         and not exists (select 1 from public.workflow_run wr
                          where wr.workflow_key = 'employee_task' and wr.context->>'task_id' = t.id::text
                            and wr.status = 'running')
       order by t.priority desc nulls last, t.created_at, t.id
       limit v_room
    loop
      begin
        v_run := public.fn_workflow_start('employee_task', null, 'org_task', r.id::text,
                   jsonb_build_object('task_id', r.id::text, 'dept_key', r.dept_key,
                                      'promoted_by', 'fn_org_task_promote',
                                      'promoted_at', now()));
        if v_run is not null then v_promoted := v_promoted + 1; end if;
      exception when others then
        -- 4 Sep 2026: two swallowed errors here hid a leg that never ran. A refusal is recorded ON THE
        -- TASK, in words, so the next census reads it instead of counting a healthy promoter.
        update public.org_tasks
           set result = coalesce(result,'{}'::jsonb) || jsonb_build_object(
                 'promotion_refused', jsonb_build_object('at', now(), 'sqlstate', sqlstate, 'error', left(sqlerrm, 400)))
         where id = r.id;
      end;
    end loop;
  end if;

  return jsonb_build_object('unparked', v_unparked, 'promoted', v_promoted,
                            'reopened_from_retired_executor', v_reopened_cos,
                            'reopened_head_authored', v_reopened_head,
                            'held_proposals_annotated', v_held,
                            'in_flight_before', v_in_flight, 'room', v_room,
                            'backlog_without_a_run', v_backlog, 'ran_at', now());
end
$function$;

-- ---------------------------------------------------------------------------------------------------
-- fn_org_task_assign: a head that nobody can review does not author. The picker is told, per task, who
-- it must not select: the department's lead_agent when that head has no active manager AND a colleague
-- who is not an independent reviewer is active in the department. Measured 5 Sep 2026: the Office of
-- the CEO is the only department shaped like that (ceo, no manager; brief and cpo beside it), and every
-- exec task the assigner had given the ceo escalated with "no independent reviewer or manager is
-- available" — 1 in 5 of the lane's exec closes. Open, unworked tasks already on such a head are
-- released to unowned first so the same tick re-homes them.
-- ---------------------------------------------------------------------------------------------------
create or replace function public.fn_org_task_assign(p_limit integer default 200)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  r record; v_pick text;
  v_assigned int := 0; v_no_capacity int := 0; v_considered int := 0; v_saturated text;
  v_released int := 0; v_gone int := 0;
  v_promote jsonb;
  REVIEW_CLASSES constant text[] := array['review','audit','verify','qa_gate','security_review',
                                          'compliance_check','legal_review','supplier_verify',
                                          'capability_review','self_review'];
begin
  -- release unworked work from a head nobody can review, where a colleague exists
  update public.org_tasks t
     set assigned_agent = null, updated_at = now(),
         result = coalesce(t.result,'{}'::jsonb) || jsonb_build_object(
           'released', jsonb_build_object('at', now(), 'by', 'fn_org_task_assign', 'from', t.assigned_agent,
             'reason', 'the department head has no manager, so work it authors cannot be reviewed; '
                    || 'released to a colleague the head can review'))
    from public.org_departments d
   where d.dept_key = t.dept_key
     and t.status in ('assigned','in_progress')
     and t.assigned_agent = d.lead_agent
     and coalesce(t.attempts, 0) = 0
     and not exists (select 1 from public.org_agents h
                      join public.org_agents m on m.agent_key = h.manager_key and m.active
                     where h.agent_key = d.lead_agent)
     and exists (select 1 from public.org_agents b
                  left join public.org_role rb on rb.runtime_agent_key = b.agent_key and rb.status = 'active'
                 where b.active and coalesce(b.available, true) and b.department = d.dept_key
                   and b.agent_key <> d.lead_agent
                   and coalesce(rb.runtime_mode, 'on_demand_specialist') <> 'independent_reviewer')
     and not exists (select 1 from public.workflow_step_run sr
                      join public.workflow_run wr on wr.id = sr.workflow_run_id
                     where wr.workflow_key = 'employee_task' and wr.context->>'task_id' = t.id::text
                       and sr.status = 'running');
  get diagnostics v_released = row_count;

  -- release work held by a colleague who is no longer active or available: fn_workflow_actor_resolve
  -- resolves such an owner to no employee and the promotion is refused (10 open tasks, 5 Sep 2026,
  -- surfaced the moment the promoter stopped swallowing the refusal)
  update public.org_tasks t
     set assigned_agent = null, updated_at = now(),
         result = coalesce(t.result,'{}'::jsonb) || jsonb_build_object(
           'released', jsonb_build_object('at', now(), 'by', 'fn_org_task_assign', 'from', t.assigned_agent,
             'reason', 'the assignee is no longer an active, available colleague; released to be re-homed'))
   where t.status in ('assigned','in_progress')
     and t.assigned_agent is not null
     and not exists (select 1 from public.org_agents a
                      where a.agent_key = t.assigned_agent and a.active and coalesce(a.available, true)
                        and (a.unavailable_until is null or a.unavailable_until < now()));
  get diagnostics v_gone = row_count;
  v_released := v_released + v_gone;

  for r in
    select t.id, t.dept_key, t.action_class
      from public.org_tasks t
     where t.assigned_agent is null
       and t.status in ('assigned','in_progress')
     order by t.priority desc, t.created_at, t.id
     limit greatest(coalesce(p_limit, 200), 1)
  loop
    v_considered := v_considered + 1;
    select a.agent_key into v_pick
      from public.org_agents a
      left join public.agent_reputation p on p.agent_key = a.agent_key
      left join public.org_role rr on rr.runtime_agent_key = a.agent_key and rr.status = 'active'
      join public.org_departments d on d.dept_key = a.department
     where a.active
       and coalesce(a.available, true)
       and (a.unavailable_until is null or a.unavailable_until < now())
       and a.department = r.dept_key
       and (coalesce(rr.runtime_mode, 'on_demand_specialist') <> 'independent_reviewer'
            or coalesce(r.action_class, '') = any (REVIEW_CLASSES))
       -- the picker knows who it must not select: a head nobody can review, while a colleague exists
       and not (a.agent_key = d.lead_agent
                and not exists (select 1 from public.org_agents h
                                 join public.org_agents m on m.agent_key = h.manager_key and m.active
                                where h.agent_key = d.lead_agent)
                and exists (select 1 from public.org_agents b
                             left join public.org_role rb on rb.runtime_agent_key = b.agent_key and rb.status = 'active'
                            where b.active and coalesce(b.available, true) and b.department = d.dept_key
                              and b.agent_key <> d.lead_agent
                              and coalesce(rb.runtime_mode, 'on_demand_specialist') <> 'independent_reviewer'))
       and (select count(*) from public.org_tasks o
             where o.assigned_agent = a.agent_key
               and o.status in ('assigned','in_progress')) < coalesce(a.max_open_tasks, 6)
     order by case when p.tier = 'probation' then 1 else 0 end,
              (select count(*) from public.org_tasks o
                where o.assigned_agent = a.agent_key
                  and o.status in ('assigned','in_progress')),
              a.agent_key
     limit 1;

    if v_pick is not null then
      update public.org_tasks set assigned_agent = v_pick, updated_at = now() where id = r.id;
      v_assigned := v_assigned + 1;
    else
      v_no_capacity := v_no_capacity + 1;
    end if;
  end loop;

  select string_agg(x.dept_key||' '||x.unowned||'/'||x.capacity, ', ' order by x.unowned desc)
    into v_saturated
    from (select t.dept_key, count(*) as unowned,
                 (select coalesce(sum(coalesce(a.max_open_tasks,6)),0) from public.org_agents a
                   where a.active and coalesce(a.available,true) and a.department = t.dept_key) as capacity
            from public.org_tasks t
           where t.assigned_agent is null and t.status in ('assigned','in_progress')
           group by t.dept_key
          having count(*) > 0
           order by count(*) desc
           limit 6) x;

  -- an unowned task carries its reason on the row: every eligible colleague is at max_open_tasks
  update public.org_tasks t
     set result = coalesce(t.result,'{}'::jsonb) || jsonb_build_object(
           'waiting', jsonb_build_object('at', now(), 'by', 'fn_org_task_assign',
             'reason', 'unowned: every eligible colleague in ' || t.dept_key || ' is at max_open_tasks; '
                    || 'it is assigned and promoted onto the spine as capacity frees (hourly)'))
   where t.assigned_agent is null and t.status in ('assigned','in_progress')
     and not (coalesce(t.result,'{}'::jsonb) ? 'waiting');

  begin
    v_promote := public.fn_org_task_promote();
  exception when others then
    v_promote := jsonb_build_object('error', sqlerrm);
  end;

  insert into public.agent_runs (agent, started_at, finished_at, status, counts, note)
  values ('org_task_assign', now(), now(), 'ok',
          jsonb_build_object('considered', v_considered, 'assigned', v_assigned,
                             'released_from_unreviewable_head', v_released,
                             'left_unowned', v_no_capacity, 'oversubscribed', coalesce(v_saturated,'none'),
                             'promoted_to_spine', v_promote),
          'Assigned '||v_assigned||' of '||v_considered||' unowned open task(s) to the currently '
          ||'least-loaded named colleague in the owning department, spreading within the department, '
          ||'skipping independent reviewers for non-review work and never a head nobody can review ('
          ||v_released||' released from one). '||v_no_capacity||' left unowned '
          ||'only where every eligible colleague was already at max_open_tasks - deliberate: an '
          ||'unowned task is visible, an overloaded one is not. Departments still carrying more open '
          ||'work than they staff (unowned/capacity): '||coalesce(v_saturated,'none')||'. Promoted onto '
          ||'the workflow spine: '||coalesce(v_promote::text,'{}')||'.');

  return jsonb_build_object('considered', v_considered, 'assigned', v_assigned,
                            'released_from_unreviewable_head', v_released,
                            'left_unowned', v_no_capacity, 'oversubscribed', coalesce(v_saturated,'none'),
                            'promoted_to_spine', v_promote);
end
$function$;

commit;
