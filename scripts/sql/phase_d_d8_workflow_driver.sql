-- PHASE D · D8 — A DRIVER THAT WALKS A WORKFLOW THROUGH THE REAL PATH, AND REPORTS WHAT REFUSED.
--
-- WHY A ROUTINE AND NOT THIRTY PROBES. D11 and D13 need 30 workflows × 4 cases and 257 steps × 7
-- cases. Written as ad-hoc SQL each of those is a fresh chance to seed a row the step under test was
-- supposed to create — the defect that made a green e2e suite prove nothing, because the harness
-- created the record before the step that needed it missing. One driver, used everywhere, either
-- has that bug once and visibly or does not have it.
--
-- WHAT IT MAY NOT DO, and each of these is enforced below rather than promised:
--
--   * It may not write a business row itself. Every effect goes through
--     fn_phase_d_handler_execute -> fn_phase_d_effect_produce -> fn_phase_d_object_write. The driver
--     supplies a PAYLOAD and nothing else.
--   * It may not choose the step order. The kernel does, through next_step_if_pass; the driver reads
--     whichever step run is open and asks no questions about which one it expected.
--   * It may not supply a review verdict of its own choosing as an approval. It passes the caller's
--     verdict through, defaulting to nothing — an absent verdict is a refusal, and this is where a
--     47-step rubber stamp would otherwise be built.
--   * It may not hide a refusal. Every raise is caught, classified by its machine code, and returned
--     in the report. A driver that stopped at the first refusal and returned "ok" would be the
--     always-passes scorer with a loop around it.
--
-- IT IS NOT A BUSINESS PATH AND DOES NOT CLAIM TO BE ONE. The fixture inputs satisfy the declared
-- input schema with named placeholder values; what is being proved is that the executor, the effect
-- service, the object services, the rules, the gates and the kernel connect and refuse correctly —
-- not that a customer typed anything. Fixtures follow this repository's existing convention:
-- ZZ DEMO in a name, @example.invalid in an email.

begin;

-- ROUTINE REMOVED 7 September 2026. public.fn_phase_d_fixture_value was dropped from the database with
-- everything else that did not belong to the new structure, and its definition is cut from
-- this file so re-applying the file cannot recreate it. The other routines defined here are
-- still running and are untouched.


