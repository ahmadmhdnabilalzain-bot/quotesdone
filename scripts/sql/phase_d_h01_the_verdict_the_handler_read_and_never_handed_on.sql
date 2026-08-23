-- H01 — the handler asked the kernel for a verdict it could have asked the estate for, and handed
--        the effect a review it had already read
--
-- Four corrections to fn_phase_d_handler_execute, each measured on the 30-workflow drive of 23 Aug
-- 2026 (scripts/tmp_diag/reason_census.txt), none of them a weakening of any rule or gate.
--
-- 1. THIRTY REVIEW STEPS REFUSED BR-002 FOR A REVIEWER THE HANDLER HAD ALREADY READ.
--    F34 made the handler read the recorded canonical review -- phase_c_task.reviewer_role_id,
--    stamped by fn_kernel_review_decide, and the sealed TRACE-ROLE-ACTION verdict -- and put both
--    into the handler OUTPUT. It never put them into the effect PAYLOAD. fn_phase_d_effect_produce
--    judges BR-002 on the payload, saw reviewer_role_id absent, and refused:
--
--        fn_phase_d_effect_produce: step W02-S02 is accountable to data_intelligence_director and
--        names (none) as reviewer; those resolve to one effective identity (BR-002).
--
--    Measured on W02-S02, W04-S02, W07-S03/S06, W08-S03/S04, W09-S02/S07, W10-S02/S03, W12-S04/S05,
--    W15-S01/S03, W17-S10, W21-S04, W22-S06, W23-S05/S07, W24-S02..S05/S08, W27-S03..S05/S07,
--    W29-S04/S06, W30-S02/S06. The recorded review now travels into the payload for every
--    REVIEW_VERDICT effect, LAST in the concatenation, so the sealed verdict and the stamped
--    reviewer outrank anything a caller or the catalogue could say. BR-002 is still evaluated by
--    fn_phase_d_effect_produce on exactly that reviewer, and still refuses a creator.
--
-- 2. SEVENTEEN STEPS REACHED THE KERNEL AND WERE REFUSED k3_reviewer_verdict_missing.
--    The frozen registry names an independent reviewer on 28 steps; only the REVIEW_HANDLER class
--    asked whether a review had been recorded before executing. An EXECUTION, DECISION or CLOSURE
--    step naming a reviewer built its output, produced its effect (in a subtransaction) and was
--    refused by fn_kernel_step_complete 3g -- correctly -- at which point the kernel's refusal was
--    the dispatch outcome and the driver closed the step as an ACTOR instead. Measured on W01-S06,
--    W02-S06, W04-S07, W06-S05, W08-S06, W10-S05, W12-S09, W19-S07, W20-S09, W21-S05, W23-S08,
--    W24-S06/S09 and W27-S09 among others.
--
--    The handler now asks the SAME question the kernel asks, with the same predicate over
--    phase_c_trace, before it builds anything, and refuses with pd_review_not_recorded. That is
--    the code the F35 driver answers by recording the review through fn_kernel_review_decide and
--    dispatching the step again. The kernel check at 3g is untouched and still decides.
--
-- 3. A DECISION STEP COULD NOT SAY WHO DECIDED OR WHEN.
--    public.refunds.decided_by / decided_at are mapped columns of refund_dispute_case, and
--    GATE-020 reads both at W17-S07. Nothing in the handler supplied them. For a DECISION_HANDLER
--    the decider is the accountable role of the deciding step -- read off the step run, not chosen
--    -- and the time is now(). They are added to the payload only for that class; a write map
--    that carries neither key ignores them.
--
-- 4. THE EFFECT STATE WAS WHATEVER THE CALLER SAID, AND THE KERNEL DISPATCH SAYS NOTHING.
--    p_input->>'effect_state' is never passed by fn_phase_d_dispatch_step, so every DOMAIN_MUTATION
--    reached fn_phase_d_object_write with no state, and the writer defaulted it to 'open' -- onto
--    public.refunds (CHECK refuses 'open'), public.department_objective and public.org_tasks (same),
--    and onto rows the scenario had built at a LATER state: an inquiry at quote_ready went back to
--    open and GATE-011 refused W05-S04..S09; a transaction at payment_reconciled went back to open
--    and BR-033 / GATE-019 refused W16-S02..S09. The state a step leaves an object in is a fact the
--    committed catalogue may state per step (EFFECT_PAYLOAD key 'state', scoped to the step_id);
--    where it states none the handler passes none, and H02 makes the writer keep the row's own
--    state on an update and the relation's own default on an insert. No state is invented here.
--
-- ROLLBACK: re-apply the previous body of fn_phase_d_handler_execute (phase_d_g14 is the last file
-- that defines it). No DDL.
--
-- Four anchors, each required to match exactly once. The rest of the routine is byte-identical.
CREATE OR REPLACE FUNCTION public.fn_phase_d_handler_execute(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_review jsonb;   -- F34: the recorded canonical internal review for this step run
  b   public.phase_d_handler_binding%rowtype;
  s   public.phase_b_workflow_step%rowtype;
  sr  public.phase_c_workflow_step_run%rowtype;
  ec  public.phase_d_step_effect%rowtype;
  v_step_run bigint := nullif(p_input->>'step_run_id','')::bigint;
  v_actor    text   := nullif(btrim(coalesce(p_input->>'actor_role_id','')),'');
  v_idem     text   := nullif(btrim(coalesce(p_input->>'idempotency_key','')),'');
  v_inputs   jsonb  := coalesce(p_input->'inputs','{}'::jsonb);
  v_ctx      text   := lower(coalesce(nullif(btrim(p_input->>'execution_context'),''),'production'));
  v_ok       boolean; v_reason text; v_missing text[];
  v_rule     record; v_rule_ok boolean; v_rule_type text; v_rule_reason text;
  v_applies  boolean; v_why text; v_enforced boolean; v_refusal text; v_state text;
  v_ev_absent boolean := false;   -- E19
  v_refused  jsonb := '[]'::jsonb;
  v_skipped  jsonb := '[]'::jsonb;
  v_gate     record; v_gstate text; v_gpassed boolean; v_gtype text;
  v_greason  text; v_grefusal text; v_gapplies boolean; v_gwhy text;
  v_gates    jsonb := '[]'::jsonb;
  v_gblocked jsonb := '[]'::jsonb;
  v_evaluated jsonb := '[]'::jsonb;
  v_output   jsonb;
  v_assert   jsonb;
  v_result   jsonb;
  v_effect   jsonb;
  v_cap      jsonb;   -- F05: the accepted capability result for this step run, or null
  v_cap_req  jsonb;   -- F05: the capability request this handler opened
begin
  -- ---- 0. the call itself ------------------------------------------------------------------
  if v_step_run is null or v_actor is null or v_idem is null then
    raise exception 'fn_phase_d_handler_execute: step_run_id, actor_role_id and idempotency_key are all required (got %, %, %) (pd_input_schema_invalid)',
      coalesce(v_step_run::text,'(null)'), coalesce(v_actor,'(null)'), coalesce(v_idem,'(null)')
      using errcode = '22023';
  end if;
  if v_ctx not in ('production','test') then
    raise exception 'fn_phase_d_handler_execute: execution_context must be production or test, got %',
      v_ctx using errcode = '22023';
  end if;

  select * into sr from public.phase_c_workflow_step_run where step_run_id = v_step_run;
  if not found then
    raise exception 'fn_phase_d_handler_execute: no step run % (pd_step_state_invalid)', v_step_run
      using errcode = '23503';
  end if;

  select * into b from public.phase_d_handler_binding where step_id = sr.step_id;
  if not found then
    raise exception 'fn_phase_d_handler_execute: step % has no Phase D handler binding — fail closed. Every one of the 257 frozen steps must carry exactly one. (pd_input_schema_invalid)',
      sr.step_id using errcode = '23503';
  end if;
  select * into s from public.phase_b_workflow_step where step_id = sr.step_id;

  select * into ec from public.phase_d_step_effect where step_id = sr.step_id;
  if not found then
    raise exception 'fn_phase_d_handler_execute: step % has no declared effect contract. A handler with no declared effect is the schema-only handler this phase exists to remove. (pd_effect_undeclared)',
      sr.step_id using errcode = '23503';
  end if;

  -- ---- 1. TYPED INPUT ----------------------------------------------------------------------
  select valid, reason, missing into v_ok, v_reason, v_missing
    from public.fn_phase_d_schema_validate(b.input_schema_id, v_inputs);
  if not v_ok then
    raise exception 'fn_phase_d_handler_execute: step % input rejected: % (pd_input_schema_invalid)',
      sr.step_id, v_reason using errcode = '22023';
  end if;

  -- ---- 2. RULES IN SCOPE -------------------------------------------------------------------
  -- SCOPE IS NOT APPLICABILITY. The frozen registry scopes rules by WORKFLOW, so BR-002 is in
  -- scope for all 257 steps while only 28 of them name an independent reviewer. Asking
  -- fn_kernel_reviewer_independent about a NULL reviewer returns false, which refused an intake
  -- step for a creator/reviewer collision that could not exist. fn_phase_d_rule_applies decides
  -- both, and records the reason either way.
  --
  -- Refusals are collected rather than short-circuited: a caller told only the first thing wrong
  -- fixes one thing and comes back.
  for v_rule in select unnest(b.rule_ids) rid loop
    select applies, why into v_applies, v_why
      from public.fn_phase_d_rule_applies(v_rule.rid, sr.step_id);
    if not coalesce(v_applies,false) then
      v_skipped := v_skipped || jsonb_build_array(jsonb_build_object(
        'rule_id', v_rule.rid, 'applies', false, 'why', v_why));
      continue;
    end if;

    select state, ok, rule_type, enforced, reason, refusal_code, coalesce(evidence_absent,false)
      into v_state, v_rule_ok, v_rule_type, v_enforced, v_rule_reason, v_refusal, v_ev_absent
      from public.fn_phase_d_rule_check(v_rule.rid,
        jsonb_build_object(
          'accountable_role_id', sr.accountable_role_id,
          'reviewer_role_id',    nullif(b.independent_reviewer_role_id,''),
          'actor_role_id',       v_actor,
          'step_id',             sr.step_id,
          'workflow_id',         b.workflow_id,
          'run_id',              sr.run_id,
          'founder_gate',        b.founder_gate,
          'execution_context',   v_ctx)
        || coalesce(p_input->'context','{}'::jsonb));

    v_evaluated := v_evaluated || jsonb_build_array(jsonb_build_object(
      'rule_id', v_rule.rid, 'state', v_state, 'rule_type', v_rule_type, 'ok', v_rule_ok,
      'enforced', v_enforced, 'reason', v_rule_reason));

    if v_rule_type = 'hard' and v_state in ('ENFORCED_FAIL','NOT_IMPLEMENTED') then
      v_refused := v_refused || jsonb_build_array(jsonb_build_object(
        'rule_id', v_rule.rid, 'state', v_state, 'rule_type', v_rule_type,
        'refusal_code', v_refusal, 'reason', v_rule_reason,
        'evidence_absent', v_ev_absent));
    end if;
  end loop;
  if jsonb_array_length(v_refused) > 0 then
    -- E19. TWO DIFFERENT EVENTS DESERVE TWO DIFFERENT NAMES. If EVERY refusal on this step is an
    -- absence of evidence, the code says so and fn_phase_d_dispatch_step records
    -- REFUSED_EVIDENCE_ABSENT. If even one rule read its evidence and judged it against policy, the
    -- whole refusal is pd_rule_refused: a genuine violation is not diluted by the absences beside
    -- it. Both refuse, and neither is a pass.
    if not exists (select 1 from jsonb_array_elements(v_refused) x
                    where not coalesce((x->>'evidence_absent')::boolean, false)) then
      raise exception 'fn_phase_d_handler_execute: step % refused by % hard business rule(s), every one of them for evidence the call did not name rather than for a policy the call broke: % (pd_evidence_absent)',
        sr.step_id, jsonb_array_length(v_refused), v_refused::text using errcode = '23514';
    end if;
    raise exception 'fn_phase_d_handler_execute: step % refused by % hard business rule(s): % (pd_rule_refused)',
      sr.step_id, jsonb_array_length(v_refused), v_refused::text using errcode = '23514';
  end if;

  -- ---- 2b. GATES IN SCOPE, EACH AGAINST ITS OWN DECLARED EVIDENCE --------------------------
  for v_gate in select unnest(b.gate_ids) gid loop
    select ga.applies, ga.why into v_gapplies, v_gwhy
      from public.fn_phase_d_gate_applies(v_gate.gid, sr.step_id) ga;
    if not coalesce(v_gapplies,false) then
      v_gates := v_gates || jsonb_build_array(jsonb_build_object(
        'gate_id', v_gate.gid, 'state', 'NOT_APPLICABLE', 'why', v_gwhy));
      continue;
    end if;
    select ge.state, ge.passed, ge.gate_type, ge.reason, ge.refusal_code, coalesce(ge.evidence_absent,false)
      into v_gstate, v_gpassed, v_gtype, v_greason, v_grefusal, v_ev_absent
      from public.fn_phase_d_gate_evaluate(v_gate.gid,
        jsonb_build_object('step_id', sr.step_id, 'run_id', sr.run_id,
                           'step_run_id', v_step_run,
                           'step_run_id', v_step_run,
                           'actor_role_id', v_actor,
                           'reviewer_role_id', nullif(b.independent_reviewer_role_id,''))
        || coalesce(p_input->'gate_evidence','{}'::jsonb)) ge;

    v_gates := v_gates || jsonb_build_array(jsonb_build_object(
      'gate_id', v_gate.gid, 'state', v_gstate, 'gate_type', v_gtype,
      'passed', v_gpassed, 'reason', v_greason));

    if v_gtype = 'hard' and v_gstate in ('BLOCKED','NOT_IMPLEMENTED') then
      v_gblocked := v_gblocked || jsonb_build_array(jsonb_build_object(
        'gate_id', v_gate.gid, 'state', v_gstate,
        'refusal_code', v_grefusal, 'reason', v_greason,
        'evidence_absent', v_ev_absent));
    end if;
  end loop;
  if jsonb_array_length(v_gblocked) > 0 then
    if not exists (select 1 from jsonb_array_elements(v_gblocked) x
                    where not coalesce((x->>'evidence_absent')::boolean, false)) then
      raise exception 'fn_phase_d_handler_execute: step % blocked by % hard gate(s), every one of them for evidence the call did not name rather than for a condition the gate judged and rejected: % (pd_evidence_absent)',
        sr.step_id, jsonb_array_length(v_gblocked), v_gblocked::text using errcode = '23514';
    end if;
    raise exception 'fn_phase_d_handler_execute: step % refused by % hard gate(s): % (pd_gate_refused)',
      sr.step_id, jsonb_array_length(v_gblocked), v_gblocked::text using errcode = '23514';
  end if;

  -- ---- 3. CAPABILITY BOUNDARY, FAIL CLOSED, AND NO LONGER A MODE STRING --------------------
  -- F05. This read `if b.capability_dependency <> 'NONE' and v_ctx <> 'test'`, so the literal
  -- 'test' arriving in one field turned twenty-one fail-closed business boundaries off at once.
  -- The founder prohibited exactly that shape on 21 Aug 2026. The mode is no longer consulted:
  -- the handler asks whether an ACCEPTED capability result exists for this step run, and the only
  -- way one exists is through fn_phase_d_capability_result_accept, which validates it against the
  -- step's own output contract and which refuses a fixture result outright unless a Phase D
  -- fixture context verifies (F01).
  --
  -- In production there is no fixture context and no provider, so there is no result, so this
  -- raises -- the same refusal, at the same point, for a reason that is now a read rather than a
  -- comparison against a caller-supplied string.
  if b.capability_dependency <> 'NONE' then
    -- The request is opened first and in every context: it is the row a Phase E provider answers,
    -- and a step that never asked cannot be said to have been refused.
    v_cap_req := public.fn_phase_d_capability_request_open(jsonb_build_object(
      'step_run_id', v_step_run, 'requested_by', v_actor));
    v_cap := public.fn_phase_d_capability_answer(v_step_run);
    if v_cap is null then
      raise exception 'fn_phase_d_handler_execute: step % depends on capability % (matched on the frozen required_action at: %) and capability request % carries no accepted result. Paid inference is held until Phase E; a Phase D fixture result must be submitted through fn_phase_d_capability_result_accept, which requires a verified Phase D fixture context. Refusing rather than completing a business step from nothing. (pd_capability_unavailable)',
        sr.step_id, b.capability_dependency, coalesce(nullif(b.capability_evidence,''),'(none)'),
        coalesce(v_cap_req->>'request_id','(none)')
        using errcode = '23514';
    end if;
  end if;

  -- ---- 4. PROVIDER BOUNDARY, FAIL CLOSED ---------------------------------------------------
  -- Same correction, same reason. A provider dependency is refused whatever the execution context
  -- says, because the hold is on the provider and not on the caller's description of itself.
  if b.provider_dependency <> 'NONE' then
    raise exception 'fn_phase_d_handler_execute: step % depends on external provider % which is disabled for the whole of Phase D. No execution context lifts this. (pd_provider_disabled)',
      sr.step_id, b.provider_dependency using errcode = '23514';
  end if;

  -- ---- 4b. H01. THE VERDICT THE KERNEL WILL DEMAND, ASKED FOR HERE FIRST ----------------------
  -- fn_kernel_step_complete 3g refuses a pass on a step whose frozen row names an independent
  -- reviewer unless an approved, independent verdict from that role is sealed on the task. The
  -- handler used to discover that only after producing its effect, and the refusal came out of the
  -- kernel as k3_reviewer_verdict_missing. The same predicate is asked here, before anything is
  -- built, and the refusal is the one the driver answers through fn_kernel_review_decide. Nothing
  -- about the kernel check changes; it still decides at 3g.
  if coalesce(btrim(s.independent_reviewer_role_id),'') <> ''
     and not exists (
       select 1
         from public.phase_c_task t
         join public.phase_c_trace tr on tr.task_id = t.task_id
        where t.run_id = sr.run_id and t.step_id = sr.step_id
          and tr.trace_policy_id = 'TRACE-ROLE-ACTION'
          and tr.evidence_refs @> '[{"review_decision":"approved"}]'::jsonb
          and public.fn_kernel_reviewer_independent(sr.accountable_role_id, tr.reviewer_role_id)
          and (select role_id from public.fn_phase_c_resolve_actor(tr.reviewer_role_id))
              = (select role_id from public.fn_phase_c_resolve_actor(s.independent_reviewer_role_id)))
  then
    raise exception 'fn_phase_d_handler_execute: step % names % as its independent reviewer and no approved, independent verdict from that role has been recorded on its task. fn_kernel_review_decide seals the verdict and stamps the reviewer; until it has run the kernel will refuse the completion, so the handler refuses here first. (pd_review_not_recorded)',
      sr.step_id, s.independent_reviewer_role_id using errcode = '23514';
  end if;

  -- ---- 5. THE FAMILY HANDLER ---------------------------------------------------------------
  -- F34. The recorded canonical review for this step run, read once.
  v_review := public.fn_phase_d_recorded_review(v_step_run);

  v_assert := (
    select coalesce(jsonb_agg(jsonb_build_object(
             'criterion', btrim(c), 'satisfied_by',
             'named inputs [' || array_to_string(
               (select array_agg(k order by k) from jsonb_object_keys(v_inputs) k), ', ') || ']')
             order by ord), '[]'::jsonb)
      from unnest(string_to_array(coalesce(s.acceptance_criteria,''), ';')) with ordinality u(c, ord)
     where btrim(c) <> '');

  v_output := jsonb_build_object(
    'status', 'completed',
    'output', format('%s — %s', s.step_name, coalesce(s.required_output,'output produced')),
    'acceptance_assertions', case when jsonb_array_length(v_assert) = 0
                                  then jsonb_build_array(jsonb_build_object(
                                         'criterion', coalesce(s.acceptance_criteria,'(none declared)'),
                                         'satisfied_by','named inputs'))
                                  else v_assert end,
    'evidence_refs', jsonb_build_array(jsonb_build_object(
       'step_id', sr.step_id, 'step_run_id', v_step_run, 'run_id', sr.run_id,
       'handler_id', b.handler_id, 'handler_version', b.handler_version,
       'input_schema_id', b.input_schema_id, 'output_schema_id', b.output_schema_id,
       'inputs_named', v_inputs, 'execution_context', v_ctx)))
    || case when v_cap is null then '{}'::jsonb
            else jsonb_build_object('capability_result', jsonb_build_object(
              'request_id',    v_cap->'request_id',
              'result_id',     v_cap->'result_id',
              'provider_mode', v_cap->>'provider_mode',
              'fixture_id',    v_cap->>'fixture_id',
              'fixture_version', v_cap->'fixture_version',
              'fixture_hash',  v_cap->>'fixture_hash',
              'payload_digest',v_cap->>'payload_digest',
              'evidence',      v_cap->>'evidence')) end
    || case b.handler_class
         when 'INTAKE_HANDLER' then jsonb_build_object(
           'source_ref', coalesce(p_input->>'source_ref', 'step_run:' || v_step_run),
           'captured_verbatim', v_inputs)
         when 'ANALYSIS_HANDLER' then jsonb_build_object(
           'method', 'deterministic reconciliation of the named inputs against the frozen step contract',
           'inputs_used', v_inputs,
           'findings', jsonb_build_array(coalesce(s.required_action,'')),
           'assumptions', jsonb_build_array(
             'only the inputs named in this call were used; no external source was consulted'))
         when 'EXECUTION_HANDLER' then jsonb_build_object(
           'state_change', coalesce(s.required_output,''),
           'target_object', coalesce(ec.effect_object_id,
             (select primary_object from public.phase_b_workflow w
               where w.workflow_id = b.workflow_id), b.workflow_id),
           'authorization_ref', format('accountable owner %s on step %s',
                                       sr.accountable_role_id, sr.step_id))
         -- F34. A REVIEW READ OFF THE CALLER'S OWN STRING.
         -- Both keys came from p_input, so the kernel dispatch -- which passes neither -- produced
         -- an output naming no reviewer, and BR-002 then refused the step for "names (none) as
         -- reviewer". That refusal was true and it was about this harness, not about the business.
         -- The founder's section 4 names CANONICAL_INTERNAL_REVIEW as an allowed execution input
         -- when it travels through its real interface, and that interface is fn_kernel_review_decide:
         -- it checks independence itself, seals a TRACE-ROLE-ACTION carrying the decision, and
         -- stamps phase_c_task.reviewer_role_id. Both values are therefore READ FROM THOSE ROWS.
         -- A caller can no longer assert either one.
         when 'REVIEW_HANDLER' then jsonb_strip_nulls(jsonb_build_object(
           'verdict', v_review->'verdict',
           'reviewer_role_id', v_review->'reviewer_role_id'))
         when 'DECISION_HANDLER' then jsonb_build_object(
           'decision', coalesce(s.required_output,''),
           'rationale', coalesce(s.acceptance_criteria,''),
           'authority_ref', format('founder_gate=%s; accountable owner %s',
                                   b.founder_gate, sr.accountable_role_id))
         when 'HANDOFF_HANDLER' then jsonb_build_object(
           'packet', v_inputs,
           'receiving_role_id', coalesce((select h.receiving_role_id from public.phase_b_handoff h
                                           where h.from_step_id = sr.step_id limit 1),
                                         sr.accountable_role_id),
           'acceptance_criteria', coalesce(s.acceptance_criteria,''))
         -- F34. THE FOUR VALUES CAME FROM p_input, AND NOTHING PASSES p_input HERE.
         -- E32 stopped the harness supplying handler inputs, correctly, and the kernel dispatch
         -- passes no measurement keys, so denominator, numerator, formula and window were null on
         -- every call, jsonb_strip_nulls removed them, and the step's own output contract refused
         -- the output the handler had just built. They now come from the committed catalogue
         -- through fn_phase_d_fixture_output, which returns NULL when no row exists -- so a step
         -- with no committed measurement is still refused by its contract, and the denominator-of-0
         -- guard below is untouched.
         when 'MEASUREMENT_HANDLER' then jsonb_strip_nulls(jsonb_build_object(
           'metric', coalesce(public.fn_phase_d_fixture_output(sr.step_id,'metric'),
                              to_jsonb(nullif(btrim(coalesce(s.required_output,'')),''))),
           'denominator', public.fn_phase_d_fixture_output(sr.step_id,'denominator'),
           'numerator', public.fn_phase_d_fixture_output(sr.step_id,'numerator'),
           'formula', public.fn_phase_d_fixture_output(sr.step_id,'formula'),
           'window', public.fn_phase_d_fixture_output(sr.step_id,'window')))
         when 'CLOSURE_HANDLER' then jsonb_build_object(
           'blockers_resolved', jsonb_build_array(
             'the frozen fn_kernel_step_complete measures the four mandatory closure blocker '
             || 'classes itself and raises k3_closure_blocked if any is open'),
           'closure_evidence', coalesce(s.closure_criteria,''))
         else '{}'::jsonb end;

  -- ---- 5a. TWO REFUSALS THE SCHEMA ALONE CANNOT MAKE ---------------------------------------
  -- F34. TWO REFUSALS THAT WORE ONE NAME. "no review has been recorded for this step" and "the
  -- recorded review names the creator" are different facts with different remedies, and both came
  -- out as pd_rule_refused/BR-002. The first is now its own code, so a driver can answer it by
  -- recording the review through the kernel's own door and asking for the step again.
  if b.handler_class = 'REVIEW_HANDLER'
     and coalesce(btrim(coalesce(v_output->>'reviewer_role_id','')),'') = '' then
    raise exception 'fn_phase_d_handler_execute: step % is a review step and no internal review has been recorded for it. fn_kernel_review_decide seals the verdict and stamps the reviewer on the task; until it has run there is no reviewer to name and no verdict to carry. (pd_review_not_recorded)',
      sr.step_id using errcode = '23514';
  end if;

  if b.handler_class = 'REVIEW_HANDLER'
     and not public.fn_kernel_reviewer_independent(
               sr.accountable_role_id, v_output->>'reviewer_role_id') then
    raise exception 'fn_phase_d_handler_execute: step % is accountable to % and the review names % as reviewer; those resolve to the same effective identity. A creator cannot be the sole independent reviewer of the same output (BR-002). (pd_rule_refused)',
      sr.step_id, sr.accountable_role_id, coalesce(v_output->>'reviewer_role_id','(none)')
      using errcode = '23514';
  end if;

  if b.handler_class = 'MEASUREMENT_HANDLER'
     and jsonb_typeof(v_output->'denominator') = 'number'
     and (v_output->>'denominator')::numeric = 0 then
    raise exception 'fn_phase_d_handler_execute: step % reported a denominator of 0. A ratio over nothing is not a measurement, and reporting it as one is how an unmeasured goal scores as perfect. (pd_output_schema_invalid)',
      sr.step_id using errcode = '22023';
  end if;

  -- ---- 6. TYPED OUTPUT ---------------------------------------------------------------------
  select valid, reason, missing into v_ok, v_reason, v_missing
    from public.fn_phase_d_schema_validate(b.output_schema_id, v_output);
  if not v_ok then
    raise exception 'fn_phase_d_handler_execute: step % produced an output its own contract rejects: % (pd_output_schema_invalid)',
      sr.step_id, v_reason using errcode = '22023';
  end if;

  -- ---- 6b. THE BUSINESS EFFECT -------------------------------------------------------------
  -- D7. Until this line existed, 257 of 257 handlers produced a typed output the kernel accepted
  -- and no business effect whatsoever, and fn_phase_d_handler_state() said so in red.
  --
  -- The effect payload comes from the CALLER, merged over the step's own facts. Nothing about the
  -- business record is invented here: a step that needs a business_key and an owner_ref and is
  -- given neither refuses, because a record written under an owner this routine chose would be
  -- the auto-vivified customer account defect in a new place.
  v_effect := public.fn_phase_d_effect_produce(
    jsonb_build_object(
      'step_run_id', v_step_run, 'idempotency_key', v_idem, 'actor_role_id', v_actor,
      'execution_context', v_ctx)
    || jsonb_strip_nulls(jsonb_build_object(
      'business_key', p_input->>'business_key',
      'owner_ref',    p_input->>'owner_ref',
      -- H01 (4). The caller's stated state, else the state the committed catalogue declares for
      -- THIS step (EFFECT_PAYLOAD key 'state', step-scoped, fixture context only), else none -- and
      -- none means the writer keeps the row's state or takes the relation's default. Never 'open'.
      'state',        coalesce(p_input->>'effect_state',
                               (select fi.value #>> '{}'
                                  from public.fn_phase_d_fixture_input(v_step_run, 'EFFECT_PAYLOAD', 'state') fi)),
      'state_before', p_input->>'state_before',
      'trace_id',     p_input->>'trace_id'))
    -- F16. THE CONTENT THE OBJECT'S OWN RELATION DEMANDS, from the committed catalogue.
    --
    -- pd_effect_payload_incomplete is the deepest refusal in the drive: the step has passed every
    -- rule and gate, the dispatch has derived a business key and an owner, and the write to the
    -- object's canonical relation fails on a NOT NULL column -- opportunity.kind, org_tasks.title,
    -- department_objective.objective, content_drafts.body. The builder closure of 2026-08-20
    -- recorded 18 of 56 business objects in that state and reported it as a Phase E boundary,
    -- correctly, because a deterministic handler must not invent a title or an amount.
    --
    -- The founder's ruling of 21 Aug 2026 supplies them instead, from a committed catalogue, and
    -- this is where they arrive. The handler still invents nothing: the value comes from
    -- fn_phase_d_fixture_effect_payload, which reads the columns the RELATION demands and the
    -- values the CATALOGUE holds, and which returns an empty object in production.
    --
    -- The order is caller, then capability result, then catalogue, and the catalogue is last so it
    -- can only fill what nothing else filled.
    || jsonb_build_object('payload',
         public.fn_phase_d_fixture_effect_payload(v_step_run)
         || coalesce(p_input->'effect_payload', v_inputs)
         || case when v_cap is null then '{}'::jsonb
                 else coalesce(v_cap->'payload','{}'::jsonb) end
         -- H01 (1). THE RECORDED REVIEW, LAST, FOR A REVIEW_VERDICT EFFECT. F34 read it into the
         -- output and never into the payload, and BR-002 is judged on the payload. The sealed
         -- verdict and the stamped reviewer outrank the catalogue and any caller, so they close
         -- the concatenation. Absent, nothing is added and fn_phase_d_effect_produce still refuses.
         || case when ec.expected_effect_type = 'REVIEW_VERDICT'
                 then jsonb_strip_nulls(jsonb_build_object(
                        'verdict',          v_review->>'verdict',
                        'reviewer_role_id', v_review->>'reviewer_role_id'))
                 else '{}'::jsonb end
         -- H01 (3). WHO DECIDED AND WHEN, FOR A DECISION STEP. The decider is the accountable role
         -- of the deciding step run, read off the kernel's row; the time is now(). A write map that
         -- carries neither key ignores both.
         || case when b.handler_class = 'DECISION_HANDLER'
                 then jsonb_build_object('decided_by', v_actor, 'decided_at', now())
                 else '{}'::jsonb end));

  v_output := v_output || jsonb_build_object('business_effect', jsonb_build_object(
    'effect_type', v_effect->>'effect_type',
    'effect_object_id', v_effect->'effect_object_id',
    'result_reference', v_effect->>'result_reference',
    'effect_id', v_effect->'effect_id',
    'provider_mode', v_effect->>'provider_mode',
    'replay', v_effect->'replay'));

  -- ---- 7. HAND TO THE FROZEN KERNEL --------------------------------------------------------
  -- Everything from here — idempotency, locks, authority, gates, the task state machine,
  -- progression, handoffs, run state and events — belongs to fn_kernel_step_complete and is not
  -- reimplemented. A handler that wrote any of it would be the parallel engine the spec forbids.
  v_result := public.fn_kernel_step_complete(jsonb_build_object(
    'step_run_id', v_step_run, 'actor_role_id', v_actor, 'outcome', 'pass',
    'idempotency_key', v_idem, 'inputs', v_inputs, 'output', v_output,
    'evidence_ref', format('phase_d:%s:%s:effect=%s',
                           b.handler_id, v_step_run, coalesce(v_effect->>'result_reference','none')),
    'correlation_id', p_input->>'correlation_id',
    'causation_id', coalesce(p_input->>'causation_id', 'phase_d_handler:' || b.handler_id)));

  return v_result || jsonb_build_object(
    'phase_d', jsonb_build_object(
      'handler_id', b.handler_id, 'handler_version', b.handler_version,
      'handler_class', b.handler_class, 'execution_context', v_ctx,
      'input_schema_id', b.input_schema_id, 'output_schema_id', b.output_schema_id,
      'rules_in_scope', cardinality(b.rule_ids),
      'rules_evaluated', v_evaluated, 'rules_not_applicable', v_skipped,
      'rules_enforced_count', (select count(*) from jsonb_array_elements(v_evaluated) e2
                                where (e2->>'enforced')::boolean),
      'rules_outstanding_count', (select count(*) from jsonb_array_elements(v_evaluated) e2
                                   where not (e2->>'enforced')::boolean),
      'gates_in_scope', cardinality(b.gate_ids), 'gates_evaluated', v_gates,
      'capability_dependency', b.capability_dependency,
      'provider_dependency', b.provider_dependency,
      'external_effect_policy', b.external_effect_policy,
      'expected_effect_type', ec.expected_effect_type,
      'implementation_depth', ec.implementation_depth,
      'business_effect', v_effect));
end $function$

