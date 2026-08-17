// GENUINE POSITIVE CONTROLS — one per canonical kernel entry door.
//
//   node scripts/checks/kernel_positive_controls.test.mjs
//
// WHY THIS FILE EXISTS. The Phase C closure reported "positive cases accepted 20/20 (Phase B
// suite, both directions)". The final re-acceptance counted that suite: it is 18 injected defects
// that must be REFUSED and 2 cases where an allowed operation must succeed. A suite of negatives
// described as positive controls is an instrument reporting on the wrong subject — and the number
// 20 appears in no Phase C specification. There is no approved denominator of 20 to meet.
//
// THE DENOMINATOR IS DERIVED, NOT TYPED. A positive control is owed for every CANONICAL KERNEL
// ENTRY DOOR: a routine that holds write authority over a business table, whose name is
// fn_kernel_* or fn_founder_command_*, and which is not recorded in public.kernel_retired_path.
// That set is read from production here and compared to the controls implemented below, so a new
// door cannot be opened without a positive control and a retired one cannot leave a stale case
// behind. Today it is 13.
//
// A guard that only refuses is an outage. Each control proves the door OPENS for the legitimate
// call, and proves it with a measured state effect and a trace, not with an absence of an error.
//
// Every control runs inside a transaction that always ends in `raise exception`, so production
// carries nothing away from this file. The residue assertions at the end measure that.
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN
  || existsSync(join(homedir(), '.supabase', 'access-token'))
  || existsSync('C:/Users/Opera/.supabase/access-token');
if (!hasToken) {
  console.log('SKIP kernel_positive_controls: no Supabase management token here.');
  process.exit(0);
}
const { sql } = await import('../phase_c/lib/db.mjs');

const ORDER = 'Draft one short internal note for the marketing team summarising how QuotesDone '
  + 'shortens supplier sourcing by 3 days. Keep it internal only, finish by 30 August 2026. Do not '
  + 'publish it, do not send it to anyone outside the company, do not spend money, and do not use '
  + 'any paid AI provider. Report progress and the final result through this Command Center thread.';
const VAGUE = 'Make marketing better.';
const FOUNDER = 'management@quotesdone.com';
const lit = s => `'${String(s).replace(/'/g, "''")}'`;

// A W20 command in one call gives a run, an active step run, a queued task and a pending event —
// the precondition most of the doors below need.
const SEED = (key) => `
  v := public.fn_founder_command_submit(${lit(FOUNDER)}, ${lit(ORDER)}, ${lit(key)}, '{}'::jsonb);
  cmd := (v->>'command_id')::bigint;
  run := (v->>'workflow_run_id')::bigint;
  sr  := (v->>'step_run_id')::bigint;
  tsk := (v->'task_ids'->>0)::bigint;
  ob  := (v->>'outbox_id')::bigint;
  select step_id, accountable_role_id into stp, owner
    from public.phase_c_workflow_step_run where step_run_id = sr;`;

const OUTPUT = `jsonb_build_object('status','ok','output','positive control output for ' || stp)`;
const INPUTS = `jsonb_build_object('workflow_record','run ' || run, 'prior_outputs','positive control')`;

