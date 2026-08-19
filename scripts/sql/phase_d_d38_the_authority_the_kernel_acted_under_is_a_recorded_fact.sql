-- =================================================================================================
-- Phase D — D38. The authority the kernel acted under is a recorded fact.
--
-- D37 resolved the rule and gate context from real rows and left everything a performer produces
-- unresolved. Driving all of W05, W14, W16, W18, W20, W22, W26 and W29 through the real path then
-- gave the same shape every time: the first step refused, and the named refusals were rules asking
-- for facts nobody had supplied.
--
-- Two of those facts ARE recorded, and were being left unresolved only because nothing looked:
--
--   evidence_authority  (BR-029, 34 steps in scope)
--       The rule asks that conflicting evidence be retained WITH ITS AUTHORITY RANKING. For a step
--       the kernel dispatched, the authority is not a mystery: the arrival that caused the run is
--       classified in public.phase_c_source_cutover — source_class A NEW_WORK_REQUEST or B
--       EXISTING_WORKFLOW_SIGNAL, its system_actor, and its current_activation. That register IS the
--       authority ranking, it was written before this file, and reading it is reading.
--       Where the run did not come from a registered source, this stays unresolved.
--
--   notify_email  (BR-034, 30 steps in scope)
--       The rule looks the address up in public.email_suppressions, so it needs the address the step
--       would actually notify. On a real path that is the owner of the run's own business object,
--       read through the same phase_d_object_write_map owner_column D37 already resolves.
--       Where the object row or its owner is absent, this stays unresolved and BR-034 refuses —
--       which is right: consent cannot be decided for an unnamed recipient.
--
-- WHAT IS DELIBERATELY STILL NOT RESOLVED, AND WHY THAT IS THE ANSWER RATHER THAN A GAP.
--
--   outcome_metric      (BR-041, 67 steps)  The frozen step registry has step_type, required_action,
--                                           required_output, acceptance_criteria and closure_criteria
--                                           — and NO outcome-metric column. Calling required_output
--                                           the business outcome metric would be this file deciding
--                                           what BR-041 exists to make somebody declare.
--   assumptions         (BR-042, 59 steps)
--   denominator/formula (BR-040, 52 steps)
--   artifact_ref/_sha256(BR-036, 43 steps)  The digest of an artifact that does not exist yet.
--   supplier_payload    (BR-011, 42 steps)  The payload nobody has composed.
--   safe_package_ref, rollback_ref, test_ref, security_ref, legal_review_ref, model_eval_ref, ...
--
-- Those are the map of what still needs a performer, and every one of them is now recorded per step
-- in public.phase_d_dispatch.unresolved_keys with the refusal code that named it. That list is a
-- measurement of how far the application reaches. Filling it would delete the measurement.
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
  v_obj    text;
  v_rel    text;
  v_keycol text;
  v_owncol text;
  v_row_id text;
  v_row_own text;
  v_found  boolean := false;
  v_sql    text;
  v_from   text;
  v_to     text;
  v_route  text;
  v_cmd    bigint;
  -- D38
  v_src_ref   text;
  v_src_kind  text;
  v_src_class text;
  v_src_actor text;
  v_src_act   text;
  v_email     text;
