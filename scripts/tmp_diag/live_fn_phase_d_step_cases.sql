CREATE OR REPLACE FUNCTION public.fn_phase_d_step_cases(p_step_id text)
 RETURNS TABLE(case_kind text, decided_at text, expectation text, passed boolean, refused_with text, detail text)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  s   public.phase_b_workflow_step%rowtype;
  b   public.phase_d_handler_binding%rowtype;
  ins public.phase_d_handler_schema%rowtype;
  outs public.phase_d_handler_schema%rowtype;
  v_full jsonb; v_short jsonb; v record; v_k text;
  v_rule text; v_gate text; v_n int;
begin
  select * into s from public.phase_b_workflow_step where step_id = p_step_id;
  if not found then
    case_kind := 'positive'; decided_at := 'step_contract'; expectation := 'the step exists';
    passed := false; refused_with := 'step_unknown';
    detail := format('%s is not a frozen step', p_step_id); return next; return;
  end if;
  select * into b from public.phase_d_handler_binding where step_id = p_step_id;
  select * into ins  from public.phase_d_handler_schema where step_id = p_step_id and schema_kind='input';
  select * into outs from public.phase_d_handler_schema where step_id = p_step_id and schema_kind='output';

  -- a complete input payload, built from the step's OWN declared keys
  select coalesce(jsonb_object_agg(k, 'evidence for ' || k), '{}'::jsonb) into v_full
    from unnest(coalesce(ins.required_keys, '{}'::text[])) k;

  -- ---- 1. POSITIVE: the step's own contract accepts a complete payload ---------------------------
  select * into v from public.fn_phase_d_schema_validate(ins.schema_id, v_full);
  case_kind := 'positive'; decided_at := 'step_contract';
  expectation := 'a payload carrying every declared input key validates';
  passed := coalesce(v.valid, false); refused_with := null;
  detail := format('%s key(s) declared; %s', cardinality(coalesce(ins.required_keys,'{}')),
                   coalesce(v.reason, '(no reason)'));
  return next;

  -- ---- 2. MISSING INPUT: one declared key removed ------------------------------------------------
  if cardinality(coalesce(ins.required_keys,'{}')) = 0 then
    -- A step that declares no input cannot have one taken away. Recorded honestly rather than
    -- scored as a pass on a case that did not run.
    case_kind := 'missing_input'; decided_at := 'step_contract';
    expectation := 'removing a declared input key is refused';
    passed := false; refused_with := 'no_declared_input';
    detail := 'the frozen step declares no required input, so this case has no subject';
    return next;
  else
    v_k := ins.required_keys[1];
    v_short := v_full - v_k;
    select * into v from public.fn_phase_d_schema_validate(ins.schema_id, v_short);
    case_kind := 'missing_input'; decided_at := 'step_contract';
    expectation := format('removing %L is refused and the refusal names it', v_k);
    passed := (not coalesce(v.valid, true)) and (v.missing @> array[v_k]);
    refused_with := case when coalesce(v.valid,true) then null else 'pd_input_schema_invalid' end;
    detail := coalesce(v.reason, '(no reason)');
    return next;
  end if;

  -- ---- 3. WRONG ACTOR ---------------------------------------------------------------------------
  -- BR-004 is the rule that decides whether an acting identity is canonical, and the executor
  -- consults it for every step. An identity nobody models must not resolve.
  select * into v from public.fn_phase_d_rule_check('BR-004',
    jsonb_build_object('actor_role_id', 'zz_not_a_canonical_role_' || p_step_id));
  case_kind := 'wrong_actor'; decided_at := 'executor_boundary';
  expectation := 'an identity nobody models does not resolve to a canonical role';
  passed := (v.state = 'ENFORCED_FAIL') and not coalesce(v.ok, true);
  refused_with := v.refusal_code; detail := v.reason;
  return next;

  -- ---- 4. INVALID STATE -------------------------------------------------------------------------
  -- A step run that does not exist. The executor refuses before it reaches any write.
  begin
    perform public.fn_phase_d_handler_execute(jsonb_build_object(
      'step_run_id', -1, 'actor_role_id', s.accountable_role_id,
      'idempotency_key', 'pd-case-invalid-state:' || p_step_id,
      'inputs', v_full, 'execution_context', 'test'));
    case_kind := 'invalid_state'; decided_at := 'executor_boundary';
    expectation := 'a step run that does not exist is refused';
    passed := false; refused_with := null; detail := 'ACCEPTED — the executor ran against no step run';
  exception when others then
    case_kind := 'invalid_state'; decided_at := 'executor_boundary';
    expectation := 'a step run that does not exist is refused';
    refused_with := coalesce((regexp_match(SQLERRM,'\((pd_[a-z0-9_]+|k[0-9]+_[a-z0-9_]+)\)'))[1], '(none)');
    passed := refused_with = 'pd_step_state_invalid';
    detail := left(SQLERRM, 200);
  end;
  return next;

  -- ---- 5. DUPLICATE -----------------------------------------------------------------------------
  -- The guarantee is a UNIQUE constraint, not a convention, so the case reads the catalogue for the
  -- constraint itself. A test that trusted a constraint it never looked at is a test nobody ran.
  select count(*) into v_n from pg_constraint c
   where c.conrelid = 'public.phase_d_effect_ledger'::regclass and c.contype = 'u'
     -- attname is `name`, not `text`; the array comparison needs the cast or Postgres refuses the
     -- operator outright — which it did, and correctly.
     and (select array_agg(a.attname::text order by a.attname::text) from unnest(c.conkey) k
           join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k)
         = array['effect_type','step_run_id']::text[];
  case_kind := 'duplicate'; decided_at := 'structural_constraint';
  expectation := 'a replayed handler cannot produce a second effect for one step run';
  passed := (v_n = 1);
  refused_with := case when v_n = 1 then 'pd_effect_replay' else null end;
  detail := format('%s UNIQUE(step_run_id, effect_type) constraint(s) on phase_d_effect_ledger', v_n);
  return next;

  -- ---- 6. FAILED RULE OR GATE -------------------------------------------------------------------
  -- Asked with an EMPTY context, at least one rule or gate in the step's own scope must refuse.
  -- A step whose whole scope passes on no evidence is a step nothing is enforcing.
  v_n := 0; v_rule := null; v_gate := null;
  if b.rule_ids is not null then
    for v_k in select unnest(b.rule_ids) loop
      select * into v from public.fn_phase_d_rule_check(v_k, '{}'::jsonb);
      if v.state in ('ENFORCED_FAIL','NOT_IMPLEMENTED') then
        v_n := v_n + 1; v_rule := coalesce(v_rule, v_k);
      end if;
    end loop;
  end if;
  if b.gate_ids is not null then
    for v_k in select unnest(b.gate_ids) loop
      select * into v from public.fn_phase_d_gate_evaluate(v_k, '{}'::jsonb);
      if not coalesce(v.passed, true) then v_n := v_n + 1; v_gate := coalesce(v_gate, v_k); end if;
    end loop;
  end if;
  case_kind := 'failed_rule_or_gate'; decided_at := 'executor_boundary';
  expectation := 'with no evidence at all, at least one rule or gate in scope refuses';
  passed := (v_n > 0);
  refused_with := case when v_n > 0 then coalesce('pd_rule_refused', 'pd_gate_refused') else null end;
  detail := format('%s of %s rule(s) and %s gate(s) in scope refuse an empty context; first %s',
                   v_n, cardinality(coalesce(b.rule_ids,'{}')), cardinality(coalesce(b.gate_ids,'{}')),
                   coalesce(v_rule, v_gate, '(none)'));
  return next;

  -- ---- 7. MALFORMED OUTPUT ----------------------------------------------------------------------
  select * into v from public.fn_phase_d_schema_validate(outs.schema_id, '{}'::jsonb);
  case_kind := 'malformed_output'; decided_at := 'step_contract';
  expectation := 'an empty output is refused by the step''s own output contract';
  passed := not coalesce(v.valid, true);
  refused_with := case when coalesce(v.valid,true) then null else 'pd_output_schema_invalid' end;
  detail := coalesce(v.reason, '(no reason)');
  return next;
end $function$
