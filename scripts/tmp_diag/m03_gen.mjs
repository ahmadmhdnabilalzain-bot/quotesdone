// M03 - replace the eight NOT_RUN blocker branches in fn_phase_d_run_injected_defects().
// Reads the LIVE body and does exact string replacement, anchored on COMPLETE branches
// including their `return next;`. Never retypes the 516-line function.
import fs from 'node:fs';
const SRC = 'scripts/tmp_diag/m03_live.sql';
let f = fs.readFileSync(SRC, 'utf8');
const cut = (a, b) => {
  if (!f.includes(a)) { console.error('ANCHOR MISS:\n' + a.slice(0, 200)); process.exit(1); }
  if (f.split(a).length !== 2) { console.error('ANCHOR NOT UNIQUE:\n' + a.slice(0, 200)); process.exit(1); }
  f = f.replace(a, b);
};

// ---- 0. the locals the new branches need ------------------------------------------------------
cut(
`  v_sup text; v_id bigint;
begin`,
`  v_sup text; v_id bigint;
  -- M03. The locals the eight re-measured branches need. Every one is scratch for a single branch
  -- except v_m3_trace and v_m3_task, which carry a REAL sealed verdict and a REAL task from the
  -- branch that produced them to the branch that has to attempt to tamper with it.
  v_m3_fx jsonb; v_m3_drive jsonb; v_m3_a jsonb;
  v_m3_refkey text; v_m3_boid text; v_m3_key text; v_m3_ctl text; v_m3_state text; v_m3_def text;
  v_m3_srid bigint; v_m3_run bigint; v_m3_task bigint; v_m3_trace bigint; v_m3_sup bigint;
  v_m3_n int; v_m3_s0 int; v_m3_s1 int; v_m3_p1 int; v_m3_p2 int; v_m3_p3 int;
  v_m3_ok2 boolean; v_m3_orph bigint;
begin`);

// the drive preamble, repeated per branch because plpgsql has no local routine
const DRIVE = (label, hold) => `
    perform set_config('app.phase_d_hold_step','${hold}', true);
    v_m3_fx := public.fn_phase_d_fixture_scenario(jsonb_build_object(
      'label','${label}','execution_context','test','for_workflow','W04'));
    select st.contributes_ref into v_m3_refkey from public.phase_d_fixture_stage st
     where st.object_id = (select primary_object from public.phase_b_workflow where workflow_id='W04')
     limit 1;
    v_m3_boid := case when v_m3_refkey is not null and coalesce(v_m3_fx->'parent_refs'->>v_m3_refkey,'') <> ''
      then (select primary_object from public.phase_b_workflow where workflow_id='W04')
           || ':' || (v_m3_fx->'parent_refs'->>v_m3_refkey) else null end;
    v_m3_drive := public.fn_phase_d_drive_workflow(jsonb_build_object(
      'workflow_id','W04','label','${label}','execution_context','production',
      'hold_at_step_id','${hold}')
      || case when v_m3_boid is null then '{}'::jsonb
              else jsonb_build_object('business_object_id', v_m3_boid) end);
    v_m3_srid := nullif(v_m3_drive->>'held_step_run_id','')::bigint;
    v_m3_run  := nullif(v_m3_drive->>'run_id','')::bigint;
    perform set_config('app.phase_d_hold_step','', true);`;

const COMPLETE = (srid, key, mode, out, crit) => `public.fn_kernel_step_complete(jsonb_build_object(
        'step_run_id', ${srid},
        'actor_role_id', (select accountable_role_id from public.phase_c_workflow_step_run
                           where step_run_id = ${srid}),
        'outcome','pass', 'idempotency_key', ${key},
        'inputs', jsonb_build_object('mode','${mode}'),
        'output', jsonb_build_object('status','completed','output',
          'PHASE_D_FIXTURE_DO_NOT_PUBLISH - ${out}'),
        'evidence_refs', jsonb_build_array(jsonb_build_object('mode','${mode}')),
        'acceptance_criteria','${crit}',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - Phase D injected-defect probe, aborted',
        'object_version', 1))`;

