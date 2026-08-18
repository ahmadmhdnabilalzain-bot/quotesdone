-- PHASE D · D8c — A FIXTURE THAT NAMES A STATE MUST NAME A DECLARED STATE.
--
-- Second drive of W04, after the driver learned to read each rule's own required_context:
--
--   W04-S01  refused by 1 hard gate   pd_gate_refused
--     GATE-006  "transition ZZ DEMO — from_state -> ZZ DEMO — to_state is NOT declared in the
--                frozen model"                          gate006_transition_undeclared
--
-- The gate is right and the fixture was wrong. 'ZZ DEMO — from_state' is a perfectly good fixture
-- for a free-text reference and a nonsense one for a STATE: GATE-006 checks the pair against
-- phase_b_workflow_transition, so a placeholder can only ever be refused. The same is true of every
-- gate-evidence key whose value has to be a member of a declared set rather than an opaque string —
-- a payment rung, a route state, a boolean, a denominator, and the customer-identity pair GATE-018
-- compares against itself.
--
-- The rule the fixture generator now follows: a key whose VALUE IS CHECKED AGAINST A MODEL takes its
-- value FROM that model; only opaque references get a 'ZZ DEMO' string. Which category each key is
-- in is stated here per key rather than inferred, because a generator that guessed would produce
-- exactly the class of refusal above and it would read as a defect in the step.
--
-- WHAT STILL CANNOT BE FIXTURED, and is left to refuse honestly: a key that must be a FOREIGN KEY
-- into real business data — inquiry_id, supplier_id, quote_id, transaction_id, document_id,
-- comparison_id, refund_id. A parent invented here would either violate the constraint or, worse,
-- pass by pointing at somebody's real row. Those come from the caller's parent_refs, and a workflow
-- driven without them stops at the first step that needs one, with the code that says so.

begin;

create or replace function public.fn_phase_d_fixture_context(p_step_run_id bigint, p_label text)
returns jsonb
language plpgsql stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  sr  public.phase_c_workflow_step_run%rowtype;
  s   public.phase_b_workflow_step%rowtype;
  b   public.phase_d_handler_binding%rowtype;
  r   public.phase_c_workflow_run%rowtype;
  v_keys text[];
  v_out  jsonb := '{}'::jsonb;
  v_k    text;
  v_to   text;
  v_from text;
  v_cust text;
begin
  select * into sr from public.phase_c_workflow_step_run where step_run_id = p_step_run_id;
  if not found then
    raise exception 'fn_phase_d_fixture_context: no step run %', p_step_run_id using errcode = '23503';
  end if;
  select * into s from public.phase_b_workflow_step where step_id = sr.step_id;
  select * into b from public.phase_d_handler_binding where step_id = sr.step_id;
  select * into r from public.phase_c_workflow_run where run_id = sr.run_id;

  -- Every key any rule or gate in scope declares it needs, and nothing else. A fixture for a key
  -- nobody asked for is a fact the step was not entitled to.
  select coalesce(array_agg(distinct k), '{}') into v_keys from (
    select unnest(re.required_context) k from public.phase_d_rule_enforcement re
     where re.rule_id = any (b.rule_ids)
    union
    select unnest(gc.evidence_keys) k from public.phase_d_gate_contract gc
     where gc.gate_id = any (b.gate_ids)) q(k);

  -- FROM the frozen transition model. The pair must be a row of phase_b_workflow_transition or
  -- GATE-006 refuses it, so it is read from there rather than composed.
  v_from := r.state;
  v_to   := nullif(btrim(coalesce(s.success_workflow_state,'')),'');
  if v_to is not null and not exists (
       select 1 from public.phase_b_workflow_transition t
        where t.from_state = v_from and t.to_state = v_to) then
    -- The step's declared successor state is not reachable from where the run actually is. Rather
    -- than substitute a transition that IS declared — which would be the fixture deciding the state
    -- machine — the real pair is passed through and the gate is allowed to refuse it.
    null;
  end if;

  v_cust := coalesce(nullif(btrim(r.business_object_id),''), 'zz-phase-d-' || p_label);

  foreach v_k in array v_keys loop
    v_out := v_out || case v_k
      -- ---- values checked against a declared model --------------------------------------------
      when 'from_state' then jsonb_build_object('from_state', v_from)
      when 'to_state'   then jsonb_build_object('to_state', coalesce(v_to, v_from))
      when 'route_state' then jsonb_build_object('route_state',
        coalesce((select t.to_state from public.phase_b_workflow_transition t
                   where t.from_state = v_from order by t.to_state limit 1), v_from))
      when 'monetary_state' then jsonb_build_object('monetary_state',
        coalesce((select ps.state_key from public.phase_d_payment_state ps
                   order by ps.rung limit 1), 'checkout_created'))
      -- ---- typed values, not opaque strings ---------------------------------------------------
      when 'denominator' then jsonb_build_object('denominator', 1)
      when 'critical_risk_resolved' then jsonb_build_object('critical_risk_resolved', true)
      when 'holdout_isolated'       then jsonb_build_object('holdout_isolated', true)
      when 'platform_edited'        then jsonb_build_object('platform_edited', false)
      -- ---- a PAIR that is compared against itself ---------------------------------------------
      -- GATE-018 exists to refuse one customer reading another's comparison. Both halves must be
      -- the SAME identity for the positive case, and the negative case is a separate test that
      -- deliberately makes them differ.
      when 'caller_customer_id' then jsonb_build_object('caller_customer_id', v_cust)
      when 'inquiry_owner'      then jsonb_build_object('inquiry_owner', v_cust)
      -- ---- opaque references: a visible fixture is correct and sufficient ----------------------
      else jsonb_build_object(v_k, 'ZZ DEMO — ' || v_k || ' for ' || sr.step_id)
    end;
  end loop;

  -- IDs THAT ARE FOREIGN KEYS ARE REMOVED, not fixtured. Leaving a placeholder in would produce a
  -- constraint violation dressed up as a business refusal.
  --
  -- AND SO ARE THE FOUR IDENTITY KEYS THE EXECUTOR SUPPLIES ITSELF. GATE-002 declares actor_role_id
  -- as its evidence, so the generator dutifully produced 'ZZ DEMO — actor_role_id' — and because the
  -- executor merges the caller's context LAST, that placeholder replaced the real accountable owner
  -- and BR-004 refused it as non-canonical. A fixture that overwrites the identity of the thing
  -- being tested is not a fixture, it is the harness answering its own question; step_id, run_id,
  -- actor_role_id and reviewer_role_id come from the step run and from nowhere else.
  v_out := v_out - array['inquiry_id','supplier_id','quote_id','transaction_id','document_id',
                         'comparison_id','refund_id','provider_event_id']
                 - array['step_id','run_id','step_run_id','actor_role_id','reviewer_role_id'];
  -- step_run_id joined that list when GATE-008 gained it as declared evidence: the fixture produced
  -- 'ZZ DEMO — step_run_id for W04-S07' and the gate cast it to bigint. An identity is never a
  -- fixture, whichever gate declares it.

  return v_out;
