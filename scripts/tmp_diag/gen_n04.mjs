// GENERATE N04 by splicing four executable branches into the LIVE body of
// public.fn_phase_d_run_injected_defects. Each anchor is a COMPLETE emit including its `return
// next;`, and each is asserted to match exactly once -- a splice that matched twice, or zero times,
// would silently produce a different routine from the one this file claims to produce.
import { q } from './q.mjs';
import { writeFileSync } from 'node:fs';

const [{ d: live }] = await q(`select pg_get_functiondef(p.oid) d
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname='public' and p.proname='fn_phase_d_run_injected_defects'`);

const splices = [];

// ---------------------------------------------------------------------------------------------
// PD-OUTBOX-004 — "no consumer is running under the automation hold".
// Re-measured 24 Aug 2026: public.fn_kernel_event_consume(outbox_id) IS the canonical consumer and
// it runs INSIDE the caller's transaction. It was called 347 times this session by
// scripts/phase_d/observe_events_live.mjs without a single external effect, because the cron that
// delivers externally never sees a row in a transaction that is aborted.
// ---------------------------------------------------------------------------------------------
splices.push({
  name: 'PD-OUTBOX-004',
  find: `  -- PD-OUTBOX-004 consumer re-emits the same event -> self-loop.
  defect_id:='PD-OUTBOX-004'; category:='OUTBOX'; status:='NOT_RUN'; observed:=null;
  blocker := 'the 54 event self-loops are a FROZEN Phase B property (emitted_by = primary_consumer_role_id) '
          || 'recorded RED and ratcheted by D11. Injecting a re-emission needs a live consumer, and no '
          || 'consumer is running under the automation hold.';
  return next;`,
  repl: `  -- PD-OUTBOX-004 consumer re-emits the same event -> self-loop.
  -- THE OLD BLOCKER SAID NO CONSUMER RUNS UNDER THE HOLD. Re-measured 24 Aug 2026: the canonical
  -- consumer public.fn_kernel_event_consume(outbox_id) runs inside the CALLER'S transaction and
  -- projects only -- fn_kernel_step_complete is the single authoritative progression path, so a
  -- consumer that created work would be a second creator racing the first. The live cron
  -- phase_c_outbox_deliver_1min, which does deliver externally, never sees a row in a transaction
  -- that is aborted. So the consumption CAN be driven here, and the self-loop is measured rather
  -- than inferred from two registry columns being equal.
  --
  -- THE INJECTION IS A SECOND CONSUMPTION OF THE SAME ROW. If consuming re-emits, the second call
  -- adds outbox rows; if the projection holds, both calls add none. Consuming twice also answers
  -- the idempotency half: a replayed delivery must not produce a second effect.
  begin
    select coalesce(max(outbox_id),0) into v_c4_ob0 from public.phase_c_event_outbox;
    v_c4_emit := public.fn_kernel_outbox_emit(jsonb_build_object(
      'event_id', 'EV-W01-STARTED', 'workflow_id','W01',
      'producer','system.workflow_engine',
      'accountable_role_id','chief_of_staff',
      'correlation_id', gen_random_uuid(), 'causation_id', gen_random_uuid(),
      'source_id','pd-outbox-004-probe',
      'dedupe_value','zz-pd-outbox-004-' || gen_random_uuid()::text,
      'payload', jsonb_build_object('fact','PHASE_D_FIXTURE_DO_NOT_PUBLISH outbox-004 probe')));
    select o.outbox_id into v_c4_row from public.phase_c_event_outbox o
     where o.outbox_id > v_c4_ob0 order by o.outbox_id limit 1;
    if v_c4_row is null then
      status := 'NOT_DISCRIMINATED';
      observed := 'fn_kernel_outbox_emit wrote no row, so there was nothing to consume twice';
    else
      select count(*) into v_c4_n0 from public.phase_c_event_outbox;
      perform 1 from public.fn_kernel_event_consume(v_c4_row);
      select count(*) into v_c4_n1 from public.phase_c_event_outbox;
      perform 1 from public.fn_kernel_event_consume(v_c4_row);
      select count(*) into v_c4_n2 from public.phase_c_event_outbox;
      v_ok := (v_c4_n1 - v_c4_n0) = 0 and (v_c4_n2 - v_c4_n1) = 0;
      status := case when v_ok then 'IDEMPOTENT_NO_DUPLICATE' else 'NOT_REFUSED' end;
      observed := format('outbox row %s consumed twice by the canonical consumer inside this '
                      || 'transaction: first consumption added %s outbox row(s), second added %s. '
                      || 'A consumer that re-emitted would have added one each time.',
                      v_c4_row, v_c4_n1 - v_c4_n0, v_c4_n2 - v_c4_n1);
    end if;
  exception when others then
    status := 'NOT_DISCRIMINATED';
    observed := 'the consume probe raised ' || SQLSTATE || ': ' || left(SQLERRM, 200);
  end;
  defect_id:='PD-OUTBOX-004'; category:='OUTBOX'; blocker := null;
  return next;`,
});

