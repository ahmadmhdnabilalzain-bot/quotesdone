-- THE `exec_review` ACTION CLASS IS AN APPROVAL-TIER RESOLUTION, NOT A PROMPT (MASTER_PLAN §5.3, 5 Sep 2026).
--
-- MEASURED before this file: 3 workflow steps carry action_class 'exec_review' (improvement_lifecycle
-- #4 "Approve within authority or escalate", #11 "AI-side sign-off", strategic_review #4 "Decide and
-- record rationale"), all routed to the edge executor exec_agents, which imports _shared/llm.ts. With
-- the model held, 9 exec_review steps closed advisory on 4 Sep with 'executor runs on the held paid
-- model; not queued' and strategic_review failed at step 4 six times. The plan's seventh category,
-- "approval-tier resolvers - inline authority decisions", is exactly this step, and the authority
-- facts already live in tables: org_role.authority_level for the deciding officer, fn_dept_authority
-- (org_authority + hard gates + reputation cap) for the department, decision_policy thresholds
-- through fn_should_escalate for money/fraud/confidence, and the run's own prior steps as evidence.
--
-- CONTRACT with fn_action_invoke_rpc: zero required arguments; self-locates its queued
-- action_execution row the same way fn_recommend_deterministic does (see that file's header).
--
-- FOUR RETURN SHAPES:
--   'approved_within_authority' -> rationale.evidence lists the prior steps read, rationale.authority
--                                  the officer tier and department tier that cover it;
--   'escalate'                  -> rationale.reasons is a non-empty array (fn_should_escalate,
--                                  founder gate, or the officer's tier below the department's need);
--   'nothing_to_review'         -> the run has no completed prior step with a deliverable, so there
--                                  is no evidence to approve; rationale.evidence is an empty array;
--   'no_scope'                  -> the caller resolves to no active employee.
-- An escalation names its addressee (the officer's manager, or the founder only for refunds /
-- money above the autonomous limit) and the reason, so the record is the rationale.

create or replace function public.fn_exec_review_deterministic(p_step_run_id bigint default null)
returns table(
  determination text, employee text, department text, workflow_key text, step_no integer, step text,
  outcome text, deliverable text, inputs jsonb, rationale jsonb, used_llm boolean)
language plpgsql security definer set search_path to 'public', 'pg_temp' as $$
declare
  v_sid bigint := p_step_run_id; v_located text := 'p_step_run_id';
  v_actor text; v_employee text; v_dept text; v_wf text; v_wfname text; v_step_no int; v_step text; v_run uuid; v_ctx jsonb := '{}'::jsonb; v_gate text;
  v_prior jsonb; v_prior_n int := 0; v_prior_with_deliv int := 0; v_failed int := 0;
  v_role text; v_officer_tier text; v_manager text;
  v_dept_auth jsonb; v_dept_tier text;
  v_amount numeric; v_esc jsonb; v_reasons jsonb := '[]'::jsonb;
  v_text text; v_evidence text; v_addressee text;
begin
  used_llm := false;
  if v_sid is null then
    select x.workflow_step_run_id, x.request->>'actor' into v_sid, v_actor
      from public.action_execution x
      join public.org_action_executor e on e.action_class = x.action_class and e.kind = 'rpc'
     where x.action_class = 'exec_review' and x.status = 'queued'
     order by x.created_at limit 1;
    v_located := case when v_sid is not null then 'action_execution.workflow_step_run_id'
                      when v_actor is not null then 'action_execution.request.actor' else 'nothing queued' end;
  end if;
  if v_sid is not null then
    select s.actor, s.step_no, s.input->>'step', s.input->>'gate', s.workflow_run_id, r.workflow_key, coalesce(r.context,'{}'::jsonb), w.name
      into v_actor, v_step_no, v_step, v_gate, v_run, v_wf, v_ctx, v_wfname
      from public.workflow_step_run s join public.workflow_run r on r.id = s.workflow_run_id
      left join public.workflow w on w.workflow_key = r.workflow_key
     where s.id = v_sid;
    v_employee := public.fn_workflow_actor_resolve(v_run, v_actor);
  elsif v_actor is not null then
    v_employee := public.fn_org_agent_resolve(v_actor);
  end if;
  select o.department, o.manager_key into v_dept, v_manager from public.org_agents o where o.agent_key = v_employee and o.active;
  employee := v_employee; department := v_dept; workflow_key := v_wf; step_no := v_step_no; step := v_step;
  if v_dept is null then
    determination := 'no_scope';
    outcome := 'no decision: the caller resolves to no active employee, so nobody holds the authority being asked for';
    deliverable := outcome;
    inputs := jsonb_build_object('located_by', v_located, 'step_run_id', v_sid, 'actor', v_actor, 'employee', v_employee);
    rationale := null; return next; return;
  end if;

  -- 1. THE EVIDENCE: what the run's earlier steps produced.
  select coalesce(jsonb_agg(jsonb_build_object('step_no', p.step_no, 'step', p.input->>'step', 'status', p.status,
           'by', coalesce(p.output->>'employee', p.actor), 'worked_by', p.output->>'worked_by',
           'outcome', left(coalesce(p.output->>'outcome', p.output->>'note', p.output#>>'{result,0,outcome}', ''), 400),
           'has_deliverable', coalesce(p.output->>'deliverable', p.output#>>'{result,0,deliverable}', '') <> '',
           'used_llm', p.output->>'used_llm') order by p.step_no), '[]'::jsonb),
         count(*) filter (where p.status = 'done'),
         count(*) filter (where p.status = 'done' and coalesce(p.output->>'deliverable', p.output#>>'{result,0,deliverable}', p.output->>'outcome', '') <> ''),
         count(*) filter (where p.status = 'failed')
    into v_prior, v_prior_n, v_prior_with_deliv, v_failed
    from public.workflow_step_run p
   where v_run is not null and p.workflow_run_id = v_run and p.step_no < coalesce(v_step_no, 0) and p.status in ('done','failed');

  -- 2. THE AUTHORITY: the officer's own tier, and the department's tier for this class.
  select r.role_id, r.authority_level into v_role, v_officer_tier
    from public.org_role r where r.runtime_agent_key = v_employee and r.status = 'active'
   order by case r.authority_level when 'execute_high' then 0 when 'execute_medium' then 1 when 'execute_low' then 2 else 3 end limit 1;
  v_dept_auth := public.fn_dept_authority(v_dept, 'exec_review', null);
  v_dept_tier := v_dept_auth->>'tier';

  -- 3. THE MONEY AND RISK CHECK from the run context and prior outputs, through decision_policy.
  v_amount := coalesce(nullif(v_ctx->>'amount_aed','')::numeric,
                       (select max(nullif(p->>'amount_aed','')::numeric) from jsonb_array_elements(v_prior) p));
  v_esc := public.fn_should_escalate(jsonb_build_object(
             'actor', v_employee, 'kind', 'exec_review', 'amount_aed', v_amount,
             'moves_money', coalesce((v_ctx->>'moves_money')::boolean, v_wf in ('refund','payment')),
             'category', v_ctx->>'category', 'text', coalesce(v_ctx->>'title', ''),
             'confidence', nullif(v_ctx->>'confidence','')::numeric));
  if coalesce((v_esc->>'escalate')::boolean, false) then v_reasons := coalesce(v_esc->'reasons', '[]'::jsonb); end if;
  if coalesce(v_gate,'') = 'founder' or v_wf = 'refund' then
    v_reasons := v_reasons || jsonb_build_array('the step is founder-gated: refunds and founder boundaries are never approved by an officer');
  end if;
  if v_officer_tier is null then
    v_reasons := v_reasons || jsonb_build_array(format('%s holds no active org_role with an authority_level, so it cannot sign off; its manager %s must', v_employee, coalesce(v_manager, '(none)')));
  elsif v_officer_tier = 'execute_low' and v_dept_tier in ('gated','advisory') then
    v_reasons := v_reasons || jsonb_build_array(format('%s is execute_low and the department tier for exec_review is %s (%s)', v_employee, v_dept_tier, v_dept_auth->>'reason'));
  end if;
  if v_failed > 0 then
    v_reasons := v_reasons || jsonb_build_array(format('%s prior step(s) of this run failed; nothing built on a failed step is approved', v_failed));
  end if;

  inputs := jsonb_build_object('located_by', v_located, 'step_run_id', v_sid, 'actor', v_actor, 'employee', v_employee, 'department', v_dept,
    'gate', v_gate, 'prior_steps_done', v_prior_n, 'prior_steps_with_deliverable', v_prior_with_deliv, 'prior_steps_failed', v_failed,
    'officer_role', v_role, 'officer_tier', v_officer_tier, 'manager', v_manager, 'department_authority', v_dept_auth,
    'amount_aed', v_amount, 'should_escalate', v_esc, 'run_context', v_ctx - 'at' - 'ref' - 'functions', 'measured_at', now());

  v_evidence := coalesce((select string_agg(format('step %s "%s" %s by %s: %s', p->>'step_no', p->>'step', p->>'status', p->>'by', coalesce(nullif(p->>'outcome',''), '(no stated outcome)')), E'\n' order by (p->>'step_no')::int) from jsonb_array_elements(v_prior) p), '(no prior steps)');

  if v_prior_with_deliv = 0 and v_failed = 0 then
    determination := 'nothing_to_review';
    outcome := format('nothing to approve: %s prior step(s) done in this run and none carries a deliverable or outcome', v_prior_n);
    rationale := jsonb_build_object('evidence', '[]'::jsonb, 'authority', jsonb_build_object('officer_tier', v_officer_tier, 'department_tier', v_dept_tier));
    deliverable := format(E'EXEC REVIEW: NOTHING TO REVIEW\nWorkflow %s step %s (%s), officer %s (%s, %s) for %s.\n%s\nA sign-off needs evidence; the run reached this step with none. Basis: workflow_step_run outputs of this run, org_role.authority_level, fn_dept_authority. No model call.',
                          coalesce(v_wfname, v_wf), v_step_no, v_step, v_employee, coalesce(v_role,'no role'), coalesce(v_officer_tier,'no tier'), v_dept, outcome);
    return next; return;
  end if;

  if jsonb_array_length(v_reasons) > 0 then
    determination := 'escalate';
    v_addressee := case when coalesce(v_gate,'') = 'founder' or v_wf = 'refund' then 'founder'
                        when nullif(v_esc->>'route_to','') is not null then v_esc->>'route_to' else coalesce(v_manager, 'ceo') end;
    outcome := left(format('escalated to %s: %s', v_addressee, (select string_agg(x #>> '{}', '; ') from jsonb_array_elements(v_reasons) x)), 600);
    rationale := jsonb_build_object('reasons', v_reasons, 'addressee', v_addressee, 'evidence', v_prior,
                   'authority', jsonb_build_object('officer_role', v_role, 'officer_tier', v_officer_tier, 'department_tier', v_dept_tier, 'department_basis', v_dept_auth->>'reason'));
    deliverable := format(E'EXEC REVIEW: ESCALATE to %s\nWorkflow %s step %s (%s), officer %s (%s, %s) for %s.\nEvidence read (%s done, %s with a deliverable, %s failed):\n%s\nReasons:\n%s\nAuthority: officer %s; department tier for exec_review %s (%s).\nBasis: fn_should_escalate over decision_policy (confidence_min, financial_review_aed, auto_action_max_aed, fraud_score_max), org_role.authority_level, fn_dept_authority, the step gate. No model call.',
                          v_addressee, coalesce(v_wfname, v_wf), v_step_no, v_step, v_employee, coalesce(v_role,'no role'), coalesce(v_officer_tier,'no tier'), v_dept,
                          v_prior_n, v_prior_with_deliv, v_failed, v_evidence,
                          (select string_agg('- ' || (x #>> '{}'), E'\n') from jsonb_array_elements(v_reasons) x),
                          coalesce(v_officer_tier,'none'), coalesce(v_dept_tier,'unknown'), coalesce(v_dept_auth->>'reason',''));
    return next; return;
  end if;

  determination := 'approved_within_authority';
  outcome := left(format('approved by %s (%s, %s): %s prior step(s) with deliverables reviewed, no money above the autonomous limit, department tier %s',
                         v_employee, coalesce(v_role, 'no role'), v_officer_tier, v_prior_with_deliv, v_dept_tier), 600);
  rationale := jsonb_build_object('evidence', v_prior, 'addressee', null,
                 'authority', jsonb_build_object('officer_role', v_role, 'officer_tier', v_officer_tier, 'department_tier', v_dept_tier, 'department_basis', v_dept_auth->>'reason'),
                 'checks', jsonb_build_object('should_escalate', v_esc, 'amount_aed', v_amount, 'gate', v_gate));
  deliverable := format(E'EXEC REVIEW: APPROVED WITHIN AUTHORITY\nWorkflow %s step %s (%s), officer %s (%s, %s) for %s.\nEvidence read (%s done, %s with a deliverable, %s failed):\n%s\nChecks: amount %s AED against decision_policy; fn_should_escalate returned escalate=%s; gate %s; officer tier %s covers department tier %s (%s).\nDecision: the prior steps stand; the run advances. Basis: workflow_step_run outputs of this run, org_role.authority_level, fn_dept_authority, fn_should_escalate. No model call.',
                        coalesce(v_wfname, v_wf), v_step_no, v_step, v_employee, coalesce(v_role,'no role'), v_officer_tier, v_dept,
                        v_prior_n, v_prior_with_deliv, v_failed, v_evidence,
                        coalesce(v_amount::text, 'none stated'), coalesce(v_esc->>'escalate','false'), coalesce(v_gate,'none'), v_officer_tier, coalesce(v_dept_tier,'unknown'), coalesce(v_dept_auth->>'reason',''));
  return next;
end $$;

revoke execute on function public.fn_exec_review_deterministic(bigint) from public;
revoke execute on function public.fn_exec_review_deterministic(bigint) from anon;
grant execute on function public.fn_exec_review_deterministic(bigint) to service_role;