// ============================== 1. PD-IDEM-002 =================================================
cut(
`  -- PD-IDEM-002 duplicate workflow step completion -> the frozen kernel decides.
  defect_id:='PD-IDEM-002'; category:='IDEMPOTENCY'; status:='NOT_RUN';
  observed := null;
  blocker := 'needs a live step run to complete twice; the driver aborts its transaction so a second '
          || 'fn_kernel_step_complete on the SAME committed step run cannot be staged here. Executing it '
          || 'requires the section 8 API path that completes a step from outside a single transaction.';
  return next;`,
`  -- PD-IDEM-002 duplicate workflow step completion -> the FIRST result is returned again.
  -- THE OLD BLOCKER SAID THIS NEEDED A COMMITTED STEP RUN. Re-measured 24 Aug 2026 and false.
  -- fn_kernel_step_complete section 1 reads public.phase_c_step_completion by idempotency_key
  -- BEFORE any work and returns v_prior || jsonb_build_object('replay', true). Nothing on that
  -- path waits for a commit, so two calls in ONE transaction exercise the real branch.
  begin${DRIVE('zz-pd-idem-002', 'W04-S03')}
    if v_m3_srid is null then
      v_ok := false;
      v_msg := 'no step run was held open at W04-S03; the drive stopped at '
            || coalesce(v_m3_drive->'stopped'->>'refused_with','(no reason given)');
    else
      v_m3_key := 'zz-pd-idem-002:' || v_m3_srid;
      v_a := ${COMPLETE('v_m3_srid', 'v_m3_key', 'first completion', 'validated customer profile', 'the step completes once')};
      v_b := ${COMPLETE('v_m3_srid', 'v_m3_key', 'duplicate completion', 'validated customer profile', 'a duplicate returns the first result')};
      begin
        perform ${COMPLETE('v_m3_srid', "v_m3_key || ':a-different-key'", 'control', 'validated customer profile', 'a different key on a step run already completed')};
        v_m3_ctl := 'ACCEPTED';
      exception when others then
        v_m3_ctl := case when position('k3_step_state_invalid' in SQLERRM) > 0
                         then 'k3_step_state_invalid/' || SQLSTATE
                         else SQLSTATE || ':' || left(SQLERRM, 60) end;
      end;
      select count(*) into v_m3_n from public.phase_c_step_completion where step_run_id = v_m3_srid;
      select state into v_m3_state from public.phase_c_workflow_step_run where step_run_id = v_m3_srid;
      v_ok := not coalesce((v_a->>'replay')::boolean, true)
          and coalesce((v_b->>'replay')::boolean, false)
          and v_m3_ctl = 'k3_step_state_invalid/23514'
          and v_m3_n = 1 and v_m3_state = 'completed';
      v_msg := format(
        'W04 driven through the kernel doors and held open at W04-S03 (step run %s). INJECTION: '
     || 'fn_kernel_step_complete called TWICE with the same idempotency_key %L. First call '
     || 'replay=%s; second call replay=%s and it returned the FIRST stored result rather than '
     || 'recomputing one. CONTROL, differing in exactly one respect - same step run, same actor, '
     || 'same output, a DIFFERENT idempotency_key: %s, because public.phase_b_step_transition '
     || 'declares no completed -> completed edge, so a second real completion is refused rather '
     || 'than replayed. public.phase_c_step_completion rows for this step run: %s. Step run state: '
     || '%s. No second completion and no second effect; the transaction is aborted.',
        v_m3_srid, v_m3_key, coalesce(v_a->>'replay','(null)'), coalesce(v_b->>'replay','(null)'),
        v_m3_ctl, v_m3_n, v_m3_state);
    end if;
  exception when others then
    perform set_config('app.phase_d_hold_step','', true);
    v_ok := false;
    v_msg := 'the W04 drive raised before the injection could be made: ' || left(SQLERRM, 220);
  end;
  defect_id:='PD-IDEM-002'; category:='IDEMPOTENCY';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;`);

