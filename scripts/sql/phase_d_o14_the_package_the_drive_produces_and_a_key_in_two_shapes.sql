-- O14. THE PACKAGE THE DRIVE PRODUCES, AND A REVISION KEY WRITTEN IN TWO SHAPES.
--
-- O11 gave the FIXTURE FACTORY's supplier-safe package a file set. Measured after it, inside a W08
-- scenario: the factory creates NO supplier_safe_package at all for W08 —
--
--   object rows: (none) | revisions: (none) | scenario_record: quotation_revision=cd93f862-…
--
-- The package GATE-013 judges at W08-S02 is produced by the DRIVE, at W08-S01, through
-- fn_phase_d_effect_produce. So the hook was in the right shape and the wrong place: the file set
-- has to arrive with the package whoever creates it, and inside a Phase D test context that is the
-- effect producer.
--
-- IT IS SCOPED TO THE TEST CONTEXT, and that boundary is the whole of its safety. Guarded on
-- public.fn_phase_d_fixture_context() being non-null, so no production write ever gains a file
-- revision it did not earn. In production a supplier-safe package that names no file is refused by
-- BR-012 and GATE-013 exactly as it should be — the estate has no file-production path yet, and
-- that absence stays visible rather than being papered over by a default.
--
-- AND BR-018 HAD THE SAME KEY PROBLEM GATE-013 HAD. fn_phase_d_step_context resolves
-- quote_revision_ref to the object record's canonical identity — the RECORD ID — and
-- fn_phase_d_quote_original_intact looked it up by business_key:
--
--   BR-018: '550609' is not a live quotation_revision record
--
-- which was true of the name it was given and false of the row it was about. That is the third
-- instance in this session of one key written in two shapes; the predicate now resolves both, the
-- same way O13 taught the package resolver to.

CREATE OR REPLACE FUNCTION public.fn_phase_d_quote_original_intact(p_revision_ref text)
 RETURNS TABLE(intact boolean, refusal_code text, reason text, normalisations bigint)
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_live text; v_n bigint; v_bad bigint; v_ref text; v_key text;
begin
  v_ref := btrim(coalesce(p_revision_ref,''));
  if v_ref = '' then
    intact := false; refusal_code := 'pd_quote_revision_not_named';
    reason := 'No supplier revision named. Nothing can be certified unedited against nothing.';
    normalisations := 0; return next; return;
  end if;

  -- THE SAME KEY IN TWO SHAPES. A caller holding the record id and a caller holding the business
  -- key are asking about one row, and a predicate that knows only one of them invents a hole.
  select o.business_key,
         encode(extensions.digest(convert_to(o.payload::text, 'UTF8'), 'sha256'), 'hex')
    into v_key, v_live
    from public.phase_d_object_record o
   where o.object_id = 'quotation_revision' and o.superseded_by is null
     and (o.business_key = v_ref
          or o.record_id::text = v_ref
          or 'quotation_revision:' || o.business_key = v_ref)
   order by o.record_id desc limit 1;

  if v_live is null then
    intact := false; refusal_code := 'pd_quote_revision_not_named';
    reason := format('%L resolves to no live quotation_revision record, by business key or by record id.', p_revision_ref);
    normalisations := 0; return next; return;
  end if;

  -- Normalisations may cite either shape too, so both are counted.
  select count(*), count(*) filter (where n.source_payload_sha256 is distinct from v_live)
    into v_n, v_bad
    from public.phase_d_quote_normalisation n
   where n.source_revision_ref in (v_key, v_ref) and n.superseded_by is null;
  normalisations := v_n;

  if v_bad > 0 then
    intact := false; refusal_code := 'pd_quote_original_overwritten';
    reason := format('%s of %s live normalisation(s) of %s were derived from a payload that hashes to something other than the revision''s current %s. Either the original was edited after normalisation, or the projection is describing a revision that no longer exists.',
                     v_bad, v_n, v_key, left(v_live, 12));
    return next; return;
  end if;

  intact := true; refusal_code := null;
  reason := format('%s is unedited at %s and carries %s live normalised projection(s), none of which restates a supplier-authored field.',
                   v_key, left(v_live, 12), v_n);
  return next;
end $function$;

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
  v_parent_col text;    -- K02: the parent identity the object's binding declares
  v_parent_src text;    -- K02: the payload key the write map reads it from
  v_parent_val jsonb;   -- K02: what the step context resolves for it
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

  -- ---- K02. THE PARENT THE OBJECT DECLARES -------------------------------------------------
  -- public.phase_d_object_write skips a mapped column whose source key the payload does not carry,
  -- and fn_phase_d_fixture_effect_payload only fills columns the RELATION demands. A parent column
  -- that is nullable demands nothing, so supplier_assignment was written with no inquiry_id and a
  -- BEFORE trigger dropped the row. The object's own binding already names its parent; that is read
  -- here, and the value comes from the step context, which resolves an identity from the row it
  -- names. Nothing is invented and no constant is used: an identity is never a fixture.
  select bb.parent_identity, wm.column_map->>bb.parent_identity
    into v_parent_col, v_parent_src
    from public.phase_d_business_object_binding bb
    join public.phase_d_object_write_map wm on wm.object_id = bb.object_id
   where bb.object_id = e.effect_object_id
     and coalesce(btrim(bb.parent_identity),'') <> ''
     and wm.column_map ? bb.parent_identity;
  if v_parent_src is not null
     and v_parent_src not in ('business_key','owner_ref','state')
     and (not (v_payload ? v_parent_src) or v_payload->v_parent_src = 'null'::jsonb) then
    v_parent_val := (public.fn_phase_d_step_context(v_step_run))->'context'->v_parent_src;
    if v_parent_val is not null and v_parent_val <> 'null'::jsonb then
      v_payload := v_payload || jsonb_build_object(v_parent_src, v_parent_val);
    end if;
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

    -- O14. A SUPPLIER-SAFE PACKAGE ARRIVES WITH ITS FILE SET, INSIDE A TEST CONTEXT AND NOWHERE ELSE.
    -- BR-012 and GATE-013 now require every live revision of a package to be redaction-approved and
    -- metadata-clean, and a package naming no file is refused. In production that refusal is
    -- correct and stays: this estate has no path that produces a supplier-facing file set, and that
    -- absence must remain visible rather than be defaulted away. Inside a Phase D fixture context
    -- there is no such path either, so the harness supplies the one thing it can honestly supply --
    -- a revision pointing at COMMITTED bytes this estate has actually scanned and found clean.
    -- The guard is fn_phase_d_fixture_context(), which is an hmac over txid_current() minted only
    -- against an approved audited operation; it is not a GUC a caller can set.
    if e.effect_object_id = 'supplier_safe_package'
       and public.fn_phase_d_fixture_context() is not null then
      perform public.fn_phase_d_fixture_file_revision(v_key);
    end if;
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
end $function$;
