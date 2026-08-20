-- =================================================================================================
-- Phase D — D53. A fixture may be opaque. It may not be the wrong type.
--
-- Regenerating the deliverables after D46–D52, deterministic closure fell from 30 of 30 to 2 of 30,
-- and 25 of the 28 stops were pd_rule_refused. The plan predicted this headline would fall — but for
-- a different reason (the capability boundary in production mode), and by a different amount. So the
-- 2 was measured rather than accepted:
--
--     BR-044 blocks 23 of 30      "policy 'ZZ DEMO — sla_policy_id for W01-S01' computes no due time"
--     BR-027 blocks 7
--     BR-042 blocks 1
--
-- All three are the harness, not the rules.
--
-- fn_phase_d_fixture_context emits `'ZZ DEMO — ' || key` for every opaque reference, and until this
-- increment that was fine because the predicates only asked whether a key was present. Three of them
-- now ask what it IS:
--
--     BR-044  the policy must be REGISTERED in phase_b_sla_policy — because fn_kernel_sla_due ends
--             in coalesce(<lookup>, 24) and hands an unknown policy a 24-hour deadline, so
--             "returns non-null" could never fail. A demo string is not registered.
--     BR-027  evidence_refs must be a non-empty ARRAY. A string is not one.
--     BR-042  assumptions must be a non-empty ARRAY, and must not be the executor's own boilerplate.
--
-- THE DISTINCTION THIS FILE KEEPS. A harness may fixture an opaque reference — that is what a
-- harness is for, and fn_phase_d_fixture_context says so in its own header. It may not fixture the
-- WRONG TYPE, because a rule that refuses the type is working correctly and the harness is then
-- measuring nothing but its own malformed input.
--
-- So sla_policy_id and handoff_id are READ from the frozen handoff registry, which makes them real
-- values rather than fixtures at all; evidence_refs and assumptions stay fixtures and become arrays,
-- still visibly marked ZZ DEMO. The real path is untouched: fn_phase_d_step_context resolves
-- sla_policy_id and handoff_id from the same registry, and leaves evidence_refs and assumptions
-- UNRESOLVED, so a business arrival still refuses where the harness proceeds. That gap is the
-- measurement, and it survives this file.
--
-- A key that resolves to NULL is now removed rather than left as a JSON null — a step that opens no
-- handoff has neither, and BR-008 and BR-044 are not applicable to it.
-- =================================================================================================