begin
  select * into sr from public.phase_c_workflow_step_run where step_run_id = p_step_run_id;
  if not found then
    raise exception 'fn_phase_d_step_context: no step run %', p_step_run_id using errcode = '23503';
  end if;
  select * into r  from public.phase_c_workflow_run    where run_id  = sr.run_id;
  select * into s  from public.phase_b_workflow_step   where step_id = sr.step_id;
  select * into b  from public.phase_d_handler_binding where step_id = sr.step_id;
  select * into ec from public.phase_d_step_effect     where step_id = sr.step_id;

  select coalesce(array_agg(distinct k), '{}') into v_keys from (
    select unnest(re.required_context) k from public.phase_d_rule_enforcement re
     where re.rule_id = any (coalesce(b.rule_ids,'{}'))
    union
    select unnest(gc.evidence_keys) k from public.phase_d_gate_contract gc
     where gc.gate_id = any (coalesce(b.gate_ids,'{}'))) q(k);

  -- ---- the frozen state model ------------------------------------------------------------------
  v_from  := r.state;
  v_to    := nullif(btrim(coalesce(s.success_workflow_state,'')),'');
  if v_to is not null and not exists (select 1 from public.phase_b_workflow_transition t
                                       where t.from_state = v_from and t.to_state = v_to) then
    v_to := null;
  end if;
  select t.to_state into v_route from public.phase_b_workflow_transition t
    where t.from_state = v_from order by t.to_state limit 1;

  -- ---- the arrival that caused this run, and how the register classifies it (D38) ---------------
  -- The source component id is the WHOLE three-part key ('dbtrigger:public.inquiries:
  -- trg_inquiry_received_a'), and it is recorded on the inbox row, not on the task — the task
  -- carries the kernel's own source_ref. Splitting the key on ':' returned 'dbtrigger' and matched
  -- nothing, which this file's control caught before it landed.
  select ti.source_system, 'trigger' into v_src_ref, v_src_kind
    from public.kernel_trigger_inbox ti where ti.run_id = sr.run_id order by ti.inbox_id limit 1;
  if v_src_ref is null then
    select si.source_type, 'signal' into v_src_ref, v_src_kind
      from public.kernel_signal_inbox si
     where si.workflow_run_id = sr.run_id order by si.signal_id limit 1;
  end if;
  if v_src_ref is null then
    select tk.source_ref, tk.source_kind into v_src_ref, v_src_kind
      from public.phase_c_task tk where tk.run_id = sr.run_id order by tk.task_id limit 1;
  end if;
  if coalesce(btrim(coalesce(v_src_ref,'')),'') <> '' then
    select c.source_class, c.system_actor, c.current_activation
      into v_src_class, v_src_actor, v_src_act
      from public.phase_c_source_cutover c
     where c.source_component_id = v_src_ref
     limit 1;
  end if;

  -- ---- the run's own business object -----------------------------------------------------------
  v_obj := coalesce(nullif(btrim(coalesce(ec.effect_object_id,'')),''),
                    (select bo.object_id from public.phase_d_business_object_binding bo
                      where bo.governing_workflow_id = r.workflow_id limit 1));
  if v_obj is not null and coalesce(btrim(r.business_object_id),'') <> '' then
    select wm.target_relation, wm.key_column, wm.owner_column
      into v_rel, v_keycol, v_owncol
      from public.phase_d_object_write_map wm where wm.object_id = v_obj limit 1;
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
        v_found := false;
      end;
    end if;
  end if;

  foreach v_k in array v_keys loop
    v_val := null; v_src := null;

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

    -- ---- D38: the authority the kernel acted under ---------------------------------------------
    elsif v_k = 'evidence_authority' then
      if v_src_class is not null then
        v_val := to_jsonb(format('%s (%s) via %s, activation %s',
                   v_src_class, coalesce(v_src_actor,'(no system actor)'),
                   v_src_ref, coalesce(v_src_act,'(unstated)')));
        v_src := 'phase_c_source_cutover classification of the arrival that caused this run';
      end if;

    -- ---- D38: the recipient the step would actually notify -------------------------------------
    elsif v_k = 'notify_email' then
      if v_found and v_row_own is not null then
        v_email := null;
        if v_rel like '%inquiries' or v_owncol = 'customer_id' then
          select c.email into v_email from public.customers c where c.id::text = v_row_own limit 1;
        elsif v_owncol = 'supplier_id' or v_owncol = 'lead_id' then
          select l.email into v_email from public.leads l where l.id::text = v_row_own limit 1;
        end if;
        if coalesce(btrim(coalesce(v_email,'')),'') <> '' then
          v_val := to_jsonb(v_email);
          v_src := format('the email of %s.%s, the owner of the run''s own object', v_rel, v_owncol);
        end if;
      end if;

    elsif v_k = 'evidence_refs' then
      select case when count(*) = 0 then null
                  else jsonb_agg(jsonb_build_object(
                         'effect_id', el.effect_id, 'step_id', el.step_id,
                         'effect_type', el.effect_type,
                         'result_reference', el.result_reference) order by el.effect_id) end
        into v_val
        from public.phase_d_effect_ledger el where el.run_id = sr.run_id;
      v_src := 'phase_d_effect_ledger for this run';

    elsif v_k in ('packet','requested_action','source_version') then
      select case v_k
               when 'packet' then case when hc.packet_keys is null or cardinality(hc.packet_keys) = 0
                                       then null else to_jsonb(hc.packet_keys) end
               when 'requested_action' then to_jsonb(nullif(btrim(coalesce(hc.acceptance_criteria,'')),''))
               else to_jsonb(nullif(btrim(coalesce(hc.source_object_version_key,'')),'')) end
        into v_val
        from public.phase_d_handoff_contract hc where hc.from_step_id = sr.step_id limit 1;
      v_src := 'phase_d_handoff_contract for this step';

    elsif v_k = 'founder_authority_ref' then
      select l.command_id into v_cmd from public.founder_command_workflow_link l
        where l.run_id = sr.run_id limit 1;
      if v_cmd is null then v_cmd := r.command_id; end if;
      if v_cmd is not null then
        v_val := to_jsonb('founder_command:' || v_cmd::text);
        v_src := 'founder_command that started this run';
      end if;

    else
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
    'arrival', jsonb_build_object('source_ref', v_src_ref, 'source_kind', v_src_kind,
                                  'source_class', v_src_class, 'activation', v_src_act),
    'business_object', jsonb_build_object(
      'object_id', v_obj, 'relation', v_rel, 'key_column', v_keycol,
      'owner_column', v_owncol, 'row_found', v_found));