// ============================== 2/3/4. PD-REV-002 / 004 / 005 ==================================
cut(
`  -- PD-REV-002/004/005 need a committed task and a sealed verdict.
  defect_id:='PD-REV-002'; category:='REVIEW'; status:='NOT_RUN'; observed:=null;
  blocker := 'the driver records a verdict and completes the step inside one aborted transaction; leaving a '
          || 'step in waiting_review to observe it requires a committed run, which the hold forbids.';
  return next;
  defect_id:='PD-REV-004'; category:='REVIEW'; status:='NOT_RUN'; observed:=null;
  blocker := 'requires driving a REJECTED verdict through a committed run to observe that no successor task '
          || 'is created; the handoff rejection path is proved separately in D9k but not as this injection.';
  return next;
  defect_id:='PD-REV-005'; category:='REVIEW'; status:='NOT_RUN'; observed:=null;
  blocker := 'needs a sealed verdict row to attempt to edit; sealing happens on commit and this file aborts.';
  return next;`,
`  -- PD-REV-002/004/005. THE OLD BLOCKERS SAID THESE NEEDED A COMMITTED RUN AND A COMMIT-TIME SEAL.
  -- Re-measured 24 Aug 2026 and false on both counts: fn_kernel_step_complete section 3g raises
  -- k3_reviewer_verdict_missing in the same statement, and fn_phase_c_trace_write stamps sealed_at
  -- in the same INSERT that sets status='sealed'. Neither waits for a commit.

  -- PD-REV-002 a required review step completed with no verdict -> refused.
  begin${DRIVE('zz-pd-rev-002', 'W04-S04')}
    if v_m3_srid is null then
      v_ok := false;
      v_msg := 'no step run was held open at W04-S04; the drive stopped at '
            || coalesce(v_m3_drive->'stopped'->>'refused_with','(no reason given)');
    else
      select t.task_id into v_m3_task from public.phase_c_task t
       where t.run_id = v_m3_run and t.step_id = 'W04-S04' order by t.task_id limit 1;
      begin
        perform ${COMPLETE('v_m3_srid', "'zz-pd-rev-002-inj:' || v_m3_srid", 'no verdict recorded', 'acceptance record linked to the exact document version and identity', 'a required review step may not pass unreviewed')};
        v_m3_ctl := 'COMPLETED_UNREVIEWED';
      exception when others then
        v_m3_ctl := case when position('k3_reviewer_verdict_missing' in SQLERRM) > 0
                         then 'k3_reviewer_verdict_missing/' || SQLSTATE
                         else SQLSTATE || ':' || left(SQLERRM, 60) end;
      end;
      perform public.fn_kernel_review_decide(jsonb_build_object(
        'task_id', v_m3_task, 'reviewer_role_id','compliance_and_privacy_officer',
        'decision','approved',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - the declared independent reviewer approves'));
      begin
        perform ${COMPLETE('v_m3_srid', "'zz-pd-rev-002-ctl:' || v_m3_srid", 'approved verdict on record', 'acceptance record linked to the exact document version and identity', 'the same step with a sealed approving verdict completes')};
        v_m3_state := 'COMPLETED';
      exception when others then
        v_m3_state := SQLSTATE || ':' || left(SQLERRM, 90);
      end;
      v_ok := v_m3_ctl = 'k3_reviewer_verdict_missing/23514' and v_m3_state = 'COMPLETED';
      v_msg := format(
        'W04 held open at W04-S04 (step run %s, task %s), one of the 28 of 257 frozen steps that '
     || 'declare an independent_reviewer_role_id - here compliance_and_privacy_officer. INJECTION: '
     || 'fn_kernel_step_complete outcome=pass with no verdict on the task at all -> %s. CONTROL, '
     || 'differing in exactly one respect - fn_kernel_review_decide first records an APPROVED '
     || 'verdict from that same declared reviewer - and the identical call then %s. Section 3g is '
     || 'the predicate: it looks for a TRACE-ROLE-ACTION trace on the task whose evidence_refs '
     || 'carry review_decision=approved from a reviewer that resolves to the declared one and is '
     || 'independent of the step owner. The refused arm left no partial completion; the whole '
     || 'transaction is aborted.',
        v_m3_srid, v_m3_task, v_m3_ctl, v_m3_state);
    end if;
  exception when others then
    perform set_config('app.phase_d_hold_step','', true);
    v_ok := false;
    v_msg := 'the W04 drive raised before the injection could be made: ' || left(SQLERRM, 220);
  end;
  defect_id:='PD-REV-002'; category:='REVIEW';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- PD-REV-004 a REJECTED output pushed forward -> refused, and no successor is opened.
  begin${DRIVE('zz-pd-rev-004', 'W04-S04')}
    if v_m3_srid is null then
      v_ok := false; v_m3_trace := null;
      v_msg := 'no step run was held open at W04-S04; the drive stopped at '
            || coalesce(v_m3_drive->'stopped'->>'refused_with','(no reason given)');
    else
      select t.task_id into v_m3_task from public.phase_c_task t
       where t.run_id = v_m3_run and t.step_id = 'W04-S04' order by t.task_id limit 1;
      select count(*) into v_m3_s0 from public.phase_c_workflow_step_run
       where run_id = v_m3_run and step_id = 'W04-S05';
      perform public.fn_kernel_review_decide(jsonb_build_object(
        'task_id', v_m3_task, 'reviewer_role_id','compliance_and_privacy_officer',
        'decision','rejected',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - the declared reviewer rejects this output'));
      begin
        perform ${COMPLETE('v_m3_srid', "'zz-pd-rev-004-inj:' || v_m3_srid", 'rejected output pushed forward', 'acceptance record linked to the exact document version and identity', 'a rejected output must not progress')};
        v_m3_ctl := 'PROGRESSED';
      exception when others then
        v_m3_ctl := case when position('k3_reviewer_verdict_missing' in SQLERRM) > 0
                         then 'k3_reviewer_verdict_missing/' || SQLSTATE
                         else SQLSTATE || ':' || left(SQLERRM, 60) end;
      end;
      select count(*) into v_m3_n from public.phase_c_workflow_step_run
       where run_id = v_m3_run and step_id = 'W04-S05';
      v_m3_a := public.fn_kernel_review_decide(jsonb_build_object(
        'task_id', v_m3_task, 'reviewer_role_id','compliance_and_privacy_officer',
        'decision','approved',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - the same reviewer approves the same output'));
      v_m3_trace := nullif(v_m3_a->>'trace_id','')::bigint;   -- the subject PD-REV-005 tampers with
      begin
        perform ${COMPLETE('v_m3_srid', "'zz-pd-rev-004-ctl:' || v_m3_srid", 'approved output progresses', 'acceptance record linked to the exact document version and identity', 'an approved output progresses to its successor')};
        v_m3_state := 'PROGRESSED';
      exception when others then
        v_m3_state := SQLSTATE || ':' || left(SQLERRM, 90);
      end;
      select count(*) into v_m3_s1 from public.phase_c_workflow_step_run
       where run_id = v_m3_run and step_id = 'W04-S05';
      v_ok := v_m3_ctl = 'k3_reviewer_verdict_missing/23514'
          and v_m3_s0 = 0 and v_m3_n = 0
          and v_m3_state = 'PROGRESSED' and v_m3_s1 = 1;
      v_msg := format(
        'W04 held open at W04-S04 (step run %s, task %s). Its successor W04-S05 has the same owner, '
     || 'so the kernel opens it directly and no handoff has to be accepted first - which is what '
     || 'makes "was a successor opened" a readable number here. INJECTION: fn_kernel_review_decide '
     || 'records a REJECTED verdict from the declared reviewer, then fn_kernel_step_complete is '
     || 'called with outcome=pass -> %s, and public.phase_c_workflow_step_run rows for W04-S05 went '
     || '%s -> %s: no successor step run was opened. CONTROL, differing in exactly one respect - '
     || 'the same reviewer records APPROVED on the same task - and the identical call %s, W04-S05 '
     || 'step runs going to %s. MEASURED GAP, STATED AND NOT FIXED HERE: section 3g runs only when '
     || 'outcome=''pass'' AND the step declares an independent_reviewer_role_id. 28 of the 257 '
     || 'frozen steps declare one, so on the other 229 a recorded rejected verdict stops nothing: '
     || 'fn_kernel_review_decide writes the sealed trace and stamps phase_c_task.reviewer_role_id, '
     || 'and no predicate in the kernel reads review_decision=rejected. That is a measurement, not '
     || 'a repair.',
        v_m3_srid, v_m3_task, v_m3_ctl, v_m3_s0, v_m3_n, v_m3_state, v_m3_s1);
    end if;
  exception when others then
    perform set_config('app.phase_d_hold_step','', true);
    v_ok := false; v_m3_trace := null;
    v_msg := 'the W04 drive raised before the injection could be made: ' || left(SQLERRM, 220);
  end;
  defect_id:='PD-REV-004'; category:='REVIEW';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- PD-REV-005 a verdict edited after sealing -> append-only refusal.
  -- The subject is the REAL sealed verdict fn_kernel_review_decide wrote for PD-REV-004. A trace
  -- this branch minted for itself would be an identity it had generated, which proves nothing.
  if v_m3_trace is null then
    v_ok := false; v_m3_ctl := 'NO_SUBJECT';
    v_msg := 'PD-REV-004 produced no sealed verdict trace, so there was no verdict to attempt to '
          || 'edit and nothing was injected. With no subject there is nothing to discriminate; this '
          || 'is not a pass.';
  else
    select (sealed_at is not null) into v_m3_ok2 from public.phase_c_trace where trace_id = v_m3_trace;
    begin
      update public.phase_c_trace
         set evidence_refs = evidence_refs || '[{"review_decision":"approved","tampered":true}]'::jsonb
       where trace_id = v_m3_trace;
      v_m3_ctl := 'ACCEPTED';
    exception when others then
      v_m3_ctl := case when position('append-only' in SQLERRM) > 0
                       then 'z10_phase_c_trace_append_only/' || SQLSTATE
                       else SQLSTATE || ':' || left(SQLERRM, 60) end;
    end;
    begin
      v_m3_sup := public.fn_phase_c_trace_write('TRACE-ROLE-ACTION', jsonb_build_object(
        'subject_kind','task', 'subject_ref', v_m3_task::text, 'task_id', v_m3_task,
        'actor_role_id','defect_probe', 'status','sealed',
        'evidence_refs', jsonb_build_array(jsonb_build_object(
          'note','PHASE_D_FIXTURE_DO_NOT_PUBLISH - the superseding row the trigger names'))));
      update public.phase_c_trace set superseded_by = v_m3_sup where trace_id = v_m3_trace;
      v_m3_state := 'ACCEPTED';
    exception when others then
      v_m3_state := SQLSTATE || ':' || left(SQLERRM, 90);
    end;
    select count(*) into v_m3_n from public.phase_c_trace
     where trace_id = v_m3_trace and evidence_refs @> '[{"tampered":true}]'::jsonb;
    v_ok := v_m3_ctl = 'z10_phase_c_trace_append_only/23514'
        and v_m3_state = 'ACCEPTED' and v_m3_n = 0 and coalesce(v_m3_ok2, false);
    v_msg := format(
      'The subject is trace %s, the sealed TRACE-ROLE-ACTION verdict fn_kernel_review_decide wrote '
   || 'for PD-REV-004. sealed_at is already not null on it: %s - fn_phase_c_trace_write stamps '
   || 'sealed_at in the same INSERT that sets status=''sealed'', so the seal does not wait for a '
   || 'commit and the old blocker was wrong about that. INJECTION: an UPDATE of its evidence_refs '
   || 'adding a second approving decision -> %s. CONTROL, differing in exactly one respect - the '
   || 'same UPDATE on the same sealed row changing ONLY superseded_by from null, pointing at a '
   || 'superseding sealed trace written through the same door -> %s. Rows on phase_c_trace carrying '
   || 'the tampered evidence afterwards: %s.',
      v_m3_trace, coalesce(v_m3_ok2::text,'(unknown)'), v_m3_ctl, v_m3_state, v_m3_n);
  end if;
  defect_id:='PD-REV-005'; category:='REVIEW';
  status := case when v_ok then 'REFUSED_AS_REQUIRED'
                 when v_m3_ctl = 'NO_SUBJECT' then 'NOT_DISCRIMINATED'
                 else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;`);

