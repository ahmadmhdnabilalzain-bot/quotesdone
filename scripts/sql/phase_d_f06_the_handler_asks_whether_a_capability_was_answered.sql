-- F06 - the handler asks whether a capability was answered, not what mode it is in
--
-- Two splices, both produced by reading the LIVE definition out with pg_get_functiondef and
-- replacing one complete block, so nothing else in either routine moves.
--
--   fn_phase_d_handler_execute  sections 3 and 4, plus two declarations, plus the two places the
--                               accepted result now travels: the output evidence and the effect
--                               payload.
--   fn_phase_d_effect_produce   the CAPABILITY_REQUEST branch.
--
-- Before:  if b.capability_dependency <> 'NONE' and v_ctx <> 'test' then raise ...
-- After:   if b.capability_dependency <> 'NONE' then
--            open the request; if no accepted result exists, raise.
--
-- The founder's section C, verbatim: "Do not bypass their boundary with execution_context = test
-- -> skip capability check." There is now no value of execution_context that skips it, and
-- fn_phase_d_capability_state() greps both routines for the old shape so a future edit that
-- reintroduces it turns a board row red.
--
-- WHY THE EFFECT PAYLOAD CHANGES. A capability-dependent step's business content comes from the
-- capability result -- that is what the capability is FOR. Merging the accepted result's payload
-- over the effect payload is how "the handler receives the fixture as input" reaches the write:
-- the handler still invents nothing, and what it writes is traceable to a fixture id, a version
-- and a hash, or to a provider event, recorded on the result row.

CREATE OR REPLACE FUNCTION public.fn_phase_d_handler_execute(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
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

  -- ---- 5. THE FAMILY HANDLER ---------------------------------------------------------------
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
         when 'REVIEW_HANDLER' then jsonb_strip_nulls(jsonb_build_object(
           'verdict', nullif(btrim(coalesce(p_input->>'verdict','')),''),
           'reviewer_role_id', nullif(btrim(coalesce(p_input->>'reviewer_role_id','')),'')))
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
         when 'MEASUREMENT_HANDLER' then jsonb_strip_nulls(jsonb_build_object(
           'metric', coalesce(s.required_output,''),
           'denominator', p_input->'denominator',
           'numerator', p_input->'numerator',
           'formula', nullif(btrim(coalesce(p_input->>'formula','')),''),
           'window', nullif(btrim(coalesce(p_input->>'window','')),'')))
         when 'CLOSURE_HANDLER' then jsonb_build_object(
           'blockers_resolved', jsonb_build_array(
             'the frozen fn_kernel_step_complete measures the four mandatory closure blocker '
             || 'classes itself and raises k3_closure_blocked if any is open'),
           'closure_evidence', coalesce(s.closure_criteria,''))
         else '{}'::jsonb end;

  -- ---- 5a. TWO REFUSALS THE SCHEMA ALONE CANNOT MAKE ---------------------------------------
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
      'state',        p_input->>'effect_state',
      'state_before', p_input->>'state_before',
      'trace_id',     p_input->>'trace_id'))
    || jsonb_build_object('payload',
         coalesce(p_input->'effect_payload', v_inputs)
         || case when v_cap is null then '{}'::jsonb
                 else coalesce(v_cap->'payload','{}'::jsonb) end));

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
;

