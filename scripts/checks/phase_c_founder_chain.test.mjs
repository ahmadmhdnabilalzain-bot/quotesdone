// The founder's whole chain, executed once, end to end.
//
//   node scripts/checks/phase_c_founder_chain.test.mjs
//
// The chain he confirmed:
//
//   Founder -> Command Center -> Chief of Staff -> command understood -> exact workflow selected
//   -> exact department and employee receive immediate tasks -> company performs the work
//   -> progress and completion return to the founder
//
// Links 1-5 were already proved. The last two were not, and the reason is worth keeping: a command
// reached `tasks_created` and STAYED there for ever, because nothing moved it when an employee
// started, got stuck or finished. This test walks the whole thing — including an employee posting
// a progress note and a task completing — and asserts the founder can read the result in the same
// thread he gave the order in.
//
// It runs inside a transaction that ALWAYS rolls back, so production carries nothing away from it.
import { existsSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const hasToken = !!process.env.SUPABASE_ACCESS_TOKEN
  || existsSync(join(homedir(), '.supabase', 'access-token'));
if (!hasToken) {
  console.log('SKIP phase_c_founder_chain: no Supabase management token in this environment.');
  process.exit(0);
}
const { sql } = await import('../phase_c/lib/db.mjs');

// Taken BEFORE anything runs, so the closing assertion can compare a delta instead of asserting
// that the company has never received a founder command.
const before = (await sql(`select
  (select count(*) from public.founder_command_message) m,
  (select count(*) from public.founder_command) c,
  (select count(*) from public.phase_c_task) t,
  (select count(*) from public.founder_command_progress_note) n`))[0];

let fail = 0;
const check = (ok, what, detail = '') => {
  console.log(`${ok ? 'ok  ' : 'FAIL'}  ${what}${detail ? '  — ' + detail : ''}`);
  if (!ok) fail++;
};

// The founder's own words, verbatim.
const ORDER = 'Add one extra social-media post this week explaining how QuotesDone makes supplier '
  + 'sourcing easier. Do not publish it before the normal brand and quality review is completed. '
  + 'Do not use paid advertising for this task. Report progress and the final result back to me '
  + 'through the Command Center.';

const lit = s => `'${String(s).replace(/'/g, "''")}'`;

const probe = `
do $chain$
declare
  v jsonb; th jsonb; mv jsonb; note jsonb; cmd bigint;
  t_primary bigint; t_child bigint; owner_primary text; owner_child text; mgr text;
  state_after_start text; state_after_block text; state_after_all text;
begin
  -- 1..5  the order becomes a plan and real tasks, atomically
  v := public.fn_founder_command_submit('management@quotesdone.com', ${lit(ORDER)},
        'chain-probe', jsonb_build_object('channel','command_center'));
  cmd := (v->>'command_id')::bigint;

  select task_id, accountable_role_id into t_primary, owner_primary
    from public.phase_c_task where command_id = cmd order by task_id limit 1;
  select task_id, accountable_role_id, manager_role_id into t_child, owner_child, mgr
    from public.phase_c_task where command_id = cmd order by task_id offset 1 limit 1;

  -- 6  the company performs the work: an employee starts, reports, gets blocked, unblocks, finishes
  mv := public.fn_phase_c_task_transition(t_primary, 'assigned', owner_primary, '{}'::jsonb);
  mv := public.fn_phase_c_task_transition(t_primary, 'accepted', owner_primary, '{}'::jsonb);
  mv := public.fn_phase_c_task_transition(t_primary, 'in_progress', owner_primary, '{}'::jsonb);
  state_after_start := (select state from public.founder_command where command_id = cmd);

  -- 7a  progress returns to the founder, from the accountable employee
  note := public.fn_founder_command_progress_add(cmd, t_primary, owner_primary,
    'Draft written and sent for brand and quality review. Not published. No paid promotion used.',
    jsonb_build_object('channel','organic'));

  mv := public.fn_phase_c_task_transition(t_primary, 'blocked', owner_primary,
    jsonb_build_object('blocker','awaiting brand review', 'blocker_owner_role_id', mgr));
  state_after_block := (select state from public.founder_command where command_id = cmd);

  mv := public.fn_phase_c_task_transition(t_primary, 'in_progress', owner_primary, '{}'::jsonb);
  mv := public.fn_phase_c_task_transition(t_primary, 'completed', owner_primary, '{}'::jsonb);

  -- every remaining child task closes
  for t_child in select task_id from public.phase_c_task
                 where command_id = cmd and closed_at is null order by task_id loop
    select accountable_role_id into owner_child from public.phase_c_task where task_id = t_child;
    perform public.fn_phase_c_task_transition(t_child, 'assigned', owner_child, '{}'::jsonb);
    perform public.fn_phase_c_task_transition(t_child, 'accepted', owner_child, '{}'::jsonb);
    perform public.fn_phase_c_task_transition(t_child, 'in_progress', owner_child, '{}'::jsonb);
    perform public.fn_phase_c_task_transition(t_child, 'completed', owner_child, '{}'::jsonb);
  end loop;
  state_after_all := (select state from public.founder_command where command_id = cmd);

  -- 7b  the founder reads the whole thing in one thread
  th := public.fn_founder_command_thread(cmd);

  raise exception 'CHAIN %', jsonb_build_object(
    'submit', v,
    'said_back_verbatim', (th->>'said') = ${lit(ORDER)},
    'secretary', th->>'secretary',
    'state_after_start', state_after_start,
    'state_after_block', state_after_block,
    'state_after_all', state_after_all,
    'workflows', th->'workflows',
    'task_count', jsonb_array_length(th->'tasks'),
    'owners', (select jsonb_agg(x->>'owner') from jsonb_array_elements(th->'tasks') x),
    'departments', (select jsonb_agg(distinct x->>'department') from jsonb_array_elements(th->'tasks') x),
    'acceptance_present', (select bool_and(coalesce(x->>'acceptance','') <> '') from jsonb_array_elements(th->'tasks') x),
    'closure_present', (select bool_and(coalesce(x->>'closure','') <> '') from jsonb_array_elements(th->'tasks') x),
    'every_task_traced', (select bool_and(x->>'trace_id' is not null) from jsonb_array_elements(th->'tasks') x),
    'progress_notes', jsonb_array_length(th->'progress'),
    'progress_note_traced', (th->'progress'->0->>'trace_id') is not null,
    'completion_summary', th->'completion'->>'summary',
    'history_len', jsonb_array_length(th->'history'),
    'traces', jsonb_array_length(th->'traces'),
    'closed_tasks_without_trace', (select count(*) from public.phase_c_task
                                   where command_id = cmd and closed_at is not null and trace_id is null),
    'founder_approvals', (select count(*) from public.founder_approval_request where command_id = cmd),

    -- THE CANONICAL START EVENT, FOUND BY RELATIONSHIP AND NOT BY STRING SHAPE.
    --
    -- This used to count dedupe_value = 'founder_command:' || cmd. Since the kernel cutover
    -- (16 Aug 2026) fn_kernel_workflow_start writes dedupe_value as
    -- kernel:started:<workflow>:founder_command:<id>:<version>, so the count read 0 for an event
    -- that had been emitted exactly once — the check was asserting an implementation string, not a
    -- fact. Every field below is a normalised relationship column: command_id, workflow_id,
    -- event_id, workflow_run_id, correlation_id, causation_id, trace_id. Swapping one string
    -- pattern for another would have rebuilt the same defect with a longer literal.
    'command_id', cmd,
    'events_for_command', (select count(*) from public.phase_c_event_outbox o where o.command_id = cmd),
    'start_events', (select count(*) from public.phase_c_event_outbox o
                      where o.command_id = cmd
                        and o.event_id = public.fn_phase_c_lifecycle_event(o.workflow_id, 'started')),
    -- flat scalars, not a nested row: the raised message is length-capped, and a payload that
    -- overflows it is a probe that produced nothing
    'ev', (select o.workflow_id || '|' || coalesce(o.workflow_run_id::text,'') || '|'
                  || coalesce(o.correlation_id,'') || '|' || coalesce(o.causation_id,'') || '|'
                  || coalesce(o.status,'') || '|' || coalesce(o.trace_id::text,'')
             from public.phase_c_event_outbox o
            where o.command_id = cmd
              and o.event_id = public.fn_phase_c_lifecycle_event(o.workflow_id, 'started')
            order by o.outbox_id limit 1),
    'ev_run', (select r.workflow_id || '|' || r.accountable_role_id || '|' || coalesce(r.command_id::text,'')
                 from public.phase_c_workflow_run r
                where r.run_id = (select o.workflow_run_id from public.phase_c_event_outbox o
                                   where o.command_id = cmd
                                     and o.event_id = public.fn_phase_c_lifecycle_event(o.workflow_id,'started')
                                   order by o.outbox_id limit 1)),
    'runs_for_command', (select count(*) from public.phase_c_workflow_run r where r.command_id = cmd),
    -- a delivery that emitted its own event again would show as a second row produced by the
    -- consumer rather than by the kernel's start
    'events_not_produced_by_the_kernel_start',
      (select count(*) from public.phase_c_event_outbox o
        where o.command_id = cmd and o.producer <> 'kernel:workflow_start'),
    -- every derived object reaches the founder command through a column, not through a payload
    'derived_objects_unlinked', (
        (select count(*) from public.phase_c_workflow_run r where r.command_id = cmd and r.command_id is null)
      + (select count(*) from public.phase_c_task t where t.command_id = cmd and t.command_id is null)
      + (select count(*) from public.phase_c_event_outbox o
          where o.command_id = cmd and (o.correlation_id is null or o.causation_id is null))
      + (select count(*) from public.phase_c_workflow_run r
           join public.phase_c_workflow_step_run s on s.run_id = r.run_id
          where r.command_id = cmd and s.run_id is null))
  )::text;
end $chain$;`;

let res = null;
try { await sql(probe); }
catch (e) {
  const msg = String(e.message).replace(/\\n/g, ' ').replace(/\\"/g, '"').replace(/\\\\/g, '\\');
  const start = msg.indexOf('{', msg.indexOf('CHAIN'));
  let depth = 0, end = -1, inStr = false, esc = false;
  for (let i = start; i < msg.length; i++) {
    const ch = msg[i];
    if (esc) { esc = false; continue; }
    if (ch === '\\') { esc = true; continue; }
    if (ch === '"') { inStr = !inStr; continue; }
    if (inStr) continue;
    if (ch === '{') depth++; else if (ch === '}') { depth--; if (!depth) { end = i; break; } }
  }
  if (end > 0) res = JSON.parse(msg.slice(start, end + 1));
  else console.log(msg.slice(0, 900));
}

if (!res) { console.error('FAIL  the chain probe produced no payload'); process.exit(1); }
const s = res.submit;

console.log('--- 1-5  order becomes a plan and real tasks');
check(s.ok === true && s.status === 'tasks_created', 'the order routes and creates work', s.intent);
check(res.secretary === 'chief_of_staff', 'the Chief of Staff owns the command', res.secretary);
check(res.said_back_verbatim === true, 'the founder’s exact words are stored and read back verbatim');
check(JSON.stringify(res.workflows).includes('W20'), 'the exact canonical workflow was selected',
      JSON.stringify(res.workflows));
check(Number(res.task_count) === Number(s.tasks_created) && Number(res.task_count) > 0,
      'every returned task exists in the thread', `${res.task_count} tasks`);
check(!JSON.stringify(res.departments).includes('null'), 'every task carries a department',
      JSON.stringify(res.departments));
check(res.acceptance_present === true, 'every task carries acceptance criteria');
check(res.closure_present === true, 'every task carries closure criteria');
check(Number(res.founder_approvals) === 0, 'no founder approval was created for a marketing order');

console.log('--- 6  the company performs the work');
check(res.state_after_start === 'in_progress',
      'the command follows its tasks into in_progress', res.state_after_start);
check(res.state_after_block === 'partially_blocked',
      'a blocked employee shows as partially_blocked, not as silence', res.state_after_block);
check(res.state_after_all === 'completed',
      'the command completes when its tasks do', res.state_after_all);

console.log('--- 7  progress and completion return to the founder');
check(Number(res.progress_notes) >= 1, 'the accountable employee’s progress note is in the thread',
      `${res.progress_notes} note(s)`);
check(res.progress_note_traced === true, 'the progress note is traced');
check(!!res.completion_summary, 'a completion summary was written', res.completion_summary);
check(Number(res.history_len) >= 3, 'the state history is readable', `${res.history_len} transitions`);
check(res.every_task_traced === true, 'every task in the thread carries a trace');
check(Number(res.closed_tasks_without_trace) === 0, 'no task closed without a trace');
check(Number(res.traces) >= 2, 'the command’s own traces are attached', `${res.traces} traces`);
// ---- the canonical workflow-start event, asserted on relationships, never on a string shape ----
const [evWf, evRun, evCorr, evCaus, evStatus, evTrace] = String(res.ev ?? '').split('|');
const [runWf, runOwner, runCmd] = String(res.ev_run ?? '').split('|');
check(Number(res.start_events) === 1, 'exactly one canonical workflow-start event for the command',
      `${res.start_events} of ${res.events_for_command} event(s) for this command`);
check(Number(res.runs_for_command) === 1, 'no duplicate workflow start', `${res.runs_for_command} run(s)`);
check(!!evWf && evWf === runWf, 'the event names the workflow its run is on', `${evWf} = ${runWf}`);
check(!!runOwner, 'the run carries an accountable role', runOwner);
check(String(runCmd) === String(res.command_id),
      'the run is linked to the founder command by column', `run.command_id = ${runCmd}`);
check(!!evRun, 'the event carries workflow_run_id', evRun);
check(!!evCorr && !!evCaus, 'the event carries correlation_id and causation_id', `${evCorr} / ${evCaus}`);
check(!!evStatus, 'the event is on record with a status', `status=${evStatus} trace_id=${evTrace || '(none)'}`);
check(Number(res.events_not_produced_by_the_kernel_start) === 0, 'no event self-emission',
      `${res.events_not_produced_by_the_kernel_start} event(s) produced by anything but kernel:workflow_start`);
check(Number(res.derived_objects_unlinked) === 0, 'every derived object is linked to the founder command',
      `${res.derived_objects_unlinked} unlinked`);

// nothing survived
// A DELTA, not an absolute count. This asserted the four tables were globally EMPTY, which is a
// claim about the whole company rather than about this probe. It held only while no real founder
// command had ever been sent; the moment the Phase C audit sent one over HTTPS it went permanently
// red with every other assertion in the file still green. "My probe left nothing" and "the table is
// empty" are different subjects, and only the first one is this test's business.
const COUNTS = `select
  (select count(*) from public.founder_command_message) m,
  (select count(*) from public.founder_command) c,
  (select count(*) from public.phase_c_task) t,
  (select count(*) from public.founder_command_progress_note) n`;
const after = (await sql(COUNTS))[0];
const delta = Object.fromEntries(Object.keys(after).map(k => [k, Number(after[k]) - Number(before[k])]));
check(Object.values(delta).every(v => v === 0),
      'the probe left nothing behind', JSON.stringify(delta) + ` (table totals ${JSON.stringify(after)})`);

console.log(`\n${fail === 0 ? 'FOUNDER CHAIN VERIFIED END TO END' : `${fail} check(s) failed`}`);
process.exit(fail === 0 ? 0 : 1);