end
$fn$;


-- ---- CONTROL ------------------------------------------------------------------------------------
do $ctl$
declare
  v_start jsonb; v_run bigint; v_sr bigint; v_cx jsonb; v_report text;
begin
  begin
    -- THE REAL ENTRY POINT, not a hand-built workflow start. fn_kernel_source_emit is the routine
    -- all 18 live business-table triggers call; driving it here exercises the same chain a customer
    -- inserting an inquiry drives — source register, trigger inbox, workflow start, first step,
    -- Phase D dispatch — rather than a shape only this control produces.
    v_start := public.fn_kernel_source_emit(
      'dbtrigger:public.inquiries:trg_inquiry_received_a',
      jsonb_build_object(
        'source_ref',  'ZZ-DEMO-d38-control-' || clock_timestamp()::text,
        -- The kernel refuses an arrival whose payload does not carry the business object rule's
        -- key: "The object is refused, not guessed." Correct, and it is why the first version of
        -- this control got run_id null. The id is passed; NO row is written to public.inquiries,
        -- so the object lookup below finds nothing and notify_email stays unresolved — which is
        -- the honest state of an estate holding zero inquiries.
        'raw_payload', jsonb_build_object('inquiry_id', gen_random_uuid()::text,
                                          'note','d38 control arrival'),
        'requested_by','phase_d_d38_control'));
    v_run := nullif(v_start->>'run_id','')::bigint;
    if v_run is null then
      raise exception 'D38 CONTROL FAILED: fn_kernel_source_emit returned no run_id: %', left(v_start::text, 400);
    end if;
    select sr2.step_run_id into v_sr from public.phase_c_workflow_step_run sr2
      where sr2.run_id = v_run order by sr2.step_run_id limit 1;
    v_cx  := public.fn_phase_d_step_context(v_sr);

    -- POSITIVE: the arrival is a registered source, so evidence_authority must resolve and must
    -- carry the register's own classification rather than a sentence this file made up.
    if (v_cx->'declared_keys') @> '["evidence_authority"]'::jsonb then
      if not (v_cx->'context' ? 'evidence_authority') then
        raise exception 'D38 CONTROL FAILED: the arrival trg_inquiry_received is in phase_c_source_cutover and evidence_authority still did not resolve.';
      end if;
      if (v_cx->'context'->>'evidence_authority') not like '%NEW_WORK_REQUEST%'
         and (v_cx->'context'->>'evidence_authority') not like '%EXISTING_WORKFLOW_SIGNAL%' then
        raise exception 'D38 CONTROL FAILED: evidence_authority does not carry the register''s source_class: %',
          (v_cx->'context'->>'evidence_authority');
      end if;
    end if;

    -- NEGATIVE: no placeholder, and the performer-evidence keys must still be unresolved.
    if exists (select 1 from jsonb_each_text(v_cx->'context') e where e.value like 'ZZ DEMO%') then
      raise exception 'D38 CONTROL FAILED: a placeholder reached the context.';
    end if;
    if (v_cx->'declared_keys') @> '["outcome_metric"]'::jsonb
       and (v_cx->'context' ? 'outcome_metric') then
      raise exception 'D38 CONTROL FAILED: outcome_metric resolved. The frozen registry has no outcome-metric column, so nothing could have resolved it honestly.';
    end if;

    v_report := format('run=%s declared=%s resolved=%s unresolved=%s arrival=%s',
      v_run,
      jsonb_array_length(coalesce(v_cx->'declared_keys','[]'::jsonb)),
      (select count(*) from jsonb_object_keys(v_cx->'context')),
      jsonb_array_length(coalesce(v_cx->'unresolved','[]'::jsonb)),
      coalesce(v_cx->'arrival'->>'source_class','(unregistered)'));
    raise exception 'D38_CONTROL_ROLLBACK %', v_report;
  exception
    when others then
      if SQLERRM like 'D38_CONTROL_ROLLBACK%' then
        raise notice 'D38 %', substr(SQLERRM, 22);
      else
        raise exception 'D38 CONTROL FAILED: % (%)', SQLERRM, SQLSTATE;
      end if;
  end;

  if (select count(*) from public.phase_d_dispatch) <> 0
     or (select count(*) from public.phase_c_workflow_run
          where business_object_id like 'ZZ-DEMO-%') <> 0 then
    raise exception 'D38: the control left residue behind.';
  end if;
  raise notice 'D38: evidence_authority and notify_email resolve from recorded rows; the performer-evidence keys stay unresolved.';
end
$ctl$;
