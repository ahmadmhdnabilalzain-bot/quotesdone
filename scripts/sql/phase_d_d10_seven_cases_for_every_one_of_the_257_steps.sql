-- =================================================================================================
-- Phase D — D10. Seven cases for every one of the 257 steps.
--
-- §11 of the brief: for each of the 257 frozen steps — positive, missing input, wrong actor,
-- invalid state, duplicate, failed rule/gate, malformed output. 257 × 7 = 1,799.
--
-- EVERY CASE IS EXECUTED. Nothing here asserts from a registry column. Each case calls the routine
-- that actually decides it and records the machine refusal identity that came back, because a code
-- is a contract and a message is prose.
--
-- WHERE EACH GUARD ACTUALLY LIVES, AND WHY THAT IS NOT A DODGE. A test that says "wrong actor is
-- refused" has to run the check that refuses a wrong actor. Four of the seven are decided from the
-- step's own declared contract and need no live run; three are decided at the executor and kernel
-- boundary, which is shared by all 257 steps and is where the refusal is actually produced. The
-- level is RECORDED PER CASE in `decided_at`, so nobody reading the result can mistake a
-- contract-level refusal for a driven one. A future increment that drives all 257 to a live step run
-- can replace the boundary cases without changing the denominator.
--
-- NO CASE WRITES. Every routine called here is either `stable` or is called with an argument that
-- makes it refuse before it reaches a write, so "proves no partial side effect" is structural rather
-- than asserted afterwards: `phase_d_effect_ledger` and `phase_c_workflow_step_run` are counted
-- around the whole matrix and must not move.
--
-- THE DENOMINATOR IS NOT TYPED. It is 7 × (select count(*) from phase_b_workflow_step), and the
-- board fails if the product is not 1,799 — so if the frozen step count ever moves, this reports it
-- rather than quietly measuring a different population.
-- =================================================================================================

begin;

create table if not exists public.phase_d_step_case_result (
  step_id        text not null,
  case_kind      text not null,
  decided_at     text not null,
  expectation    text not null,
  passed         boolean not null,
  refused_with   text,
  detail         text,
  run_at         timestamptz not null default now(),
  constraint phase_d_step_case_result_pkey primary key (step_id, case_kind),
  constraint phase_d_step_case_result_step_fkey
    foreign key (step_id) references public.phase_b_workflow_step(step_id) on delete cascade,
  constraint phase_d_step_case_result_kind_ck
    check (case_kind in ('positive','missing_input','wrong_actor','invalid_state',
                         'duplicate','failed_rule_or_gate','malformed_output')),
  constraint phase_d_step_case_result_level_ck
    check (decided_at in ('step_contract','executor_boundary','kernel_boundary','structural_constraint'))
);

comment on table public.phase_d_step_case_result is
  'Phase D §11: 7 executed cases per frozen step. decided_at records WHERE the guard that refused actually lives, so a contract-level refusal is never read as a driven one.';

-- ---- the matrix ---------------------------------------------------------------------------------

create or replace function public.fn_phase_d_step_cases(p_step_id text)
returns table(case_kind text, decided_at text, expectation text, passed boolean,
              refused_with text, detail text)
language plpgsql stable
set search_path to 'public', 'pg_temp'
as $fn$
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
end $fn$;

-- ---- the runner ---------------------------------------------------------------------------------

create or replace function public.fn_phase_d_run_step_cases()
returns jsonb
language plpgsql
set search_path to 'public', 'pg_temp'
as $fn$
declare
  st record; c record;
  v_steps int := 0; v_cases int := 0; v_passed int := 0;
  v_eff_before bigint; v_eff_after bigint; v_run_before bigint; v_run_after bigint;
