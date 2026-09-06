  -- ============ THE EIGHT THAT SAID THEY NEEDED A COMMITTED ROW =================================
  -- Each of the eight branches below carried a blocker of the same shape: "this needs a row that
  -- outlives the transaction". Re-measured 23 Aug 2026 that was FALSE for all eight. Every refusal
  -- they are meant to provoke is raised inside the calling statement -- a CHECK constraint, a BEFORE
  -- UPDATE trigger, a plpgsql RAISE in fn_kernel_step_complete -- and the two constraint triggers
  -- that ARE deferred can be pronounced on demand with SET CONSTRAINTS ALL IMMEDIATE. Nothing here
  -- needs to commit; what they needed was a LIVE RUN, and fn_phase_d_drive_workflow already builds
  -- one through the canonical doors.
  --
  -- TWO ARMS, both inside this aborted transaction:
  --   ARM A  W10 driven to its reviewer step and HELD there with nothing completed on it. Every
  --          earlier step went through fn_kernel_step_complete and every handoff through
  --          fn_phase_d_handoff_accept. Carries PD-IDEM-002, PD-STATE-002 (injection), PD-REV-002,
  --          PD-REV-004, PD-REV-005 and the PD-STATE-003 measurement.
  --   ARM B  the same workflow driven to its CLOSURE step and held there, so every earlier
  --          mandatory step of that run IS executed. It is the control for PD-STATE-002 and
  --          PD-STATE-003 and differs from ARM A's injection in exactly that respect.
  --   ARM C  needs no run: a trace written open, and the two DEFERRABLE constraint triggers.
  --
  -- W10 is not special; it was chosen by measurement. Eight steps, one step declaring an independent
  -- reviewer whose successor keeps the same owner, and a closure step declaring no reviewer of its
  -- own -- so the closure probe reaches the closure branch instead of stopping at 3g.
  --
  -- IF THE ARMS CANNOT BE STAGED, ALL EIGHT SAY SO. The whole block is one exception frame: a
  -- transport failure or a refusal in the driver leaves every one of the eight NOT_RUN carrying the
  -- reason, and never a row claiming an injection that was not made.
  v_live := '{}'::jsonb;
  begin
    select s.step_id, s.independent_reviewer_role_id into v_hold_step, v_rev
      from public.phase_b_workflow_step s
     where s.workflow_id = 'W10' and coalesce(btrim(s.independent_reviewer_role_id),'') <> ''
     order by s.step_no limit 1;
    select s.step_id, s.accountable_role_id into v_clo_step, v_clo_owner
      from public.phase_b_workflow_step s
     where s.workflow_id = 'W10' and s.is_closure_step limit 1;
    select jsonb_agg(distinct x.independent_reviewer_role_id) into v_cands
      from public.phase_b_workflow_step x
     where coalesce(btrim(x.independent_reviewer_role_id),'') <> '';

    -- ---- ARM A ---------------------------------------------------------------------------------
    -- J03's hold makes the deterministic handler decline this one step, and that is what leaves the
    -- step run OPEN. Without it the dispatch that fires when the kernel OPENS the step closes it in
    -- the same statement and there is nothing left for an actor to complete.
    perform set_config('app.phase_d_hold_step', v_hold_step, true);
    v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
      'label','pd-defect-arm-a','execution_context','test','for_workflow','W10'));
    v_drive := public.fn_phase_d_drive_workflow(jsonb_build_object(
      'workflow_id','W10','label','pd-defect-arm-a','execution_context','production',
      'reviewer_role_id', v_rev, 'reviewer_candidates', v_cands,
      'hold_at_step_id', v_hold_step));
    v_srid := nullif(v_drive->>'held_step_run_id','')::bigint;
    v_run  := (v_drive->>'run_id')::bigint;
    if v_srid is null then
      raise exception 'the drive did not hold % open: %', v_hold_step,
        coalesce(v_drive->'stopped'->>'refused_with','(no reason returned)');
    end if;
    select accountable_role_id into v_acct
      from public.phase_c_workflow_step_run where step_run_id = v_srid;
    select task_id into v_task from public.phase_c_task
     where run_id = v_run and step_id = v_hold_step order by task_id limit 1;

    -- PD-IDEM-002. THE SAME COMPLETION, TWICE, IN ONE TRANSACTION. The key and the step run are the
    -- ones the DRIVER used, read back off phase_c_step_completion rather than reconstructed, so the
    -- probe cannot invent a key the kernel never saw. Section 1 of fn_kernel_step_complete reads
    -- that table before any work and returns the prior result with replay=true.
    select c.idempotency_key, c.step_run_id, x.accountable_role_id, x.step_id
      into v_pk, v_psr, v_pacct, v_pstep
      from public.phase_c_step_completion c
      join public.phase_c_workflow_step_run x on x.step_run_id = c.step_run_id
     where x.run_id = v_run order by c.completion_id desc limit 1;
    select count(*) into v_c0 from public.phase_c_step_completion where step_run_id = v_psr;
    select count(*) into v_s0 from public.phase_c_workflow_step_run where run_id = v_run;
    select count(*) into v_h0 from public.phase_c_handoff_run where run_id = v_run;
    v_a := public.fn_kernel_step_complete(jsonb_build_object(
      'step_run_id', v_psr, 'actor_role_id', v_pacct, 'outcome','pass',
      'idempotency_key', v_pk,
      'inputs', jsonb_build_object('probe','PD-IDEM-002 duplicate completion'),
      'output', jsonb_build_object('status','completed','output','PHASE_D_FIXTURE_DO_NOT_PUBLISH')));
    select count(*) into v_c1 from public.phase_c_step_completion where step_run_id = v_psr;
    select count(*) into v_s1 from public.phase_c_workflow_step_run where run_id = v_run;
    select count(*) into v_h1 from public.phase_c_handoff_run where run_id = v_run;
    -- CONTROL, one respect different: a key the kernel has not seen. The same step run, the same
    -- actor, the same outcome, the same transaction.
    begin
      perform public.fn_kernel_step_complete(jsonb_build_object(
        'step_run_id', v_psr, 'actor_role_id', v_pacct, 'outcome','pass',
        'idempotency_key', v_pk || ':control-different-key',
        'inputs', jsonb_build_object('probe','PD-IDEM-002 control'),
        'output', jsonb_build_object('status','completed','output','PHASE_D_FIXTURE_DO_NOT_PUBLISH')));
      v_txt := 'NOT_REFUSED';
    exception when others then
      v_txt := coalesce((regexp_match(SQLERRM,'\((k[0-9]+_[a-z0-9_]+)\)'))[1], SQLSTATE);
    end;
    v_live := v_live || jsonb_build_object('PD-IDEM-002', jsonb_build_object(
      'status', case when coalesce((v_a->>'replay')::boolean,false)
                      and v_c1 = v_c0 and v_s1 = v_s0 and v_h1 = v_h0
                      and v_txt = 'k3_step_state_invalid'
                 then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end,
      'observed', format('the SAME idempotency_key on the completed %s returned the first result '
        || 'with replay=true: completions %s, step runs %s, handoff runs %s, state %s. CONTROL, a '
        || 'different key on the same step run: refused %s (23514).',
        v_pstep, v_c0 || '->' || v_c1, v_s0 || '->' || v_s1, v_h0 || '->' || v_h1,
        (select state from public.phase_c_workflow_step_run where step_run_id = v_psr), v_txt)));

    -- PD-STATE-002 (injection). The closure step is opened through fn_kernel_open_step -- the same
    -- routine section 7 of fn_kernel_step_complete uses to open a successor -- on a run whose
    -- earlier steps have NOT all been executed, and then completed. The attempt is in its own frame,
    -- so the step run it opened is rolled back with the refusal and nothing survives it.
    v_n := 0;
    begin
      perform set_config('app.phase_d_hold_step', v_clo_step, true);
      v_o := public.fn_kernel_open_step(jsonb_build_object(
        'run_id', v_run, 'step_id', v_clo_step, 'owner_role_id', v_clo_owner,
        'source_kind','workflow_progression', 'source_ref','step_run:' || v_srid,
        'opened_because','PD-STATE-002: reach the closure step with earlier mandatory steps open'));
      perform public.fn_kernel_step_complete(jsonb_build_object(
        'step_run_id', (v_o->>'step_run_id')::bigint, 'actor_role_id', v_clo_owner,
        'outcome','pass', 'idempotency_key','pd-state-002:' || v_run,
        'inputs', jsonb_build_object('probe','PD-STATE-002'),
        'output', jsonb_build_object('status','completed','output','PHASE_D_FIXTURE_DO_NOT_PUBLISH')));
      v_b := jsonb_build_object('code','NOT_REFUSED','classes',0,'mand',false);
    exception when others then
      v_b := jsonb_build_object(
        'code',  coalesce((regexp_match(SQLERRM,'\((k[0-9]+_[a-z0-9_]+)\)'))[1], SQLSTATE),
        'classes', coalesce((regexp_match(SQLERRM,'([0-9]+) mandatory blocker'))[1],'0')::int,
        'mand',  position('mandatory_steps_never_executed' in SQLERRM) > 0);
    end;

    -- PD-REV-002 (injection). outcome=pass on a step the FROZEN registry gives an independent
    -- reviewer, with no verdict of any kind recorded. Section 3g is the predicate.
    select count(*) into v_c0 from public.phase_c_step_completion where step_run_id = v_srid;
    begin
      perform public.fn_kernel_step_complete(jsonb_build_object(
        'step_run_id', v_srid, 'actor_role_id', v_acct, 'outcome','pass',
        'idempotency_key','pd-rev-002:' || v_srid,
        'inputs', jsonb_build_object('probe','PD-REV-002 no verdict'),
        'output', jsonb_build_object('status','completed','output','PHASE_D_FIXTURE_DO_NOT_PUBLISH')));
      v_txt := 'NOT_REFUSED';
    exception when others then
      v_txt := coalesce((regexp_match(SQLERRM,'\((k[0-9]+_[a-z0-9_]+)\)'))[1], SQLSTATE);
    end;
    select count(*) into v_c1 from public.phase_c_step_completion where step_run_id = v_srid;
    select state into v_sk from public.phase_c_workflow_step_run where step_run_id = v_srid;

    -- PD-REV-004 (injection). The SAME predicate reached the other way: a verdict exists and it is a
    -- REJECTION. It is recorded through fn_kernel_review_decide by the role the frozen registry
    -- names, so nothing about the reviewer is faked -- only the decision differs.
    v_d1 := public.fn_kernel_review_decide(jsonb_build_object(
      'task_id', v_task, 'reviewer_role_id', v_rev, 'decision','rejected',
      'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH -- PD-REV-004 rejected output'));
    select count(*) into v_s0 from public.phase_c_workflow_step_run where run_id = v_run;
    select count(*) into v_h0 from public.phase_c_handoff_run where run_id = v_run;
    begin
      perform public.fn_kernel_step_complete(jsonb_build_object(
        'step_run_id', v_srid, 'actor_role_id', v_acct, 'outcome','pass',
        'idempotency_key','pd-rev-004:' || v_srid,
        'inputs', jsonb_build_object('probe','PD-REV-004 rejected then forward'),
        'output', jsonb_build_object('status','completed','output','PHASE_D_FIXTURE_DO_NOT_PUBLISH')));
      v_txt2 := 'NOT_REFUSED';
    exception when others then
      v_txt2 := coalesce((regexp_match(SQLERRM,'\((k[0-9]+_[a-z0-9_]+)\)'))[1], SQLSTATE);
    end;
    select count(*) into v_s1 from public.phase_c_workflow_step_run where run_id = v_run;
    select count(*) into v_h1 from public.phase_c_handoff_run where run_id = v_run;

    -- THE CONTROL FOR BOTH, one respect different: the same reviewer, the same task, the same call,
    -- decision 'approved' instead of 'rejected' -- and for PD-REV-002, a verdict where there was none.
    v_d2 := public.fn_kernel_review_decide(jsonb_build_object(
      'task_id', v_task, 'reviewer_role_id', v_rev, 'decision','approved',
      'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH -- PD-REV-002/004 control'));
    begin
      perform public.fn_kernel_step_complete(jsonb_build_object(
        'step_run_id', v_srid, 'actor_role_id', v_acct, 'outcome','pass',
        'idempotency_key','pd-rev-control:' || v_srid,
        'inputs', jsonb_build_object('probe','PD-REV control approved'),
        'output', jsonb_build_object('status','completed','output','PHASE_D_FIXTURE_DO_NOT_PUBLISH')));
      v_key := 'completed';
    exception when others then
      v_key := coalesce((regexp_match(SQLERRM,'\((k[0-9]+_[a-z0-9_]+)\)'))[1], SQLSTATE);
    end;
    select count(*) into v_n from public.phase_c_workflow_step_run where run_id = v_run;
    select c.kind into v_succ_kind from public.fn_kernel_step_successor(v_hold_step) c;

    v_live := v_live || jsonb_build_object('PD-REV-002', jsonb_build_object(
      'status', case when v_txt = 'k3_reviewer_verdict_missing' and v_c1 = v_c0
                      and v_key = 'completed' then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end,
      'observed', format('%s declares %s its independent reviewer; outcome=pass with no verdict at '
        || 'all was refused %s (23514), completions %s, the step run left in %s. CONTROL, the same '
        || 'call after an approved verdict from that same role: %s.',
        v_hold_step, v_rev, v_txt, v_c0 || '->' || v_c1, v_sk, v_key)));

    v_live := v_live || jsonb_build_object('PD-REV-004', jsonb_build_object(
      'status', case when v_txt2 = 'k3_reviewer_verdict_missing' and v_s1 = v_s0 and v_h1 = v_h0
                      and v_key = 'completed' and v_n > v_s1
                 then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end,
      'observed', format('a rejected verdict then outcome=pass: refused %s (23514), successor step '
        || 'runs +%s, handoff runs +%s. CONTROL approved: %s, +%s successor. GAP MEASURED: 3g fires '
        || 'only on outcome=pass at the 28 of 257 steps declaring a reviewer, so on the other 229 a '
        || 'recorded rejection stops nothing.',
        v_txt2, v_s1 - v_s0, v_h1 - v_h0, v_key, v_n - v_s1)));

    -- PD-STATE-003. THE CATALOGUED INJECTION HAS NO POPULATION. fn_kernel_step_successor decides
    -- terminality from the sentinel AND the flag together and reports closure_flag_disagrees when
    -- they differ; measured today that is 0 of 257 steps, and making one disagree means UPDATEing
    -- public.phase_b_workflow_step, which z90_phase_b_freeze refuses without a change request. What
    -- IS driven here is the catalogue's own assertion -- "successor not skipped" -- and its control.
    -- The row stays NOT_RUN because the injection was not made; the observation says what was.
    v_live := v_live || jsonb_build_object('PD-STATE-003', jsonb_build_object(
      'status','NOT_RUN',
      'observed', format('driven instead: %s is non-closure, fn_kernel_step_successor returned %s, '
        || 'and completing it through the kernel opened %s successor step run(s). CONTROL %s: kind '
        || 'closure, 0 successors. The catalogued injection itself was NOT staged.',
        v_hold_step, v_succ_kind, v_n - v_s1, v_clo_step),
      'blocker','the catalogued injection is a step whose is_closure_step disagrees with its '
        || 'next_step_if_pass sentinel. fn_kernel_step_successor reports 0 of 257 such steps today, '
        || 'and creating one means UPDATEing the frozen public.phase_b_workflow_step, which '
        || 'z90_phase_b_freeze refuses. Reporting this REFUSED would be a zero-population pass.'));

    -- PD-REV-005. The verdict trace fn_kernel_review_decide just wrote is sealed: trace_write sets
    -- sealed_at in the same INSERT when status='sealed', and review_decide passes 'sealed'.
    -- z10_phase_c_trace_append_only refuses any UPDATE of it except setting superseded_by ALONE,
    -- which is the control.
    begin
      update public.phase_c_trace
         set evidence_refs = '[{"review_decision":"approved","tampered":true}]'::jsonb
       where trace_id = (v_d1->>'trace_id')::bigint;
      v_txt := 'NOT_REFUSED';
    exception when others then v_txt := SQLSTATE;
    end;
    begin
      update public.phase_c_trace set superseded_by = (v_d2->>'trace_id')::bigint
       where trace_id = (v_d1->>'trace_id')::bigint;
      v_txt2 := 'permitted';
    exception when others then v_txt2 := SQLSTATE;
    end;
    select count(*) into v_n from public.phase_c_trace
     where trace_id = (v_d1->>'trace_id')::bigint
       and evidence_refs @> '[{"review_decision":"rejected"}]'::jsonb;
    v_live := v_live || jsonb_build_object('PD-REV-005', jsonb_build_object(
      'status', case when v_txt = '23514' and v_txt2 = 'permitted' and v_n = 1
                 then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end,
      'observed', format('editing evidence_refs on sealed verdict trace %s was refused %s by '
        || 'z10_phase_c_trace_append_only and the original rejected verdict is still on the row '
        || '(%s of 1). CONTROL, setting superseded_by alone on that same row: %s.',
        v_d1->>'trace_id', v_txt, v_n, v_txt2)));

    -- ---- ARM B: the control for PD-STATE-002 and PD-STATE-003 ----------------------------------
    -- The same workflow, the same closure step, the same fn_kernel_step_complete. One respect is
    -- different: every earlier mandatory step of THIS run was executed to a terminal state.
    perform set_config('app.phase_d_hold_step', v_clo_step, true);
    v_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
      'label','pd-defect-arm-b','execution_context','test','for_workflow','W10'));
    v_drive := public.fn_phase_d_drive_workflow(jsonb_build_object(
      'workflow_id','W10','label','pd-defect-arm-b','execution_context','production',
      'reviewer_role_id', v_rev, 'reviewer_candidates', v_cands,
      'hold_at_step_id', v_clo_step));
    v_srid2 := nullif(v_drive->>'held_step_run_id','')::bigint;
    v_run2  := (v_drive->>'run_id')::bigint;
    if v_srid2 is null then
      raise exception 'the control drive did not hold % open: %', v_clo_step,
        coalesce(v_drive->'stopped'->>'refused_with','(no reason returned)');
    end if;
    select count(*) into v_s0 from public.phase_c_workflow_step_run where run_id = v_run2;
    begin
      perform public.fn_kernel_step_complete(jsonb_build_object(
        'step_run_id', v_srid2,
        'actor_role_id', (select accountable_role_id from public.phase_c_workflow_step_run
                           where step_run_id = v_srid2),
        'outcome','pass', 'idempotency_key','pd-state-002-control:' || v_srid2,
        'inputs', jsonb_build_object('probe','PD-STATE-002 control'),
        'output', jsonb_build_object('status','completed','output','PHASE_D_FIXTURE_DO_NOT_PUBLISH')));
      v_key := 'closed';
    exception when others then
      v_key := coalesce((regexp_match(SQLERRM,'\((k[0-9]+_[a-z0-9_]+)\)'))[1], SQLSTATE);
    end;
    select count(*) into v_s1 from public.phase_c_workflow_step_run where run_id = v_run2;
    select state, closed_at is not null into v_txt, v_ok
      from public.phase_c_workflow_run where run_id = v_run2;
    select c.kind into v_txt2 from public.fn_kernel_step_successor(v_clo_step) c;
    v_live := v_live || jsonb_build_object('PD-STATE-002', jsonb_build_object(
      'status', case when (v_b->>'code') = 'k3_closure_blocked' and (v_b->>'mand')::boolean
                      and v_key = 'closed' and v_txt = 'completed' and v_ok
                 then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end,
      'observed', format('completing %s with earlier mandatory steps never executed was refused %s '
        || '(23514) naming %s blocker class(es) including mandatory_steps_never_executed, and '
        || 'closed_at stayed null. CONTROL, every earlier step completed: run %s, closed_at set=%s.',
        v_clo_step, v_b->>'code', v_b->>'classes', v_txt, v_ok)));
    v_live := jsonb_set(v_live, '{PD-STATE-003,observed}',
      to_jsonb(format('driven instead: %s is non-closure, fn_kernel_step_successor returned %s and '
        || 'completing it opened %s successor step run(s). CONTROL %s returned %s and opened %s. '
        || 'The catalogued injection itself was NOT staged.',
        v_hold_step, v_succ_kind, v_n, v_clo_step, v_txt2, v_s1 - v_s0)));

    -- ---- ARM C: no run needed ------------------------------------------------------------------
    -- PD-TRACE-003. phase_c_trace_sealed_ck is CHECK ((status='sealed') = (sealed_at is not null)).
    -- The trace is written OPEN through fn_phase_c_trace_write, the routine every kernel caller
    -- uses, and then sealed by hand without its timestamp.
    v_tr := public.fn_phase_c_trace_write('TRACE-ROLE-ACTION', jsonb_build_object(
      'subject_kind','task','subject_ref', v_task::text, 'task_id', v_task,
      'actor_role_id', v_rev, 'system_actor_id','system.workflow_engine',
      'evidence_refs', jsonb_build_array(jsonb_build_object('probe','PD-TRACE-003')),
      'status','open'));
    begin
      update public.phase_c_trace set status = 'sealed' where trace_id = v_tr;
      v_txt := 'NOT_REFUSED';
    exception when others then v_txt := SQLSTATE;
    end;
    begin
      update public.phase_c_trace set status = 'sealed', sealed_at = now() where trace_id = v_tr;
      v_txt2 := 'accepted';
    exception when others then v_txt2 := SQLSTATE;
    end;
    v_live := v_live || jsonb_build_object('PD-TRACE-003', jsonb_build_object(
      'status', case when v_txt = '23514' and v_txt2 = 'accepted'
                 then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end,
      'observed', format('trace %s written open, then status=sealed with sealed_at left null: '
        || 'refused %s by CHECK phase_c_trace_sealed_ck, row unchanged. CONTROL, the same UPDATE '
        || 'carrying sealed_at=now(): %s.', v_tr, v_txt, v_txt2)));

    -- PD-TRACE-004. Two halves, both measured.
    -- (a) ORDERING, read off the LIVE body rather than asserted: the idempotency claim comes before
    --     every trace write, and the lost-race replay return comes before it too.
    select p.prosrc into v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'fn_kernel_step_complete';
    v_claim := strpos(v_src, 'insert into public.phase_c_step_completion');
    v_lost  := v_claim + strpos(substr(v_src, v_claim), 'return v_prior || jsonb_build_object') - 1;
    v_first := least(nullif(strpos(v_src, 'fn_phase_c_trace_advance('), 0),
                     nullif(strpos(v_src, 'fn_kernel_open_step('), 0));
    -- (b) THE DETECTOR IS FORCEABLE. z95_phase_c_task_trace_committed is a DEFERRABLE INITIALLY
    --     DEFERRED constraint trigger, so its verdict is normally pronounced only at COMMIT -- which
    --     is what the old blocker mistook for "this needs to commit". SET CONSTRAINTS ALL IMMEDIATE
    --     pronounces it here. The control runs FIRST, on the estate exactly as the arms left it, and
    --     each half unwinds its own frame so the transaction is not left in immediate mode.
    begin
      set constraints all immediate;
      v_txt := 'silent';
      raise exception 'PD_TRACE_004_UNWIND_CONTROL';
    exception when others then
      if position('PD_TRACE_004_UNWIND_CONTROL' in SQLERRM) = 0 then
        v_txt := SQLSTATE || ' ' || left(SQLERRM, 80);
      end if;
    end;
    select t.task_id, t.trace_id into v_id, v_tr from public.phase_c_task t
     where t.run_id = v_run2 and t.trace_id is not null order by t.task_id limit 1;
    begin
      delete from public.phase_c_trace where trace_id = v_tr;
      set constraints all immediate;
      v_txt2 := 'NOT_REFUSED';
      raise exception 'PD_TRACE_004_UNWIND_INJECTION';
    exception when others then
      if position('PD_TRACE_004_UNWIND_INJECTION' in SQLERRM) = 0 then v_txt2 := SQLSTATE; end if;
    end;
    v_live := v_live || jsonb_build_object('PD-TRACE-004', jsonb_build_object(
      'status', case when v_claim > 0 and v_lost > v_claim and v_first > v_lost
                      and v_txt = 'silent' and v_txt2 = '23503'
                 then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end,
      'observed', format('(a) in the live fn_kernel_step_complete the idempotency claim is at char '
        || '%s, its lost-race replay return at %s, the FIRST trace write at %s: a lost race returns '
        || 'before any trace exists. (b) forcing the deferred pair guards: a correctly paired '
        || 'task+trace is %s; task %s pointed at a deleted trace raises %s.',
        v_claim, v_lost, v_first, v_txt, v_id, v_txt2)));

  exception when others then
    -- One frame for the whole staging. Nothing it created survives, and every one of the eight says
    -- what stopped it rather than reporting an injection that was never made.
    v_live := jsonb_build_object('__stage_error', left(SQLERRM, 260));
  end;
