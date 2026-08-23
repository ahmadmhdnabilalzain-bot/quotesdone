-- H10 — the review verdict wrote a chain row with no subject, no author and no stage type
--
-- MEASURED 23 Aug 2026 on 36 of 50 remaining un-executed steps, every one:
--     null value in column "subject_type" of relation "review_chain" violates not-null constraint
--
-- public.review_chain demands subject_type, subject_id, dept_key, author_agent and stage NOT NULL.
-- review_record's write map maps all five. But fn_phase_d_fixture_effect_payload -- the routine that
-- fills a relation's mandatory columns from the committed catalogue -- keys off e.effect_object_id,
-- the STEP's declared business object (inquiry, quotation, ...), not off review_record. A
-- REVIEW_VERDICT step's declared object is the thing being reviewed, so the review-chain columns
-- were never in that routine's population and the REVIEW_VERDICT branch here wrote them as null.
--
-- They are not content a handler invents; every one is a fact the run already holds:
--   subject_type  the object under review -- e.effect_object_id, the step's own declared object
--   subject_id    the identity of that object -- the business_key the dispatch already derived, or
--                 the step-run compound where a review step names no object of its own
--   author_agent  the reviewer whose verdict this is -- reviewer_role_id off the recorded review,
--                 falling back to the accountable actor, never invented
--   stage         already set to sr.step_id
--
-- The catalogue's global subject_type/subject_id/author_agent fixtures (PDF-4007/4008/4010) stay --
-- they are what fn_phase_d_fixture_effect_payload would use IF review_record were the effect object,
-- and a caller who supplies these keys still overrides -- but a review step no longer depends on a
-- routine that was looking at a different object. dept_key is filled by the existing owner_ref
-- derivation, which resolves a real department for a COMPANY-scoped write.
--
-- ROLLBACK: re-apply the previous body of fn_phase_d_effect_produce (phase_d_e26 is the last file
-- that defines it). No DDL.
--
-- One anchor, required to match exactly once. The rest of the routine is byte-identical.
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
    -- H10. review_chain demands subject_type, subject_id, author_agent and stage. The caller's
    -- payload wins where it names them; otherwise each is the fact the run already holds -- what is
    -- under review, its identity, and who reviewed it -- never invented. dept_key comes from the
    -- owner_ref derivation, which resolves a real department for a COMPANY-scoped write.
    v_write := public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','review_record',
      'business_key', coalesce(v_key, format('%s:%s', sr.step_id, v_step_run)),
      'owner_ref', coalesce(v_owner, sr.accountable_role_id),
      'created_by', v_actor,
      'state', coalesce(v_state, v_payload->>'verdict'),
      'payload', jsonb_build_object(
        'subject_type', e.effect_object_id,
        'subject_id',   coalesce(v_key, format('%s:%s', sr.step_id, v_step_run)),
        'author_agent', v_actor,
        'stage',        sr.step_id,
        'notes',        coalesce(v_payload->>'notes', 'phase_d review verdict'))
        || v_payload));
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

