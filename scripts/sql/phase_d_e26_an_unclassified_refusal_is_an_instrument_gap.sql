-- E26 — an unclassified refusal is an instrument gap
--
-- E25 stopped the dispatch withholding business_key and owner_ref. Two steps promptly got further
-- than any step ever had — past every rule, past every gate, past fn_phase_d_effect_produce's
-- owner/key check — and reached the actual write to the business relation, where they failed:
--
--   W21-S01, W21-S06:  null value in column "kind" of relation "opportunity"
--                      violates not-null constraint   (SQLSTATE 23502)
--
-- That is a real and rather interesting refusal, and it was being recorded as `pd_unclassified`,
-- which reads like a bug in the dispatch rather than what it is: THE PAYLOAD CARRIES AN IDENTITY
-- FOR THE RECORD BUT NOT ITS CONTENT. E25 could derive who owns an opportunity and what to call it,
-- because the frozen registry answers both. It cannot derive what KIND of opportunity it is; that is
-- a judgement, and the capability that would make it is held until Phase E. The boundary has moved
-- from "the caller withheld two fields it already knew" to "a business record needs business
-- content", which is a smaller and a much more honest place for it to sit.
--
-- Five SQLSTATEs that can only come from the target relation are now named. A raised Phase D or
-- kernel code still wins the match; this only classifies what previously fell through to
-- 'pd_unclassified', so nothing that was already named changes.
--
-- CREATE OR REPLACE preserves the ACL.