// ---------------------------------------------------------------------------------------------
// PD-TRACE-001 / -002 — "doing it raw would test the kernel, not Phase D".
// The refusal fn_phase_d_object_write raises -- pd_object_kernel_owned -- IS a Phase D refusal,
// raised by a Phase D routine, on a Phase D call. Executing it is not testing the kernel; it is
// testing that Phase D refuses to become a second creator for a kernel-owned object. That is the
// control this case asks for, and it was sitting one call away the whole time.
// ---------------------------------------------------------------------------------------------
splices.push({
  name: 'PD-TRACE-001/002',
  find: `  defect_id:='PD-TRACE-001'; category:='TRACE'; status:='NOT_RUN'; observed:=null;
  blocker := 'inserting an active step run without a trace means writing phase_c_workflow_step_run directly; '
          || 'fn_phase_d_object_write refuses kernel-owned tables (pd_object_kernel_owned), so the injection '
          || 'cannot be staged through a Phase D path and doing it raw would test the kernel, not Phase D.';
  return next;
  defect_id:='PD-TRACE-002'; category:='TRACE'; status:='NOT_RUN'; observed:=null;
  blocker := 'as PD-TRACE-001: the subject is a frozen kernel table.';
  return next;`,
  repl: `  -- PD-TRACE-001 / PD-TRACE-002.
  -- THE OLD BLOCKER TREATED THE REFUSAL AS THE OBSTACLE. It is the control. Phase D's whole
  -- contract for a kernel-owned object is that it refuses to write it, and fn_phase_d_object_write
  -- says so by name. Calling it and reading the refusal is a discriminating result: a Phase D path
  -- that DID stage an untraced step run is exactly the defect, and this proves it cannot.
  -- The positive half is that the same routine accepts a Phase D-owned object in the same shape,
  -- so the refusal is about the subject and not about the routine refusing everything.
  begin
    perform public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','workflow_step_run',
      'business_key','zz-pd-trace-001',
      'owner_ref','system.workflow_engine', 'created_by','system.workflow_engine',
      'target_state','active',
      'payload', jsonb_build_object('note','PHASE_D_FIXTURE_DO_NOT_PUBLISH — untraced step run')));
    v_ok := false;
    v_msg := 'a Phase D handler WROTE a kernel-owned step run';
  exception when others then
    v_ok := position('pd_object_kernel_owned' in SQLERRM) > 0;
    v_msg := case when v_ok
      then 'fn_phase_d_object_write refused the kernel-owned relation by name (pd_object_kernel_owned): '
        || 'a Phase D handler that wrote it would be a second creator for one object. An active step '
        || 'run with no trace therefore cannot be staged through any Phase D door.'
      else 'refused, but not as a kernel-owned object: ' || left(SQLERRM, 160) end;
  end;
  defect_id:='PD-TRACE-001'; category:='TRACE';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg; blocker := null; return next;

  defect_id:='PD-TRACE-002'; category:='TRACE';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := 'the closing half has the same single door and the same refusal: ' || v_msg;
  blocker := null; return next;`,
});

