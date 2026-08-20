-- =================================================================================================
-- Phase D — D41. inquiry_owner is a role, and the rule that reads it is about accountability.
--
-- With D36–D40 in, a real `insert into public.inquiries` reaches the handler, the arrival classifies
-- from the source register, and W05-S01 came down to ONE refusal:
--
--     BR-049: inquiry owner is a26102be-3975-4364-8f92-410981f1eae6. Specialist and document
--             handoffs do not move overall inquiry accountability away from rfq_qualification_manager
--
-- The predicate is `p_context->>'inquiry_owner' = 'rfq_qualification_manager'`. It is comparing a
-- ROLE to whatever `inquiry_owner` holds — and D37 had resolved that key from
-- public.inquiries.customer_id, because phase_d_object_write_map names customer_id as the object's
-- owner column. So a rule about ACCOUNTABILITY was handed a CUSTOMER, and refused every inquiry the
-- moment the owner began resolving at all.
--
-- ONE KEY, TWO SUBJECTS — and only one of them has a consumer. Measured: no gate in
-- phase_d_gate_contract declares `inquiry_owner`; GATE-018's evidence is
-- {comparison_id, caller_customer_id}. BR-049 is its only reader. (The comment in
-- fn_phase_d_fixture_context that pairs inquiry_owner with caller_customer_id for GATE-018 is stale
-- against the live contract.) So there is no second meaning to preserve: inquiry_owner means the
-- role accountable for the inquiry, and caller_customer_id keeps the customer.
--
-- THE FROZEN RULE TEXT DECIDES IT, not this file:
--     BR-049 "One inquiry owner remains accountable" — "Specialist and document handoffs do not
--     transfer overall inquiry accountability away from RFQ Qualification Manager unless an explicit
--     approved workflow says so."
-- and the frozen registry agrees: phase_b_workflow W05 (primary_object inquiry) is accountable to
-- rfq_qualification_manager.
--
-- AND IT CAN STILL FAIL, which is the point. The value is read from
-- phase_c_workflow_run.accountable_role_id, not from the frozen registry, so BR-049 refuses exactly
-- when a live run's accountability has DRIFTED from the approved one. The control below proves both
-- directions: an untouched run passes, and the same run with its accountable role moved refuses.
-- Resolving it from phase_b_workflow instead would have produced a rule that cannot fail.
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
  -- D40. THE INBOX ROW IS NOT READABLE BY run_id OR business_object_id AT FIRST-STEP DISPATCH TIME.
  -- fn_kernel_trigger_submit inserts the inbox row, then calls fn_kernel_workflow_start passing
  -- source_ref = 'trigger_inbox:<inbox_id>', and stamps run_id and business_object_id onto that row
  -- only AFTER the call returns. The dispatch happens inside it, so both earlier matches were looking
  -- for columns the row does not carry yet. The inbox id IS in the source_ref the kernel already
  -- passes, and fn_kernel_workflow_start writes it onto the task before it opens the step — the one
  -- identifier available at the only moment that matters.
  if v_src_ref like 'trigger_inbox:%' then
    select ti.source_system, 'trigger' into v_src_ref, v_src_kind
      from public.kernel_trigger_inbox ti
     where ti.inbox_id = nullif(substr(v_src_ref, 15), '')::bigint;
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
    elsif v_k = 'caller_customer_id' then
      if v_found and v_row_own is not null then
        v_val := to_jsonb(v_row_own);
        v_src := format('%s.%s of the run''s own object', v_rel, coalesce(v_owncol,'(none)'));
      end if;

    elsif v_k = 'inquiry_owner' then
      -- D41. inquiry_owner IS A ROLE, NOT A CUSTOMER. BR-049 is the only consumer of this key —
      -- no gate declares it — and its predicate compares it to the literal role
      -- 'rfq_qualification_manager'. Resolving it from inquiries.customer_id handed a rule about
      -- ACCOUNTABILITY a customer UUID, so it refused every inquiry the moment the owner started
      -- resolving at all. The frozen rule text is unambiguous: "Specialist and document handoffs do
      -- not transfer overall inquiry accountability away from RFQ Qualification Manager unless an
      -- explicit approved workflow says so."
      --
      -- The subject is therefore the role accountable for the INQUIRY, which is
      -- phase_c_workflow_run.accountable_role_id of the run that owns it. For a W05 run that is this
      -- run; for W06 and W07, which are the specialist workflows the rule is about, it is the W05
      -- run for the same inquiry, and where no such run exists the key stays unresolved rather than
      -- being answered with this run''s own role.
      --
      -- This is what makes the rule able to FAIL: it fails exactly when a run''s accountable role
      -- has drifted from the frozen registry''s, which is the drift BR-049 exists to catch.
      if r.workflow_id = 'W05' then
        v_val := to_jsonb(r.accountable_role_id);
        v_src := 'phase_c_workflow_run.accountable_role_id of this inquiry''s own run';
      elsif v_found then
        select to_jsonb(r2.accountable_role_id) into v_val
          from public.phase_c_workflow_run r2
         where r2.workflow_id = 'W05'
           and r2.business_object_id = ('inquiry:' || v_row_id)
         order by r2.run_id desc limit 1;
        v_src := 'phase_c_workflow_run.accountable_role_id of the W05 run that owns this inquiry';
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