CREATE OR REPLACE FUNCTION public.fn_phase_d_dispatch_step(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  sr public.phase_c_workflow_step_run%rowtype;
  v_step_run bigint := nullif(p_input->>'step_run_id','')::bigint;
  v_actor    text   := nullif(btrim(coalesce(p_input->>'actor_role_id','')),'');
  v_kind     text   := coalesce(nullif(btrim(p_input->>'opened_by_kind'),''),'(unstated)');
  v_ref      text   := coalesce(nullif(btrim(p_input->>'opened_by_ref'),''),'(unstated)');
  v_idem     text   := coalesce(nullif(btrim(p_input->>'idempotency_key'),''),'');
  v_wf       text;
  v_on       text;
  v_depth    int;
  v_in       jsonb;
  v_cx       jsonb;
  v_res      jsonb;
  v_unres    text[];
  v_err      text;
  v_bkey     text;   -- E25
  v_owner    text;   -- E25
  v_scope    text;   -- E25
  v_code     text;
begin
  if v_step_run is null or v_actor is null then
    raise exception 'fn_phase_d_dispatch_step: step_run_id and actor_role_id are required (got %, %)',
      coalesce(v_step_run::text,'(null)'), coalesce(v_actor,'(null)') using errcode = '22023';
  end if;

  select * into sr from public.phase_c_workflow_step_run where step_run_id = v_step_run;
  if not found then
    raise exception 'fn_phase_d_dispatch_step: no step run %', v_step_run using errcode = '23503';
  end if;

  if not exists (select 1 from public.phase_d_handler_binding hb where hb.step_id = sr.step_id)
     or not exists (select 1 from public.phase_d_step_effect se where se.step_id = sr.step_id) then
    return jsonb_build_object('dispatched', false, 'outcome', 'NO_BINDING', 'step_id', sr.step_id);
  end if;

  select b2.workflow_id into v_wf from public.phase_d_handler_binding b2 where b2.step_id = sr.step_id;
  if v_idem = '' then v_idem := 'kernel|' || sr.run_id || '|' || sr.step_id; end if;

  v_on    := lower(coalesce(nullif(btrim(current_setting('app.phase_d_dispatch', true)),''), 'on'));
  v_depth := coalesce(nullif(btrim(current_setting('app.phase_d_dispatch_depth', true)),'')::int, 0);

  if v_on = 'off' then
    insert into public.phase_d_dispatch
      (step_run_id, run_id, step_id, workflow_id, opened_by_kind, opened_by_ref, actor_role_id,
       outcome, refusal_code, reason, dispatch_depth)
    values (v_step_run, sr.run_id, sr.step_id, v_wf, v_kind, v_ref, v_actor,
            'DISPATCH_OFF', 'pd_dispatch_off',
            'app.phase_d_dispatch is off for this transaction', v_depth);
    return jsonb_build_object('dispatched', false, 'outcome', 'DISPATCH_OFF');
  end if;

  if v_depth >= 64 then
    insert into public.phase_d_dispatch
      (step_run_id, run_id, step_id, workflow_id, opened_by_kind, opened_by_ref, actor_role_id,
       outcome, refusal_code, reason, dispatch_depth)
    values (v_step_run, sr.run_id, sr.step_id, v_wf, v_kind, v_ref, v_actor,
            'DEPTH_LIMIT', 'pd_dispatch_depth_limit',
            format('dispatch depth %s reached at step %s', v_depth, sr.step_id), v_depth);
    return jsonb_build_object('dispatched', false, 'outcome', 'DEPTH_LIMIT', 'depth', v_depth);
  end if;

  perform set_config('app.phase_d_dispatch_depth', (v_depth + 1)::text, true);

  begin
    v_in := public.fn_phase_d_step_inputs(v_step_run);
    select array_agg(x) into v_unres
      from jsonb_array_elements_text(coalesce(v_in->'unresolved','[]'::jsonb)) x;
    v_unres := coalesce(v_unres, '{}');

    if cardinality(v_unres) > 0 then
      insert into public.phase_d_dispatch
        (step_run_id, run_id, step_id, workflow_id, opened_by_kind, opened_by_ref, actor_role_id,
         outcome, refusal_code, reason, unresolved_keys, inputs_provenance, dispatch_depth)
      values (v_step_run, sr.run_id, sr.step_id, v_wf, v_kind, v_ref, v_actor,
              'INPUTS_UNRESOLVED', 'pd_input_unresolved',
              format('%s of the %s declared input keys resolve from no real source: %s',
                     cardinality(v_unres),
                     jsonb_array_length(coalesce(v_in->'declared_keys','[]'::jsonb)),
                     array_to_string(v_unres, ', ')),
              v_unres, coalesce(v_in->'provenance','{}'::jsonb), v_depth);
      perform set_config('app.phase_d_dispatch_depth', v_depth::text, true);
      return jsonb_build_object('dispatched', false, 'outcome', 'INPUTS_UNRESOLVED',
                                'unresolved', to_jsonb(v_unres));
    end if;

    -- D37. The same treatment for what the RULES and GATES read. Unresolved keys are not supplied,
    -- so a rule that needs one refuses instead of passing on a placeholder.
    v_cx := public.fn_phase_d_step_context(v_step_run);

    -- E25. THE DISPATCH WITHHELD THE TWO FIELDS THE WRITE SERVICE REQUIRES, AND IT KNEW BOTH.
    --
    -- fn_phase_d_effect_produce raises pd_effect_owner_or_key_missing for DOMAIN_MUTATION and
    -- VERSIONED_ARTIFACT unless the CALL names business_key and owner_ref. That is the right
    -- behaviour for the routine -- a record written under an owner it chose for itself would be the
    -- auto-vivified account defect in a new place -- but the kernel dispatch passed neither and had
    -- no branch that could. The R3 independent acceptance measured the consequence: 125 of 257 steps
    -- structurally excluded before any rule was consulted, and the only two steps that executed were
    -- KERNEL_ONLY_TRANSITION ones that write no business object at all.
    --
    -- Neither field is invented here. Both are READ, and where they cannot be read the step still
    -- refuses:
    --
    --   owner_ref  COMPANY-scoped object -> phase_c_workflow_step_run.accountable_role_id, which is
    --              the frozen registry's own answer to who is accountable for this step. Not chosen.
    --              CUSTOMER- or SUPPLIER-scoped -> the owner column of the run's OWN business row,
    --              and null when no such row exists. A customer is never conjured to own a record.
    --
    --   business_key  the run's business_object_id, and ONLY when it actually carried the
    --              '<object>:' prefix of the object this step writes -- 'inquiry:<uuid>' is an
    --              identity, 'outbox:195' and a probe label are not. fn_phase_d_step_context reports
    --              key_is_prefixed for exactly this decision.
    --
    -- jsonb_strip_nulls means an underivable field is ABSENT rather than null, so the write service
    -- sees precisely what it saw before and refuses in precisely the same way.
    v_scope := v_cx#>>'{business_object,ownership_scope}';
    if coalesce((v_cx#>>'{business_object,key_is_prefixed}')::boolean, false) then
      v_bkey := nullif(btrim(coalesce(v_cx#>>'{business_object,object_key}','')),'');
    end if;
    v_owner := nullif(btrim(coalesce(v_cx#>>'{business_object,row_owner_ref}','')),'');
    if v_owner is null and coalesce(v_scope,'COMPANY') = 'COMPANY' then
      v_owner := nullif(btrim(coalesce(sr.accountable_role_id,'')),'');
    end if;

    v_res := public.fn_phase_d_handler_execute(jsonb_build_object(
      'step_run_id',       v_step_run,
      'actor_role_id',     v_actor,
      'idempotency_key',   v_idem || '|phase_d',
      'inputs',            v_in->'inputs',
      'context',           v_cx->'context',
      'gate_evidence',     v_cx->'context',
      'execution_context', 'production',
      'correlation_id',    p_input->>'correlation_id',
      'causation_id',      'kernel_dispatch:' || v_kind || ':' || v_ref)
      || jsonb_strip_nulls(jsonb_build_object(
      'business_key',      v_bkey,
      'owner_ref',         v_owner)));

    insert into public.phase_d_dispatch
      (step_run_id, run_id, step_id, workflow_id, opened_by_kind, opened_by_ref, actor_role_id,
       outcome, inputs_provenance, effect_id, dispatch_depth)
    values (v_step_run, sr.run_id, sr.step_id, v_wf, v_kind, v_ref, v_actor,
            'EXECUTED',
            coalesce(v_in->'provenance','{}'::jsonb) || coalesce(v_cx->'provenance','{}'::jsonb),
            nullif(v_res#>>'{phase_d,business_effect,effect_id}','')::bigint, v_depth);

    perform set_config('app.phase_d_dispatch_depth', v_depth::text, true);
    return jsonb_build_object('dispatched', true, 'outcome', 'EXECUTED',
             'handler_id', v_res#>>'{phase_d,handler_id}',
             'effect_id',  v_res#>'{phase_d,business_effect,effect_id}');

  exception
    when others then
      v_err  := SQLERRM;
      -- E26. AN UNCLASSIFIED REFUSAL IS AN INSTRUMENT GAP, NOT A CATEGORY.
      -- Once E25 stopped the dispatch withholding business_key and owner_ref, two steps reached the
      -- real business write for the first time and failed on a NOT NULL column of the target
      -- relation -- public.opportunity.kind. That is a genuine and interesting refusal: the payload
      -- carries an IDENTITY for the record but not its CONTENT, and the content of an opportunity is
      -- a judgement no deterministic handler can make while the reasoning capability is held. It
      -- deserves to be named. Recorded as pd_unclassified it looked like a bug in the dispatch.
      --
      -- A raised Phase D or kernel code still wins; this only names what used to fall through.
      v_code := coalesce((regexp_match(v_err, '\((pd_[a-z0-9_]+|k[0-9]+_[a-z0-9_]+)\)'))[1],
        case SQLSTATE
          when '23502' then 'pd_effect_payload_incomplete'   -- not-null column the payload did not fill
          when '23503' then 'pd_effect_reference_unresolved'  -- foreign key the payload pointed nowhere
          when '23505' then 'pd_effect_identity_collision'    -- unique key already taken
          when '23514' then 'pd_effect_check_violated'        -- a check constraint on the target relation
          when '22P02' then 'pd_effect_value_malformed'       -- a value the target column cannot parse
          else 'pd_unclassified' end);
      insert into public.phase_d_dispatch
        (step_run_id, run_id, step_id, workflow_id, opened_by_kind, opened_by_ref, actor_role_id,
         outcome, refusal_code, sqlstate_code, reason, unresolved_keys, inputs_provenance,
         dispatch_depth)
      values (v_step_run, sr.run_id, sr.step_id, v_wf, v_kind, v_ref, v_actor,
              -- E19. This column used to say REFUSED whether the handler had judged the evidence
              -- and rejected it, or had never been given any. Those are different events, and the
              -- 2026-08-20 acceptance audit read the second as the first. Both are refusals and
              -- neither is a pass; only the name differs.
              case when v_code = 'pd_evidence_absent' then 'REFUSED_EVIDENCE_ABSENT' else 'REFUSED' end,
              v_code, SQLSTATE, left(v_err, 1000),
              coalesce((select array_agg(x) from jsonb_array_elements_text(
                          coalesce(v_cx->'unresolved','[]'::jsonb)) x), '{}'),
              coalesce(v_cx->'provenance','{}'::jsonb), v_depth);
      perform set_config('app.phase_d_dispatch_depth', v_depth::text, true);
      return jsonb_build_object('dispatched', false,
                                'outcome', case when v_code = 'pd_evidence_absent'
                                                then 'REFUSED_EVIDENCE_ABSENT' else 'REFUSED' end,
                                'refusal_code', v_code, 'sqlstate', SQLSTATE);
  end;
end
$function$;
