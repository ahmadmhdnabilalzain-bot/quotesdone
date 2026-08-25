-- Q02 DOWN. RESTORE THE decision KEY ON THE SEVENTEEN, UNBIND W16-S04, AND RE-APPLY THE PREVIOUS
-- DECISION_HANDLER ARM.
--
-- NO TRANSACTION CONTROL. One implicit transaction under a simple-query batch; rehearsable.
--
-- APPLYING THIS RESTORES THE STATE THE FOUNDER'S INSTRUCTION OF 25 AUG NAMES AS A DEFECT: 35
-- decision fields, 2 with an enforced domain, 33 registered CLOSED_ENUM_UNDEFINED. It exists so Q02
-- is reversible, not because reverting is advisable.
--
-- THE REGISTRY ROWS ARE REGENERATED, NOT RETYPED. Their domain_source text is produced by the same
-- deterministic expression P01 used, reading the frozen public.phase_b_workflow_step.required_action
-- — so the seventeen rows this file writes are the seventeen rows Q02 deleted, and not a paraphrase
-- of them. If the frozen text had moved in between, the regenerated row would say so rather than
-- silently reproduce a stale sentence.

-- ================================================================================================
-- 1. THE SEVENTEEN — RESTORE THE KEY.

UPDATE public.phase_d_handler_schema hs
   SET required_keys  = hs.required_keys || array['decision'],
       field_types    = hs.field_types || jsonb_build_object('decision','string'),
       schema_version = greatest(hs.schema_version - 1, 1)
 WHERE hs.schema_kind = 'output'
   AND NOT (hs.required_keys @> array['decision'])
   AND hs.step_id IN ('W01-S04','W03-S01','W04-S05','W11-S04','W13-S03','W15-S05','W18-S05',
                      'W20-S01','W22-S01','W23-S02','W25-S02','W26-S02','W26-S08','W27-S06',
                      'W27-S09','W29-S02','W30-S03');

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
 WHERE hs.schema_kind = 'output'
   AND hs.step_id IN ('W01-S04','W03-S01','W04-S05','W11-S04','W13-S03','W15-S05','W18-S05',
                      'W20-S01','W22-S01','W23-S02','W25-S02','W26-S02','W26-S08','W27-S06',
                      'W27-S09','W29-S02','W30-S03')
ON CONFLICT (schema_id, field_name) DO NOTHING;

-- ================================================================================================
-- 2. W16-S04 — UNBIND.

UPDATE public.phase_d_handler_schema hs
   SET enum_domains   = hs.enum_domains - 'decision',
       schema_version = greatest(hs.schema_version - 1, 1)
 WHERE hs.schema_kind = 'output' AND hs.step_id = 'W16-S04';

UPDATE public.phase_d_output_domain_registry r
   SET field_semantic_type = 'CLOSED_ENUM_UNDEFINED',
       allowed_values = NULL,
       domain_source =
         'NO AUTHORITATIVE DOMAIN IN THE FROZEN ESTATE. Raised as PBCR-002, '
         'docs/phase-b/PHASE_B_CHANGE_REQUEST_PBCR-002.md. The frozen '
         'public.phase_b_workflow_step.required_action for this step is: '
         || (SELECT coalesce(nullif(btrim(ws.required_action),''),'(none stated)')
               FROM public.phase_b_workflow_step ws WHERE ws.step_id = 'W16-S04')
         || ' — which names an act with a single artefact outcome and no alternatives at all. '
            'Whether this schema should carry a decision key is itself the question PBCR-002 puts '
            'to the founder. Until he decides, the field declares no domain, so no correct run can '
            'be refused by one, and the derivation falls back to the frozen prose unchanged.',
       source_object = 'phase_b_workflow_step.required_action',
       domain_version = 1,
       source_digest = public.fn_phase_d_domain_source_digest('table:public.phase_b_workflow_step'),
       valid_control_value = NULL,
       invalid_sentinel_value = NULL,
       runtime_validator_binding =
         'NONE — declared undefined and disclosed. fn_phase_d_schema_validate still enforces the '
         'key is present, typed string and non-empty via required_keys, and the closed contract '
         'still refuses an invented key.',
       recorded_at = now()
 WHERE r.step_id = 'W16-S04' AND r.field_name = 'decision' AND r.schema_kind = 'output';

DELETE FROM public.phase_d_fixture_catalogue WHERE fixture_id = 'PDF-4108';

-- ================================================================================================
-- 3. THE HANDLER — RE-APPLY THE ARM THAT ALWAYS EMITS decision.
--
-- Read out of production with pg_get_functiondef before Q02 ran. Byte-identical to that definition.

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
           -- P04. THE FALLBACK WAS A RUNTIME TOKEN, NOT A FROZEN ROLE.
           -- 17 of the 25 handoff steps resolve from public.phase_b_handoff, which is frozen and
           -- always canonical. The other 8 — W04-S06, W07-S07, W08-S05, W08-S07, W09-S08, W12-S07,
           -- W14-S06, W25-S07 — have no handoff row and fell back to sr.accountable_role_id, where
           -- sr is public.phase_c_workflow_step_run: a RUNTIME row whose accountable_role_id
           -- fn_kernel_open_step takes from the caller as owner_role_id, validates only with
           -- fn_phase_c_actor_may_own, and stores VERBATIM. That predicate returns true for an
           -- ALIAS — measured true for 'cs_onboarding', 'moderation_specialist' and
           -- 'Content Moderation Reviewer' — and public.org_role_alias holds 324 aliases over 171
           -- roles, with 20 across the 7 roles behind those 8 steps. phase_c_workflow_step_run
           -- carries no foreign key on the column either.
           --
           -- So P01's per-step domain would have refused a run opened under any registered alias of
           -- the very role it names: fn_phase_d_schema_validate('schema_output_w04_s06', …) returns
           -- "receiving_role_id='cs_onboarding' is not one of [customer_onboarding]". That is a
           -- guard firing when the system works, and the fix is to canonicalise the value rather
           -- than to widen the domain to 324 spellings or drop it.
           --
           -- fn_phase_c_resolve_actor is the estate's canonical resolver and the kernel's own
           -- progression path already uses it; this makes the handler agree with the kernel.
           'receiving_role_id', coalesce(
              (select h.receiving_role_id from public.phase_b_handoff h
                where h.from_step_id = sr.step_id limit 1),
              (select ra.role_id from public.fn_phase_c_resolve_actor(sr.accountable_role_id) ra),
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
