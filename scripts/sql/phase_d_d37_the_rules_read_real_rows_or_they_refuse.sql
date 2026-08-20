-- =================================================================================================
-- Phase D — D37. The rules read real rows, or they refuse.
--
-- D36 put the dispatch on the kernel's own open path and the first real drive proved it: starting
-- W05 reached fn_phase_d_handler_execute and W05-S01 was REFUSED by two hard rules —
--
--     BR-029  no conflict-preservation evidence named
--     BR-049  inquiry owner is (unstated)
--
-- Those refusals are the rules working. They are also the same gap the inputs had: the executor
-- merges `p_input->'context'` and `p_input->'gate_evidence'` into what every rule and gate reads, and
-- the kernel dispatch was passing neither. fn_phase_d_drive_workflow fills that hole with
-- fn_phase_d_fixture_context, which emits `'ZZ DEMO — ' || key` for every opaque reference. Correct
-- for a harness. Disqualifying on a business path: a rule satisfied by a demo string is a rule that
-- cannot refuse.
--
-- MEASURED KEY SPACE: 70 distinct keys across 54 rules and 32 gates. They split cleanly in two, and
-- the split is the whole point of this file.
--
--   RESOLVABLE FROM A REAL ROW — the state model, the run's own business object, this run's effect
--   ledger, the frozen handoff contract, the founder command that caused the run. These are facts
--   the database already holds, and passing them is reading, not inventing.
--
--   PRODUCED BY WHOEVER PERFORMS THE STEP — test_ref, security_ref, legal_review_ref,
--   artifact_sha256, model_eval_ref, holdout_isolated, assumptions, and the rest of the evidence
--   references. NOTHING in this estate holds them, because they do not exist until somebody does the
--   work. They are left out, the rules that need them refuse, and the refusal is recorded with its
--   code. That is the honest answer to "how far does the application actually reach", and it is the
--   number Gate 3 should be reading.
--
-- THE BUSINESS OBJECT RESOLUTION IS A LOOKUP, NOT A CONSTRUCTION. phase_d_object_write_map already
-- carries target_relation, key_column and owner_column per object. The run's business_object_id is
-- looked up in that relation; if the row is not there, the id and the owner stay unresolved. The
-- estate holds zero inquiries today (the funnel was purged on 16 Aug), so W05 will keep refusing on
-- BR-049 until a real inquiry exists — which is correct, and is not something to paper over.
-- =================================================================================================