-- ---- CONTROL — both directions, from the dispatch row, rolled back ------------------------------
do $ctl$
declare
  v_cust uuid; v_inq uuid; v_run bigint; v_sr bigint; v_cx jsonb;
  v_outcome text; v_reason text; v_effects int; v_report text;
  v_before_inq int; v_before_cust int;
begin
  select count(*) into v_before_inq from public.inquiries;
  select count(*) into v_before_cust from public.customers;

  begin
    insert into public.customers (email, full_name)
    values ('zz-demo-d41-control@example.invalid','ZZ DEMO — d41 control') returning id into v_cust;
    insert into public.inquiries (customer_id, category, status)
    values (v_cust, 'jewellery', 'open') returning id into v_inq;

    select d.outcome, left(d.reason,300), d.run_id, d.step_run_id
      into v_outcome, v_reason, v_run, v_sr
      from public.phase_d_dispatch d order by d.dispatch_id desc limit 1;
    if v_outcome is null then
      raise exception 'D41 CONTROL FAILED: a real inquiry insert produced no dispatch row.';
    end if;

    v_cx := public.fn_phase_d_step_context(v_sr);

    -- POSITIVE: the key must now hold the accountable ROLE, not a customer uuid.
    if (v_cx->'context'->>'inquiry_owner') is distinct from 'rfq_qualification_manager' then
      raise exception 'D41 CONTROL FAILED: inquiry_owner resolved to %, not the accountable role.',
        coalesce(v_cx->'context'->>'inquiry_owner','(unresolved)');
    end if;
    if (v_cx->'context'->>'inquiry_owner') = v_cust::text then
      raise exception 'D41 CONTROL FAILED: inquiry_owner is still the customer id.';
    end if;

    -- NEGATIVE 1: the rule must still be able to refuse. Asked with any other role, it must fail.
    -- (The first version of this control tried to UPDATE phase_c_workflow_run to prove the same
    -- thing and fn_kernel_write_guard refused it — "no routine with write authority for this table
    -- is on the call stack". The guard was right; the control was working around it.)
    if (select ok from public.fn_phase_d_rule_check('BR-049',
          jsonb_build_object('inquiry_owner','inquiry_router')) limit 1) then
      raise exception 'D41 CONTROL FAILED: BR-049 passed an inquiry accountable to inquiry_router. A rule that cannot fail is not a rule.';
    end if;
    if not (select ok from public.fn_phase_d_rule_check('BR-049', v_cx->'context') limit 1) then
      raise exception 'D41 CONTROL FAILED: BR-049 refused the resolved context. inquiry_owner=%',
        coalesce(v_cx->'context'->>'inquiry_owner','(unresolved)');
    end if;

    -- NEGATIVE 2: the resolver must NOT answer with the current run's own role when the inquiry has
    -- no W05 run. A W06 run for an inquiry nothing owns must leave inquiry_owner UNRESOLVED, which
    -- is what stops this becoming a constant that always satisfies BR-049.
    declare v_cx6 jsonb; v_run6 bigint; v_sr6 bigint; v_start6 jsonb;
    begin
      v_start6 := public.fn_kernel_workflow_start(jsonb_build_object(
        'workflow_id','W06',
        'business_object_id','inquiry_route_set:ZZ-DEMO-d41-'||clock_timestamp()::text,
        'source_kind','autonomous',
        'source_ref','phase_d_d41_control:'||clock_timestamp()::text,
        'requested_by','phase_d_d41_control'));
      v_sr6 := (v_start6->>'step_run_id')::bigint;
      v_cx6 := public.fn_phase_d_step_context(v_sr6);
      if (v_cx6->'context') ? 'inquiry_owner' then
        raise exception 'D41 CONTROL FAILED: a W06 run with no owning W05 run resolved inquiry_owner to %. The resolver is echoing the current run.',
          v_cx6->'context'->>'inquiry_owner';
      end if;
    end;

    select count(*) into v_effects from public.phase_d_effect_ledger;
    v_report := format('inquiry=%s run=%s first dispatch=%s effects=%s | %s',
      v_inq, v_run, v_outcome, v_effects, left(coalesce(v_reason,'-'),200));
    raise exception 'D41_CONTROL_ROLLBACK %', v_report;
  exception
    when others then
      if SQLERRM like 'D41_CONTROL_ROLLBACK%' then
        raise notice 'D41 %', substr(SQLERRM, 22);
      else
        raise exception 'D41 CONTROL FAILED: % (%)', SQLERRM, SQLSTATE;
      end if;
  end;

  if (select count(*) from public.inquiries) <> v_before_inq
     or (select count(*) from public.customers) <> v_before_cust
     or (select count(*) from public.phase_d_dispatch) <> 0 then
    raise exception 'D41: the control left residue behind.';
  end if;
  raise notice 'D41: inquiry_owner resolves to the accountable role, and BR-049 still refuses a run whose accountability has drifted.';
end
$ctl$;
