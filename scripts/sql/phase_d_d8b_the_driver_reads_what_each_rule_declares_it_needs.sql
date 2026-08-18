-- PHASE D · D8b — THE DRIVER SUPPLIES WHAT THE RULES SAY THEY NEED, FROM THE RULES THEMSELVES.
--
-- The first drive of W04 stopped at step 1:
--
--   W04-S01  refused by 2 hard business rule(s)   pd_rule_refused
--     BR-025  "acceptance must reference the exact displayed version AND hash;
--              one without the other is not an acceptance of anything specific"
--     BR-026  certificate before acceptance
--   customers 0 -> 0,  review_chain 1904 -> 1904,  effect_ledger_delta 0
--
-- THAT REFUSAL IS THE RULES WORKING. It is also the reason the driver could not reach a closure, and
-- the two facts are easy to confuse: a driver that reported "W04 cannot close" would be describing
-- its own missing fixture, not the workflow.
--
-- The fix is NOT to weaken a rule or to hand-type a payload per step. phase_d_rule_enforcement
-- already declares required_context per rule — BR-025 needs terms_version and terms_hash, BR-026
-- needs acceptance_ref — and phase_d_gate_contract declares evidence_keys per gate. So the driver
-- reads the rules in scope for the step it is about to drive and supplies exactly the named facts,
-- with a fixture value each. Nothing is supplied that a rule did not ask for by name.
--
-- WHAT THIS DELIBERATELY DOES NOT DO:
--   * It does not supply a review verdict. That still comes from the caller, and its absence is
--     still a refusal — otherwise 41 review steps become a rubber stamp driven by a loop.
--   * It does not supply reviewer_role_id from anywhere but the FROZEN step. A driver that named a
--     reviewer of its own choosing would defeat BR-002, which is the rule that exists because a
--     picker not told who wrote the thing returned its own author 182 times.
--   * It does not satisfy a foreign key. A fixture cannot, and a parent invented here would make a
--     legitimate refusal look like a defect in the step.
--
-- The fixture values are visibly fixtures — 'ZZ DEMO' and '@example.invalid', this repository's
-- existing convention — so a row that escaped a rollback would be identifiable as one.

begin;

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
  v_extra   jsonb := coalesce(p_input->'context','{}'::jsonb);
  v_run    bigint;
  v_start  jsonb;
  v_steps  jsonb := '[]'::jsonb;
  v_i      int := 0;
  v_res    jsonb;
  v_inputs jsonb;
  v_eff    jsonb;
  v_rulectx jsonb;
  v_gatectx jsonb;
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

    select coalesce(jsonb_object_agg(k, 'ZZ DEMO — ' || k || ' for ' || sr.step_id), '{}'::jsonb)
      into v_inputs
      from public.phase_d_handler_schema sc, unnest(sc.required_keys) k
     where sc.step_id = sr.step_id and sc.schema_kind = 'input';

    -- ---- the rule context, read from the rules in scope ------------------------------------
    -- Each rule declares the facts it needs by name. Anything a rule did not ask for is not sent,
    -- so a rule that passes here passed because its own named evidence was present.
    select coalesce(jsonb_object_agg(k, 'ZZ DEMO — ' || k), '{}'::jsonb) into v_rulectx
      from (select distinct unnest(re.required_context) k
              from public.phase_d_rule_enforcement re
             where re.rule_id = any (b.rule_ids)
               and cardinality(re.required_context) > 0) q(k);

    -- ---- the gate evidence, read from the gate contracts -----------------------------------
    -- step_id, run_id, actor_role_id and reviewer_role_id are supplied by the executor itself from
    -- the step run, so they are excluded here: a driver that overwrote actor_role_id could pass a
    -- gate on an identity the step run does not name.
    select coalesce(jsonb_object_agg(k, 'ZZ DEMO — ' || k), '{}'::jsonb) into v_gatectx
      from (select distinct unnest(gc.evidence_keys) k
              from public.phase_d_gate_contract gc
             where gc.gate_id = any (b.gate_ids)
               and cardinality(gc.evidence_keys) > 0) q(k)
     where k not in ('step_id','run_id','actor_role_id','reviewer_role_id');

    v_key := format('zz-phase-d-%s-%s-%s', v_label, sr.step_id, v_run);
    v_eff := '{}'::jsonb;
    v_reviewer := null;

    if e.expected_effect_type = 'MEASUREMENT_RECORD' then
      v_eff := jsonb_build_object('numerator', 1, 'denominator', 1,
                                  'formula', 'fixture', 'window', 'fixture');
    elsif e.expected_effect_type = 'EXTERNAL_EFFECT_INTENT' then
      v_eff := jsonb_build_object(
        'recipient', 'zz-phase-d-' || v_label || '@example.invalid',
        'consent_basis', 'fixture: no consent record is asserted and nothing is sent',
        'suppressed', false);
    elsif e.expected_effect_type = 'REVIEW_VERDICT' then
      v_reviewer := nullif(btrim(coalesce(b.independent_reviewer_role_id,'')),'');
      v_eff := jsonb_strip_nulls(jsonb_build_object(
        'verdict', v_verdict, 'reviewer_role_id', v_reviewer,
        'subject_type', 'phase_d_step', 'subject_id', sr.step_id,
        'author_agent', sr.accountable_role_id, 'stage', sr.step_id,
        'notes', 'fixture review through fn_phase_d_drive_workflow'));
    elsif e.expected_effect_type in ('DOMAIN_MUTATION','VERSIONED_ARTIFACT') then
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
          'context', v_rulectx || v_extra,
          'gate_evidence', v_gatectx,
          'business_key', coalesce(nullif(v_eff->>'business_key',''), v_key),
          'owner_ref', coalesce(v_owner, nullif(v_eff->>'owner_ref',''), v_key),
          'effect_state', 'open',
          'effect_payload', v_eff)
        || case when e.expected_effect_type = 'REVIEW_VERDICT'
                then jsonb_strip_nulls(jsonb_build_object(
                       'verdict', v_verdict, 'reviewer_role_id', v_reviewer))
                else '{}'::jsonb end
        || case when b.handler_class = 'REVIEW_HANDLER'
                then jsonb_strip_nulls(jsonb_build_object(
                       'verdict', v_verdict,
                       'reviewer_role_id', nullif(btrim(coalesce(b.independent_reviewer_role_id,'')),'')))
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
      v_code := coalesce((regexp_match(v_err, '\((pd_[a-z0-9_]+|k[0-9]+_[a-z0-9_]+)\)'))[1], '(none)');
      v_steps := v_steps || jsonb_build_array(jsonb_build_object(
        'step_id', sr.step_id, 'step_run_id', sr.step_run_id,
        'expected_effect_type', e.expected_effect_type,
        'handler_class', b.handler_class,
        'ok', false, 'refused_with', v_code, 'sqlstate', v_sqlstate,
        'reason', left(v_err, 400)));
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

commit;