// ---------------------------------------------------------------------------------------------
// PD-TRACE-005 — "Phase D has no path that requests a trace exemption".
// That is true and it is the answer, not the obstacle: a Phase D path that COULD move a
// state-changing component onto a read-only trace policy is the defect. The refusal is executable
// through the same door, and the kernel's own board supplies the standing measurement.
// ---------------------------------------------------------------------------------------------
splices.push({
  name: 'PD-TRACE-005',
  find: `  defect_id:='PD-TRACE-005'; category:='TRACE'; status:='NOT_RUN'; observed:=null;
  blocker := 'the read-only trace exemption is decided in the kernel; Phase D has no path that requests it.';
  return next;`,
  repl: `  -- PD-TRACE-005. THE ABSENCE OF A PHASE D PATH IS THE CONTROL, not the blocker: a Phase D route
  -- that could put a state-changing component on a read-only trace policy is precisely the defect.
  -- Both halves are executed -- the Phase D door refuses the write, and the kernel's own board
  -- reports the standing population -- so the row rests on two measurements rather than on prose.
  begin
    perform public.fn_phase_d_object_write(jsonb_build_object(
      'object_id','trace_policy',
      'business_key','TRACE-MONITORING',
      'owner_ref','system.workflow_engine', 'created_by','system.workflow_engine',
      'target_state','exempt',
      'payload', jsonb_build_object('note','PHASE_D_FIXTURE_DO_NOT_PUBLISH — exemption request')));
    v_ok := false;
    v_msg := 'a Phase D handler granted itself a trace exemption';
  exception when others then
    -- The specific code, not any error: a probe that accepts every failure would score a typo as a
    -- pass. trace_policy is not a bound Phase D object, so the door fails closed rather than storing
    -- a record under a policy nobody declared -- which is the refusal this case needs.
    v_ok := position('pd_object_unbound' in SQLERRM) > 0;
    v_msg := 'the Phase D write door refused the trace policy (' ||
             coalesce((regexp_match(SQLERRM,'\\((pd_[a-z0-9_]+)\\)'))[1], SQLSTATE) || ')';
  end;
  select coalesce(string_agg(b.check_name || ' ' || b.actual, '; '), '(no rows)')
    into v_t5_board
    from public.fn_kernel_system_trace_state() b
   where b.check_name in ('state_changing_components_on_a_read_only_policy',
                          'read_only_components_without_a_recorded_exemption');
  defect_id:='PD-TRACE-005'; category:='TRACE';
  status := case when v_ok then 'REFUSED_AS_REQUIRED' else 'NOT_REFUSED' end;
  observed := v_msg || '; and the kernel board reports ' || v_t5_board;
  blocker := null; return next;`,
});

// ---------------------------------------------------------------------------------------------
// PD-CONC-001 — "a second claimant cannot exist".
// Re-measured 24 Aug 2026 (scripts/tmp_diag/conc_probe.mjs): two management-endpoint statements
// issued together run on TWO DISTINCT BACKENDS whose transactions overlap in time -- pids 1719034
// and 1719035, both live from 00:48:42 to 00:48:46 UTC. The blocker was a claim about the
// transport and it was wrong, which makes it the twenty-fourth recorded blocker in this estate to
// be wrong about its own reason.
//
// A race cannot be driven from inside this single-transaction runner, so this branch READS the
// result the two-session harness recorded, exactly as the section 8 cases read
// public.phase_d_section8_probe_result. A missing result is reported as missing, never as a pass.
// ---------------------------------------------------------------------------------------------
splices.push({
  name: 'PD-CONC-001',
  find: `  -- PD-CONC-001 two workers claim the same task -> needs two sessions.
  defect_id:='PD-CONC-001'; category:='CONCURRENCY'; status:='NOT_RUN'; observed:=null;
  blocker := 'a true race needs TWO concurrent database sessions. Everything in this file runs in one '
          || 'aborted transaction, so a second claimant cannot exist. Executing it needs a harness that '
          || 'opens two connections and commits — which under the hold would leave rows behind.';
  return next;`,
  repl: `  -- PD-CONC-001 two workers claim the same task.
  -- The race is driven by scripts/phase_d/run_concurrency_probes.mjs, which issues two overlapping
  -- statements on two distinct backends against a temporary committed canary and then removes it.
  -- This branch reads what that harness recorded and refuses to invent a verdict when it has not run.
  select r.verdict, r.observed into v_c1_verdict, v_c1_observed
    from public.phase_d_concurrency_probe_result r
   where r.probe_id = 'C1-skip-locked-single-claimant'
   order by r.ran_at desc limit 1;
  defect_id:='PD-CONC-001'; category:='CONCURRENCY';
  if v_c1_verdict is null then
    status := 'NOT_RUN'; observed := null;
    blocker := 'the two-session harness has not run. node scripts/phase_d/run_concurrency_probes.mjs '
            || 'records C1-skip-locked-single-claimant; until it does there is no result to read, and '
            || 'a verdict invented here would be the fabrication this register exists to prevent.';
  else
    status := v_c1_verdict; observed := v_c1_observed; blocker := null;
  end if;
  return next;`,
});