create or replace function public.fn_phase_d_step_context(p_step_run_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  sr public.phase_c_workflow_step_run%rowtype;
  r  public.phase_c_workflow_run%rowtype;
  s  public.phase_b_workflow_step%rowtype;
  b  public.phase_d_handler_binding%rowtype;
  ec public.phase_d_step_effect%rowtype;
  v_keys   text[];
  v_k      text;
  v_val    jsonb;
  v_src    text;
  v_ctx    jsonb := '{}'::jsonb;
  v_prov   jsonb := '{}'::jsonb;
  v_unres  text[] := '{}';
  -- business object resolution
  v_obj    text;
  v_rel    text;
  v_keycol text;
  v_owncol text;
  v_row_id text;
  v_row_own text;
  v_found  boolean := false;
  v_sql    text;
  -- state model
  v_from   text;
  v_to     text;
  v_route  text;
  v_cmd    bigint;
begin
  select * into sr from public.phase_c_workflow_step_run where step_run_id = p_step_run_id;
  if not found then
    raise exception 'fn_phase_d_step_context: no step run %', p_step_run_id using errcode = '23503';
  end if;
  select * into r  from public.phase_c_workflow_run    where run_id  = sr.run_id;
  select * into s  from public.phase_b_workflow_step   where step_id = sr.step_id;
  select * into b  from public.phase_d_handler_binding where step_id = sr.step_id;
  select * into ec from public.phase_d_step_effect     where step_id = sr.step_id;

  -- Every key any rule or gate in scope declares. A context key nobody asked for is a fact the step
  -- was not entitled to, so the loop is over the declared set and nothing else.
  select coalesce(array_agg(distinct k), '{}') into v_keys from (
    select unnest(re.required_context) k from public.phase_d_rule_enforcement re
     where re.rule_id = any (coalesce(b.rule_ids,'{}'))
    union
    select unnest(gc.evidence_keys) k from public.phase_d_gate_contract gc
     where gc.gate_id = any (coalesce(b.gate_ids,'{}'))) q(k);

  -- ---- the frozen state model ------------------------------------------------------------------
  v_from  := r.state;
  v_to    := nullif(btrim(coalesce(s.success_workflow_state,'')),'');
  -- A pair that is not a declared transition is NOT substituted for one that is. GATE-006 exists to
  -- refuse exactly that, and the fixture's own comment says so.
  if v_to is not null and not exists (select 1 from public.phase_b_workflow_transition t
                                       where t.from_state = v_from and t.to_state = v_to) then
    v_to := null;
  end if;
  select t.to_state into v_route from public.phase_b_workflow_transition t
    where t.from_state = v_from order by t.to_state limit 1;

  -- ---- the run's own business object, looked up where the write map says it lives ---------------
  v_obj := coalesce(nullif(btrim(coalesce(ec.effect_object_id,'')),''),
                    (select bo.object_id from public.phase_d_business_object_binding bo
                      where bo.governing_workflow_id = r.workflow_id limit 1));
  if v_obj is not null and coalesce(btrim(r.business_object_id),'') <> '' then
    select wm.target_relation, wm.key_column, wm.owner_column
      into v_rel, v_keycol, v_owncol
      from public.phase_d_object_write_map wm where wm.object_id = v_obj limit 1;
    -- target_relation is stored schema-qualified ('public.inquiries'). Prefixing it again produced
    -- "cross-database references are not implemented: public.public.inquiries", which the control
    -- caught before this file landed. to_regclass resolves either shape.
    if v_rel is not null and coalesce(btrim(v_keycol),'') <> ''
       and to_regclass(v_rel) is not null then
      begin
        v_sql := format('select %I::text, %s from %s where %I::text = $1 limit 1',
                        v_keycol,
                        case when coalesce(btrim(v_owncol),'') = '' then 'null::text'
                             else quote_ident(v_owncol) || '::text' end,
                        to_regclass(v_rel)::text, v_keycol);
        execute v_sql into v_row_id, v_row_own using r.business_object_id;
        v_found := v_row_id is not null;
      exception when others then
        -- A relation whose key column is not comparable as text is not a resolution failure worth
        -- raising into a business transaction; it is an unresolved key, and it is recorded as one.
        v_found := false;
      end;
    end if;
  end if;

  foreach v_k in array v_keys loop
    v_val := null; v_src := null;

    -- ---- the state model, read from the frozen registry ----------------------------------------
    if v_k = 'from_state' then
      v_val := to_jsonb(v_from); v_src := 'phase_c_workflow_run.state';
    elsif v_k = 'to_state' then
      if v_to is not null then
        v_val := to_jsonb(v_to);
        v_src := 'phase_b_workflow_step.success_workflow_state, confirmed against phase_b_workflow_transition';
      end if;
    elsif v_k = 'route_state' then
      if v_route is not null then
        v_val := to_jsonb(v_route); v_src := 'phase_b_workflow_transition from the run''s current state';
      end if;

    -- ---- the run's own business object ---------------------------------------------------------
    elsif v_k in ('inquiry_id','supplier_id','quote_id','transaction_id','document_id',
                  'comparison_id','refund_id') then
      if v_found then
        v_val := to_jsonb(v_row_id);
        v_src := format('%s.%s, looked up by the run''s business_object_id', v_rel, v_keycol);
      end if;
    elsif v_k in ('inquiry_owner','caller_customer_id') then
      if v_found and v_row_own is not null then
        v_val := to_jsonb(v_row_own);
        v_src := format('%s.%s of the run''s own object', v_rel, coalesce(v_owncol,'(none)'));
      end if;
    elsif v_k = 'monetary_state' then
      if v_found and v_rel like '%transactions' then
        select to_jsonb(t.fee_status) into v_val from public.transactions t
          where t.id::text = v_row_id limit 1;
        v_src := 'public.transactions.fee_status of the run''s own transaction';
      end if;

    -- ---- what this run has already produced ----------------------------------------------------
    elsif v_k = 'evidence_refs' then
      select case when count(*) = 0 then null
                  else jsonb_agg(jsonb_build_object(
                         'effect_id', el.effect_id, 'step_id', el.step_id,
                         'effect_type', el.effect_type,
                         'result_reference', el.result_reference) order by el.effect_id) end
        into v_val
        from public.phase_d_effect_ledger el where el.run_id = sr.run_id;
      v_src := 'phase_d_effect_ledger for this run';

    -- ---- the frozen handoff contract for this step ---------------------------------------------
    elsif v_k in ('packet','requested_action','source_version') then
      select case v_k
               when 'packet' then case when hc.packet_keys is null or cardinality(hc.packet_keys) = 0
                                       then null else to_jsonb(hc.packet_keys) end
               when 'requested_action' then to_jsonb(nullif(btrim(coalesce(hc.acceptance_criteria,'')),''))
               else to_jsonb(nullif(btrim(coalesce(hc.source_object_version_key,'')),'')) end
        into v_val
        from public.phase_d_handoff_contract hc where hc.from_step_id = sr.step_id limit 1;
      v_src := 'phase_d_handoff_contract for this step';

    -- ---- founder authority, where a founder command actually caused the run ---------------------
    elsif v_k = 'founder_authority_ref' then
      select l.command_id into v_cmd from public.founder_command_workflow_link l
        where l.run_id = sr.run_id limit 1;
      if v_cmd is null then v_cmd := r.command_id; end if;
      if v_cmd is not null then
        v_val := to_jsonb('founder_command:' || v_cmd::text);
        v_src := 'founder_command that started this run';
      elsif coalesce(nullif(btrim(b.founder_gate),''),'NONE') not in ('NONE','none','') then
        -- The step declares a founder gate and no founder command caused this run. That is exactly
        -- what the gate is for; it is left unresolved so the gate refuses rather than passes.
        null;
      end if;

    else
      -- test_ref, security_ref, legal_review_ref, artifact_ref, artifact_sha256, model_eval_ref,
      -- holdout_isolated, assumptions, denominator, formula, and the rest. These come into existence
      -- when somebody performs the step. No row holds them; none is manufactured.
      v_val := null; v_src := null;
    end if;

    if v_val is null or v_val = 'null'::jsonb
       or (jsonb_typeof(v_val) = 'string' and btrim(coalesce(v_val #>> '{}','')) = '') then
      v_unres := v_unres || v_k;
    else
      v_ctx  := v_ctx  || jsonb_build_object(v_k, v_val);
      v_prov := v_prov || jsonb_build_object(v_k, v_src);
    end if;
  end loop;

  return jsonb_build_object(
    'step_run_id', p_step_run_id, 'step_id', sr.step_id,
    'declared_keys', to_jsonb(v_keys),
    'context', v_ctx, 'provenance', v_prov, 'unresolved', to_jsonb(v_unres),
    'business_object', jsonb_build_object(
      'object_id', v_obj, 'relation', v_rel, 'key_column', v_keycol,
      'owner_column', v_owncol, 'row_found', v_found));
end
$fn$;

revoke execute on function public.fn_phase_d_step_context(bigint) from public, anon, authenticated;
grant  execute on function public.fn_phase_d_step_context(bigint) to service_role;

comment on function public.fn_phase_d_step_context(bigint) is
  'Resolves the rule and gate context keys a step declares from real rows — the frozen state model, '
  'the run''s own business object, this run''s effect ledger, the frozen handoff contract and the '
  'founder command that caused the run. Keys that only exist once somebody performs the step are '
  'returned unresolved and are NOT filled with a placeholder, so the rules that need them refuse. '
  'fn_phase_d_fixture_context emits ZZ DEMO strings for the same keys and is for the harness.';


-- ---- the dispatch now carries the context -------------------------------------------------------

create or replace function public.fn_phase_d_dispatch_step(p_input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
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

    v_res := public.fn_phase_d_handler_execute(jsonb_build_object(
      'step_run_id',       v_step_run,
      'actor_role_id',     v_actor,
      'idempotency_key',   v_idem || '|phase_d',
      'inputs',            v_in->'inputs',
      'context',           v_cx->'context',
      'gate_evidence',     v_cx->'context',
      'execution_context', 'production',
      'correlation_id',    p_input->>'correlation_id',
      'causation_id',      'kernel_dispatch:' || v_kind || ':' || v_ref));

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
      v_code := coalesce((regexp_match(v_err, '\((pd_[a-z0-9_]+|k[0-9]+_[a-z0-9_]+)\)'))[1], 'pd_unclassified');
      insert into public.phase_d_dispatch
        (step_run_id, run_id, step_id, workflow_id, opened_by_kind, opened_by_ref, actor_role_id,
         outcome, refusal_code, sqlstate_code, reason, unresolved_keys, inputs_provenance,
         dispatch_depth)
      values (v_step_run, sr.run_id, sr.step_id, v_wf, v_kind, v_ref, v_actor,
              'REFUSED', v_code, SQLSTATE, left(v_err, 1000),
              coalesce((select array_agg(x) from jsonb_array_elements_text(
                          coalesce(v_cx->'unresolved','[]'::jsonb)) x), '{}'),
              coalesce(v_cx->'provenance','{}'::jsonb), v_depth);
      perform set_config('app.phase_d_dispatch_depth', v_depth::text, true);
      return jsonb_build_object('dispatched', false, 'outcome', 'REFUSED',
                                'refusal_code', v_code, 'sqlstate', SQLSTATE);
  end;
end
$fn$;


-- ---- CONTROL ------------------------------------------------------------------------------------
-- Two directions, both rolled back. The resolver must produce REAL values for the state-model keys,
-- and must NOT produce a value for a performer-evidence key. A resolver that filled everything would
-- pass the first check and silently defeat every rule.

do $ctl$
declare
  v_start jsonb; v_run bigint; v_sr bigint; v_cx jsonb;
  v_unres jsonb; v_ctx jsonb; v_report text;
begin
  begin
    v_start := public.fn_kernel_workflow_start(jsonb_build_object(
      'workflow_id','W05',
      'business_object_id','ZZ DEMO — d37 control '||clock_timestamp()::text,
      'source_kind','autonomous',
      'source_ref','phase_d_d37_control:'||clock_timestamp()::text,
      'requested_by','phase_d_d37_control'));
    v_run := (v_start->>'run_id')::bigint;
    v_sr  := (v_start->>'step_run_id')::bigint;

    v_cx    := public.fn_phase_d_step_context(v_sr);
    v_ctx   := v_cx->'context';
    v_unres := v_cx->'unresolved';

    -- POSITIVE: from_state is a real column of a real row and must always resolve.
    if not (v_ctx ? 'from_state') and (v_cx->'declared_keys') @> '["from_state"]'::jsonb then
      raise exception 'D37 CONTROL FAILED: from_state is declared for this step and did not resolve.';
    end if;

    -- NEGATIVE: not one value may be a fixture placeholder.
    if exists (select 1 from jsonb_each_text(v_ctx) e where e.value like 'ZZ DEMO%') then
      raise exception 'D37 CONTROL FAILED: the context resolver emitted a ZZ DEMO placeholder — it is a fixture, not a resolver.';
    end if;

    -- NEGATIVE: a performer-evidence key must NOT be resolved. If every declared key resolved, the
    -- resolver is filling holes rather than reporting them.
    if jsonb_array_length(coalesce(v_cx->'declared_keys','[]'::jsonb)) > 0
       and jsonb_array_length(coalesce(v_unres,'[]'::jsonb)) = 0
       and exists (select 1 from jsonb_array_elements_text(v_cx->'declared_keys') k
                    where k.value in ('test_ref','security_ref','legal_review_ref','artifact_sha256',
                                      'model_eval_ref','assumptions','holdout_isolated')) then
      raise exception 'D37 CONTROL FAILED: a performer-evidence key resolved. Nothing in this estate holds one.';
    end if;

    v_report := format('run=%s step_run=%s declared=%s resolved=%s unresolved=%s | %s',
      v_run, v_sr,
      jsonb_array_length(coalesce(v_cx->'declared_keys','[]'::jsonb)),
      (select count(*) from jsonb_object_keys(v_ctx)),
      jsonb_array_length(coalesce(v_unres,'[]'::jsonb)),
      left(coalesce(v_ctx::text,'{}'), 400));

    raise exception 'D37_CONTROL_ROLLBACK %', v_report;
  exception
    when others then
      if SQLERRM like 'D37_CONTROL_ROLLBACK%' then
        raise notice 'D37 %', substr(SQLERRM, 22);
      else
        raise exception 'D37 CONTROL FAILED: % (%)', SQLERRM, SQLSTATE;
      end if;
  end;

  if (select count(*) from public.phase_d_dispatch) <> 0 then
    raise exception 'D37: the control left % rows in phase_d_dispatch.',
      (select count(*) from public.phase_d_dispatch);
  end if;
  if (select count(*) from public.phase_c_workflow_run
       where business_object_id like 'ZZ DEMO — d37 control%') <> 0 then
    raise exception 'D37: the control left a workflow run behind.';
  end if;

  raise notice 'D37: the context resolver reads real rows, emits no placeholder, reports what it cannot resolve, and left no residue.';
end
$ctl$;