CREATE OR REPLACE FUNCTION public.fn_phase_d_fixture_context(p_step_run_id bigint, p_label text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
      -- D53. THREE MORE KEYS WHOSE PREDICATE IS NOW TYPED, so an opaque string is no longer a
      -- fixture of the right shape — it is a fixture of the wrong one, and the rule refuses it.
      --
      --   sla_policy_id   BR-044 requires the policy to be REGISTERED in phase_b_sla_policy, because
      --                   fn_kernel_sla_due ends in coalesce(<lookup>, 24) and hands an unknown
      --                   policy a 24-hour deadline. 'ZZ DEMO — sla_policy_id for W01-S01' is not
      --                   registered, so it refused 23 of the 30 driven workflows. It is READ from
      --                   the frozen handoff registry here, which is a real value, not a fixture.
      --   evidence_refs   BR-027 requires a non-empty ARRAY. A string is not one.
      --   assumptions     BR-042 requires a non-empty ARRAY, and refuses the executor's own
      --                   boilerplate by name, so the fixture must state something else.
      --
      -- The harness may fixture an opaque reference; it may not fixture the WRONG TYPE, because a
      -- rule that refuses the type is doing its job and the harness is then testing nothing.
      when 'sla_policy_id' then jsonb_build_object('sla_policy_id',
        (select h.sla_policy_id from public.phase_b_handoff h
          where h.from_step_id = sr.step_id and coalesce(btrim(h.sla_policy_id),'') <> ''
          order by h.handoff_id limit 1))
      when 'handoff_id' then jsonb_build_object('handoff_id',
        (select hc.handoff_id from public.phase_d_handoff_contract hc
          where hc.from_step_id = sr.step_id order by hc.handoff_id limit 1))
      when 'evidence_refs' then jsonb_build_object('evidence_refs',
        jsonb_build_array('ZZ DEMO — evidence_ref for ' || sr.step_id))
      when 'assumptions' then jsonb_build_object('assumptions',
        jsonb_build_array('ZZ DEMO — the fixture states one assumption for ' || sr.step_id))
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
  -- D53. A key that resolved to NULL is removed rather than left as a JSON null, which
  -- fn_phase_d_schema_validate and every presence check read as absent anyway. A step that opens no
  -- handoff has no sla_policy_id and no handoff_id, and BR-008 and BR-044 are not applicable to it.
  select coalesce(jsonb_object_agg(k, v), '{}'::jsonb) into v_out
    from jsonb_each(v_out) e(k, v) where jsonb_typeof(v) <> 'null';

  v_out := v_out - array['inquiry_id','supplier_id','quote_id','transaction_id','document_id',
                         'comparison_id','refund_id','provider_event_id']
                 - array['step_id','run_id','step_run_id','actor_role_id','reviewer_role_id'];
  -- step_run_id joined that list when GATE-008 gained it as declared evidence: the fixture produced
  -- 'ZZ DEMO — step_run_id for W04-S07' and the gate cast it to bigint. An identity is never a
  -- fixture, whichever gate declares it.

  return v_out;
end $function$;


-- ---- CONTROL ------------------------------------------------------------------------------------
-- Both directions. The harness must stop failing on its own malformed input, AND the real path must
-- still refuse the same keys — otherwise this file has quietly made the business path as permissive
-- as the harness, which is the one thing it must not do.

do $ctl$
declare
  v_start jsonb; v_run bigint; v_sr bigint; v_fix jsonb; v_cx jsonb;
  v_before_cust int; v_before_inq int; v_report text;
begin
  select count(*) into v_before_cust from public.customers;
  select count(*) into v_before_inq  from public.inquiries;

  begin
    v_start := public.fn_kernel_workflow_start(jsonb_build_object(
      'workflow_id','W05',
      'business_object_id','inquiry:ZZ-DEMO-d53-'||clock_timestamp()::text,
      'source_kind','autonomous',
      'source_ref','phase_d_d53_control:'||clock_timestamp()::text,
      'requested_by','phase_d_d53_control'));
    v_sr := (v_start->>'step_run_id')::bigint;
    v_run := (v_start->>'run_id')::bigint;

    v_fix := public.fn_phase_d_fixture_context(v_sr, 'd53_control');
    v_cx  := public.fn_phase_d_step_context(v_sr);

    -- POSITIVE 1: no fixture value may still be the WRONG TYPE for a typed predicate.
    if v_fix ? 'evidence_refs' and jsonb_typeof(v_fix->'evidence_refs') <> 'array' then
      raise exception 'D53: the fixture still gives evidence_refs as %.', jsonb_typeof(v_fix->'evidence_refs');
    end if;
    if v_fix ? 'assumptions' and jsonb_typeof(v_fix->'assumptions') <> 'array' then
      raise exception 'D53: the fixture still gives assumptions as %.', jsonb_typeof(v_fix->'assumptions');
    end if;
    if v_fix ? 'assumptions'
       and (select rc.state from public.fn_phase_d_rule_check('BR-042', v_fix) rc limit 1) = 'ENFORCED_FAIL' then
      raise exception 'D53: BR-042 still refuses the fixture assumptions: %', v_fix->'assumptions';
    end if;

    -- POSITIVE 2: an sla_policy_id the fixture supplies must be one BR-044 accepts, or be absent.
    if v_fix ? 'sla_policy_id' then
      if not exists (select 1 from public.phase_b_sla_policy sp
                      where sp.sla_policy_id = v_fix->>'sla_policy_id') then
        raise exception 'D53: the fixture supplies sla_policy_id %L, which is not in phase_b_sla_policy.',
          v_fix->>'sla_policy_id';
      end if;
    end if;

    -- POSITIVE 3: no null survives in the fixture.
    if exists (select 1 from jsonb_each(v_fix) e where jsonb_typeof(e.value) = 'null') then
      raise exception 'D53: the fixture left a JSON null in %',
        (select string_agg(e.key, ', ') from jsonb_each(v_fix) e where jsonb_typeof(e.value) = 'null');
    end if;

    -- NEGATIVE, AND THE IMPORTANT ONE: the REAL path must still leave the performer keys unresolved.
    -- If this ever passes, the business path has been made as permissive as the harness.
    if (v_cx->'declared_keys') @> '["assumptions"]'::jsonb and (v_cx->'context') ? 'assumptions' then
      raise exception 'D53: fn_phase_d_step_context now resolves assumptions. The real path must not.';
    end if;
    if exists (select 1 from jsonb_each_text(v_cx->'context') e where e.value like 'ZZ DEMO%') then
      raise exception 'D53: a ZZ DEMO value reached the real context.';
    end if;

    v_report := format('fixture keys=[%s]  real context keys=[%s]',
      (select string_agg(k, ',' order by k) from jsonb_object_keys(v_fix) k),
      (select string_agg(k, ',' order by k) from jsonb_object_keys(v_cx->'context') k));
    raise exception 'D53_CONTROL_ROLLBACK %', v_report;
  exception
    when others then
      if SQLERRM like 'D53_CONTROL_ROLLBACK%' then
        raise notice 'D53 %', substr(SQLERRM, 22);
      else
        raise exception 'D53 CONTROL FAILED: % (%)', SQLERRM, SQLSTATE;
      end if;
  end;

  if (select count(*) from public.customers) <> v_before_cust
     or (select count(*) from public.inquiries) <> v_before_inq
     or (select count(*) from public.phase_d_dispatch) <> 0
     or (select coalesce(sum(surviving_rows),0) from public.fn_phase_d_fixture_residue()) <> 0 then
    raise exception 'D53: the control left residue behind.';
  end if;

  raise notice 'D53: the fixture is correctly typed, the real path still refuses the performer keys, and nothing was left behind.';
end
$ctl$;