// ============================== 5/6. PD-STATE-002 / 003 ========================================
cut(
`  -- PD-STATE-002/003/004 need a committed run to observe closure and successor behaviour.
  defect_id:='PD-STATE-002'; category:='STATE'; status:='NOT_RUN'; observed:=null;
  blocker := 'closing a workflow with a mandatory blocker open needs a committed run whose closed_at can be '
          || 'read afterwards; every Phase D drive aborts.';
  return next;
  defect_id:='PD-STATE-003'; category:='STATE'; status:='NOT_RUN'; observed:=null;
  blocker := 'requires a committed run to show the successor was not skipped.';
  return next;`,
`  -- PD-STATE-002/003. THE OLD BLOCKERS SAID BOTH NEEDED A COMMITTED RUN. Re-measured 24 Aug 2026
  -- and false: k3_closure_blocked is raised by fn_kernel_step_complete in the same statement, and
  -- closed_at is written in the same statement too, so both are readable before any commit.

  -- PD-STATE-002 a workflow closed with a mandatory blocker open -> a stable refusal code.
  -- ONE drive carries both arms. The injection runs inside its own subtransaction, so the refusal
  -- unwinds every row it staged and the control then starts from the state the drive left.
  begin${DRIVE('zz-pd-state-002', 'W04-S06')}
    if v_m3_srid is null then
      v_ok := false; v_m3_task := null;
      v_msg := 'no step run was held open at W04-S06; the drive stopped at '
            || coalesce(v_m3_drive->'stopped'->>'refused_with','(no reason given)');
    else
      perform set_config('app.phase_d_hold_step','W04-S07', true);
      select count(*) into v_m3_s0 from public.phase_c_workflow_step_run where run_id = v_m3_run;
      begin
        v_m3_a := public.fn_kernel_open_step(jsonb_build_object(
          'run_id', v_m3_run, 'step_id','W04-S07', 'owner_role_id','customer_onboarding',
          'opened_because','PHASE_D_FIXTURE_DO_NOT_PUBLISH - closure attempted with W04-S06 open'));
        select t.task_id into v_m3_task from public.phase_c_task t
         where t.run_id = v_m3_run and t.step_id = 'W04-S07' order by t.task_id limit 1;
        perform public.fn_kernel_review_decide(jsonb_build_object(
          'task_id', v_m3_task, 'reviewer_role_id','customer_success_director','decision','approved',
          'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - the closure step''s declared reviewer approves'));
        perform ${COMPLETE("(v_m3_a->>'step_run_id')::bigint", "'zz-pd-state-002-inj:' || v_m3_run", 'closure with a mandatory step still open', 'closed onboarding record', 'a run may not close over an unexecuted mandatory step')};
        v_m3_ctl := 'CLOSED';
      exception when others then
        v_m3_ctl := case when position('k3_closure_blocked' in SQLERRM) > 0
                         then 'k3_closure_blocked/' || SQLSTATE
                              || case when position('mandatory_steps_never_executed' in SQLERRM) > 0
                                      then ' listing mandatory_steps_never_executed'
                                      else ' WITHOUT naming mandatory_steps_never_executed' end
                         else SQLSTATE || ':' || left(SQLERRM, 60) end;
      end;
      select count(*) into v_m3_s1 from public.phase_c_workflow_step_run where run_id = v_m3_run;
      select count(*) into v_m3_p1 from public.phase_c_workflow_run
       where run_id = v_m3_run and closed_at is not null;
      -- CONTROL: the one thing that differs is that the mandatory step is executed first.
      perform ${COMPLETE('v_m3_srid', "'zz-pd-state-002-ctl6:' || v_m3_run", 'the last mandatory step is executed', 'onboarding completion and inquiry-start handoff', 'every earlier mandatory step reaches a terminal state')};
      select sr.step_run_id into v_m3_sup from public.phase_c_workflow_step_run sr
       where sr.run_id = v_m3_run and sr.step_id = 'W04-S07' order by sr.step_run_id limit 1;
      select t.task_id into v_m3_task from public.phase_c_task t
       where t.run_id = v_m3_run and t.step_id = 'W04-S07' order by t.task_id limit 1;
      perform public.fn_kernel_review_decide(jsonb_build_object(
        'task_id', v_m3_task, 'reviewer_role_id','customer_success_director','decision','approved',
        'reason','PHASE_D_FIXTURE_DO_NOT_PUBLISH - the closure step''s declared reviewer approves'));
      begin
        perform ${COMPLETE('v_m3_sup', "'zz-pd-state-002-ctl7:' || v_m3_run", 'closure with every mandatory step executed', 'closed onboarding record', 'the run closes')};
        v_m3_state := 'CLOSED';
      exception when others then
        v_m3_state := SQLSTATE || ':' || left(SQLERRM, 90);
      end;
      select count(*) into v_m3_p2 from public.phase_c_workflow_run
       where run_id = v_m3_run and closed_at is not null;
      select state into v_m3_def from public.phase_c_workflow_run where run_id = v_m3_run;
      v_ok := v_m3_ctl like 'k3_closure_blocked/23514 listing mandatory_steps%'
          and v_m3_p1 = 0 and v_m3_s0 = v_m3_s1
          and v_m3_state = 'CLOSED' and v_m3_p2 = 1 and v_m3_def = 'completed';
      v_msg := format(
        'W04 driven to W04-S06 and held there, so W04-S01..S05 are completed and W04-S06 - a '
     || 'mandatory step of this workflow - has never reached a terminal state. INJECTION: the '
     || 'closure step W04-S07 is opened through the kernel''s own fn_kernel_open_step, its declared '
     || 'reviewer approves, and fn_kernel_step_complete is called with outcome=pass -> %s. The run''s '
     || 'closed_at rows: %s; step runs on the run went %s -> %s, so the refusal left nothing behind. '
     || 'CONTROL, differing in exactly one respect - W04-S06 is completed through '
     || 'fn_kernel_step_complete first, so no mandatory step is open - and the closure step then %s, '
     || 'the run reaching state %L with closed_at set on %s row. The closure step run in the control '
     || 'was opened by the kernel''s own progression rather than by fn_kernel_open_step; that is a '
     || 'consequence of the injected condition, not a second variable, because progression cannot '
     || 'reach a closure step whose predecessor is still open.',
        v_m3_ctl, v_m3_p1, v_m3_s0, v_m3_s1, v_m3_state, v_m3_def, v_m3_p2);
    end if;
  exception when others then
    perform set_config('app.phase_d_hold_step','', true);
    v_ok := false;
    v_msg := 'the W04 drive raised before the injection could be made: ' || left(SQLERRM, 220);
  end;
  defect_id:='PD-STATE-002'; category:='STATE';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  -- PD-STATE-003 a nonterminal step treated as closure -> a stable refusal code.
  -- THIS ONE IS NOT CLOSED, AND SAYING SO IS THE POINT. The refusal exists - fn_kernel_step_successor
  -- returns kind=closure_flag_disagrees and fn_kernel_step_complete turns that into
  -- k3_no_valid_successor (23514) - but the condition it answers cannot be created. Terminality is
  -- stated twice in public.phase_b_workflow_step (next_step_if_pass = 'WORKFLOW_COMPLETE' and
  -- is_closure_step) and the two agree on all 257 rows. Making them disagree means UPDATE-ing
  -- phase_b_workflow_step, which z90_phase_b_freeze refuses without a Phase B change request, and
  -- setting app.phase_b_change_reason to get past the founder's freeze inside a defect probe is not
  -- something this file will do. A zero-population arm is NOT_DISCRIMINATED, never a pass.
  select count(*) into v_m3_n from public.phase_b_workflow_step
   where (next_step_if_pass = 'WORKFLOW_COMPLETE') is distinct from is_closure_step;
  select count(*) into v_m3_p1 from public.phase_b_workflow_step;
  select count(*) into v_m3_p2 from public.phase_b_workflow_step where is_closure_step;
  v_m3_ctl   := (select kind from public.fn_kernel_step_successor('W04-S06'));
  v_m3_state := (select kind from public.fn_kernel_step_successor('W04-S07'));
  defect_id:='PD-STATE-003'; category:='STATE';
  status := 'NOT_DISCRIMINATED';
  observed := format(
      'The injection has an empty population: %s of %s frozen steps state their terminality '
   || 'inconsistently, so there is no nonterminal step anywhere in the estate that any caller '
   || 'could present to the kernel as a closure step. What IS driveable, and was driven in this '
   || 'transaction by PD-STATE-002 on the same W04 run, is the discrimination itself: completing '
   || 'the NON-closure step W04-S06 returned successor kind %L and the kernel opened a successor '
   || 'step run for W04-S07, while the run''s closure step W04-S07 returns kind %L, opens no '
   || 'successor at all and closes the run instead - %s of the %s steps are closure steps. That '
   || 'shows the kernel does not confuse the two; it is not the catalogued injection and it '
   || 'observes no refusal, so it is not recorded as one.',
      v_m3_n, v_m3_p1, coalesce(v_m3_ctl,'(none)'), coalesce(v_m3_state,'(none)'), v_m3_p2, v_m3_p1);
  blocker := 'UNREACHABLE INJECTION, not an unbuilt harness. fn_kernel_step_successor already '
          || 'carries the refusal (kind=closure_flag_disagrees -> k3_no_valid_successor, 23514) and '
          || 'fn_kernel_step_complete already raises it. Creating the disagreement requires an '
          || 'UPDATE of the FROZEN public.phase_b_workflow_step, refused by z90_phase_b_freeze '
          || 'unless app.phase_b_change_reason names a Phase B change request. Closing this row '
          || 'honestly needs the founder to approve a change request that introduces the '
          || 'inconsistency deliberately, or it stays open.';
  return next;`);