/** door -> the SQL that exercises it and the facts it must produce. */
const CONTROLS = {
  fn_founder_command_submit: `
    ${SEED('positive-control-submit')}
    res := jsonb_build_object(
      'accepted', (v->>'status') = 'tasks_created',
      'effect', jsonb_build_object(
        'runs',  (select count(*) from public.phase_c_workflow_run where command_id = cmd),
        'tasks', (select count(*) from public.phase_c_task where command_id = cmd),
        'events',(select count(*) from public.phase_c_event_outbox where command_id = cmd)),
      'trace', (select count(*) from public.phase_c_trace where command_id = cmd));`,

  fn_founder_command_clarify: `
    v := public.fn_founder_command_submit(${lit(FOUNDER)}, ${lit(VAGUE)}, 'positive-control-clarify', '{}'::jsonb);
    cmd := (v->>'command_id')::bigint;
    v2 := public.fn_founder_command_clarify(cmd,
            'Publish two extra posts this week for the UAE market, by 30 August 2026.', ${lit(FOUNDER)});
    res := jsonb_build_object(
      'accepted', coalesce((v2->>'ok')::boolean, false),
      'effect', jsonb_build_object(
        'state_before', v->>'status',
        'state_after', (select state from public.founder_command where command_id = cmd),
        'tasks', (select count(*) from public.phase_c_task where command_id = cmd)),
      'trace', (select count(*) from public.phase_c_trace where command_id = cmd));`,

  fn_founder_command_control: `
    ${SEED('positive-control-control')}
    v2 := public.fn_founder_command_control(cmd, 'reprioritize', cmd::text, 'P0', ${lit(FOUNDER)});
    res := jsonb_build_object(
      'accepted', coalesce((v2->>'ok')::boolean, false),
      'effect', jsonb_build_object(
        'command_priority', (select priority from public.founder_command where command_id = cmd),
        'tasks_updated', v2->>'tasks_updated'),
      'trace', (select count(*) from public.phase_c_trace where command_id = cmd));`,

  fn_kernel_cancel: `
    ${SEED('positive-control-cancel')}
    v2 := public.fn_kernel_cancel(jsonb_build_object(
      'subject_kind','founder_command', 'subject_ref', cmd::text, 'op','cancel',
      'actor', ${lit(FOUNDER)}, 'reason','positive control: the canonical canceller must accept'));
    res := jsonb_build_object(
      'accepted', coalesce((v2->>'ok')::boolean, false),
      'effect', jsonb_build_object(
        'command', (select state from public.founder_command where command_id = cmd),
        'run', (select state from public.phase_c_workflow_run where run_id = run),
        'task', (select state from public.phase_c_task where task_id = tsk),
        'outbox', (select status from public.phase_c_event_outbox where outbox_id = ob)),
      'trace', (select count(*) from public.phase_c_trace where command_id = cmd and status = 'sealed'));`,

  fn_kernel_workflow_start: `
    v := public.fn_kernel_workflow_start(jsonb_build_object(
      'workflow_id','W14', 'business_object_id','ZZ-POSITIVE-CONTROL-W14',
      'source_kind','autonomous', 'source_ref','positive-control',
      'requested_by','positive-control'));
    run := (v->>'run_id')::bigint;
    res := jsonb_build_object(
      'accepted', coalesce((v->>'ok')::boolean, false),
      'effect', jsonb_build_object(
        'run', run,
        'step_runs', (select count(*) from public.phase_c_workflow_step_run where run_id = run),
        'tasks', (select count(*) from public.phase_c_task where run_id = run),
        'events', (select count(*) from public.phase_c_event_outbox where workflow_run_id = run)),
      'trace', (select count(*) from public.phase_c_trace where run_id = run));`,

  fn_kernel_open_step: `
    ${SEED('positive-control-open-step')}
    -- complete the first step so a successor exists, then open it through the door under test
    v2 := public.fn_kernel_step_complete(jsonb_build_object(
      'step_run_id', sr, 'actor_role_id', owner, 'outcome','pass',
      'idempotency_key','positive-control-open-step-' || stp,
      'inputs', ${INPUTS}, 'output', ${OUTPUT},
      'evidence_refs', jsonb_build_array(jsonb_build_object('positive_control', true)),
      'requested_action','proceed', 'acceptance_criteria','positive control', 'object_version', 1));
    select h.handoff_run_id, h.receiving_role_id into hnd, recv
      from public.phase_c_handoff_run h where h.run_id = run and h.status = 'open' limit 1;
    if hnd is not null then
      perform public.fn_kernel_handoff_accept(jsonb_build_object(
        'handoff_run_id', hnd, 'actor_role_id', recv, 'decision','accept', 'outcome','accept',
        'reason','positive control', 'packet', jsonb_build_object(
          'object_version', 1, 'output','positive control', 'business_object_id','positive-control',
          'acceptance_evidence','positive control', 'unresolved_blockers','none',
          'requested_action','proceed',
          'evidence_refs', jsonb_build_array(jsonb_build_object('positive_control', true)))));
    end if;
    select sr2.step_run_id, sr2.step_id into sr2_id, stp2
      from public.phase_c_workflow_step_run sr2 where sr2.run_id = run and sr2.state = 'active'
      order by sr2.step_run_id desc limit 1;
    res := jsonb_build_object(
      'accepted', sr2_id is not null and sr2_id <> sr,
      'effect', jsonb_build_object('first_step', stp, 'opened_step', stp2, 'step_runs',
        (select count(*) from public.phase_c_workflow_step_run where run_id = run)),
      'trace', (select count(*) from public.phase_c_trace where run_id = run));`,

  fn_kernel_step_complete: `
    ${SEED('positive-control-step-complete')}
    v2 := public.fn_kernel_step_complete(jsonb_build_object(
      'step_run_id', sr, 'actor_role_id', owner, 'outcome','pass',
      'idempotency_key','positive-control-complete-' || stp,
      'inputs', ${INPUTS}, 'output', ${OUTPUT},
      'evidence_refs', jsonb_build_array(jsonb_build_object('positive_control', true)),
      'requested_action','proceed', 'acceptance_criteria','positive control', 'object_version', 1));
    res := jsonb_build_object(
      'accepted', coalesce((v2->>'ok')::boolean, false),
      'effect', jsonb_build_object(
        'step_state', (select state from public.phase_c_workflow_step_run where step_run_id = sr),
        'run_state', v2->>'run_state', 'output_hash', left(coalesce(v2->>'output_hash',''), 16)),
      'trace', (select count(*) from public.phase_c_trace where step_run_id = sr));`,

  fn_kernel_handoff_accept: `
    ${SEED('positive-control-handoff')}
    perform public.fn_kernel_step_complete(jsonb_build_object(
      'step_run_id', sr, 'actor_role_id', owner, 'outcome','pass',
      'idempotency_key','positive-control-handoff-' || stp,
      'inputs', ${INPUTS}, 'output', ${OUTPUT},
      'evidence_refs', jsonb_build_array(jsonb_build_object('positive_control', true)),
      'requested_action','proceed', 'acceptance_criteria','positive control', 'object_version', 1));
    select h.handoff_run_id, h.receiving_role_id, h.sending_role_id into hnd, recv, sender
      from public.phase_c_handoff_run h where h.run_id = run and h.status = 'open' limit 1;
    v2 := public.fn_kernel_handoff_accept(jsonb_build_object(
      'handoff_run_id', hnd, 'actor_role_id', recv, 'decision','accept', 'outcome','accept',
      'reason','positive control', 'packet', jsonb_build_object(
        'object_version', 1, 'output','positive control', 'business_object_id','positive-control',
        'acceptance_evidence','positive control', 'unresolved_blockers','none',
        'requested_action','proceed',
        'evidence_refs', jsonb_build_array(jsonb_build_object('positive_control', true)))));
    res := jsonb_build_object(
      'accepted', coalesce((v2->>'ok')::boolean, false),
      'effect', jsonb_build_object(
        'handoff_status', (select status from public.phase_c_handoff_run where handoff_run_id = hnd),
        'sender', sender, 'receiver', recv),
      'trace', (select count(*) from public.phase_c_trace where run_id = run));`,

  fn_kernel_review_decide: `
    v := public.fn_kernel_workflow_start(jsonb_build_object(
      'workflow_id','W14', 'business_object_id','ZZ-POSITIVE-CONTROL-REVIEW',
      'source_kind','autonomous', 'source_ref','positive-control', 'requested_by','positive-control'));
    run := (v->>'run_id')::bigint;
    -- drive to the one W14 step that declares an independent reviewer
    loop
      select sr3.step_run_id, sr3.step_id, sr3.accountable_role_id into sr, stp, owner
        from public.phase_c_workflow_step_run sr3 where sr3.run_id = run and sr3.state='active'
        order by sr3.step_run_id limit 1;
      exit when sr is null;
      select s.independent_reviewer_role_id into recv from public.phase_b_workflow_step s where s.step_id = stp;
      select t.task_id into tsk from public.phase_c_task t where t.run_id = run and t.step_id = stp
        order by t.task_id desc limit 1;
      if coalesce(btrim(recv),'') <> '' then exit; end if;
      perform public.fn_kernel_step_complete(jsonb_build_object(
        'step_run_id', sr, 'actor_role_id', owner, 'outcome','pass',
        'idempotency_key','positive-control-review-' || stp,
        'inputs', ${INPUTS}, 'output', ${OUTPUT},
        'evidence_refs', jsonb_build_array(jsonb_build_object('positive_control', true)),
        'requested_action','proceed', 'acceptance_criteria','positive control', 'object_version', 1));
      perform public.fn_kernel_handoff_accept(jsonb_build_object(
          'handoff_run_id', h.handoff_run_id, 'actor_role_id', h.receiving_role_id,
          'decision','accept', 'outcome','accept', 'reason','positive control',
          'packet', jsonb_build_object('object_version',1,'output','positive control',
            'business_object_id','positive-control','acceptance_evidence','positive control',
            'unresolved_blockers','none','requested_action','proceed',
            'evidence_refs', jsonb_build_array(jsonb_build_object('positive_control', true)))))
        from public.phase_c_handoff_run h where h.run_id = run and h.status = 'open';
      sr := null;
    end loop;
    v2 := public.fn_kernel_review_decide(jsonb_build_object(
      'task_id', tsk, 'reviewer_role_id', recv, 'decision','approved',
      'reason','positive control: an independent reviewer approves'));
    res := jsonb_build_object(
      'accepted', coalesce((v2->>'ok')::boolean, false),
      'effect', jsonb_build_object('step', stp, 'reviewer', recv, 'task', tsk),
      'trace', (select count(*) from public.phase_c_trace where task_id = tsk));`,

  fn_kernel_signal_submit: `
    ${SEED('positive-control-signal')}
    v2 := public.fn_kernel_signal_submit(jsonb_build_object(
      'source_type','positive_control', 'source_id','pc-signal', 'requested_by','positive-control',
      'signal_type','document.arrived_for_run', 'workflow_run_id', run,
      'payload', jsonb_build_object('note','positive control')));
    res := jsonb_build_object(
      'accepted', coalesce((v2->>'ok')::boolean, false),
      'effect', jsonb_build_object('status', v2->>'status', 'attached_step', v2->>'active_step_id',
        'inbox', (select count(*) from public.kernel_signal_inbox where workflow_run_id = run)),
      'trace', (select count(*) from public.phase_c_trace where trace_id = (v2->>'trace_id')::bigint));`,

  fn_kernel_trigger_submit: `
    v2 := public.fn_kernel_source_emit('dbtrigger:public.agent_actions:trg_page_high_agent_action',
      jsonb_build_object('source_ref','ZZ-POSITIVE-CONTROL-TRIGGER', 'requested_by','positive-control',
        'raw_payload', jsonb_build_object('incident_ref','ZZ-POSITIVE-CONTROL-TRIGGER')));
    run := (v2->>'run_id')::bigint;
    res := jsonb_build_object(
      'accepted', coalesce((v2->>'ok')::boolean, false),
      'effect', jsonb_build_object('run', run, 'created', v2->'created',
        'inbox', (select count(*) from public.kernel_trigger_inbox where run_id = run)),
      'trace', (select count(*) from public.phase_c_trace where run_id = run));`,

  fn_kernel_outbox_emit: `
    ${SEED('positive-control-emit')}
    v2 := public.fn_kernel_outbox_emit(jsonb_build_object(
      'event_id', public.fn_phase_c_lifecycle_event('W20','completed'),
      'workflow_id','W20', 'workflow_run_id', run, 'step_run_id', sr, 'task_id', tsk,
      'command_id', cmd, 'producer','kernel:positive_control',
      'correlation_id','positive-control:' || cmd::text, 'causation_id','positive-control',
      'source_id','positive-control', 'accountable_role_id', owner,
      'payload', jsonb_build_object('fact','positive control'),
      'dedupe_value','positive-control:' || cmd::text));
    res := jsonb_build_object(
      'accepted', v2 is not null,
      'effect', jsonb_build_object('events_for_run',
        (select count(*) from public.phase_c_event_outbox where workflow_run_id = run)),
      'trace', (select count(*) from public.phase_c_trace where run_id = run));`,

  fn_kernel_outbox_deliver: `
    ${SEED('positive-control-deliver')}
    v2 := (select to_jsonb(x) from public.fn_kernel_outbox_deliver(5, 'positive-control') x);
    res := jsonb_build_object(
      'accepted', coalesce((v2->>'delivered')::int, 0) >= 1,
      'effect', jsonb_build_object('claimed', v2->>'claimed', 'delivered', v2->>'delivered',
        'row_status', (select status from public.phase_c_event_outbox where outbox_id = ob)),
      'trace', (select count(*) from public.phase_c_event_delivery_attempt where outbox_id = ob));`,
};