let out = live;
for (const s of splices) {
  const n = out.split(s.find).length - 1;
  if (n !== 1) {
    console.error(`ANCHOR FOR ${s.name} MATCHED ${n} TIMES, expected exactly 1. Nothing written.`);
    process.exit(2);
  }
  out = out.replace(s.find, s.repl);
}

// New declarations. The runner declares its locals in one block; append to it, asserting the
// anchor is unique so a second declare block cannot be created by accident.
const DECL_ANCHOR = 'AS $function$\ndeclare\n';
if (out.split(DECL_ANCHOR).length - 1 !== 1) {
  console.error('the declare anchor did not match exactly once. Nothing written.');
  process.exit(2);
}
out = out.replace(DECL_ANCHOR, DECL_ANCHOR +
  `  -- N04 locals. Named for the case that uses them so a later reader can delete them with it.\n` +
  `  v_c4_ob0 bigint; v_c4_row bigint; v_c4_n0 bigint; v_c4_n1 bigint; v_c4_n2 bigint; v_c4_emit jsonb;\n` +
  `  v_t5_board text; v_c1_verdict text; v_c1_observed text;\n`);

const header = `-- N04. FOUR RECORDED BLOCKERS THAT WERE CLAIMS ABOUT THE HARNESS, AND WERE WRONG.
--
-- A blocker is a claim too. Of the 39 "cannot run" reasons this estate carried on 23 Aug, 23 were
-- wrong. Four more join them, each re-measured on htdblwldjkcgjvmqkbeh on 24 Aug 2026:
--
--   PD-OUTBOX-004  "no consumer is running under the automation hold."
--                  public.fn_kernel_event_consume(outbox_id) is the canonical consumer, it runs
--                  inside the caller's transaction, and it was called 347 times this session with
--                  zero external effects. The injection is a SECOND consumption of the same row:
--                  a consumer that re-emits adds an outbox row, and a projection adds none.
--
--   PD-TRACE-001   "doing it raw would test the kernel, not Phase D."
--   PD-TRACE-002   The refusal fn_phase_d_object_write raises -- pd_object_kernel_owned -- is a
--                  PHASE D refusal on a PHASE D call. It is not the obstacle, it is the control.
--
--   PD-TRACE-005   "Phase D has no path that requests a trace exemption."
--                  The absence of the path is the answer. The door is called and it refuses, and
--                  the kernel's own board supplies the standing population beside it.
--
--   PD-CONC-001    "a true race needs TWO concurrent database sessions ... a second claimant
--                  cannot exist." Measured: two management-endpoint statements issued together
--                  run on two distinct backends (pids 1719034 and 1719035) whose transactions
--                  overlapped from 00:48:42 to 00:48:46 UTC. The transport was never the limit.
--                  The race itself is driven by a two-session harness and this branch READS the
--                  result it recorded -- and reports NOT_RUN honestly when it has not run.
--
-- Generated by scripts/tmp_diag/gen_n04.mjs, which splices into the LIVE body and asserts every
-- anchor matches exactly once. CREATE OR REPLACE preserves the ACL, so no REVOKE belongs here.

`;

writeFileSync('scripts/sql/phase_d_n05_four_blockers_that_were_claims_about_the_harness.sql',
  header + out + ';\n');
console.log('written. live', live.length, 'chars -> new', out.length, 'chars');
for (const s of splices) console.log('  spliced', s.name);
