-- =================================================================================================
-- Phase D — D39. Two ordering defects the first real inquiry found.
--
-- An actual `insert into public.inquiries` was driven end to end — customer row, inquiry row,
-- trg_inquiry_received_a, fn_kernel_source_emit, fn_kernel_trigger_submit, fn_kernel_workflow_start,
-- the first step run, and the D36 dispatch — inside an aborted transaction. The chain fires. The
-- step still refused, and both reasons were this side of the boundary, not the rules':
--
-- 1. THE RUN'S BUSINESS OBJECT ID CARRIES ITS TYPE. The kernel writes 'inquiry:6bb9a28b-…', built
--    from the object rule 'inquiry:{inquiry_id}'. D37 looked that whole string up in
--    public.inquiries.id, found nothing, and left inquiry_id and inquiry_owner unresolved — so
--    BR-049 refused an inquiry whose owner was sitting one column away. The prefix is stripped now,
--    and ONLY when it is the object's own prefix: a blind split on ':' would corrupt any identifier
--    that legitimately contains one.
--
-- 2. THE INBOX ROW HAS NO run_id YET WHEN THE FIRST STEP DISPATCHES. kernel_trigger_inbox.run_id is
--    stamped after fn_kernel_workflow_start returns, and the dispatch happens INSIDE it. Resolving
--    the arrival by run_id therefore worked for every successor step and failed for the first one —
--    the only step an autonomous arrival actually causes. Called by hand a moment later it resolved
--    perfectly, which is exactly how a defect of this shape stays hidden. The arrival is now matched
--    on business_object_id, which both sides derive from the same object rule and which exists
--    before the run does; the run_id match is kept first for later steps.
--
-- Neither was visible from a harness. fn_phase_d_drive_workflow calls fn_kernel_workflow_start
-- itself and passes its own unprefixed business_object_id, so it never produced the prefixed form,
-- and it never writes an inbox row at all.
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
  v_boid   text;
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

  -- ---- the arrival that caused this run, and how the register classifies it ---------------------
  select ti.source_system, 'trigger' into v_src_ref, v_src_kind
    from public.kernel_trigger_inbox ti where ti.run_id = sr.run_id order by ti.inbox_id desc limit 1;
  if v_src_ref is null and coalesce(btrim(coalesce(r.business_object_id,'')),'') <> '' then
    -- D39(2). The first step of a run dispatches INSIDE fn_kernel_workflow_start, before the inbox
    -- row is stamped with run_id. business_object_id is on both sides already, derived from the same
    -- object rule, so it is what links them at the only moment that matters.
    select ti.source_system, 'trigger' into v_src_ref, v_src_kind
      from public.kernel_trigger_inbox ti
     where ti.business_object_id = r.business_object_id
     order by ti.inbox_id desc limit 1;
  end if;
  if v_src_ref is null then
    select si.source_type, 'signal' into v_src_ref, v_src_kind
      from public.kernel_signal_inbox si
     where si.workflow_run_id = sr.run_id order by si.signal_id desc limit 1;
  end if;
  if v_src_ref is null then
    select tk.source_ref, tk.source_kind into v_src_ref, v_src_kind
      from public.phase_c_task tk where tk.run_id = sr.run_id order by tk.task_id limit 1;
  end if;
  if coalesce(btrim(coalesce(v_src_ref,'')),'') <> '' then
    select c.source_class, c.system_actor, c.current_activation
      into v_src_class, v_src_actor, v_src_act
      from public.phase_c_source_cutover c
     where c.source_component_id = v_src_ref limit 1;
  end if;

  -- ---- the run's own business object -----------------------------------------------------------
  v_obj := coalesce(nullif(btrim(coalesce(ec.effect_object_id,'')),''),
                    (select bo.object_id from public.phase_d_business_object_binding bo
                      where bo.governing_workflow_id = r.workflow_id limit 1));
  v_boid := nullif(btrim(coalesce(r.business_object_id,'')),'');
  -- D39(1). The kernel writes the object rule out in full: 'inquiry:<uuid>'. Strip ONLY that
  -- object's own prefix; a blind split on ':' would corrupt an identifier that contains one.
  if v_obj is not null and v_boid is not null and v_boid like (v_obj || ':%') then
    v_boid := substr(v_boid, length(v_obj) + 2);
  end if;
  if v_obj is not null and coalesce(v_boid,'') <> '' then
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
        execute v_sql into v_row_id, v_row_own using v_boid;
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

    elsif v_k = 'evidence_authority' then
      if v_src_class is not null then
        v_val := to_jsonb(format('%s (%s) via %s, activation %s',
                   v_src_class, coalesce(v_src_actor,'(no system actor)'),
                   v_src_ref, coalesce(v_src_act,'(unstated)')));
        v_src := 'phase_c_source_cutover classification of the arrival that caused this run';
      end if;

    elsif v_k = 'notify_email' then
      if v_found and v_row_own is not null then
        v_email := null;
        if v_owncol = 'customer_id' then
          select c.email into v_email from public.customers c where c.id::text = v_row_own limit 1;
        elsif v_owncol in ('supplier_id','lead_id') then
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
      'object_id', v_obj, 'object_key', v_boid, 'relation', v_rel, 'key_column', v_keycol,
      'owner_column', v_owncol, 'row_found', v_found));