create or replace function public.fn_phase_d_drive_workflow(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  w        public.phase_b_workflow%rowtype;
  sr       public.phase_c_workflow_step_run%rowtype;
  e        public.phase_d_step_effect%rowtype;
  b        public.phase_d_handler_binding%rowtype;
  wm       public.phase_d_object_write_map%rowtype;
  v_wf     text := nullif(btrim(coalesce(p_input->>'workflow_id','')),'');
  v_ctx    text := lower(coalesce(nullif(btrim(p_input->>'execution_context'),''),'test'));
  v_max    int  := coalesce(nullif(p_input->>'max_steps','')::int, 40);
  v_label  text := coalesce(nullif(btrim(p_input->>'label'),''), 'phase-d-drive');
  v_owner  text := nullif(btrim(coalesce(p_input->>'owner_ref','')),'');
  v_verdict text := nullif(btrim(coalesce(p_input->>'verdict','')),'');
  v_parents jsonb := coalesce(p_input->'parent_refs','{}'::jsonb);
  v_run    bigint;
  v_start  jsonb;
  v_steps  jsonb := '[]'::jsonb;
  v_i      int := 0;
  v_res    jsonb;
  v_inputs jsonb;
  v_eff    jsonb;
  v_key    text;
  v_col    record;
  v_err    text; v_sqlstate text; v_code text;
  v_run_state text;
  v_ledger int; v_before int; v_after int;
  v_reviewer text;
begin
  if v_wf is null then
    raise exception 'fn_phase_d_drive_workflow: workflow_id is required' using errcode = '22023';
  end if;
  select * into w from public.phase_b_workflow where workflow_id = v_wf;
  if not found then
    raise exception 'fn_phase_d_drive_workflow: % is not a frozen workflow', v_wf using errcode = '23503';
  end if;

  select count(*) into v_before from public.phase_d_effect_ledger;

  -- ---- the run is opened by the KERNEL, not by this routine ------------------------------------
  v_start := public.fn_kernel_workflow_start(jsonb_build_object(
    'workflow_id', v_wf,
    'business_object_id', w.primary_object,
    'source_kind', 'autonomous',
    'source_ref', format('zz-phase-d-%s-%s', v_label, v_wf),
    'requested_by', w.accountable_role_id,
    'trigger_ctx', jsonb_build_object('driver','fn_phase_d_drive_workflow','fixture',true)));
  v_run := (v_start->>'run_id')::bigint;
  if v_run is null then
    return jsonb_build_object('ok', false, 'workflow_id', v_wf,
      'stopped_because', 'the kernel returned no run_id', 'kernel_result', v_start);
  end if;

  -- ---- drive whatever step is open, for as long as one is -------------------------------------
  loop
    v_i := v_i + 1;
    exit when v_i > v_max;

    select * into sr from public.phase_c_workflow_step_run
     where run_id = v_run
       and state in ('ready','active','not_ready','waiting_input','waiting_review','blocked')
     order by step_run_id
     limit 1;
    exit when not found;

    select * into e from public.phase_d_step_effect where step_id = sr.step_id;
    select * into b from public.phase_d_handler_binding where step_id = sr.step_id;

    -- Inputs: exactly the keys the step's own declared input schema requires, no more.
    select coalesce(jsonb_object_agg(k, 'ZZ DEMO — ' || k || ' for ' || sr.step_id), '{}'::jsonb)
      into v_inputs
      from public.phase_d_handler_schema sc, unnest(sc.required_keys) k
     where sc.step_id = sr.step_id and sc.schema_kind = 'input';

    -- The effect payload, shaped by the step's DECLARED effect type. Nothing is invented for a type
    -- that does not need it, and nothing is supplied for a review verdict the caller did not give.
    v_key := format('zz-phase-d-%s-%s-%s', v_label, sr.step_id, v_run);
    v_eff := '{}'::jsonb;

    if e.expected_effect_type = 'MEASUREMENT_RECORD' then
      -- A real, non-zero denominator. Passing 0 here would be the probe proving the refusal path
      -- rather than the happy path, and there is a separate negative case for that.
      v_eff := jsonb_build_object('numerator', 1, 'denominator', 1,
                                  'formula', 'fixture', 'window', 'fixture');
    elsif e.expected_effect_type = 'EXTERNAL_EFFECT_INTENT' then
      v_eff := jsonb_build_object(
        'recipient', 'zz-phase-d-' || v_label || '@example.invalid',
        'consent_basis', 'fixture: no consent record is asserted and nothing is sent',
        'suppressed', false);
    elsif e.expected_effect_type = 'REVIEW_VERDICT' then
      -- The reviewer comes from the FROZEN step, not from this routine, and the verdict comes from
      -- the caller. Where the frozen step names no independent reviewer the executor's own BR-002
      -- check refuses, and that refusal is reported rather than worked around.
      v_reviewer := nullif(btrim(coalesce(b.independent_reviewer_role_id,'')),'');
      v_eff := jsonb_strip_nulls(jsonb_build_object(
        'verdict', v_verdict, 'reviewer_role_id', v_reviewer,
        'subject_type', 'phase_d_step', 'subject_id', sr.step_id,
        'author_agent', sr.accountable_role_id, 'stage', sr.step_id,
        'notes', 'fixture review through fn_phase_d_drive_workflow'));
    elsif e.expected_effect_type in ('DOMAIN_MUTATION','VERSIONED_ARTIFACT') then
      -- Every column the target REQUIRES gets a fixture of the right type, resolved from the
      -- catalogue. Identity and generated columns are excluded, exactly as the writer excludes them.
      select * into wm from public.phase_d_object_write_map where object_id = e.effect_object_id;
      if found then
        for v_col in
          select k.key as col, wm.column_map->>k.key as src,
                 format_type(a.atttypid, a.atttypmod) as ftype,
                 (select typcategory from pg_type ty where ty.oid = a.atttypid) as tcat
            from jsonb_each(wm.column_map) k
            join pg_attribute a
              on a.attrelid = wm.target_relation::regclass and a.attname = k.key and a.attnum > 0
           where a.attnotnull and a.atthasdef = false and a.attidentity = '' and a.attgenerated = ''
        loop
          -- A caller-supplied parent reference always wins: a foreign key cannot be satisfied by a
          -- fixture, and inventing one produces a refusal that looks like a defect in the step.
          if v_parents ? v_col.src then
            v_eff := v_eff || jsonb_build_object(v_col.src, v_parents->v_col.src);
          else
            v_eff := v_eff || jsonb_build_object(v_col.src,
              public.fn_phase_d_fixture_value(v_col.ftype, v_col.tcat, v_label));
          end if;
        end loop;
      end if;
      v_eff := v_eff || v_parents;
      if v_eff = '{}'::jsonb then
        v_eff := jsonb_build_object('fixture', v_label);
      end if;
    end if;

    begin
      v_res := public.fn_phase_d_handler_execute(
        jsonb_build_object(
          'step_run_id', sr.step_run_id,
          'actor_role_id', sr.accountable_role_id,
          'idempotency_key', format('%s:%s:%s', v_label, sr.step_id, sr.step_run_id),
          'inputs', v_inputs,
          'execution_context', v_ctx,
          'business_key', coalesce(nullif(v_eff->>'business_key',''), v_key),
          'owner_ref', coalesce(v_owner, nullif(v_eff->>'owner_ref',''), v_key),
          'effect_state', 'open',
          'effect_payload', v_eff)
        || case when e.expected_effect_type = 'REVIEW_VERDICT'
                then jsonb_strip_nulls(jsonb_build_object(
                       'verdict', v_verdict, 'reviewer_role_id', v_reviewer))
                else '{}'::jsonb end
        || case when e.expected_effect_type = 'MEASUREMENT_RECORD'
                then jsonb_build_object('numerator', 1, 'denominator', 1,
                                        'formula','fixture','window','fixture')
                else '{}'::jsonb end);

      v_steps := v_steps || jsonb_build_array(jsonb_build_object(
        'step_id', sr.step_id, 'step_run_id', sr.step_run_id,
        'expected_effect_type', e.expected_effect_type,
        'handler_class', b.handler_class,
        'ok', v_res->'ok', 'outcome', v_res->>'outcome',
        'step_state', v_res->>'step_state', 'run_state', v_res->>'run_state',
        'effect', v_res->'phase_d'->'business_effect'->'result_reference',
        'effect_id', v_res->'phase_d'->'business_effect'->'effect_id'));
    exception when others then
      v_sqlstate := SQLSTATE; v_err := SQLERRM;
      -- The machine code is the part a test asserts on. It is extracted rather than the message
      -- matched, because a message is prose and a code is a contract.
      v_code := coalesce((regexp_match(v_err, '\((pd_[a-z0-9_]+|k[0-9]+_[a-z0-9_]+)\)'))[1], '(none)');
      v_steps := v_steps || jsonb_build_array(jsonb_build_object(
        'step_id', sr.step_id, 'step_run_id', sr.step_run_id,
        'expected_effect_type', e.expected_effect_type,
        'handler_class', b.handler_class,
        'ok', false, 'refused_with', v_code, 'sqlstate', v_sqlstate,
        'reason', left(v_err, 320)));
      -- STOP. A driver that skipped a refused step and carried on would report a closure the
      -- workflow never reached.
      exit;
    end;
  end loop;

  select state into v_run_state from public.phase_c_workflow_run where run_id = v_run;
  select count(*) into v_after from public.phase_d_effect_ledger;
  select count(*) into v_ledger from public.phase_d_effect_ledger where run_id = v_run;

  return jsonb_build_object(
    'ok', (v_run_state is not null
           and not exists (select 1 from jsonb_array_elements(v_steps) x
                            where coalesce((x->>'ok')::boolean, false) = false)),
    'workflow_id', v_wf, 'run_id', v_run, 'run_state', v_run_state,
    'steps_in_workflow', (select count(*) from public.phase_b_workflow_step
                           where workflow_id = v_wf),
    'steps_driven', jsonb_array_length(v_steps),
    'effects_for_this_run', v_ledger,
    'effect_ledger_delta', v_after - v_before,
    'terminal', (select terminal from public.phase_b_workflow_state
                  where state = v_run_state),
    'steps', v_steps);
end $fn$;

revoke all on function public.fn_phase_d_drive_workflow(jsonb) from public;
revoke all on function public.fn_phase_d_fixture_value(text, text, text) from public;
grant execute on function public.fn_phase_d_drive_workflow(jsonb) to service_role;
grant execute on function public.fn_phase_d_fixture_value(text, text, text) to service_role;

commit;