end $fn$;

revoke all on function public.fn_phase_d_fixture_context(bigint, text) from public;
grant execute on function public.fn_phase_d_fixture_context(bigint, text) to service_role;

-- ---------------------------------------------------------------- the driver uses it
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
  -- THE REVIEWER IS A RUNTIME FACT FOR 45 OF THE 47 REVIEW STEPS. Measured on the frozen registry:
  -- 47 steps are step_type='review' and 45 of them name no independent_reviewer_role_id, so there is
  -- no reviewer to read for all but two. The executor is right to refuse — fn_kernel_reviewer_
  -- independent(owner, NULL) is false and BR-002 blocks — and the identity has to come from whoever
  -- is driving. It is taken from the CALLER and never chosen here: a driver that picked a reviewer
  -- would be fn_pick_reviewer returning the department head 182 times, one layer up. Independence is
  -- still decided by the kernel, not by this parameter.
  v_caller_reviewer text := nullif(btrim(coalesce(p_input->>'reviewer_role_id','')),'');
  v_parents jsonb := coalesce(p_input->'parent_refs','{}'::jsonb);
  v_extra   jsonb := coalesce(p_input->'context','{}'::jsonb);
  v_run    bigint;
  v_start  jsonb;
  v_steps  jsonb := '[]'::jsonb;
  v_i      int := 0;
  v_res    jsonb;
  v_inputs jsonb;
  v_eff    jsonb;
  v_fix    jsonb;
  v_key    text;
  v_keys   jsonb := '{}'::jsonb;
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

    -- One source for every rule fact and gate fact the step declares it needs, typed per key.
    v_fix := public.fn_phase_d_fixture_context(sr.step_run_id, v_label);

    -- THE BUSINESS KEY MUST BE THE TARGET'S KEY TYPE. public.customers.id is a uuid, and a label
    -- string reached it as one: "invalid input syntax for type uuid". A driver that hands a business
    -- key of the wrong type produces a type error where a business refusal belongs, and the two read
    -- nothing alike in a result table.
    select * into wm from public.phase_d_object_write_map where object_id = e.effect_object_id;
    if found and exists (
         select 1 from pg_attribute a
          where a.attrelid = wm.target_relation::regclass and a.attname = wm.key_column
            and format_type(a.atttypid, a.atttypmod) = 'uuid') then
      v_key := gen_random_uuid()::text;
    else
      v_key := format('zz-phase-d-%s-%s-%s', v_label, e.effect_object_id, v_run);
    end if;
    -- ONE BUSINESS KEY PER (RUN, OBJECT), NOT PER STEP. The first drive of W04 wrote TWO customer
    -- rows — one at S01 (create) and another at S03 (verify) — because the key carried the step id,
    -- so the second write found no existing row and inserted instead of moving the first one's
    -- state. A workflow that creates a fresh account at every step it touches is not onboarding a
    -- customer, and the ledger would have counted both as successful effects. Keys are remembered
    -- per object for the life of the run.
    if v_keys ? e.effect_object_id then
      v_key := v_keys->>e.effect_object_id;
    elsif e.effect_object_id is not null then
      v_keys := v_keys || jsonb_build_object(e.effect_object_id, v_key);
    end if;
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
      v_reviewer := coalesce(nullif(btrim(coalesce(b.independent_reviewer_role_id,'')),''),
                             v_caller_reviewer);
      v_eff := jsonb_strip_nulls(jsonb_build_object(
        'verdict', v_verdict, 'reviewer_role_id', v_reviewer,
        'subject_type', 'phase_d_step', 'subject_id', sr.step_id,
        'author_agent', sr.accountable_role_id, 'stage', sr.step_id,
        'notes', 'fixture review through fn_phase_d_drive_workflow'));
    elsif e.expected_effect_type in ('DOMAIN_MUTATION','VERSIONED_ARTIFACT') then
      if wm.object_id is not null then
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
          'context', v_fix || v_extra,
          'gate_evidence', v_fix || v_extra,
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
                       'reviewer_role_id',
                         coalesce(nullif(btrim(coalesce(b.independent_reviewer_role_id,'')),''),
                                  v_caller_reviewer)))
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
      v_code := coalesce((regexp_match(v_err, '\((pd_[a-z0-9_]+|k[0-9]+_[a-z0-9_]+|gate[0-9]+_[a-z0-9_]+|br[0-9]+_[a-z0-9_]+)\)'))[1], '(none)');
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