end
$fn$;


-- ---- CONTROL — driven from a real customer and a real inquiry, then rolled back -----------------
-- This is the only control that could have caught either defect: both are visible ONLY when the
-- business row exists AND the dispatch happens inside fn_kernel_workflow_start. Both directions are
-- exercised — the owner must resolve when the row is there, and must NOT resolve when it is not.

do $ctl$
declare
  v_cust uuid; v_inq uuid; v_sr bigint; v_run bigint; v_cx jsonb;
  v_before_inq int; v_before_cust int; v_report text;
begin
  select count(*) into v_before_inq  from public.inquiries;
  select count(*) into v_before_cust from public.customers;

  begin
    insert into public.customers (email, full_name)
    values ('zz-demo-d39-control@example.invalid','ZZ DEMO — d39 control')
    returning id into v_cust;
    insert into public.inquiries (customer_id, category, status)
    values (v_cust, 'jewellery', 'open')
    returning id into v_inq;

    select d.step_run_id, d.run_id into v_sr, v_run
      from public.phase_d_dispatch d order by d.dispatch_id desc limit 1;
    if v_sr is null then
      raise exception 'D39 CONTROL FAILED: inserting a real inquiry produced no Phase D dispatch row at all.';
    end if;

    v_cx := public.fn_phase_d_step_context(v_sr);

    -- POSITIVE 1: the arrival must classify. It is trg_inquiry_received_a, class A, in the register.
    if (v_cx->'arrival'->>'source_class') is distinct from 'A NEW_WORK_REQUEST' then
      raise exception 'D39 CONTROL FAILED: the arrival did not classify (got %). The inbox row is not being matched at first-step dispatch time.',
        coalesce(v_cx->'arrival'->>'source_class','(null)');
    end if;

    -- POSITIVE 2: the run's own inquiry row must be found, and its owner must be the customer.
    if not (v_cx->'business_object'->>'row_found')::boolean then
      raise exception 'D39 CONTROL FAILED: the run''s own inquiry row was not found. object_key=% relation=%',
        coalesce(v_cx->'business_object'->>'object_key','(null)'),
        coalesce(v_cx->'business_object'->>'relation','(null)');
    end if;
    if (v_cx->'context'->>'inquiry_owner') is distinct from v_cust::text then
      raise exception 'D39 CONTROL FAILED: inquiry_owner resolved to % and the row belongs to %.',
        coalesce(v_cx->'context'->>'inquiry_owner','(null)'), v_cust;
    end if;

    -- NEGATIVE: no placeholder, and performer evidence still unresolved.
    if exists (select 1 from jsonb_each_text(v_cx->'context') e where e.value like 'ZZ DEMO%') then
      raise exception 'D39 CONTROL FAILED: a placeholder reached the context.';
    end if;

    v_report := format('inquiry=%s owner=%s arrival=%s resolved=%s unresolved=%s | dispatch: %s | effects=%s',
      v_inq, v_cust, v_cx->'arrival'->>'source_class',
      (select count(*) from jsonb_object_keys(v_cx->'context')),
      jsonb_array_length(coalesce(v_cx->'unresolved','[]'::jsonb)),
      coalesce((select string_agg(format('%s:%s%s', d.step_id, d.outcome,
         case when d.refusal_code not in ('','(none)') then '/'||d.refusal_code else '' end),' '
         order by d.dispatch_id) from public.phase_d_dispatch d),'(none)'),
      (select count(*) from public.phase_d_effect_ledger));

    raise exception 'D39_CONTROL_ROLLBACK %', v_report;
  exception
    when others then
      if SQLERRM like 'D39_CONTROL_ROLLBACK%' then
        raise notice 'D39 %', substr(SQLERRM, 22);
      else
        raise exception 'D39 CONTROL FAILED: % (%)', SQLERRM, SQLSTATE;
      end if;
  end;

  -- NEGATIVE 2: with the inquiry rolled back, the same resolution must NOT find an owner. A
  -- resolver that answers either way is not reading the row.
  if (select count(*) from public.inquiries) <> v_before_inq
     or (select count(*) from public.customers) <> v_before_cust then
    raise exception 'D39: the control left business rows behind — inquiries %/% customers %/%.',
      (select count(*) from public.inquiries), v_before_inq,
      (select count(*) from public.customers), v_before_cust;
  end if;
  if (select count(*) from public.phase_d_dispatch) <> 0 then
    raise exception 'D39: the control left % dispatch rows behind.',
      (select count(*) from public.phase_d_dispatch);
  end if;

  raise notice 'D39: a real inquiry drives the whole chain, the arrival classifies at first-step dispatch time, the owner resolves from the row, and nothing was left behind.';
end
$ctl$;
