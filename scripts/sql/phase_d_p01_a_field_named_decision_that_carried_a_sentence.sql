-- P01. A FIELD NAMED `decision` THAT CARRIED A SENTENCE.
--
-- GATE 5 of the final independent acceptance audit, 24 Aug 2026:
--
--   schema_output_w17_s06 accepts decision = NOT_A_DECISION.
--   Every output schema declares exactly ONE enum domain and it is always `status`.
--   140 of 257 output schemas type a consequential verdict-shaped key as a bare string with no
--   domain — decision on 35 steps, verdict on 47, state_change on 58.
--
-- THE MEASUREMENT BEHIND IT, RE-DERIVED HERE. public.fn_phase_d_handler_execute builds every
-- output. Its DECISION_HANDLER arm sets
--     'decision', coalesce(s.required_output,'')
-- and its EXECUTION_HANDLER arm sets
--     'state_change', coalesce(s.required_output,'')
-- where s is public.phase_b_workflow_step. required_output is a PROSE SENTENCE — "Case decision
-- with required actions.", "Active customer account." So the field named `decision` never carried
-- a decision and the field named `state_change` never carried a state; both carried a restatement
-- of the artefact the step produces, which the `output` key already carries in full
-- (format('%s — %s', step_name, required_output)).
--
-- That is why no domain could be declared: there was nothing to declare a domain OVER. Constraining
-- the field without correcting the derivation would have produced the estate's worst defect shape —
-- a guard that fires when the system works.
--
-- WHAT THIS FILE DOES, IN ORDER:
--   1. a versioned semantic-domain registry, public.phase_d_output_domain_registry, DERIVED from
--      the frozen authorities rather than typed;
--   2. the two handler derivations corrected, so a real decision and a real state land in the
--      fields that name them;
--   3. enum_domains populated on public.phase_d_handler_schema FROM the registry;
--   4. public.fn_phase_d_schema_validate made to FAIL CLOSED on a consequential field the registry
--      classifies CLOSED_ENUM and the schema declares no domain for;
--   5. the contract board's probe fixtures moved onto the new domain, and a probe added for the
--      case the audit named.
--
-- WHAT IT DOES NOT DO. It does not weaken a business rule, a gate or a downstream service to
-- accommodate the new constraints. Every domain below is READ from an authority that already
-- refuses an out-of-domain value somewhere else in the estate; this file moves that refusal
-- earlier, to the declared step contract, which is the layer Gate 5 audits.

-- ================================================================================================
-- 1. THE SEMANTIC-DOMAIN REGISTRY
-- ================================================================================================
-- One row per (schema_id, field_name) for EVERY consequential field on all 514 schemas — not only
-- the closed ones. A field classified FREE_FORM or REFERENTIAL is recorded WITH ITS REASON, so the
-- denominator is the whole population and "this field has no domain" is a measured classification
-- rather than an absence. An absent row is not a permitted field: section 4 fails closed on one.

CREATE TABLE IF NOT EXISTS public.phase_d_output_domain_registry (
  schema_id                text        NOT NULL REFERENCES public.phase_d_handler_schema(schema_id) ON DELETE CASCADE,
  field_name               text        NOT NULL,
  step_id                  text        NOT NULL REFERENCES public.phase_b_workflow_step(step_id) ON DELETE CASCADE,
  schema_kind              text        NOT NULL,
  handler_id               text        NOT NULL,
  handler_version          text        NOT NULL,
  field_semantic_type      text        NOT NULL,
  allowed_values           text[],
  domain_source            text        NOT NULL,
  source_object            text,
  domain_version           integer     NOT NULL DEFAULT 1,
  source_digest            text        NOT NULL,
  valid_control_value      text,
  invalid_sentinel_value   text,
  runtime_validator_binding text       NOT NULL,
  recorded_at              timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (schema_id, field_name),
  CONSTRAINT phase_d_output_domain_registry_kind CHECK (
    schema_kind = ANY (ARRAY['input','output'])),
  CONSTRAINT phase_d_output_domain_registry_semantic_type CHECK (
    field_semantic_type = ANY (ARRAY[
      'CLOSED_ENUM',      -- a finite vocabulary an authority enumerates; enum_domains MUST carry it
      -- The semantics ARE a finite domain and the frozen contract does not state the vocabulary.
      -- This is not a softer CLOSED_ENUM: it is a disclosed hole with a change request against it.
      -- A value this session chose would be an invented domain value, which the founder's
      -- instruction of 24 Aug 2026 section 4 forbids as strongly as it forbids leaving a
      -- consequential field unconstrained. domain_source must name the change request.
      'CLOSED_ENUM_UNDEFINED',
      'REFERENTIAL',      -- membership of a registry that is read, not enumerated (role tokens)
      'NUMERIC',          -- a number with its own guard (denominator = 0 is refused separately)
      'STRUCTURED',       -- object/array; the scalar domain check cannot reach it
      'FREE_FORM'])),     -- prose or a formatted reference; forcing a vocabulary would invent one
  -- A disclosed hole must name the change request that discloses it, or it is just an absence.
  CONSTRAINT phase_d_output_domain_registry_undefined_names_its_request CHECK (
    field_semantic_type <> 'CLOSED_ENUM_UNDEFINED' OR domain_source ~ 'PBCR-[0-9]{3}'),
  -- A CLOSED_ENUM row must actually carry its vocabulary and both of its control values. This is
  -- the constraint that stops a field being registered as closed and left empty, which is how
  -- "absent input scores as satisfied" gets back in.
  CONSTRAINT phase_d_output_domain_registry_closed_is_complete CHECK (
    field_semantic_type <> 'CLOSED_ENUM'
    OR (allowed_values IS NOT NULL
        AND cardinality(allowed_values) >= 1
        AND nullif(btrim(valid_control_value), '')    IS NOT NULL
        AND nullif(btrim(invalid_sentinel_value), '') IS NOT NULL
        AND valid_control_value = ANY (allowed_values)
        AND NOT (invalid_sentinel_value = ANY (allowed_values)))),
  CONSTRAINT phase_d_output_domain_registry_open_has_no_values CHECK (
    field_semantic_type = 'CLOSED_ENUM' OR allowed_values IS NULL),
  CONSTRAINT phase_d_output_domain_registry_digest_shape CHECK (
    source_digest ~ '^[0-9a-f]{64}$'),
  CONSTRAINT phase_d_output_domain_registry_source_is_reasoned CHECK (
    length(btrim(domain_source)) >= 30)
);

COMMENT ON TABLE public.phase_d_output_domain_registry IS
  'P01 / Gate 5. The semantic domain of every consequential field on all 514 Phase D handler '
  'schemas, derived from the frozen authority that already enforces it elsewhere. '
  'phase_d_handler_schema.enum_domains is populated FROM this table and '
  'fn_phase_d_schema_validate fails closed on a CLOSED_ENUM field whose schema declares no domain.';

REVOKE ALL ON TABLE public.phase_d_output_domain_registry FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.phase_d_output_domain_registry TO service_role;

DROP TRIGGER IF EXISTS z00_kernel_truncate_guard ON public.phase_d_output_domain_registry;
CREATE TRIGGER z00_kernel_truncate_guard
  BEFORE TRUNCATE ON public.phase_d_output_domain_registry
  FOR EACH STATEMENT EXECUTE FUNCTION public.fn_kernel_truncate_guard();

-- ================================================================================================
-- 2. THE DIGEST OF THE AUTHORITY EACH DOMAIN IS READ FROM
-- ================================================================================================
-- A domain that cannot say what it was read from, at the version it was read, is a constant someone
-- typed. fn_phase_d_domain_source_digest returns the sha256 of the authority itself: the routine
-- body for a routine, the ordered content for a registry table.