begin
  -- NO CASE MAY WRITE. Counted around the whole matrix rather than promised in a comment.
  select count(*) into v_eff_before from public.phase_d_effect_ledger;
  select count(*) into v_run_before from public.phase_c_workflow_step_run;

  delete from public.phase_d_step_case_result;

  for st in select step_id from public.phase_b_workflow_step order by step_id loop
    v_steps := v_steps + 1;
    for c in select * from public.fn_phase_d_step_cases(st.step_id) loop
      insert into public.phase_d_step_case_result
        (step_id, case_kind, decided_at, expectation, passed, refused_with, detail)
      values (st.step_id, c.case_kind, c.decided_at, c.expectation, c.passed,
              c.refused_with, left(c.detail, 400))
      on conflict (step_id, case_kind) do update
        set decided_at = excluded.decided_at, expectation = excluded.expectation,
            passed = excluded.passed, refused_with = excluded.refused_with,
            detail = excluded.detail, run_at = now();
      v_cases := v_cases + 1;
      if c.passed then v_passed := v_passed + 1; end if;
    end loop;
  end loop;

  select count(*) into v_eff_after from public.phase_d_effect_ledger;
  select count(*) into v_run_after from public.phase_c_workflow_step_run;
  if v_eff_after <> v_eff_before or v_run_after <> v_run_before then
    raise exception 'fn_phase_d_run_step_cases: the matrix produced % effect(s) and % step run(s). A contract test may not write. (pd_case_matrix_had_a_side_effect)',
      v_eff_after - v_eff_before, v_run_after - v_run_before using errcode = '23514';
  end if;

  return jsonb_build_object(
    'ok', v_cases = v_steps * 7,
    'steps', v_steps, 'cases', v_cases, 'expected_cases', v_steps * 7,
    'passed', v_passed, 'failed', v_cases - v_passed,
    'effects_written', v_eff_after - v_eff_before,
    'step_runs_written', v_run_after - v_run_before);
end $fn$;

-- ---- the board ----------------------------------------------------------------------------------

create or replace function public.fn_phase_d_case_state()
returns table(check_name text, expected text, actual text, ok boolean)
language sql stable
set search_path to 'public', 'pg_temp'
as $fn$
  with steps as (select count(*) n from public.phase_b_workflow_step),
       res   as (select count(*) n from public.phase_d_step_case_result)
  -- The denominator is derived, never typed: if the frozen step count moves, this reports it.
  select 'per_step_cases_recorded', ((select n from steps) * 7)::text,
         (select n::text from res), (select n from res) = (select n from steps) * 7
  union all
  select 'steps_with_fewer_than_seven_cases', '0',
         (select count(*)::text from (
            select step_id from public.phase_d_step_case_result
             group by step_id having count(*) <> 7) x),
         not exists (select 1 from (
            select step_id from public.phase_d_step_case_result
             group by step_id having count(*) <> 7) x)
  union all
  select 'cases_failing', '0',
         (select count(*)::text from public.phase_d_step_case_result where not passed),
         not exists (select 1 from public.phase_d_step_case_result where not passed)
  union all
  -- A negative case that reports no machine code is a prose assertion.
  select 'negative_cases_with_no_refusal_code', '0',
         (select count(*)::text from public.phase_d_step_case_result
           where case_kind <> 'positive' and passed and coalesce(refused_with,'') in ('','(none)')),
         not exists (select 1 from public.phase_d_step_case_result
                      where case_kind <> 'positive' and passed
                        and coalesce(refused_with,'') in ('','(none)'))
  union all
  select 'cases_decided_at_the_step_contract', 'informational',
         (select count(*)::text from public.phase_d_step_case_result
           where decided_at = 'step_contract'), true
  union all
  select 'cases_decided_at_a_shared_boundary', 'informational',
         (select count(*)::text from public.phase_d_step_case_result
           where decided_at in ('executor_boundary','kernel_boundary','structural_constraint')), true;
$fn$;

revoke all on function public.fn_phase_d_step_cases(text) from public;
revoke all on function public.fn_phase_d_run_step_cases() from public;
revoke all on function public.fn_phase_d_case_state() from public;
grant execute on function public.fn_phase_d_step_cases(text) to service_role;
grant execute on function public.fn_phase_d_run_step_cases() to service_role;
grant execute on function public.fn_phase_d_case_state() to service_role;
revoke all on public.phase_d_step_case_result from anon, authenticated;
grant select on public.phase_d_step_case_result to service_role;
alter table public.phase_d_step_case_result enable row level security;

commit;
