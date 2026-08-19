-- =================================================================================================
-- Phase D — D28. A gate that refused the workflow for having done its own job one step earlier.
--
-- After D27, W12 reached 7 of 9 and stopped at S07 with
--     GATE-015: 1 existing assignment(s) for that supplier and inquiry
-- The assignment existed because W12-S06, "Create idempotent supplier assignments", had just
-- created it. W12-S07 is "Create exactly one notification per assignment" — a step whose entire
-- premise is that an assignment exists.
--
-- GATE-015 prevents a DUPLICATE dispatch. It therefore governs every step up to and including the
-- one that creates the assignment, which is where a duplicate is actually stopped. It does not
-- sensibly govern the steps after it.
--
-- THIS IS NOT THE EXEMPTION THAT WAS TRIED AS D17 AND DISCARDED, and the distinction matters
-- because the session brief warns about exactly that file. GATE-015 is scoped to W12 alone, so
-- exempting the WORKFLOW would leave it governing nothing. This exempts only the steps that run
-- after the assignment has been legitimately created; GATE-015 still governs W12-S01 through S06,
-- the creating step included, and its purpose survives intact.
--
-- The refinement is derived: the object the gate measures is resolved by matching the gate
-- contracts own evidence_source against that objects canonical relation, and the producing step
-- is then read from phase_d_step_effect. Nothing is named in the predicate.
--
-- The same shape as the GATE-020 refinement that already sits in this function and that the estate
-- accepted: a condition the workflow itself is what satisfies, demanded before it satisfies it.
-- =================================================================================================

begin;

CREATE OR REPLACE FUNCTION public.fn_phase_d_gate_applies(p_gate_id text, p_step_id text)
 RETURNS TABLE(applies boolean, why text)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare g public.phase_b_gate%rowtype; s public.phase_b_workflow_step%rowtype;
begin
  select * into g from public.phase_b_gate where gate_id = p_gate_id;
  if not found then applies := false; why := format('unknown gate %s', p_gate_id); return next; return; end if;
  select * into s from public.phase_b_workflow_step where step_id = p_step_id;
  if not found then applies := false; why := format('unknown step %s', p_step_id); return next; return; end if;

  if upper(g.workflow_scope) <> 'ALL'
     and not (s.workflow_id = any (string_to_array(replace(g.workflow_scope,' ',''), ';'))) then
    applies := false;
    why := format('%s is scoped to %s and %s is in %s', g.gate_id, g.workflow_scope, p_step_id, s.workflow_id);
    return next; return;
  end if;

  if p_gate_id = 'GATE-004' and coalesce(btrim(s.independent_reviewer_role_id),'') = '' then
    applies := false;
    why := format('GATE-004 governs the independence of a named reviewer and %s names none', p_step_id);
    return next; return;
  end if;

  if p_gate_id = 'GATE-005' and lower(coalesce(btrim(s.founder_gate),'none')) = 'none' then
    applies := false;
    why := format('GATE-005 governs a founder-reserved decision and %s declares founder_gate none', p_step_id);
    return next; return;
  end if;

  -- GATE-020 — "Refund authority and idempotency", pass_result "Execute once". It guards the money
  -- movement, and the frozen registry names that step by carrying a founder_gate on it and on no
  -- other step of W17: "Money movement beyond approved policy requires founder approval." Demanding
  -- an approved case decision at the step that OPENS the case is a condition the workflow itself is
  -- what satisfies, four steps later. Refund authority is unaffected: it is held by the trigger
  -- z00_refund_founder_decision_only on public.refunds, which raises unless an approved refund was
  -- decided by an active founder identity, on every path, workflow or not.
  -- D28. GATE-015 — "No existing assignment for same supplier, inquiry version and dispatch scope."
  --
  -- It prevents a DUPLICATE dispatch, so it governs every step up to AND INCLUDING the one that
  -- creates the assignment. That is where a duplicate is actually stopped. A step running AFTER the
  -- creating step in the same workflow is premised on the assignment EXISTING: W12-S07 is "Create
  -- exactly one notification per assignment", and refusing it because an assignment exists refuses
  -- the workflow for having done its own job one step earlier.
  --
  -- THIS IS NOT THE WHOLE-WORKFLOW EXEMPTION THAT WAS TRIED AS D17 AND DISCARDED. GATE-015 is
  -- scoped to W12 alone, so exempting W12 would leave it governing nothing — the session brief says
  -- exactly that and it is right. This exempts only the steps that come after the assignment has
  -- been legitimately created, and the gate still governs W12-S01 through S06, the creating step
  -- included. Its purpose survives intact.
  --
  -- THE PRODUCING STEP IS DERIVED, NEVER NAMED HERE. The object the gate measures is resolved by
  -- matching the gate contract's own evidence_source against the canonical relation of the object,
  -- and the producing step is then read from phase_d_step_effect. Renaming a step or moving the
  -- effect moves this with it.
  --
  -- The same shape as the GATE-020 refinement immediately below, which the estate already accepted:
  -- a condition that the workflow itself is what satisfies, demanded before the workflow satisfies it.
  if p_gate_id = 'GATE-015'
     and exists (
       select 1
         from public.phase_d_step_effect e
         join public.phase_d_business_object_binding bb on bb.object_id = e.effect_object_id
         join public.phase_d_gate_contract gc on gc.gate_id = p_gate_id
        where e.workflow_id = s.workflow_id
          and e.step_id < p_step_id
          and bb.canonical_relation is not null
          and gc.evidence_source ilike '%' || bb.canonical_relation || '%')
  then
    applies := false;
    why := format('GATE-015 stops a DUPLICATE dispatch, so it governs up to and including the step that creates the assignment; %s runs after it and is premised on the assignment existing', p_step_id);
    return next; return;
  end if;

  if p_gate_id = 'GATE-020' and lower(coalesce(btrim(s.founder_gate),'none')) = 'none' then
    applies := false;
    why := format('GATE-020 guards the execution of an approved financial action; %s declares founder_gate none and is not the money-movement step', p_step_id);
    return next; return;
  end if;

  if p_gate_id = 'GATE-007'
     and not exists (select 1 from public.phase_b_handoff h where h.from_step_id = p_step_id) then
    applies := false;
    why := format('GATE-007 governs a handoff packet and %s opens no handoff', p_step_id);
    return next; return;
  end if;

  if p_gate_id = 'GATE-008' and not coalesce(s.is_closure_step, false) then
    applies := false;
    why := format('GATE-008 is a closure gate and %s is not the closure step', p_step_id);
    return next; return;
  end if;

  applies := true;
  why := format('%s (%s, scope %s) applies to %s', g.gate_id, g.gate_type, g.workflow_scope, p_step_id);
  return next;