CREATE OR REPLACE FUNCTION public.fn_phase_d_domain_source_digest(p_authority text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_catalog', 'pg_temp'
AS $function$
declare v text;
begin
  if p_authority like 'routine:%' then
    select pg_get_functiondef(p.oid) into v
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')'
           = substring(p_authority from 9);
    if v is null then
      raise exception 'fn_phase_d_domain_source_digest: no routine % — a domain may not cite an authority that does not exist (pd_domain_authority_absent)',
        substring(p_authority from 9) using errcode = '42883';
    end if;
    return encode(sha256(convert_to(v,'UTF8')),'hex');
  end if;

  if p_authority = 'table:public.phase_d_object_state_contract' then
    select string_agg(object_id || '|' || policy_family || '|' || array_to_string(allowed_states,',')
                      || '|' || initial_state, E'\n' order by object_id)
      into v from public.phase_d_object_state_contract;
  elsif p_authority = 'table:public.phase_b_handoff' then
    select string_agg(handoff_id || '|' || from_step_id || '|' || receiving_role_id, E'\n' order by handoff_id)
      into v from public.phase_b_handoff;
  elsif p_authority = 'table:public.phase_b_workflow_step' then
    select string_agg(step_id || '|' || accountable_role_id, E'\n' order by step_id)
      into v from public.phase_b_workflow_step;
  elsif p_authority = 'table:public.phase_d_step_effect' then
    select string_agg(step_id || '|' || expected_effect_type || '|' || coalesce(effect_object_id,''),
                      E'\n' order by step_id)
      into v from public.phase_d_step_effect;
  elsif p_authority = 'table:public.phase_b_business_object' then
    select string_agg(object_id, E'\n' order by object_id) into v from public.phase_b_business_object;
  else
    raise exception 'fn_phase_d_domain_source_digest: % is not a registered authority. A domain source is named from a closed list so that "where did this come from" always has an answer. (pd_domain_authority_unregistered)',
      p_authority using errcode = '22023';
  end if;

  if v is null then
    raise exception 'fn_phase_d_domain_source_digest: authority % is EMPTY. An empty authority hashes to a stable value and would silently certify an empty domain. (pd_domain_authority_empty)',
      p_authority using errcode = '22023';
  end if;
  return encode(sha256(convert_to(v,'UTF8')),'hex');
end
$function$;

REVOKE ALL ON FUNCTION public.fn_phase_d_domain_source_digest(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_phase_d_domain_source_digest(text) TO service_role;


-- ================================================================================================
-- 3. THE TWO HANDLER DERIVATIONS, CORRECTED
-- ================================================================================================
-- Produced by splicing the LIVE fn_phase_d_handler_execute body, anchored on two COMPLETE branch
-- expressions. 32,798 of its 33,565 bytes are carried verbatim; only the EXECUTION_HANDLER and
-- DECISION_HANDLER arms of the single case-expression that builds v_output move.

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

  -- ---- 0b. THE BRANCH PROBE'S HOLD --------------------------------------------------------
  -- Section 1 of the founder's ruling asks for BRANCH coverage of all 257 frozen steps. The frozen
  -- model is a linear chain: next_step_if_pass names the next step (or WORKFLOW_COMPLETE), and
  -- next_step_if_fail names one of three symbolic outcomes and never a step. So a step's fail edge
  -- is exercised by an ACTOR reporting failure on it, which requires the step to be OPEN.
  --
  -- MEASURED 23 Aug 2026: 249 of 257 steps are completed by this handler in the same statement the
  -- kernel opens them, so they are never open and no actor can ever take them. W18 is the extreme
  -- case -- all seven steps EXECUTED unaided, the run reaching completed inside
  -- fn_kernel_workflow_start, nothing left to fail or cancel. A handler that succeeds is the
  -- system working; it also means the fail edge of the frozen model is unreachable through the
  -- actor door, and an unexercised branch cannot be reported as covered.
  --
  -- This is the hold, and every part of it is deliberately narrow:
  --   * it acts only inside an open Phase D fixture context, which fn_phase_d_test_context_open
  --     grants for one operation inside one transaction that ends in raise exception;
  --   * it names ONE step, set by the caller at transaction level, and never a workflow or a class;
  --   * it refuses with its own code, pd_handler_held_for_branch_probe, which appears in
  --     phase_d_dispatch.refusal_code -- so no reader, and no deliverable, can mistake a held step
  --     for a handler that could not do its work;
  --   * it changes nothing else. The kernel then does exactly what it does for any refused
  --     dispatch: the step stays open and owned.
  --
  -- What the fail-branch case then proves is the KERNEL's edge for that step -- outcome fail moves
  -- the step to failed and the run to the step's declared failure_workflow_state, with no partial
  -- effect and no residue -- and NOT that the handler could have failed. Those are different
  -- claims and the coverage matrix records which one it has, per step.
  if nullif(btrim(coalesce(current_setting('app.phase_d_hold_step', true), '')), '') = sr.step_id
     and public.fn_phase_d_fixture_context() is not null then
    raise exception 'fn_phase_d_handler_execute: step % is held open by an audited Phase D branch probe; the handler declined so an actor can take the step (pd_handler_held_for_branch_probe)',
      sr.step_id using errcode = '23505';
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
           -- P01. A FIELD NAMED state_change THAT CARRIED A SENTENCE.
           -- This was coalesce(s.required_output,'') — the frozen step's PROSE description of the
           -- artefact it produces ("Active customer account."), not a state. Gate 5 of the final
           -- independent acceptance audit measured 58 output schemas typing it as a bare string
           -- with no domain, and no domain could be declared over a sentence.
           --
           -- The value now states the post-condition the effect is ABOUT to record, from the same
           -- two sources fn_phase_d_effect_produce already reads twelve lines below — the caller's
           -- stated state, then the committed catalogue — and falls back to the object's own
           -- declared initial_state rather than to fn_phase_d_object_write's hard-coded 'open'.
           -- Every arm is inside public.phase_d_object_state_contract.allowed_states by
           -- construction, which is the domain the output contract now declares, so a correct run
           -- can never be refused by the new constraint. A caller who supplies an out-of-domain
           -- effect_state is refused HERE, by the step's own contract, instead of sixteen lines
           -- later by z40_phase_d_object_record_contract.
           --
           -- The nine steps whose frozen effect declares that no object state moves say so with
           -- the explicit sentinel instead of borrowing a state they never write:
           -- 7 EXTERNAL_EFFECT_INTENT ("intent recorded as mock; no provider state moves and
           -- nothing is sent") and 2 CAPABILITY_REQUEST ("no state moves: the capability is
           -- unavailable in Phase D and the step refuses"). fn_phase_d_effect_produce's branches
           -- for those two types write no phase_d_object_record at all.
           'state_change', case
             when ec.expected_effect_type in ('EXTERNAL_EFFECT_INTENT','CAPABILITY_REQUEST')
               then 'NO_STATE_CHANGE'
             else coalesce(
                    nullif(btrim(coalesce(p_input->>'effect_state','')), ''),
                    (select fi.value #>> '{}'
                       from public.fn_phase_d_fixture_input(v_step_run,'EFFECT_PAYLOAD','state') fi),
                    (select c.initial_state from public.phase_d_object_state_contract c
                      where c.object_id = coalesce(ec.effect_object_id,
                              (select primary_object from public.phase_b_workflow w
                                where w.workflow_id = b.workflow_id))))
           end,
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
           -- P01. A FIELD NAMED decision THAT CARRIED A SENTENCE.
           -- This was coalesce(s.required_output,'') — the same prose the 'output' key twelve
           -- lines above already carries in full as format('%s — %s', step_name, required_output).
           -- So 'decision' was a duplicate of 'output' with the step name stripped, and
           -- schema_output_w17_s06 accepted decision = NOT_A_DECISION because there was no decision
           -- in the field for a domain to be about. Nothing downstream read it: no
           -- phase_d_object_write_map column_map names a 'decision' key on any of the 8 mapped
           -- objects, and the DECISION_HANDLER effect payload adds only decided_by and decided_at.
           --
           -- The value now comes from the caller, then from the committed catalogue, and only then
           -- falls back to the frozen prose. The fallback is deliberate and it is narrow: 33 of the
           -- 35 decision steps have NO decision vocabulary anywhere in the frozen estate — their
           -- required_action names an act, not a choice — and inventing one for them is what
           -- section 4 of the founder's instruction forbids. Those 33 declare no domain and are
           -- raised as PBCR-002; a step with no declared domain cannot be refused by one, so the
           -- prose fallback keeps them working unchanged until he decides.
           --
           -- The 2 that DO have an enforcing authority declare it, and for them the catalogue
           -- answers so the prose never reaches the field:
           --   W17-S06  approved | rejected                  CHECK phase_c_refund_decision_ck and
           --                                                  fn_kernel_refund_decision_record
           --   W08-S06  approved | rejected | changes_requested
           --                                                  CHECK phase_d_file_revision_verdict_ck
           'decision', coalesce(
              nullif(btrim(coalesce(p_input->>'decision','')), ''),
              (select fi.value #>> '{}'
                 from public.fn_phase_d_fixture_input(v_step_run,'EFFECT_PAYLOAD','decision') fi),
              coalesce(s.required_output,'')),
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
                 else '{}'::jsonb end
         -- L03. THE VERSION AND THE DIGEST THAT WERE ACCEPTED, FOR A STEP THAT RECORDS AN
         -- ACCEPTANCE. W09-S06's own frozen completion condition is "Displayed version, recorded
         -- version and document hash match", and the record it wrote carried none of the three:
         -- the payload was the workflow_record blob and nothing else. It went unseen because the
         -- fixture scenario built the acceptance itself, with the published pair on it, so every
         -- downstream read found the FIXTURE's record rather than the product's. Withhold that
         -- stage and W09-S07, S08 and S09 refuse on BR-025.
         -- The pair is the step's own resolved context -- the same value BR-025 has just judged at
         -- this step -- so the record states what was accepted and BR-025 can judge it again
         -- downstream. A step whose object is not a registered acceptance adds nothing, and a
         -- context that resolved neither key adds nothing.
         || case when exists (select 1 from public.phase_d_acceptance_document a
                               where a.object_id = ec.effect_object_id)
                 then jsonb_strip_nulls(jsonb_build_object(
                        'terms_version', p_input->'context'->>'terms_version',
                        'terms_hash',    p_input->'context'->>'terms_hash'))
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
end $function$;

REVOKE ALL ON FUNCTION public.fn_phase_d_handler_execute(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_phase_d_handler_execute(jsonb) TO service_role;

-- ================================================================================================
-- 4. THE REGISTRY, DERIVED. Nothing below is typed: every allowed_values array is READ from the
--    authority that already refuses an out-of-domain value somewhere else in the estate.
-- ================================================================================================

DELETE FROM public.phase_d_output_domain_registry;

-- ---- 4a. status — 257 output schemas. The frozen Phase C output authority. ----------------------
INSERT INTO public.phase_d_output_domain_registry
  (schema_id, field_name, step_id, schema_kind, handler_id, handler_version, field_semantic_type,
   allowed_values, domain_source, source_object, source_digest,
   valid_control_value, invalid_sentinel_value, runtime_validator_binding)
SELECT hs.schema_id, 'status', hs.step_id, hs.schema_kind, b.handler_id, b.handler_version,
       'CLOSED_ENUM',
       array['ok','success','completed','refused','empty'],
       'public.fn_phase_c_output_validate — the frozen Phase C output authority. Its operative line '
       'is: if coalesce(p_output->>''status'','''') not in (''ok'',''success'',''completed'',''refused'',''empty'') '
       'then valid := false. The declared domain is byte-identical to that list; it is not wider.',
       'fn_phase_c_output_validate',
       public.fn_phase_d_domain_source_digest('routine:fn_phase_c_output_validate(p_contract text, p_output jsonb)'),
       'completed', 'purple-elephant',
       'fn_phase_d_schema_validate section D46(c) over phase_d_handler_schema.enum_domains'
  FROM public.phase_d_handler_schema hs
  JOIN public.phase_d_handler_binding b ON b.step_id = hs.step_id
 WHERE hs.schema_kind = 'output' AND hs.required_keys @> array['status'];

-- ---- 4b. verdict — 47 REVIEW_HANDLER schemas. The frozen canonical review service. --------------
-- public.phase_c_frozen_subject registers fn_kernel_review_decide(p_input jsonb) under subject
-- internal_review_service. Its enforcing line, verbatim:
--   if v_decision not in ('approved','rejected','changes_requested') then raise exception …
-- The value reaches the field by exactly one path — fn_kernel_review_decide seals it into
-- phase_c_trace.evidence_refs as {"review_decision": …} and fn_phase_d_recorded_review reads that
-- key back — so the REVIEW_HANDLER branch carries it through verbatim and needs no change.
-- All three values belong in the domain: fn_phase_c_step_run_review_verdict_guard refuses a
-- completion on 'rejected'/'changes_requested' AFTER the output is built, so a domain of
-- ['approved'] alone would stop the handler faithfully reporting a rejection.
INSERT INTO public.phase_d_output_domain_registry
  (schema_id, field_name, step_id, schema_kind, handler_id, handler_version, field_semantic_type,
   allowed_values, domain_source, source_object, source_digest,
   valid_control_value, invalid_sentinel_value, runtime_validator_binding)
SELECT hs.schema_id, 'verdict', hs.step_id, hs.schema_kind, b.handler_id, b.handler_version,
       'CLOSED_ENUM',
       array['approved','rejected','changes_requested'],
       'public.fn_kernel_review_decide(p_input jsonb), registered frozen in '
       'public.phase_c_frozen_subject under subject internal_review_service. There is no CHECK '
       'constraint on any review-verdict column; the routine body IS the enforcement, and it is the '
       'single path by which a value reaches this field (sealed TRACE-ROLE-ACTION -> '
       'fn_phase_d_recorded_review). NOTE public.artifact_review carries a column also named '
       'verdict with the domain pass/fail/blocked — that is a different subject and NOT this authority.',
       'fn_kernel_review_decide',
       public.fn_phase_d_domain_source_digest('routine:fn_kernel_review_decide(p_input jsonb)'),
       'approved', 'NOT_A_VERDICT',
       'fn_phase_d_schema_validate section D46(c) over phase_d_handler_schema.enum_domains'
  FROM public.phase_d_handler_schema hs
  JOIN public.phase_d_handler_binding b ON b.step_id = hs.step_id
 WHERE hs.schema_kind = 'output' AND hs.required_keys @> array['verdict'];

-- ---- 4c. state_change — 58 EXECUTION_HANDLER schemas. -------------------------------------------
-- The authority is public.phase_d_object_state_contract.allowed_states for the object the handler's
-- own coalesce resolves, enforced at write time by BEFORE trigger z40_phase_d_object_record_contract
-- (fn_phase_d_object_record_contract), which raises pd_object_state_outside_domain. Measured: all
-- 58 resolved objects are present in the contract; 0 fall through to the workflow_id arm.
-- The 9 steps whose frozen effect declares no state movement carry the explicit sentinel.
INSERT INTO public.phase_d_output_domain_registry
  (schema_id, field_name, step_id, schema_kind, handler_id, handler_version, field_semantic_type,
   allowed_values, domain_source, source_object, source_digest,
   valid_control_value, invalid_sentinel_value, runtime_validator_binding)
SELECT hs.schema_id, 'state_change', hs.step_id, hs.schema_kind, b.handler_id, b.handler_version,
       'CLOSED_ENUM',
       CASE WHEN ec.expected_effect_type IN ('EXTERNAL_EFFECT_INTENT','CAPABILITY_REQUEST')
            THEN array['NO_STATE_CHANGE'] ELSE c.allowed_states END,
       CASE WHEN ec.expected_effect_type IN ('EXTERNAL_EFFECT_INTENT','CAPABILITY_REQUEST')
            THEN 'public.phase_d_step_effect.expected_effect_type = ' || ec.expected_effect_type
                 || ' — the frozen declaration that this step moves no object state ('
                 || coalesce(ec.expected_state_transition,'(no transition stated)')
                 || '). fn_phase_d_effect_produce''s branch for this type writes no '
                 || 'phase_d_object_record, so the explicit sentinel is the only honest value; '
                 || '''open'' is precisely the fabrication it blocks.'
            ELSE 'public.phase_d_object_state_contract.allowed_states for object '
                 || c.object_id || ' (policy family ' || c.policy_family
                 || '), enforced at write time by BEFORE trigger z40_phase_d_object_record_contract '
                 || 'on public.phase_d_object_record, which raises pd_object_state_outside_domain.'
       END,
       coalesce(c.object_id, ec.expected_effect_type),
       public.fn_phase_d_domain_source_digest('table:public.phase_d_object_state_contract'),
       CASE WHEN ec.expected_effect_type IN ('EXTERNAL_EFFECT_INTENT','CAPABILITY_REQUEST')
            THEN 'NO_STATE_CHANGE' ELSE c.initial_state END,
       CASE WHEN ec.expected_effect_type IN ('EXTERNAL_EFFECT_INTENT','CAPABILITY_REQUEST')
            THEN 'open' ELSE 'zz_not_a_state' END,
       'fn_phase_d_schema_validate section D46(c) over phase_d_handler_schema.enum_domains; '
       'corroborated at write time by z40_phase_d_object_record_contract'
  FROM public.phase_d_handler_schema hs
  JOIN public.phase_d_handler_binding b ON b.step_id = hs.step_id
  JOIN public.phase_b_workflow_step ws ON ws.step_id = hs.step_id
  LEFT JOIN public.phase_b_workflow w ON w.workflow_id = ws.workflow_id
  LEFT JOIN public.phase_d_step_effect ec ON ec.step_id = hs.step_id
  LEFT JOIN public.phase_d_object_state_contract c
         ON c.object_id = coalesce(ec.effect_object_id, w.primary_object)
 WHERE hs.schema_kind = 'output' AND hs.required_keys @> array['state_change'];

-- ---- 4d. target_object — 58 schemas. The 56-id business-object registry. ------------------------
-- Measured: public.phase_b_business_object, public.phase_d_business_object_binding and
-- public.phase_d_object_state_contract hold the SAME 56 ids (all four set-differences empty). Per
-- schema the handler's coalesce is deterministic, so the domain is the single resolved id.
INSERT INTO public.phase_d_output_domain_registry
  (schema_id, field_name, step_id, schema_kind, handler_id, handler_version, field_semantic_type,
   allowed_values, domain_source, source_object, source_digest,
   valid_control_value, invalid_sentinel_value, runtime_validator_binding)
SELECT hs.schema_id, 'target_object', hs.step_id, hs.schema_kind, b.handler_id, b.handler_version,
       'CLOSED_ENUM',
       array[coalesce(ec.effect_object_id, w.primary_object)],
       'public.phase_d_step_effect.effect_object_id for this step, else the frozen '
       'public.phase_b_workflow.primary_object of its workflow — the same coalesce the handler '
       'runs. Both resolve into the 56-id business-object registry held identically by '
       'public.phase_b_business_object, public.phase_d_business_object_binding and '
       'public.phase_d_object_state_contract.'
       || CASE WHEN ec.effect_object_id IS NULL
               THEN ' NOTE: this step''s frozen effect records object_resolution '
                    || coalesce(ec.object_resolution,'(none)')
                    || ', so the handler names an object the effect registry declined to name. '
                    || 'The domain records what the handler produces; that mismatch is raised '
                    || 'separately and is not resolved here.'
               ELSE '' END,
       coalesce(ec.effect_object_id, w.primary_object),
       public.fn_phase_d_domain_source_digest('table:public.phase_d_step_effect'),
       coalesce(ec.effect_object_id, w.primary_object), 'zz_not_an_object',
       'fn_phase_d_schema_validate section D46(c) over phase_d_handler_schema.enum_domains'
  FROM public.phase_d_handler_schema hs
  JOIN public.phase_d_handler_binding b ON b.step_id = hs.step_id
  JOIN public.phase_b_workflow_step ws ON ws.step_id = hs.step_id
  LEFT JOIN public.phase_b_workflow w ON w.workflow_id = ws.workflow_id
  LEFT JOIN public.phase_d_step_effect ec ON ec.step_id = hs.step_id
 WHERE hs.schema_kind = 'output' AND hs.required_keys @> array['target_object'];

-- ---- 4e. receiving_role_id — 25 HANDOFF_HANDLER schemas. ----------------------------------------
-- Measured: public.phase_b_handoff holds 159 rows with 76 distinct receiving_role_id and ALL 76 are
-- canonical role_ids in public.org_role — zero aliases, zero unresolvable; the 78 distinct
-- accountable_role_id values used as the frozen fallback are likewise all in org_role. The
-- derivation is deterministic per step, so the domain is the single producible role.
INSERT INTO public.phase_d_output_domain_registry
  (schema_id, field_name, step_id, schema_kind, handler_id, handler_version, field_semantic_type,
   allowed_values, domain_source, source_object, source_digest,
   valid_control_value, invalid_sentinel_value, runtime_validator_binding)
SELECT hs.schema_id, 'receiving_role_id', hs.step_id, hs.schema_kind, b.handler_id, b.handler_version,
       'CLOSED_ENUM',
       array[coalesce(h.receiving_role_id, ws.accountable_role_id)],
       CASE WHEN h.receiving_role_id IS NOT NULL
            THEN 'public.phase_b_handoff.receiving_role_id where from_step_id = ' || hs.step_id
                 || ' (frozen). The value is a canonical role_id in public.org_role.'
            ELSE 'no public.phase_b_handoff row names from_step_id = ' || hs.step_id
                 || ', so the handler falls back to the frozen '
                 || 'public.phase_b_workflow_step.accountable_role_id, which is likewise a '
                 || 'canonical role_id in public.org_role.'
       END,
       coalesce(h.receiving_role_id, ws.accountable_role_id),
       public.fn_phase_d_domain_source_digest('table:public.phase_b_handoff'),
       coalesce(h.receiving_role_id, ws.accountable_role_id), 'zz_not_a_role',
       'fn_phase_d_schema_validate section D46(c) over phase_d_handler_schema.enum_domains'
  FROM public.phase_d_handler_schema hs
  JOIN public.phase_d_handler_binding b ON b.step_id = hs.step_id
  JOIN public.phase_b_workflow_step ws ON ws.step_id = hs.step_id
  LEFT JOIN LATERAL (SELECT x.receiving_role_id FROM public.phase_b_handoff x
                      WHERE x.from_step_id = hs.step_id LIMIT 1) h ON true
 WHERE hs.schema_kind = 'output' AND hs.required_keys @> array['receiving_role_id'];

-- ---- 4f. method — 31 ANALYSIS_HANDLER schemas. A closed domain of one. --------------------------
-- The ANALYSIS_HANDLER branch of fn_phase_d_handler_execute sets a bare string literal and nothing
-- else in the 504-line body writes the key. A field with exactly one reachable value IS a closed
-- domain, and declaring it turns "the handler happens to produce this" into "the contract requires it".
INSERT INTO public.phase_d_output_domain_registry
  (schema_id, field_name, step_id, schema_kind, handler_id, handler_version, field_semantic_type,
   allowed_values, domain_source, source_object, source_digest,
   valid_control_value, invalid_sentinel_value, runtime_validator_binding)
SELECT hs.schema_id, 'method', hs.step_id, hs.schema_kind, b.handler_id, b.handler_version,
       'CLOSED_ENUM',
       array['deterministic reconciliation of the named inputs against the frozen step contract'],
       'public.fn_phase_d_handler_execute — its ANALYSIS_HANDLER branch sets ''method'' to a bare '
       'string literal and no other branch, coalesce or input path writes the key. Measured by '
       'reading the whole body: exactly one value is reachable.',
       'fn_phase_d_handler_execute',
       public.fn_phase_d_domain_source_digest('routine:fn_phase_d_handler_execute(p_input jsonb)'),
       'deterministic reconciliation of the named inputs against the frozen step contract',
       'zz_not_a_method',
       'fn_phase_d_schema_validate section D46(c) over phase_d_handler_schema.enum_domains'
  FROM public.phase_d_handler_schema hs
  JOIN public.phase_d_handler_binding b ON b.step_id = hs.step_id
 WHERE hs.schema_kind = 'output' AND hs.required_keys @> array['method'];

-- ---- 4g. decision — 35 DECISION_HANDLER schemas. TWO have an enforcing authority. ---------------
-- The two the estate can actually refuse an out-of-domain value for:
INSERT INTO public.phase_d_output_domain_registry
  (schema_id, field_name, step_id, schema_kind, handler_id, handler_version, field_semantic_type,
   allowed_values, domain_source, source_object, source_digest,
   valid_control_value, invalid_sentinel_value, runtime_validator_binding)
SELECT hs.schema_id, 'decision', hs.step_id, hs.schema_kind, b.handler_id, b.handler_version,
       'CLOSED_ENUM',
       d.vals, d.src, d.obj,
       public.fn_phase_d_domain_source_digest(d.digest_authority),
       d.ctl, d.bad,
       'fn_phase_d_schema_validate section D46(c) over phase_d_handler_schema.enum_domains; '
       'corroborated by the named CHECK constraint at the point the decision is recorded'
  FROM public.phase_d_handler_schema hs
  JOIN public.phase_d_handler_binding b ON b.step_id = hs.step_id
  JOIN (VALUES
    ('W17-S06', array['approved','rejected'],
     'CHECK phase_c_refund_decision_ck on public.phase_c_refund_decision — '
     '(decision = ANY (ARRAY[''approved'',''rejected''])) — enforced identically by name in '
     'public.fn_kernel_refund_decision_record: "decision must be approved or rejected, got %". '
     'The founder''s instruction of 24 Aug 2026 section 5 names this authority for this step '
     'explicitly. NOTE the frozen required_action names five outcomes (approve, reject, escalate, '
     'partially resolve, request further evidence); no table in the estate can record the other '
     'three, and the founder''s instruction directs this exact domain.',
     'phase_c_refund_decision', 'routine:fn_kernel_refund_decision_record(p_input jsonb)',
     'approved', 'NOT_A_DECISION'),
    ('W08-S06', array['approved','rejected','changes_requested'],
     'CHECK phase_d_file_revision_verdict_ck on public.phase_d_file_revision — '
     'reviewer_verdict = ANY (ARRAY[''approved'',''rejected'',''changes_requested'']) — the verdict '
     'domain for exactly the file-revision this step approves. Corroborated by BR-012, which '
     'requires phase_d_object_record.state = ''approved'' for supplier_safe_package.',
     'phase_d_file_revision', 'routine:fn_kernel_review_decide(p_input jsonb)',
     'approved', 'NOT_A_DECISION')
  ) AS d(step_id, vals, src, obj, digest_authority, ctl, bad) ON d.step_id = hs.step_id
 WHERE hs.schema_kind = 'output' AND hs.required_keys @> array['decision'];

-- The other 33: the frozen contract states NO decision vocabulary, and inventing one is what the
-- founder's instruction section 4 forbids ("invented generic domain values = 0"). 15 of them state
-- ALTERNATIVES in prose ("Approve, request correction, refuse, suspend or escalate the supplier")
-- without stating the tokens; 18 name an act with a single artefact outcome and no choice at all.
-- Both are recorded here with their measured status and raised as PBCR-002. Section 4 of the
-- instruction provides for exactly this: "a formal Phase B change request where the frozen contract
-- is genuinely undefined".
INSERT INTO public.phase_d_output_domain_registry
  (schema_id, field_name, step_id, schema_kind, handler_id, handler_version, field_semantic_type,
   allowed_values, domain_source, source_object, source_digest,
   valid_control_value, invalid_sentinel_value, runtime_validator_binding)
SELECT hs.schema_id, 'decision', hs.step_id, hs.schema_kind, b.handler_id, b.handler_version,
       'CLOSED_ENUM_UNDEFINED',
       NULL,
       'NO AUTHORITATIVE DOMAIN IN THE FROZEN ESTATE. Raised as PBCR-002, '
       'docs/phase-b/PHASE_B_CHANGE_REQUEST_PBCR-002.md. The frozen '
       'public.phase_b_workflow_step.required_action for this step is: '
       || coalesce(nullif(btrim(ws.required_action),''),'(none stated)')
       || ' — which '
       || CASE WHEN ws.required_action ~* '(^|[ ,])(approve|confirm|accept|set the|classify|issue|restore)'
                 AND ws.required_action ~* '( or |, )'
               THEN 'names alternatives in PROSE. The alternatives are frozen; their TOKEN SPELLING '
                    'is not, and a spelling this session chose would be an invented value in a '
                    'production contract.'
               ELSE 'names an act with a single artefact outcome and no alternatives at all. '
                    'Whether this schema should carry a decision key is itself the question '
                    'PBCR-002 puts to the founder.'
          END
       || ' Until he decides, the field declares no domain, so no correct run can be refused by '
       'one, and the derivation falls back to the frozen prose unchanged.',
       'phase_b_workflow_step.required_action',
       public.fn_phase_d_domain_source_digest('table:public.phase_b_workflow_step'),
       NULL, NULL,
       'NONE — declared undefined and disclosed. fn_phase_d_schema_validate still enforces the key '
       'is present, typed string and non-empty via required_keys, and the closed contract still '
       'refuses an invented key.'
  FROM public.phase_d_handler_schema hs
  JOIN public.phase_d_handler_binding b ON b.step_id = hs.step_id
  JOIN public.phase_b_workflow_step ws ON ws.step_id = hs.step_id
 WHERE hs.schema_kind = 'output' AND hs.required_keys @> array['decision']
   AND hs.step_id NOT IN ('W17-S06','W08-S06');

-- ---- 4h. THE REST OF THE POPULATION, CLASSIFIED. ------------------------------------------------
-- Every remaining consequential field on all 514 schemas, with its measured reason. An absent row
-- is not a permitted field: section 6 below fails closed on one. This is what makes the denominator
-- the whole population rather than the fields that happened to be easy.
INSERT INTO public.phase_d_output_domain_registry
  (schema_id, field_name, step_id, schema_kind, handler_id, handler_version, field_semantic_type,
   allowed_values, domain_source, source_object, source_digest,
   valid_control_value, invalid_sentinel_value, runtime_validator_binding)
SELECT hs.schema_id, k.key, hs.step_id, hs.schema_kind, b.handler_id, b.handler_version,
       cl.semantic_type, NULL, cl.reason, cl.src,
       public.fn_phase_d_domain_source_digest('routine:fn_phase_d_handler_execute(p_input jsonb)'),
       NULL, NULL, cl.binding
  FROM public.phase_d_handler_schema hs
  JOIN public.phase_d_handler_binding b ON b.step_id = hs.step_id
  CROSS JOIN LATERAL unnest(hs.required_keys || coalesce(hs.optional_keys,'{}')) AS k(key)
  CROSS JOIN LATERAL (SELECT
    CASE
      WHEN k.key = 'reviewer_role_id' THEN 'REFERENTIAL'
      WHEN k.key IN ('denominator','numerator') THEN 'NUMERIC'
      WHEN hs.field_types->>k.key IN ('object','array') THEN 'STRUCTURED'
      ELSE 'FREE_FORM'
    END AS semantic_type,
    CASE
      WHEN k.key = 'reviewer_role_id' THEN
        'REFERENTIAL, not enumerable, and already fail-closed. fn_kernel_review_decide stores the '
        'caller''s RAW token (which may be an alias) and fn_phase_d_recorded_review returns it raw, '
        'so an enum of canonical org_role.role_id would refuse a legitimate alias-named reviewer. '
        'Membership is checked instead by fn_kernel_reviewer_independent, which resolves the token '
        'through fn_phase_c_resolve_actor and returns false for anything that does not resolve — '
        'fn_phase_d_handler_execute then raises pd_rule_refused. An enum listing 176 role names '
        'would duplicate that check and go stale the next time a role is created; org_role is not '
        'a frozen subject.'
      WHEN k.key IN ('denominator','numerator') THEN
        'NUMERIC. Typed number by the schema. A denominator of 0 is refused separately and by name '
        'in fn_phase_d_handler_execute (pd_output_schema_invalid, "a ratio over nothing is not a '
        'measurement"), which is the consequential guard here; a vocabulary is not.'
      WHEN hs.field_types->>k.key IN ('object','array') THEN
        'STRUCTURED (' || (hs.field_types->>k.key) || '). fn_phase_d_schema_validate''s domain check '
        'compares p_payload->>k, which for an object or array returns the whole JSON serialization, '
        'so a scalar domain on this key could never match. Where a nested key DOES carry a finite '
        'vocabulary it is enforced at its own boundary: business_effect.effect_type by the 7-value '
        'CHECK on public.phase_d_step_effect.expected_effect_type, and capability_result.provider_mode '
        'by CHECK (provider_mode = ANY (ARRAY[''fixture'',''provider''])) on '
        'public.phase_d_capability_result, applied by fn_phase_d_capability_result_accept.'
      WHEN k.key IN ('formula','window','metric') THEN
        'FREE_FORM. A formula is an expression and a window is a time range; neither is a '
        'vocabulary. Exactly one value is producible for formula and window today because the '
        'committed catalogue holds one global row each — but that is a value the handler currently '
        'produces, not a value the frozen contract permits, and both carry the literal marker '
        'PHASE_D_FIXTURE_DO_NOT_PUBLISH. Freezing a fixture string into a production contract as '
        'the only legal value would be worse than leaving it referential. metric has NO catalogue '
        'row at all, so it always falls through to the frozen required_output prose.'
      WHEN k.key IN ('authorization_ref','authority_ref','source_ref') THEN
        'FREE_FORM. A formatted reference sentence built by format(), not a vocabulary — '
        'authorization_ref alone has 58 distinct values, one per schema. Forcing a domain here '
        'would re-state the format() call as data and go stale the moment a role is reassigned. '
        'fn_phase_d_schema_validate does membership testing only and cannot express "matches this '
        'shape and names a registered role".'
      ELSE
        'FREE_FORM. Built by fn_phase_d_handler_execute from the frozen registry as prose or as the '
        'caller''s own text: ' ||
        CASE k.key
          WHEN 'output' THEN 'format(''%s — %s'', step_name, required_output).'
          WHEN 'rationale' THEN 'coalesce(s.acceptance_criteria,'''').'
          WHEN 'closure_evidence' THEN 'coalesce(s.closure_criteria,'''').'
          WHEN 'acceptance_criteria' THEN 'coalesce(s.acceptance_criteria,'''').'
          ELSE 'a per-class expression with no finite value set.'
        END || ' A vocabulary forced onto prose is an invented domain.'
    END AS reason,
    CASE WHEN k.key = 'reviewer_role_id' THEN 'org_role via fn_phase_c_resolve_actor'
         ELSE 'fn_phase_d_handler_execute' END AS src,
    CASE
      WHEN k.key = 'reviewer_role_id' THEN
        'fn_kernel_reviewer_independent -> fn_phase_c_resolve_actor; refusal pd_rule_refused'
      WHEN k.key IN ('denominator','numerator') THEN
        'fn_phase_d_schema_validate declared type + the denominator-of-zero guard in fn_phase_d_handler_execute'
      ELSE
        'fn_phase_d_schema_validate: required-key presence, non-empty, declared type, and '
        'additional_properties=false'
    END AS binding
  ) cl
 WHERE NOT EXISTS (SELECT 1 FROM public.phase_d_output_domain_registry r
                    WHERE r.schema_id = hs.schema_id AND r.field_name = k.key);

-- ---- 4i. THE POPULATION MUST BE COMPLETE, MEASURED HERE AND NOT ASSERTED ------------------------
DO $$
declare v_fields bigint; v_rows bigint; v_closed bigint; v_undef bigint;
begin
  select count(*) into v_fields
    from public.phase_d_handler_schema hs,
         lateral unnest(hs.required_keys || coalesce(hs.optional_keys,'{}')) k;
  select count(*) into v_rows from public.phase_d_output_domain_registry;
  if v_fields <> v_rows then
    raise exception 'P01: % (schema, field) pairs exist across the 514 schemas and the domain registry holds %. A registry that does not cover its own population is the absent-input-scores-as-satisfied defect in a new place.',
      v_fields, v_rows using errcode = '22023';
  end if;
  select count(*) filter (where field_semantic_type = 'CLOSED_ENUM'),
         count(*) filter (where field_semantic_type = 'CLOSED_ENUM_UNDEFINED')
    into v_closed, v_undef from public.phase_d_output_domain_registry;
  raise notice 'P01 domain registry: % pairs, % CLOSED_ENUM, % CLOSED_ENUM_UNDEFINED (PBCR-002)',
    v_rows, v_closed, v_undef;
end $$;

-- ================================================================================================
-- 5. enum_domains ON THE 514 SCHEMAS, POPULATED FROM THE REGISTRY
-- ================================================================================================
-- The registry is the derivation with its provenance; enum_domains is the surface
-- fn_phase_d_schema_validate enforces. Section 6 makes the two unable to disagree.
UPDATE public.phase_d_handler_schema hs
   SET enum_domains = coalesce(
         (SELECT jsonb_object_agg(r.field_name, to_jsonb(r.allowed_values))
            FROM public.phase_d_output_domain_registry r
           WHERE r.schema_id = hs.schema_id
             AND r.field_semantic_type = 'CLOSED_ENUM'), '{}'::jsonb);

-- ================================================================================================
-- 6. THE VALIDATOR FAILS CLOSED ON AN UNKNOWN SEMANTIC DOMAIN
-- ================================================================================================
-- Two new refusals, both added AFTER the existing checks so no existing refusal changes:
--   (e) a required or optional key with NO row in the domain registry — an unregistered field is
--       not a permitted one;
--   (f) a key the registry classifies CLOSED_ENUM whose schema declares no domain for it — the
--       registry and the enforcement surface may not disagree.
-- The reason string of the successful branch is left byte-identical apart from the domain count it
-- already interpolated, which necessarily moves.

CREATE OR REPLACE FUNCTION public.fn_phase_d_schema_validate(p_schema_id text, p_payload jsonb)
 RETURNS TABLE(valid boolean, reason text, missing text[])
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  sc public.phase_d_handler_schema%rowtype;
  v_missing text[];
  v_empty   text[];
  v_untyped text[];
  v_wrong   text[];
  v_badenum text[];
  v_unknown text[];
  v_known   text[];
  v_nodomain text[];
  v_undeclared text[];
begin
  select * into sc from public.phase_d_handler_schema where schema_id = p_schema_id;
  if not found then
    valid := false;
    reason := format('unknown schema %L — fail closed', p_schema_id);
    missing := '{}'; return next; return;
  end if;

  -- An absent payload is a refusal, never an empty pass. pct(got, 0) returning 100 is the shape
  -- of defect this avoids: no evidence is not full evidence.
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    valid := false;
    reason := format('schema %s expects an object, got %s',
                     p_schema_id, coalesce(jsonb_typeof(p_payload),'null'));
    missing := sc.required_keys; return next; return;
  end if;

  select array_agg(k order by k) into v_missing
    from unnest(sc.required_keys) k where not (p_payload ? k);
  if v_missing is not null then
    valid := false;
    reason := format('schema %s: required keys missing [%s]',
                     p_schema_id, array_to_string(v_missing, ', '));
    missing := v_missing; return next; return;
  end if;

  -- A key present and empty is the same absence wearing a different hat.
  select array_agg(k order by k) into v_empty
    from unnest(sc.required_keys) k
   where jsonb_typeof(p_payload->k) = 'null'
      or (jsonb_typeof(p_payload->k) = 'string' and btrim(p_payload->>k) = '')
      or (jsonb_typeof(p_payload->k) = 'array'  and jsonb_array_length(p_payload->k) = 0)
      or (jsonb_typeof(p_payload->k) = 'object' and p_payload->k = '{}'::jsonb);
  if v_empty is not null then
    valid := false;
    reason := format('schema %s: required keys present but empty [%s]',
                     p_schema_id, array_to_string(v_empty, ', '));
    missing := v_empty; return next; return;
  end if;

  -- ---- D46 (a) A KEY WITH NO RECORDED TYPE IS A BROKEN SCHEMA, NOT A PERMITTED ONE --------------
  -- If field_types does not mention a key the schema requires, the schema itself is refused. The
  -- alternative — treating an unstated type as "anything goes" — is how a missing declaration reads
  -- as a satisfied one.
  select array_agg(k order by k) into v_untyped
    from unnest(sc.required_keys) k where not (sc.field_types ? k);
  if v_untyped is not null then
    valid := false;
    reason := format('schema %s is incomplete: no declared type for [%s]. An unstated type is not an unconstrained one.',
                     p_schema_id, array_to_string(v_untyped, ', '));
    missing := v_untyped; return next; return;
  end if;

  -- ---- P01 (e) A KEY WITH NO REGISTERED SEMANTIC DOMAIN IS A BROKEN SCHEMA ----------------------
  -- Same shape as D46(a), one layer up. Gate 5 of the final acceptance audit failed because 140
  -- consequential keys carried no domain and nothing said so; an unregistered key is now refused
  -- rather than silently treated as free-form. public.phase_d_output_domain_registry classifies
  -- EVERY field on all 514 schemas, including the ones it classifies FREE_FORM — so this fires only
  -- when a schema has gained a key the registry has not been rebuilt for.
  select array_agg(k order by k) into v_nodomain
    from unnest(sc.required_keys || coalesce(sc.optional_keys,'{}')) k
   where not exists (select 1 from public.phase_d_output_domain_registry r
                      where r.schema_id = p_schema_id and r.field_name = k);
  if v_nodomain is not null then
    valid := false;
    reason := format('schema %s declares [%s] and public.phase_d_output_domain_registry classifies no semantic domain for %s. An unknown semantic domain fails closed: a field nobody has classified is not a field everybody may fill.',
                     p_schema_id, array_to_string(v_nodomain, ', '),
                     case when cardinality(v_nodomain) = 1 then 'it' else 'them' end);
    missing := v_nodomain; return next; return;
  end if;

  -- ---- P01 (f) THE REGISTRY AND THE ENFORCEMENT SURFACE MAY NOT DISAGREE -----------------------
  -- A field the registry calls CLOSED_ENUM whose schema declares no domain for it would be an
  -- unenforced closed domain — the exact state Gate 5 measured, wearing a registry row as cover.
  select array_agg(k order by k) into v_undeclared
    from public.phase_d_output_domain_registry r, lateral (select r.field_name k) x
   where r.schema_id = p_schema_id
     and r.field_semantic_type = 'CLOSED_ENUM'
     and not (sc.enum_domains ? r.field_name);
  if v_undeclared is not null then
    valid := false;
    reason := format('schema %s: [%s] are registered CLOSED_ENUM and the schema declares no domain for them. The registry and enum_domains may not disagree; rebuild the schema from the registry.',
                     p_schema_id, array_to_string(v_undeclared, ', '));
    missing := v_undeclared; return next; return;
  end if;

  -- ---- D46 (b) DECLARED TYPES ------------------------------------------------------------------
  select array_agg(format('%s expected %s got %s', k, sc.field_types->>k, jsonb_typeof(p_payload->k))
                   order by k)
    into v_wrong
    from unnest(sc.required_keys || coalesce(sc.optional_keys,'{}')) k
   where p_payload ? k
     and coalesce(sc.field_types->>k,'unconstrained') <> 'unconstrained'
     and jsonb_typeof(p_payload->k) is distinct from (sc.field_types->>k);
  if v_wrong is not null then
    valid := false;
    reason := format('schema %s: wrong types [%s]', p_schema_id, array_to_string(v_wrong, '; '));
    missing := '{}'; return next; return;
  end if;

  -- ---- D46 (c) DECLARED DOMAINS ----------------------------------------------------------------
  select array_agg(format('%s=%L is not one of [%s]', k, p_payload->>k,
                          (select string_agg(d, ', ')
                             from jsonb_array_elements_text(sc.enum_domains->k) d))
                   order by k)
    into v_badenum
    from jsonb_object_keys(sc.enum_domains) k
   where p_payload ? k
     and not (sc.enum_domains->k @> to_jsonb(p_payload->>k));
  if v_badenum is not null then
    valid := false;
    reason := format('schema %s: outside the declared domain [%s]',
                     p_schema_id, array_to_string(v_badenum, '; '));
    missing := '{}'; return next; return;
  end if;

  -- ---- D46 (d) UNKNOWN KEYS, WHERE THE CONTRACT IS CLOSED --------------------------------------
  if not coalesce(sc.additional_properties, true) then
    v_known := sc.required_keys || coalesce(sc.optional_keys, '{}');
    select array_agg(k order by k) into v_unknown
      from jsonb_object_keys(p_payload) k where not (k = any (v_known));
    if v_unknown is not null then
      valid := false;
      reason := format('schema %s declares a closed contract and the payload carries [%s]',
                       p_schema_id, array_to_string(v_unknown, ', '));
      missing := '{}'; return next; return;
    end if;
  end if;

  valid := true;
  reason := format('payload satisfies %s v%s (%s keys, %s typed, %s domain(s), %s, source digest %s)',
                   p_schema_id, sc.schema_version, cardinality(sc.required_keys),
                   (select count(*) from jsonb_each_text(sc.field_types) t
                     where t.value <> 'unconstrained'),
                   (select count(*) from jsonb_object_keys(sc.enum_domains)),
                   case when coalesce(sc.additional_properties,true)
                        then 'open to further keys' else 'closed' end,
                   left(sc.source_digest,12));
  missing := '{}'; return next;
end
$function$;

REVOKE ALL ON FUNCTION public.fn_phase_d_schema_validate(text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_phase_d_schema_validate(text, jsonb) TO service_role;

-- ================================================================================================
-- 6b. PROBE BUILDERS — a payload DERIVED from the registry, never typed into the check it guards
-- ================================================================================================
-- 15 count literals inside fn_phase_b_invariants were the last instance of an expectation typed
-- into its own check. These two routines let the contract board and the domain test suite build a
-- conforming payload, and a payload wrong in exactly one field, from the registry itself.

CREATE OR REPLACE FUNCTION public.fn_phase_d_domain_probe_schema(p_field text)
 RETURNS text
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select r.schema_id from public.phase_d_output_domain_registry r
   where r.field_name = p_field and r.field_semantic_type = 'CLOSED_ENUM'
   order by r.step_id limit 1;
$function$;

CREATE OR REPLACE FUNCTION public.fn_phase_d_domain_probe_payload(
  p_schema_id text, p_field text, p_conforming boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare sc public.phase_d_handler_schema%rowtype; v jsonb := '{}'::jsonb; k text; r record;
begin
  select * into sc from public.phase_d_handler_schema where schema_id = p_schema_id;
  if not found then
    raise exception 'fn_phase_d_domain_probe_payload: no schema % (pd_domain_probe_unknown_schema)',
      coalesce(p_schema_id,'(null)') using errcode = '23503';
  end if;
  if not exists (select 1 from public.phase_d_output_domain_registry
                  where schema_id = p_schema_id and field_name = p_field
                    and field_semantic_type = 'CLOSED_ENUM') then
    raise exception 'fn_phase_d_domain_probe_payload: % is not a registered CLOSED_ENUM field on %. A probe that cannot name a domain proves nothing about one. (pd_domain_probe_field_not_closed)',
      p_field, p_schema_id using errcode = '22023';
  end if;

  foreach k in array sc.required_keys loop
    select * into r from public.phase_d_output_domain_registry
     where schema_id = p_schema_id and field_name = k;
    if k = p_field then
      v := v || jsonb_build_object(k, to_jsonb(case when p_conforming then r.valid_control_value
                                                   else r.invalid_sentinel_value end));
    elsif r.field_semantic_type = 'CLOSED_ENUM' then
      v := v || jsonb_build_object(k, to_jsonb(r.valid_control_value));
    else
      v := v || jsonb_build_object(k, case coalesce(sc.field_types->>k,'string')
                                        when 'array'  then jsonb_build_array('probe')
                                        when 'object' then jsonb_build_object('probe', true)
                                        when 'number' then to_jsonb(1)
                                        when 'boolean' then to_jsonb(true)
                                        else to_jsonb('probe'::text) end);
    end if;
  end loop;
  return v;
end
$function$;

REVOKE ALL ON FUNCTION public.fn_phase_d_domain_probe_schema(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_phase_d_domain_probe_payload(text, text, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_phase_d_domain_probe_schema(text) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_phase_d_domain_probe_payload(text, text, boolean) TO service_role;

-- ================================================================================================
-- 7. THE CONTRACT BOARD: FIXTURES MOVED, GUARD UNCHANGED, THREE PROBES ADDED
-- ================================================================================================
-- Two of its probes carried decision = "APPROVE" — a value nothing in the estate could record.
-- Those FIXTURES move onto the declared domain. No expectation changes. Added: the exact case the
-- audit named (decision = NOT_A_DECISION with a conforming status, so the refusal is attributable),
-- plus refuse/accept pairs for verdict and state_change built FROM the registry.

CREATE OR REPLACE FUNCTION public.fn_phase_d_contract_state()
 RETURNS TABLE(check_name text, expected text, actual text, ok boolean)
 LANGUAGE sql
 STABLE
AS $function$
  with p as (
    select 'schema_output_w17_s06'::text sid
  ),
  probe(nm, res) as (
    values
      ('wrong_types_are_refused',
       (select valid from public.fn_phase_d_schema_validate('schema_output_w17_s06',
         '{"status":12345,"output":true,"acceptance_assertions":"not-an-array","evidence_refs":99,
           "decision":[1,2],"rationale":{"x":1},"authority_ref":-1}'::jsonb))),
      ('out_of_domain_status_is_refused',
       (select valid from public.fn_phase_d_schema_validate('schema_output_w17_s06',
         '{"status":"purple-elephant","output":"o","acceptance_assertions":["a"],"evidence_refs":["e"],
           "decision":"NOT_A_DECISION","rationale":"r","authority_ref":"auth"}'::jsonb))),
      ('invented_keys_are_refused',
       (select valid from public.fn_phase_d_schema_validate('schema_output_w17_s06',
         '{"status":"ok","output":"o","acceptance_assertions":["a"],"evidence_refs":["e"],
           "decision":"approved","rationale":"r","authority_ref":"auth",
           "totally_invented_field":"x","refund_amount_aed":999999}'::jsonb))),
      ('a_string_zero_denominator_is_refused',
       (select valid from public.fn_phase_d_schema_validate('schema_output_w02_s08',
         (select jsonb_object_agg(k, case when k='denominator' then to_jsonb('0'::text)
                                          when k='numerator' then to_jsonb(1)
                                          when k='status' then to_jsonb('ok'::text)
                                          when k in ('acceptance_assertions','evidence_refs')
                                               then jsonb_build_array('x')
                                          else to_jsonb('x'::text) end)
            from unnest((select required_keys from public.phase_d_handler_schema
                          where schema_id='schema_output_w02_s08')) k)))),
      ('a_conforming_payload_is_accepted',
       (select valid from public.fn_phase_d_schema_validate('schema_output_w17_s06',
         '{"status":"completed","output":"o","acceptance_assertions":["a"],"evidence_refs":["e"],
           "decision":"approved","rationale":"r","authority_ref":"auth"}'::jsonb))),
      ('a_missing_required_key_is_still_refused',
       (select valid from public.fn_phase_d_schema_validate('schema_output_w17_s06',
         '{"status":"ok"}'::jsonb))),
      ('an_unknown_schema_is_still_refused',
       (select valid from public.fn_phase_d_schema_validate('schema_output_does_not_exist',
         '{"status":"ok"}'::jsonb))),
      -- P01 / GATE 5. THE CASE THE FINAL INDEPENDENT ACCEPTANCE AUDIT NAMED.
      -- Measured 24 Aug 2026: schema_output_w17_s06 ACCEPTED decision = NOT_A_DECISION, because
      -- every output schema declared exactly one enum domain and it was always status. The probe
      -- above (out_of_domain_status_is_refused) sent NOT_A_DECISION too, but alongside
      -- status=purple-elephant, so it could never distinguish which field caused the refusal. This
      -- one holds status conforming and moves only the decision.
      ('out_of_domain_decision_is_refused',
       (select valid from public.fn_phase_d_schema_validate('schema_output_w17_s06',
         '{"status":"completed","output":"o","acceptance_assertions":["a"],"evidence_refs":["e"],
           "decision":"NOT_A_DECISION","rationale":"r","authority_ref":"auth"}'::jsonb))),
      -- The same shape for the two other consequential domains Gate 5 measured, so a regression in
      -- any one of the three is a red row rather than a silent acceptance. Both payloads are BUILT
      -- FROM public.phase_d_output_domain_registry rather than typed here: every closed field takes
      -- its own registered valid_control_value, and only the field under test is moved to its
      -- registered invalid_sentinel_value. A literal typed into a probe is an expectation typed
      -- into the check it guards.
      ('out_of_domain_verdict_is_refused',
       (select valid from public.fn_phase_d_schema_validate(
          public.fn_phase_d_domain_probe_schema('verdict'),
          public.fn_phase_d_domain_probe_payload(
            public.fn_phase_d_domain_probe_schema('verdict'), 'verdict', false)))),
      ('a_conforming_verdict_is_accepted',
       (select valid from public.fn_phase_d_schema_validate(
          public.fn_phase_d_domain_probe_schema('verdict'),
          public.fn_phase_d_domain_probe_payload(
            public.fn_phase_d_domain_probe_schema('verdict'), 'verdict', true)))),
      ('out_of_domain_state_change_is_refused',
       (select valid from public.fn_phase_d_schema_validate(
          public.fn_phase_d_domain_probe_schema('state_change'),
          public.fn_phase_d_domain_probe_payload(
            public.fn_phase_d_domain_probe_schema('state_change'), 'state_change', false)))),
      ('a_conforming_state_change_is_accepted',
       (select valid from public.fn_phase_d_schema_validate(
          public.fn_phase_d_domain_probe_schema('state_change'),
          public.fn_phase_d_domain_probe_payload(
            public.fn_phase_d_domain_probe_schema('state_change'), 'state_change', true))))
  )
  select nm,
         case when nm like 'a_conforming%_is_accepted' then 'accepted' else 'refused' end,
         case when res then 'accepted' else 'refused' end,
         case when nm like 'a_conforming%_is_accepted' then res else not res end
    from probe
  union all
  select 'every_schema_types_every_required_key', '0',
         (select count(*)::text from public.phase_d_handler_schema sc
           where exists (select 1 from unnest(sc.required_keys) k where not (sc.field_types ? k))),
         (select count(*) from public.phase_d_handler_schema sc
           where exists (select 1 from unnest(sc.required_keys) k where not (sc.field_types ? k))) = 0
  union all
  select 'every_schema_carries_a_version', '514',
         (select count(*)::text from public.phase_d_handler_schema where schema_version >= 1),
         (select count(*) from public.phase_d_handler_schema where schema_version >= 1) = 514
  union all
  -- P01. EVERY FIELD ON EVERY SCHEMA CARRIES A CLASSIFIED SEMANTIC DOMAIN.
  -- The denominator is the whole population, not the fields that were easy. A field the registry
  -- does not classify is refused at validation time (fn_phase_d_schema_validate section P01(e)),
  -- so this row goes red before a payload ever reaches it.
  select 'every_schema_field_carries_a_registered_semantic_domain', '0',
         (select count(*)::text
            from public.phase_d_handler_schema hs,
                 lateral unnest(hs.required_keys || coalesce(hs.optional_keys,'{}')) k
           where not exists (select 1 from public.phase_d_output_domain_registry r
                              where r.schema_id = hs.schema_id and r.field_name = k))
         || ' unclassified of '
         || (select count(*)::text from public.phase_d_handler_schema hs,
                    lateral unnest(hs.required_keys || coalesce(hs.optional_keys,'{}')) k),
         (select count(*) from public.phase_d_handler_schema hs,
                 lateral unnest(hs.required_keys || coalesce(hs.optional_keys,'{}')) k
           where not exists (select 1 from public.phase_d_output_domain_registry r
                              where r.schema_id = hs.schema_id and r.field_name = k)) = 0
  union all
  -- P01. EVERY REGISTERED CLOSED DOMAIN IS ACTUALLY DECLARED ON ITS SCHEMA.
  -- The registry is the derivation; enum_domains is what fn_phase_d_schema_validate enforces. A
  -- CLOSED_ENUM row with no matching enum_domains entry is an unenforced closed domain — the exact
  -- state Gate 5 measured, wearing a registry row as cover.
  select 'every_registered_closed_domain_is_declared_on_its_schema', '0',
         (select count(*)::text from public.phase_d_output_domain_registry r
            join public.phase_d_handler_schema hs on hs.schema_id = r.schema_id
           where r.field_semantic_type = 'CLOSED_ENUM'
             and not (hs.enum_domains ? r.field_name))
         || ' undeclared of '
         || (select count(*)::text from public.phase_d_output_domain_registry
              where field_semantic_type = 'CLOSED_ENUM')
         || ' registered CLOSED_ENUM field(s); '
         || (select count(*)::text from public.phase_d_output_domain_registry
              where field_semantic_type = 'CLOSED_ENUM_UNDEFINED')
         || ' field(s) are registered CLOSED_ENUM_UNDEFINED and raised as PBCR-002 — their frozen '
         || 'contract states no vocabulary and one this session chose would be an invented value.',
         (select count(*) from public.phase_d_output_domain_registry r
            join public.phase_d_handler_schema hs on hs.schema_id = r.schema_id
           where r.field_semantic_type = 'CLOSED_ENUM'
             and not (hs.enum_domains ? r.field_name)) = 0;
$function$;

REVOKE ALL ON FUNCTION public.fn_phase_d_contract_state() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_phase_d_contract_state() TO service_role;
