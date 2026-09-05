-- A CLOSE IS 'DETERMINED' ONLY WHEN ITS EXECUTOR RAN (5 Sep 2026).
--
-- The adversarial audit of PR #513 measured that the two review_queue rows labelled 'determined' had
-- executed nothing (executor withheld: notifies_human) and that 0 of 33 applier closes invoked an
-- executor -- the 48 succeeded executions in the window belonged to fn_workflow_step_sweep. The word
-- was a routing outcome ("not model-routed") dressed as an execution outcome. It is earned now: a
-- close is 'determined' only when the action_execution it created succeeded; facts bound and a
-- deliverable rendered with no executor run is 'rendered'. advisory_held_model and needs_narrative
-- are unchanged. Every other line is the live definition.
--
--   node scripts/apply_sql.mjs scripts/sql/a_close_is_determined_only_when_its_executor_ran.sql --apply --ddl
CREATE OR REPLACE FUNCTION public.fn_workflow_step_deterministic_done(p_step_run_id bigint, p_output jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  sr           record;
  v_sim        numeric;
  v_floor      numeric := 0.85;
  v_terms      int;
  v_employee   text;
  v_dept       text;
  v_trace      uuid;
  v_review     bigint;
  v_superseded int := 0;
  v_res        text;
  v_out        jsonb;
  -- the record applied
  v_pb_id text; v_pb_title text; v_pb_type text; v_pb_content text; v_pb_sd jsonb;
  -- facts + rendering
  v_facts jsonb; v_bound int; v_deliv text; v_outcome text;
  -- executor
  ex record; v_has_ex boolean := false; v_needs_model boolean := false; v_exec_status text; v_exec_id uuid;
  v_exec_result jsonb; v_req_args int; v_kind text := null; v_source text := 'playbook_rendered';
  v_queued boolean := false; v_refused text; v_err text; v_target text;
  -- measurement
  v_llm int := 0; v_cost int := 0; v_used_llm boolean;
  v_disp text; v_mode text;
begin
  select s.id, s.workflow_run_id, s.step_no, s.actor, s.action_class, s.input, s.attempts, s.started_at, s.output as prev_output,
         r.workflow_key, r.context, r.correlation_id, r.trigger_event_id
    into sr
    from public.workflow_step_run s
    join public.workflow_run r on r.id = s.workflow_run_id
   where s.id = p_step_run_id and s.status = 'running' and s.finished_at is null;
  if not found then
    return jsonb_build_object('ok', false, 'reason', 'step is not held running by a dispatcher');
  end if;

  v_sim      := nullif(p_output->>'similarity', '')::numeric;
  v_terms    := nullif(p_output->>'terms_matched', '')::int;
  v_employee := coalesce(nullif(p_output->>'employee',''), sr.actor);

  -- FALSE-SUCCESS GUARDS. Nothing below runs unless the determination has substance. The floors are the
  -- applier's own (0.85 cosine AND keyword corroboration), so a caller cannot pass on cosine alone.
  if coalesce(p_output->>'playbook_record_id','') = '' then
    return jsonb_build_object('ok', false, 'reason', 'no playbook_record_id: a determination must cite the company knowledge it applied');
  end if;
  if v_sim is null or v_sim < v_floor then
    return jsonb_build_object('ok', false, 'reason', 'similarity ' || coalesce(v_sim::text,'null') || ' is below the apply floor ' || v_floor);
  end if;
  if v_terms is null or v_terms < 2 then
    return jsonb_build_object('ok', false, 'reason', 'terms_matched ' || coalesce(v_terms::text,'null') || ' is below the corroboration floor of 2 step terms');
  end if;
  select k.record_id, k.title, k.record_type, k.content, k.structured_data
    into v_pb_id, v_pb_title, v_pb_type, v_pb_content, v_pb_sd
    from public.ops_knowledge k
   where k.record_id = p_output->>'playbook_record_id' and k.runtime_eligible;
  if v_pb_id is null then
    return jsonb_build_object('ok', false, 'reason', 'playbook ' || (p_output->>'playbook_record_id') || ' is not a runtime-eligible ops_knowledge record');
  end if;
  if v_pb_type not in ('decision_playbook','decision_rule','standard_operating_procedure','exception_playbook') then
    return jsonb_build_object('ok', false, 'reason', 'record ' || v_pb_id || ' is a ' || v_pb_type || ', not an actionable kind');
  end if;

  -- THE FACTS, then the deliverable AS A FUNCTION OF THEM.
  v_facts := public.fn_workflow_step_facts(sr.id);
  v_bound := coalesce((v_facts->>'facts_bound')::int, 0);

  -- THE EXECUTOR. Read the registry row and decide from it, in words.
  select e.action_class, e.kind, e.target, e.active, e.risk_tier, e.advisory_safe, e.reversible,
         e.notifies_human, e.unattended_ok, e.required_authority, e.compensation_action_class
    into ex
    from public.org_action_executor e
   where e.action_class = sr.action_class and e.active
   order by e.kind limit 1;
  v_has_ex := found;
  if v_has_ex then v_target := ex.target; end if;
  if not v_has_ex then
    v_exec_status := 'none: no active executor is mapped to action_class ' || coalesce(sr.action_class, '(null)');
  else
    v_kind := ex.kind;
    v_needs_model := public.fn_executor_needs_model(ex.target);
    if v_needs_model then
      v_exec_status := 'held: ' || ex.target || ' is routed to a model task class by fn_task_class and the paid provider is held; not invoked';
    elsif coalesce(ex.required_authority, '') = 'founder' then
      v_exec_status := 'withheld: ' || ex.target || ' is reserved to the founder';
    elsif ex.notifies_human then
      v_exec_status := 'withheld: ' || ex.target || ' notifies a human (org_action_executor.notifies_human); the deterministic close never sends';
    elsif not (ex.risk_tier = 'low' and ex.advisory_safe and ex.reversible) then
      v_exec_status := format('withheld: %s is risk_tier=%s advisory_safe=%s reversible=%s; the close invokes low/advisory_safe/reversible only',
                              ex.target, ex.risk_tier, ex.advisory_safe, ex.reversible);
    elsif ex.kind not in ('rpc', 'edge') then
      v_exec_status := 'withheld: ' || ex.target || ' is a ' || ex.kind || ' executor and no invoker handles that kind';
    elsif exists (select 1 from public.action_execution x where x.workflow_step_run_id = sr.id and x.status in ('queued','running')) then
      return jsonb_build_object('ok', false, 'reason', 'executor ' || ex.target || ' is already queued or running for this step; the sweep settles it');
    elsif ex.kind = 'rpc' then
      select coalesce(p.pronargs - p.pronargdefaults, -1) into v_req_args
        from pg_proc p where p.proname = ex.target and p.pronamespace = 'public'::regnamespace
       order by p.pronargs limit 1;
      if v_req_args is null then
        v_exec_status := 'failed: public.' || ex.target || '() does not exist';
      elsif v_req_args > 0 then
        v_exec_status := 'withheld: public.' || ex.target || '() requires ' || v_req_args || ' argument(s) a workflow step cannot supply';
      else
        v_exec_id := gen_random_uuid();
        begin
          execute format('select coalesce(jsonb_agg(to_jsonb(t)), ''[]''::jsonb) from public.%I() t', ex.target) into v_exec_result;
          insert into public.action_execution(id, correlation_id, workflow_step_run_id, action_class, executor, idempotency_key,
                                              risk_tier, reversible, request, response, status, attempts, started_at, finished_at)
          values (v_exec_id, coalesce(sr.correlation_id, gen_random_uuid()), sr.id, sr.action_class, ex.target,
                  'workflow_step:' || sr.id || ':det:' || to_char(now(), 'YYYYMMDDHH24MISSMS'),
                  ex.risk_tier, ex.reversible,
                  jsonb_build_object('workflow_step_run_id', sr.id, 'workflow_run_id', sr.workflow_run_id, 'step_no', sr.step_no,
                                     'actor', sr.actor, 'source', 'fn_workflow_step_deterministic_done', 'kind', 'rpc'),
                  jsonb_build_object('invoker', 'succeeded', 'at', now(), 'kind', 'rpc', 'inline', true,
                                     'result_rows', coalesce(jsonb_array_length(v_exec_result), 0),
                                     'result', case when pg_column_size(v_exec_result) > 20000 then to_jsonb(left(v_exec_result::text, 20000)) else v_exec_result end),
                  'succeeded', 1, now(), now());
          v_exec_status := 'ran: public.' || ex.target || '() inline, ' || coalesce(jsonb_array_length(v_exec_result), 0)
                           || ' row(s), action_execution ' || v_exec_id;
          v_source := 'executor:' || ex.target;
        exception when others then
          v_err := sqlstate || ' ' || left(sqlerrm, 400);
          -- the failure is a fact: record it and refuse the close, so the step is released with the reason
          insert into public.action_execution(id, correlation_id, workflow_step_run_id, action_class, executor, idempotency_key,
                                              risk_tier, reversible, request, response, status, attempts, started_at, finished_at)
          values (v_exec_id, coalesce(sr.correlation_id, gen_random_uuid()), sr.id, sr.action_class, ex.target,
                  'workflow_step:' || sr.id || ':det:' || to_char(now(), 'YYYYMMDDHH24MISSMS'),
                  ex.risk_tier, ex.reversible,
                  jsonb_build_object('workflow_step_run_id', sr.id, 'workflow_run_id', sr.workflow_run_id, 'step_no', sr.step_no,
                                     'actor', sr.actor, 'source', 'fn_workflow_step_deterministic_done', 'kind', 'rpc'),
                  jsonb_build_object('invoker', 'failed', 'at', now(), 'kind', 'rpc', 'inline', true, 'error', v_err),
                  'failed', 1, now(), now());
          return jsonb_build_object('ok', false, 'reason', 'executor public.' || ex.target || '() failed: ' || v_err,
                                    'action_execution_id', v_exec_id);
        end;
      end if;
    else -- edge, deterministic
      select x.response->>'reason' into v_refused
        from public.action_execution x
       where x.workflow_step_run_id = sr.id and x.response->>'invoker' = 'refused'
       order by x.created_at desc limit 1;
      if v_refused is not null then
        v_exec_status := 'withheld: the invoker refused ' || ex.target || ' for this step earlier (' || left(v_refused, 200) || '); not re-queued';
      elsif exists (select 1 from public.action_execution x
                     where x.workflow_step_run_id = sr.id and x.request->>'source' = 'fn_workflow_step_deterministic_done') then
        select 'withheld: an earlier re-queue of ' || ex.target || ' for this step ended ' || x.status into v_exec_status
          from public.action_execution x
         where x.workflow_step_run_id = sr.id and x.request->>'source' = 'fn_workflow_step_deterministic_done'
         order by x.created_at desc limit 1;
      else
        v_exec_id := gen_random_uuid();
        insert into public.action_execution(id, correlation_id, workflow_step_run_id, action_class, executor, idempotency_key,
                                            risk_tier, reversible, request, status, attempts)
        values (v_exec_id, coalesce(sr.correlation_id, gen_random_uuid()), sr.id, sr.action_class, ex.target,
                'workflow_step:' || sr.id || ':det:' || to_char(now(), 'YYYYMMDDHH24MISSMS'),
                ex.risk_tier, ex.reversible,
                jsonb_build_object('workflow_step_run_id', sr.id, 'workflow_run_id', sr.workflow_run_id, 'step_no', sr.step_no,
                                   'actor', sr.actor, 'input', coalesce(sr.input, '{}'::jsonb),
                                   'source', 'fn_workflow_step_deterministic_done', 'kind', 'edge'),
                'queued', 0);
        v_queued := true;
        v_exec_status := 'queued: ' || ex.target || ' as action_execution ' || v_exec_id || ' for the HTTP invoker; the step closes when the sweep settles it';
        v_source := 'executor:' || ex.target;
      end if;
    end if;
  end if;

  -- THE DELIVERABLE, rendered from the facts, with the executor line.
  v_deliv := public.fn_workflow_step_render(v_facts, v_pb_title, v_pb_type, v_pb_content, v_pb_sd);
  v_deliv := regexp_replace(v_deliv, E'\nAPPLIED RECORD: ',
               E'- executor: ' || coalesce(v_exec_status, '?') || E'\n\nAPPLIED RECORD: ');

  -- THE DISPOSITION, earned.
  -- 5 SEP 2026, from the skeptic that audited this routine: 'determined' used to mean "not routed
  -- to a model", and both rows that carried it had executed nothing (executor withheld). A label
  -- that reads as 'executed' must be EARNED by an execution: an action_execution this close created
  -- and which succeeded. Facts bound and rendered, but no executor ran (none mapped, withheld,
  -- queued for the HTTP invoker, refused) is 'rendered' -- true, and not the same word as done.
  v_disp := case when v_bound = 0 then 'needs_narrative'
                 when v_needs_model then 'advisory_held_model'
                 when v_exec_id is not null and exists (select 1 from public.action_execution x
                        where x.id = v_exec_id and x.status = 'succeeded') then 'determined'
                 else 'rendered' end;
  v_mode := case when v_disp = 'determined' then 'determined' else 'advisory' end;
  v_outcome := case when v_disp = 'needs_narrative'
                    then 'No fact was bound for this step (no metric, goal, event payload or prior conclusion); the record "'
                         || v_pb_title || '" applies as written and the step needs narrative from a reviewer or the model path.'
                    else coalesce(nullif(v_facts#>>'{derived,band}', '') || ' ' || coalesce(v_facts#>>'{metric,label}', '') || ': ', '')
                         || 'applied ' || v_pb_type || ' "' || v_pb_title || '" to ' || v_bound || ' bound fact(s)'
                         || case when v_facts#>>'{derived,cause}' is not null then '; cause ' || (v_facts#>>'{derived,cause}') else '' end
                         || '; executor ' || split_part(coalesce(v_exec_status, 'none'), ':', 1) end;

  -- used_llm IS A MEASUREMENT: the provider ledgers since the dispatcher claimed this step.
  select count(*) into v_llm  from public.llm_attempt a where a.fn = 'workflow_dispatch' and a.created_at >= sr.started_at;
  select count(*) into v_cost from public.ai_cost_log c where c.fn = 'workflow_dispatch' and c.occurred_at >= sr.started_at;
  v_used_llm := (v_llm + v_cost) > 0;

  select o.department into v_dept from public.org_agents o where o.agent_key = v_employee;

  -- The sealed record of what was decided, on what, by which rule, with what confidence.
  insert into public.decision_trace(
      correlation_id, causation_event_id, entity_type, entity_id, decision_type,
      proposed_by, decided_by, policy_keys, knowledge_refs, evidence_refs, alternatives,
      assumptions, risk, confidence, authority_result,
      decision, outcome_status, agent_key, department_id, task_class,
      knowledge_versions, source_freshness, tools_requested, tools_executed, tool_result_refs,
      uncertainty, escalation_decision, proposed_action, expected_outcome,
      model, provider, input_tokens, output_tokens, estimated_cost_aed, final_status, sealed_at)
  values (
      coalesce(sr.correlation_id, gen_random_uuid()), sr.trigger_event_id,
      'workflow_step_run', sr.id::text, 'deterministic_playbook_application',
      v_employee, 'fn_workflow_step_deterministic_done', array['deterministic_first']::text[],
      jsonb_build_array(jsonb_build_object('record_id', v_pb_id, 'title', v_pb_title, 'record_type', v_pb_type,
                                           'similarity', v_sim, 'terms_matched', v_terms)),
      jsonb_build_array(jsonb_build_object('workflow_run_id', sr.workflow_run_id, 'workflow_key', sr.workflow_key,
                                           'step_no', sr.step_no, 'step', sr.input->>'step',
                                           'facts', v_facts)),
      coalesce(p_output->'candidates', '[]'::jsonb),
      jsonb_build_array('the corroborated nearest actionable company record is the applicable one for this step',
                        'the facts read at close time are the facts the step is about'),
      jsonb_build_object('level', 'low', 'note', case when v_source like 'executor:%'
                                                      then 'a low-risk, advisory-safe, reversible executor was invoked; moves no money, sends nothing, approves nobody'
                                                      else 'determination only; moves no money, sends nothing, approves nobody' end),
      v_sim,
      jsonb_build_object('mode', v_mode, 'gate', coalesce(sr.input->>'gate', 'none'), 'paid_provider', 'held', 'executor', v_exec_status),
      jsonb_build_object('determination', left(v_deliv, 8000), 'outcome', v_outcome, 'disposition', v_disp,
                         'determination_source', v_source, 'basis', 'facts of the step rendered against the corroborated record; no model call'),
      'pending', v_employee, v_dept, 'workflow_step',
      '{}'::jsonb, jsonb_build_object('ops_knowledge', 'live at decision time', 'facts_read_at', v_facts->>'read_at'),
      case when v_target is not null then array[v_target] else '{}'::text[] end,
      case when v_source like 'executor:%' then array[v_target] else '{}'::text[] end,
      case when v_exec_id is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('action_execution_id', v_exec_id)) end,
      case v_disp when 'determined' then 'determined from ' || v_bound || ' bound fact(s); queued for review'
                  when 'advisory_held_model' then 'determined from ' || v_bound || ' bound fact(s), but the step''s executor needs the held model; advisory until the hold lifts'
                  else 'no fact bound: the record applies as written; narrative is needed' end,
      'review_queued', 'close the workflow step with disposition ' || v_disp,
      'the run advances; a reviewer can overturn the determination',
      'none', 'deterministic', 0, 0, 0, 'auto_done', now())
  returning id into v_trace;

  -- Never a silent pass: the determination is queued for review, with everything needed to overturn it.
  insert into public.review_queue(kind, dept_key, title, summary, payload, status)
  values ('deterministic_step', v_dept,
          left(initcap(replace(v_disp, '_', ' ')) || ': ' || sr.workflow_key || ' step ' || sr.step_no || ' — ' || coalesce(sr.input->>'step',''), 240),
          left(v_outcome, 600),
          jsonb_build_object('workflow_run_id', sr.workflow_run_id, 'step_run_id', sr.id, 'step_no', sr.step_no,
                             'employee', v_employee, 'playbook_record_id', v_pb_id,
                             'playbook_title', v_pb_title, 'similarity', v_sim, 'terms_matched', v_terms,
                             'decision_trace_id', v_trace, 'disposition', v_disp,
                             'determination_source', v_source, 'executor_status', v_exec_status,
                             'facts_bound', v_bound, 'used_llm', v_used_llm),
          'pending')
  returning id into v_review;

  -- The executor's parked/stranded attempt is superseded: fn_action_release_held must not re-run it at
  -- launch over a step that is already closed.
  update public.action_execution
     set status = 'cancelled', finished_at = coalesce(finished_at, now()),
         response = coalesce(response,'{}'::jsonb) || jsonb_build_object(
           'superseded_at', now(), 'superseded_by', 'deterministic determination',
           'decision_trace_id', v_trace, 'prior_status', status)
   where workflow_step_run_id = sr.id and status in ('held','stalled');
  get diagnostics v_superseded = row_count;

  v_out := coalesce(p_output, '{}'::jsonb) || jsonb_build_object(
             'mode', v_mode,
             'deliverable', left(v_deliv, 20000),
             'outcome', left(v_outcome, 400),
             'disposition', v_disp,
             'determination_source', v_source,
             'executor_status', v_exec_status,
             'executor_kind', v_kind,
             'action_execution_id', v_exec_id,
             'facts_bound', v_bound,
             'facts', v_facts,
             'used_llm', v_used_llm,
             'used_llm_basis', 'measured at close: ' || v_llm || ' llm_attempt + ' || v_cost
                               || ' ai_cost_log row(s) by workflow_dispatch since the step was claimed at ' || sr.started_at,
             'decision_trace_id', v_trace,
             'review_queue_id', v_review,
             'review_status', 'pending',
             'superseded_executions', v_superseded);

  if v_queued then
    -- the step stays running with a queued execution; fn_workflow_step_sweep settles it when the
    -- executor answers, merging the response over this determination
    update public.workflow_step_run set output = v_out where id = sr.id;
    return jsonb_build_object('ok', true, 'advanced', 'awaiting executor ' || v_target, 'decision_trace_id', v_trace,
                              'review_queue_id', v_review, 'superseded_executions', v_superseded,
                              'disposition', v_disp, 'determination_source', v_source,
                              'executor_status', v_exec_status, 'action_execution_id', v_exec_id,
                              'facts_bound', v_bound, 'used_llm', v_used_llm);
  end if;

  v_res := public.fn_workflow_step_done(sr.workflow_run_id, sr.step_no, v_out, 'done');

  return jsonb_build_object('ok', true, 'advanced', v_res, 'decision_trace_id', v_trace,
                            'review_queue_id', v_review, 'superseded_executions', v_superseded,
                            'disposition', v_disp, 'determination_source', v_source,
                            'executor_status', v_exec_status, 'action_execution_id', v_exec_id,
                            'facts_bound', v_bound, 'used_llm', v_used_llm);
end
$function$