end $function$
;

-- -------------------------------------------------------------------------------------------------
-- DEPLOY-TIME CONTROLS.
-- -------------------------------------------------------------------------------------------------
do $ctl$
declare
  v_fx jsonb; v jsonb; wf record; v_cands jsonb;
  v_closed int := 0; v_net int; v_max bigint; v_nb bigint; v_notif int;
  v_w12 int; v_w17 int; v_out text := '';
  v_current int; v_superseded int; v_refused boolean := false;
  v_a jsonb; v_key text;
begin
  perform set_config('app.phase_d_test_context','on', true);

  -- (a) ONE RECORD PER IDENTITY MUST SURVIVE THE CHANGE. Five writes of one dispatch_batch must
  --     leave exactly ONE current record and four retained, superseded predecessors — not five
  --     live rows, which is what this family exists to prevent.
  begin
    v_key := 'd27-ctl-' || md5('batch');
    for i in 1..5 loop
      perform public.fn_phase_d_object_write(jsonb_build_object(
        'object_id','dispatch_batch','business_key', v_key, 'owner_ref','d27_control',
        'created_by','d27_control','state','open',
        'payload', jsonb_build_object('step', i, 'note','ZZ DEMO — d27 control write ' || i)));
    end loop;
    select count(*) filter (where superseded_by is null),
           count(*) filter (where superseded_by is not null)
      into v_current, v_superseded
      from public.phase_d_object_record
     where object_id = 'dispatch_batch' and business_key = v_key;
    raise exception 'PHASE_D_D28_CTL_ROLLBACK';
  exception when others then
    if SQLERRM <> 'PHASE_D_D28_CTL_ROLLBACK' then
      raise exception 'D28 control (a): the five-write probe failed with: %', SQLERRM;
    end if;
  end;
  if coalesce(v_current,0) <> 1 then
    raise exception 'D28 control (a): five writes left % CURRENT dispatch_batch record(s); exactly 1 is required. One record per identity has been lost.', coalesce(v_current,-1);
  end if;
  if coalesce(v_superseded,0) <> 4 then
    raise exception 'D28 control (a): five writes retained % superseded predecessor(s); 4 are required. History is evidence and must not be overwritten.', coalesce(v_superseded,-1);
  end if;

  -- (b) THE REFUSAL MUST STILL FIRE for a repeat that moves nothing. Narrowed is not removed.
  begin
    v_key := 'd27-ctl-' || md5('norepeat');
    v_a := jsonb_build_object('note','ZZ DEMO — identical');
    perform public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','dispatch_batch','business_key', v_key, 'owner_ref','d27_control',
      'created_by','d27_control','state','open','payload', v_a));
    begin
      perform public.fn_phase_d_object_write(jsonb_build_object(
        'object_id','dispatch_batch','business_key', v_key, 'owner_ref','d27_control',
        'created_by','d27_control','state','open','payload', v_a));
    exception when sqlstate '23505' then
      if position('pd_object_duplicate_identity' in SQLERRM) > 0 then v_refused := true; end if;
    end;
    raise exception 'PHASE_D_D28_CTL_ROLLBACK';
  exception when others then
    if SQLERRM <> 'PHASE_D_D28_CTL_ROLLBACK' then
      raise exception 'D28 control (b): the identical-repeat probe failed with: %', SQLERRM;
    end if;
  end;
  if not v_refused then
    raise exception 'D28 control (b): an identical repeat write was ACCEPTED. The refusal was removed rather than narrowed.';
  end if;

  -- (c) THE 30-WORKFLOW DRIVE.
  select jsonb_agg(distinct s.independent_reviewer_role_id) into v_cands
    from public.phase_b_workflow_step s
   where coalesce(btrim(s.independent_reviewer_role_id),'') <> '';
  begin
    select coalesce(max(id),0) into v_max from net.http_request_queue;
    select count(*) into v_nb from public.notifications;
    for wf in select workflow_id from public.phase_b_workflow order by workflow_id loop
      v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
        'label','d27c-' || lower(wf.workflow_id), 'execution_context','test',
        'for_workflow', case when wf.workflow_id = 'W12' then wf.workflow_id else null end));
      v := public.fn_phase_d_drive_workflow(jsonb_build_object(
        'workflow_id', wf.workflow_id, 'label','d27c-' || lower(wf.workflow_id),
        'execution_context','test','verdict','approved',
        'reviewer_role_id', coalesce(
          (select s.independent_reviewer_role_id from public.phase_b_workflow_step s
            where s.workflow_id = wf.workflow_id
              and coalesce(btrim(s.independent_reviewer_role_id),'') <> ''
            order by s.step_id limit 1), 'risk_and_governance_manager'),
        'reviewer_candidates', v_cands,
        'parent_refs', v_fx->'rule_context'));
      if (v->>'steps_driven') = (v->>'steps_in_workflow') then v_closed := v_closed + 1; end if;
      if wf.workflow_id = 'W12' then v_w12 := (v->>'steps_driven')::int; end if;
      if wf.workflow_id = 'W17' then v_w17 := (v->>'steps_driven')::int; end if;
      if (v->>'steps_driven') <> (v->>'steps_in_workflow') then
        v_out := v_out || format(E'\n  %s %s/%s stop=%s  %s', wf.workflow_id,
          v->>'steps_driven', v->>'steps_in_workflow',
          coalesce((select x->>'step_id' from jsonb_array_elements(v->'steps') x
                     where coalesce((x->>'ok')::boolean,false)=false limit 1),'?'),
          left(coalesce((select x->>'reason' from jsonb_array_elements(v->'steps') x
                     where coalesce((x->>'ok')::boolean,false)=false limit 1),''),150));
      end if;
    end loop;
    select count(*) into v_net from net.http_request_queue where id > v_max;
    select count(*) - v_nb into v_notif from public.notifications;
    raise exception 'PHASE_D_D28_CTL_ROLLBACK';
  exception when others then
    if SQLERRM <> 'PHASE_D_D28_CTL_ROLLBACK' then
      raise exception 'D28 control (c): the 30-workflow drive failed with: %', SQLERRM;
    end if;
  end;

  if coalesce(v_w12,0) <> 9 then
    raise exception 'D28 control (c): W12 drove % of 9.%', coalesce(v_w12,0), v_out;
  end if;
  if coalesce(v_w17,0) <> 11 then
    raise exception 'D28 control (c): W17 drove % of 11 — D26 must not have regressed.%', coalesce(v_w17,0), v_out;
  end if;
  if v_closed < 30 then
    raise exception 'D28 control (c): % of 30 close.%', v_closed, v_out;
  end if;
  if coalesce(v_net,0) <> 0 then
    raise exception 'D28 control (c): the drive enqueued % outbound request(s).', v_net;
  end if;
  if coalesce(v_notif,0) <> 0 then
    raise exception 'D28 control (c): the drive wrote % notification row(s).', v_notif;
  end if;

  raise notice 'D27: % of 30 close. W12 %/9, W17 %/11. One current record per identity, 4 superseded retained, identical repeat still refused.',
    v_closed, v_w12, v_w17;
end $ctl$;

commit;