// ============================== 7. PD-TRACE-003 ================================================
cut(
`  defect_id:='PD-TRACE-003'; category:='TRACE'; status:='NOT_RUN'; observed:=null;
  blocker := 'as PD-TRACE-001: sealing is a kernel operation and sealed_at is a kernel column.';
  return next;`,
`  -- PD-TRACE-003 a sealed trace with no sealed_at -> refused.
  -- THE OLD BLOCKER SAID sealed_at IS A KERNEL COLUMN AND SO OUT OF REACH. Re-measured 24 Aug 2026:
  -- the refusal is a CHECK constraint, phase_c_trace_sealed_ck ((status='sealed') = (sealed_at is
  -- not null)), which fires on the statement, not at commit and not through any kernel routine.
  begin
    v_m3_trace := public.fn_phase_c_trace_write('TRACE-ROLE-ACTION', jsonb_build_object(
      'subject_kind','task', 'subject_ref','zz-pd-trace-003',
      'actor_role_id','defect_probe', 'status','open',
      'evidence_refs', jsonb_build_array(jsonb_build_object(
        'note','PHASE_D_FIXTURE_DO_NOT_PUBLISH - an OPEN trace, written through the kernel door'))));
    -- ALIASED: status, observed, category, defect_id and blocker are OUT columns of this
    -- function, so an unqualified status in a query against phase_c_trace is ambiguous (42702).
    select (tr.sealed_at is null and tr.status = 'open') into v_m3_ok2
      from public.phase_c_trace tr where tr.trace_id = v_m3_trace;
    begin
      update public.phase_c_trace set status = 'sealed' where trace_id = v_m3_trace;
      v_m3_ctl := 'ACCEPTED';
    exception when others then
      v_m3_ctl := case when position('phase_c_trace_sealed_ck' in SQLERRM) > 0
                       then 'phase_c_trace_sealed_ck/' || SQLSTATE
                       else SQLSTATE || ':' || left(SQLERRM, 60) end;
    end;
    begin
      update public.phase_c_trace set status = 'sealed', sealed_at = now()
       where trace_id = v_m3_trace;
      v_m3_state := 'ACCEPTED';
    exception when others then
      v_m3_state := SQLSTATE || ':' || left(SQLERRM, 90);
    end;
    select count(*) into v_m3_n from public.phase_c_trace tr
     where tr.trace_id = v_m3_trace and tr.status = 'sealed' and tr.sealed_at is null;
    v_ok := coalesce(v_m3_ok2,false) and v_m3_ctl = 'phase_c_trace_sealed_ck/23514'
        and v_m3_state = 'ACCEPTED' and v_m3_n = 0;
    v_msg := format(
      'An OPEN trace %s was written through fn_phase_c_trace_write (status=open, sealed_at null: %s). '
   || 'INJECTION: update it to status=''sealed'' and leave sealed_at null -> %s. CONTROL, differing '
   || 'in exactly one respect - the SAME update with sealed_at = now() -> %s. Rows on '
   || 'public.phase_c_trace that are sealed with a null sealed_at after both attempts: %s. The '
   || 'refusal is the table''s own CHECK, so it is the same answer for every writer of that column, '
   || 'kernel or not; the whole transaction is aborted.',
      v_m3_trace, coalesce(v_m3_ok2::text,'(unknown)'), v_m3_ctl, v_m3_state, v_m3_n);
  exception when others then
    v_ok := false;
    v_msg := 'the open trace could not be written, so nothing was injected: ' || left(SQLERRM, 200);
  end;
  defect_id:='PD-TRACE-003'; category:='TRACE';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;`);