CREATE OR REPLACE FUNCTION public.fn_phase_d_effect_produce(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  e            public.phase_d_step_effect%rowtype;
  sr           public.phase_c_workflow_step_run%rowtype;
  prior        public.phase_d_effect_ledger%rowtype;
  v_step_run   bigint := nullif(p_input->>'step_run_id','')::bigint;
  v_idem       text   := nullif(btrim(coalesce(p_input->>'idempotency_key','')),'');
  v_actor      text   := nullif(btrim(coalesce(p_input->>'actor_role_id','')),'');
  v_payload    jsonb  := coalesce(p_input->'payload','{}'::jsonb);
  v_key        text   := nullif(btrim(coalesce(p_input->>'business_key','')),'');
  v_owner      text   := nullif(btrim(coalesce(p_input->>'owner_ref','')),'');
  v_state      text   := nullif(btrim(coalesce(p_input->>'state','')),'');
  v_ctx        text   := lower(coalesce(nullif(btrim(p_input->>'execution_context'),''),'production'));
  v_write      jsonb;
  v_result_ref text;
  v_relation   text;
  v_mode       text := 'none';
  v_eid        bigint;
  v_num        numeric; v_den numeric;
  v_cap        jsonb;   -- F05: the accepted capability result for this step run, or null
begin
  if v_step_run is null or v_idem is null or v_actor is null then
    raise exception 'fn_phase_d_effect_produce: step_run_id, idempotency_key and actor_role_id are all required (pd_effect_input_invalid)'
      using errcode = '22023';
  end if;

  select * into sr from public.phase_c_workflow_step_run where step_run_id = v_step_run;
  if not found then
    raise exception 'fn_phase_d_effect_produce: no step run % (pd_step_state_invalid)', v_step_run
      using errcode = '23503';
  end if;

  select * into e from public.phase_d_step_effect where step_id = sr.step_id;
  if not found then
    raise exception 'fn_phase_d_effect_produce: step % has no declared effect contract — fail closed. All 257 frozen steps carry one. (pd_effect_undeclared)',
      sr.step_id using errcode = '23503';
  end if;

  -- ---- IDEMPOTENCY IS A READ, NOT A HOPE -------------------------------------------------
  -- A replayed handler must produce NO second effect. The assertion a duplicate-effect test makes
  -- is the ledger ROW COUNT, not the returned payload, so the check is done here and the prior
  -- row is returned verbatim.
  select * into prior from public.phase_d_effect_ledger
   where step_run_id = v_step_run and effect_type = e.expected_effect_type;
  if found then
    return jsonb_build_object(
      'ok', true, 'replay', true, 'effect_id', prior.effect_id,
      'effect_type', prior.effect_type, 'effect_object_id', prior.effect_object_id,
      'result_reference', prior.result_reference, 'provider_mode', prior.provider_mode,
      'note', 'the effect for this step run already exists; no second effect was produced');
  end if;

  -- ---- the seven types -------------------------------------------------------------------
  if e.expected_effect_type = 'KERNEL_ONLY_TRANSITION' then
    -- Nothing is written here beyond the ledger entry. The effect IS the kernel's step run and
    -- run-state move, which is persistent and kernel-verifiable; a domain row invented to make a
    -- count look better would be a fabricated effect.
    v_result_ref := format('public.phase_c_workflow_step_run:step_run_id=%s', v_step_run);
    v_relation   := 'public.phase_c_workflow_step_run';

  elsif e.expected_effect_type = 'CAPABILITY_REQUEST' then
    -- Fail closed in production, and record the refusal as the effect. A capability step whose
    -- effect was a success record would be a mock completing a business step.
    -- F05. This read `if v_ctx <> 'test' then raise`, which is the bypass the founder prohibited
    -- seen from the effect side: the string 'test' turned the refusal into a record. The subject
    -- is now the same one the handler asks about -- is there an ACCEPTED capability result for
    -- this step run? The declared effect of a capability step IS the request; what the result
    -- adds is the answer it can point at, and its provider_mode is recorded rather than assumed.
    v_cap := public.fn_phase_d_capability_answer(v_step_run);
    if v_cap is null then
      raise exception 'fn_phase_d_effect_produce: step % is capability-dependent and its capability request carries no accepted result. The declared effect is a refusal, not a record. No execution context lifts this. (pd_capability_unavailable)',
        sr.step_id using errcode = '23514';
    end if;
    v_result_ref := format('capability_request:%s:result=%s:mode=%s:digest=%s',
                           v_cap->>'request_id', v_cap->>'result_id', v_cap->>'provider_mode',
                           left(coalesce(v_cap->>'payload_digest',''), 12));
    v_relation   := 'public.phase_d_capability_result';
    v_mode       := v_cap->>'provider_mode';

  elsif e.expected_effect_type = 'EXTERNAL_EFFECT_INTENT' then
    -- MOCK, ALWAYS. provider_mode has no 'live' value, so this cannot be turned into a send by
    -- changing a parameter. A recipient and a consent basis are REQUIRED and are not defaulted:
    -- an intent that cannot say who it is for is not an intent.
    if not (v_payload ? 'recipient') or not (v_payload ? 'consent_basis') then
      raise exception 'fn_phase_d_effect_produce: step % declares an external effect and the payload names no %. An intent with no recipient or no consent basis must not be recorded as one. (pd_effect_intent_incomplete)',
        sr.step_id,
        case when not (v_payload ? 'recipient') then 'recipient' else 'consent_basis' end
        using errcode = '22023';
    end if;
    if coalesce(v_payload->>'suppressed','false') = 'true' then
      v_result_ref := format('external_intent:SUPPRESSED:%s', v_payload->>'recipient');
    else
      v_result_ref := format('external_intent:MOCK:%s', v_payload->>'recipient');
    end if;
    v_relation := 'public.phase_d_effect_ledger';
    v_mode     := 'mock';

  elsif e.expected_effect_type = 'MEASUREMENT_RECORD' then
    -- least(100, NULL) returns 100 and put 97.7% attainment in the founder's email on a
    -- zero-revenue day. Nothing is defaulted, and a zero denominator raises.
    if not (v_payload ? 'numerator') or not (v_payload ? 'denominator') then
      raise exception 'fn_phase_d_effect_produce: step % is a measurement step and the payload names no %. An absent input must not score as satisfied. (pd_effect_measurement_incomplete)',
        sr.step_id,
        case when not (v_payload ? 'numerator') then 'numerator' else 'denominator' end
        using errcode = '22023';
    end if;
    v_num := (v_payload->>'numerator')::numeric;
    v_den := (v_payload->>'denominator')::numeric;
    if v_den = 0 then
      raise exception 'fn_phase_d_effect_produce: step % reported a denominator of 0. A ratio over nothing is not a measurement. (pd_effect_zero_denominator)',
        sr.step_id using errcode = '22023';
    end if;
    v_result_ref := format('measurement:%s/%s', v_num, v_den);
    v_relation   := 'public.phase_d_effect_ledger';

  elsif e.expected_effect_type = 'REVIEW_VERDICT' then
    -- The verdict is the caller's. An absent one is a refusal, not an approval: a review handler
    -- that supplied its own verdict would make all 47 review steps a rubber stamp.
    if not (v_payload ? 'verdict') or nullif(btrim(v_payload->>'verdict'),'') is null then
      raise exception 'fn_phase_d_effect_produce: step % is a review step and the payload names no verdict. This routine does not have one to give. (pd_effect_verdict_absent)',
        sr.step_id using errcode = '22023';
    end if;
    if not public.fn_kernel_reviewer_independent(
             sr.accountable_role_id, nullif(btrim(v_payload->>'reviewer_role_id'),'')) then
      raise exception 'fn_phase_d_effect_produce: step % is accountable to % and names % as reviewer; those resolve to one effective identity (BR-002). (pd_rule_refused)',
        sr.step_id, sr.accountable_role_id, coalesce(v_payload->>'reviewer_role_id','(none)')
        using errcode = '23514';
    end if;
    v_write := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','review_record',
      'business_key', coalesce(v_key, format('%s:%s', sr.step_id, v_step_run)),
      'owner_ref', coalesce(v_owner, sr.accountable_role_id),
      'created_by', v_actor,
      'state', coalesce(v_state, v_payload->>'verdict'),
      'payload', v_payload || jsonb_build_object(
        'stage', sr.step_id, 'notes', coalesce(v_payload->>'notes', 'phase_d review verdict'))));
    v_result_ref := v_write->>'result_reference';
    v_relation   := v_write->>'canonical_relation';

  else
    -- DOMAIN_MUTATION and VERSIONED_ARTIFACT: the object's own canonical service.
    if v_key is null or v_owner is null then
      raise exception 'fn_phase_d_effect_produce: step % writes business object % and the call names no %. (pd_effect_owner_or_key_missing)',
        sr.step_id, e.effect_object_id,
        case when v_key is null then 'business_key' else 'owner_ref' end
        using errcode = '22023';
    end if;
    v_write := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id', e.effect_object_id, 'business_key', v_key, 'owner_ref', v_owner,
      'created_by', v_actor, 'state', v_state, 'payload', v_payload,
      'run_id', sr.run_id, 'step_run_id', v_step_run, 'trace_id', p_input->>'trace_id'));
    v_result_ref := v_write->>'result_reference';
    v_relation   := coalesce(v_write->>'canonical_relation', e.effect_relation);
  end if;

  insert into public.phase_d_effect_ledger
    (step_run_id, step_id, workflow_id, run_id, effect_type, effect_object_id, effect_relation,
     effect_operation, result_reference, state_before, state_after, provider_mode,
     payload_digest, idempotency_key, produced_by, trace_id)
  values (v_step_run, sr.step_id, e.workflow_id, sr.run_id, e.expected_effect_type,
          e.effect_object_id, v_relation, e.effect_operation, v_result_ref,
          nullif(p_input->>'state_before',''), v_state, v_mode,
          encode(sha256(convert_to(v_payload::text,'UTF8')),'hex'), v_idem, v_actor,
          nullif(p_input->>'trace_id','')::bigint)
  returning effect_id into v_eid;

  if v_eid is null then
    raise exception 'fn_phase_d_effect_produce: the ledger insert for step run % returned no effect_id. (pd_effect_produced_nothing)',
      v_step_run using errcode = '23502';
  end if;

  return jsonb_build_object(
    'ok', true, 'replay', false, 'effect_id', v_eid,
    'effect_type', e.expected_effect_type, 'effect_object_id', e.effect_object_id,
    'effect_relation', v_relation, 'effect_operation', e.effect_operation,
    'result_reference', v_result_ref, 'provider_mode', v_mode,
    'completion_condition', e.completion_condition,
    'object_write', v_write);
end $function$
;
