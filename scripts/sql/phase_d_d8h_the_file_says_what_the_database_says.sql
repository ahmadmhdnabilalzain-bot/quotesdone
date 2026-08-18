-- PHASE D · D8h — THE FILE HAS TO SAY WHAT THE DATABASE SAYS, NOT DESCRIBE AN EDIT TO IT.
--
-- D8g needed one line added to fn_phase_d_handler_execute — step_run_id in the gate-evidence block,
-- so GATE-008 can exclude the step run that is asking it — and did it with a DO block that read
-- pg_get_functiondef, string-replaced, and executed the result. It worked, and the canonical routine
-- engine immediately reported what it cost:
--
--   REPOSITORY -> PRODUCTION drift (canonical body not deployed): 1
--      fn_phase_d_handler_execute  DRIFTED
--      [scripts/sql/phase_d_d7_effect_contract_and_business_writes.sql]
--
-- The live body was produced by an edit performed at deploy time, so no file in this repository
-- described it. That is exactly the state the read-back convention exists to prevent: what is LIVE
-- must be what a committed file says, verified by reading the definition back — not by trusting that
-- a transformation did what it was supposed to.
--
-- This file is the live body, read back out of the database and committed verbatim. The engine's own
-- newest-wins rule then makes THIS the canonical definition of the routine, and D7's copy stops
-- claiming it.
--
-- The general rule, restated because the shortcut was tempting and cheap: a migration may CREATE OR
-- REPLACE a routine, and may not compute one.

begin;

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

    select state, ok, rule_type, enforced, reason, refusal_code
      into v_state, v_rule_ok, v_rule_type, v_enforced, v_rule_reason, v_refusal
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
        'refusal_code', v_refusal, 'reason', v_rule_reason));
    end if;
  end loop;
  if jsonb_array_length(v_refused) > 0 then
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
    select ge.state, ge.passed, ge.gate_type, ge.reason, ge.refusal_code
      into v_gstate, v_gpassed, v_gtype, v_greason, v_grefusal
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
        'refusal_code', v_grefusal, 'reason', v_greason));
    end if;
  end loop;
  if jsonb_array_length(v_gblocked) > 0 then
    raise exception 'fn_phase_d_handler_execute: step % refused by % hard gate(s): % (pd_gate_refused)',
      sr.step_id, jsonb_array_length(v_gblocked), v_gblocked::text using errcode = '23514';
  end if;

  -- ---- 3. CAPABILITY BOUNDARY, FAIL CLOSED -------------------------------------------------
  if b.capability_dependency <> 'NONE' and v_ctx <> 'test' then
    raise exception 'fn_phase_d_handler_execute: step % depends on capability % (matched on the frozen required_action at: %) and no capability provider is available in Phase D. Paid inference is held until Phase E. Refusing rather than completing a business step from a fixture. (pd_capability_unavailable)',
      sr.step_id, b.capability_dependency, coalesce(nullif(b.capability_evidence,''),'(none)')
      using errcode = '23514';
  end if;

  -- ---- 4. PROVIDER BOUNDARY, FAIL CLOSED ---------------------------------------------------
  if b.provider_dependency <> 'NONE' and v_ctx <> 'test' then
    raise exception 'fn_phase_d_handler_execute: step % depends on external provider % which is disabled for the whole of Phase D. (pd_provider_disabled)',
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
    || jsonb_build_object('payload', coalesce(p_input->'effect_payload', v_inputs)));

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

commit;