// ============================== 8. PD-TRACE-004 ================================================
cut(
`  defect_id:='PD-TRACE-004'; category:='TRACE'; status:='NOT_RUN'; observed:=null;
  blocker := 'observing an ORPHAN trace after a failed insert needs the failed insert to commit its trace, '
          || 'which cannot happen inside one aborted transaction.';
  return next;`,
`  -- PD-TRACE-004 a failed idempotent insert leaves an orphan trace -> zero orphan.
  -- THE OLD BLOCKER SAID THE ORPHAN HAD TO COMMIT TO BE SEEN. Re-measured 24 Aug 2026 and false in
  -- two independent ways, both below: the ORDERING that makes the orphan impossible is readable
  -- from the routine itself, and the detector that would catch one is DEFERRABLE, which means
  -- SET CONSTRAINTS ALL IMMEDIATE fires it inside this transaction instead of at a commit.

  -- (a) ORDERING, measured off the live routine rather than asserted about it.
  select pg_get_functiondef('public.fn_kernel_step_complete(jsonb)'::regprocedure) into v_m3_def;
  v_m3_p1 := position('4. CLAIM THE IDEMPOTENCY KEY' in v_m3_def);
  v_m3_p2 := position('idempotency key % is claimed and carries no result' in v_m3_def);
  v_m3_p3 := least(nullif(position('fn_phase_c_trace_advance' in v_m3_def),0),
                   nullif(position('fn_phase_c_trace_write'   in v_m3_def),0));
  v_m3_ok2 := v_m3_p1 > 0 and v_m3_p2 > 0 and v_m3_p3 > 0
          and v_m3_p1 < v_m3_p2 and v_m3_p2 < v_m3_p3;

  -- (b) THE DETECTOR IS FORCEABLE. z90_system_execution_pair_guard on public.phase_c_trace is a
  --     CONSTRAINT TRIGGER, DEFERRABLE INITIALLY DEFERRED.
  begin
    v_m3_trace := public.fn_phase_c_trace_write('TRACE-SYSTEM-EXECUTION', jsonb_build_object(
      'subject_kind','system_execution', 'subject_ref','zz.pd.trace004.probe',
      'component_id','zz.pd.trace004.probe', 'actor_role_id','defect_probe', 'status','open'));
    set constraints all immediate;
    v_m3_state := 'SILENT';
    set constraints all deferred;
  exception when others then
    v_m3_state := SQLSTATE || ':' || left(SQLERRM, 90);
  end;
  begin
    v_m3_sup := public.fn_phase_c_trace_write('TRACE-SYSTEM-EXECUTION', jsonb_build_object(
      'subject_kind','system_execution', 'subject_ref','zz.pd.trace004.probe',
      'component_id','zz.pd.trace004.probe', 'actor_role_id','defect_probe', 'status','sealed'));
    set constraints all immediate;
    v_m3_ctl := 'SILENT';
    set constraints all deferred;
  exception when others then
    v_m3_ctl := case when position('with no row in phase_c_system_execution' in SQLERRM) > 0
                     then 'z90_system_execution_pair_guard/' || SQLSTATE
                     else SQLSTATE || ':' || left(SQLERRM, 60) end;
  end;

  -- (c) THE TASK SIDE CANNOT EVEN BE STAGED, and that is a stronger answer than the one expected.
  if v_m3_task is null then
    v_m3_key := 'no task from the PD-STATE-002 drive was available to point at a deleted trace';
  else
    begin
      v_m3_orph := public.fn_phase_c_trace_write('TRACE-ROLE-ACTION', jsonb_build_object(
        'subject_kind','task', 'subject_ref','zz-pd-trace-004-orphan',
        'actor_role_id','defect_probe', 'status','open'));
      delete from public.phase_c_trace where trace_id = v_m3_orph;
      update public.phase_c_task set trace_id = v_m3_orph where task_id = v_m3_task;
      set constraints all immediate;
      v_m3_key := 'the orphan was STAGED AND NOT DETECTED';
      set constraints all deferred;
    exception when others then
      v_m3_key := case when SQLSTATE = '42501'
        then 'refused 42501 before the orphan could be staged at all - a direct UPDATE of '
             || 'public.phase_c_task is refused because no routine with write authority for that '
             || 'table is on the call stack, so z95_phase_c_task_trace_committed never has to fire'
        else SQLSTATE || ': ' || left(SQLERRM, 110) end;
    end;
  end if;

  select count(*) into v_m3_n from public.phase_c_task t
   where t.trace_id is null
      or not exists (select 1 from public.phase_c_trace x where x.trace_id = t.trace_id);
  v_ok := v_m3_ok2 and v_m3_state = 'SILENT'
      and v_m3_ctl = 'z90_system_execution_pair_guard/23514' and v_m3_n = 0;
  defect_id:='PD-TRACE-004'; category:='TRACE';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := format(
      '(a) ORDERING, measured off pg_get_functiondef of the live fn_kernel_step_complete rather '
   || 'than asserted: the idempotency claim (section 4) is at character %s, the lost-race branch '
   || 'that returns the other caller''s result is at %s, and the FIRST trace write of any kind is '
   || 'at %s - claim before lost-race return before any trace, ordered correctly: %s. A caller that '
   || 'loses the race therefore returns before a trace exists to be orphaned. '
   || '(b) THE DETECTOR IS FORCEABLE IN-TRANSACTION. z90_system_execution_pair_guard on '
   || 'public.phase_c_trace is DEFERRABLE INITIALLY DEFERRED, so SET CONSTRAINTS ALL IMMEDIATE '
   || 'fires it here. CONTROL: a correctly paired TRACE-SYSTEM-EXECUTION trace left OPEN - an '
   || 'execution in flight, which is allowed to have no phase_c_system_execution row - forced -> '
   || '%s. INJECTION, differing in exactly one respect, the same trace written SEALED with no '
   || 'execution row -> %s. (c) THE TASK-SIDE ORPHAN CANNOT BE STAGED: pointing a real task at a '
   || 'trace deleted in this transaction was %s. Tasks in the whole estate with a null or '
   || 'unresolvable trace_id after all of it: %s.',
      v_m3_p1, v_m3_p2, v_m3_p3, v_m3_ok2, v_m3_state, v_m3_ctl, v_m3_key, v_m3_n);
  blocker := null; return next;`);

fs.writeFileSync('scripts/tmp_diag/m03_candidate.sql', f);
console.log('all 8 anchors replaced:', f.split('\n').length, 'lines');