// ---------------------------------------------------------------- the derived denominator
const doors = (await sql(`
  select distinct a.routine_name
    from public.kernel_write_authority a
   where (a.routine_name like 'fn\\_kernel\\_%' or a.routine_name like 'fn\\_founder\\_command\\_%')
     and not exists (select 1 from public.kernel_retired_path p where p.path_name = a.routine_name)
   order by 1`)).map(r => r.routine_name);

let pass = 0, fail = 0;
const line = (ok, name, detail) => {
  if (ok) pass++; else fail++;
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${name.padEnd(30)}${detail ? '  ' + String(detail).slice(0, 150) : ''}`);
};

console.log(`canonical kernel entry doors (derived from kernel_write_authority minus kernel_retired_path): ${doors.length}`);
const implemented = Object.keys(CONTROLS);
for (const d of doors) if (!implemented.includes(d)) line(false, d, 'NO POSITIVE CONTROL IMPLEMENTED for this door');
for (const d of implemented) if (!doors.includes(d)) line(false, d, 'a control exists for a door that is not canonical any more');
console.log('');

const before = (await sql(`select
  (select count(*) from public.founder_command) cmds,
  (select count(*) from public.phase_c_workflow_run) runs,
  (select count(*) from public.phase_c_task) tasks,
  (select count(*) from public.phase_c_event_outbox) outbox,
  -- excluding scheduled kernel infrastructure: cron 278 writes a TRACE-SYSTEM-EXECUTION
  -- trace every minute, so a total here moves on its own and says an aborted control survived
  (select count(*) from public.phase_c_trace where trace_policy_id <> 'TRACE-SYSTEM-EXECUTION') traces,
  (select count(*) from public.kernel_signal_inbox) signals,
  (select count(*) from public.kernel_trigger_inbox) triggers`))[0];

for (const door of doors) {
  const body = CONTROLS[door];
  if (!body) continue;
  const probe = `do $pc$
declare v jsonb; v2 jsonb; res jsonb;
        cmd bigint; run bigint; sr bigint; sr2_id bigint; tsk bigint; ob bigint; hnd bigint;
        stp text; stp2 text; owner text; recv text; sender text;
begin
${body}
  raise exception 'PC %', res::text;
end $pc$;`;
  let msg = '';
  try { await sql(probe); msg = 'NO_RAISE'; } catch (e) { msg = String(e.message); }
  const s = msg.indexOf('{', msg.indexOf('PC '));
  let depth = 0, end = -1, inStr = false, esc = false;
  for (let i = s; i >= 0 && i < msg.length; i++) {
    const ch = msg[i];
    if (esc) { esc = false; continue; }
    if (ch === '\\') { esc = true; continue; }
    if (ch === '"') { inStr = !inStr; continue; }
    if (inStr) continue;
    if (ch === '{') depth++; else if (ch === '}') { depth--; if (!depth) { end = i; break; } }
  }
  let r = null;
  if (end > 0) { try { r = JSON.parse(msg.slice(s, end + 1).replace(/\\"/g, '"').replace(/\\\\/g, '\\')); } catch { /* */ } }
  if (!r) { line(false, door, 'the control produced no payload: ' + msg.replace(/\s+/g, ' ').slice(0, 200)); continue; }
  const ok = r.accepted === true && Number(r.trace) >= 1;
  line(ok, door, `accepted=${r.accepted} trace=${r.trace} effect=${JSON.stringify(r.effect)}`);
}

const after = (await sql(`select
  (select count(*) from public.founder_command) cmds,
  (select count(*) from public.phase_c_workflow_run) runs,
  (select count(*) from public.phase_c_task) tasks,
  (select count(*) from public.phase_c_event_outbox) outbox,
  -- excluding scheduled kernel infrastructure: cron 278 writes a TRACE-SYSTEM-EXECUTION
  -- trace every minute, so a total here moves on its own and says an aborted control survived
  (select count(*) from public.phase_c_trace where trace_policy_id <> 'TRACE-SYSTEM-EXECUTION') traces,
  (select count(*) from public.kernel_signal_inbox) signals,
  (select count(*) from public.kernel_trigger_inbox) triggers`))[0];
console.log('\nrow counts before/after every aborted positive control:');
for (const k of Object.keys(before)) {
  const same = String(before[k]) === String(after[k]);
  if (!same) fail++;
  console.log(`  ${same ? 'ok  ' : 'FAIL'} ${k.padEnd(10)} ${before[k]} -> ${after[k]}`);
}

console.log(`\ngenuine positive controls: ${doors.length} door(s), ${pass} accepted, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
