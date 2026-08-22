import { writeFileSync } from 'node:fs';
import { sql } from '../phase_c/lib/db.mjs';

const HEAD = `-- G07 — a run the kernel carried to completion by itself was counted by nobody
--
-- W18 on 23 Aug 2026: 7 steps, 7 dispatches SEEN, 7 dispatches EXECUTED, 7 business effects,
-- 4 handoffs accepted, run state completed, terminal true, drive stopped with pd_drive_no_open_work
-- — and steps_driven 0, steps_closed_by_the_handler 0, closure verdict
-- TERMINAL_WITH_WORK_STILL_OPEN.
--
-- Nothing was open. What happened is that fn_phase_d_handler_execute section 7 hands each completed
-- step to the frozen kernel, the kernel closes it and opens the successor, and that successor is
-- dispatched immediately — so for a workflow whose every step the handler can execute, the WHOLE
-- RUN completes inside fn_kernel_workflow_start before this driver's loop takes its first
-- iteration. The loop then finds no open step run, stops correctly, and increments neither counter,
-- because both counters only ever counted what the loop itself observed.
--
-- So the one workflow in the estate that ran end to end without an actor touching it was the one
-- workflow scored as not having closed. That is F38's shape a second time and the founder's §2
-- warning read from the other side: a closure metric must measure the RUN, not the harness.
--
-- The fix is to attribute from the dispatch ledger, which already records the answer. A step run
-- that carries an EXECUTED dispatch and is no longer in any open state was closed by the handler.
-- The loop keeps its own count for the steps it saw; this adds the ones it never saw, and the two
-- cannot overlap because the loop records every step_run_id it handled.
--
-- Nothing about the verdict is loosened. A run still has to be terminal, still has to stop with
-- pd_drive_no_open_work, and every closure still has to have come through a canonical door — the
-- handler's own call into fn_kernel_step_complete or the driver's. What changes is that a closure
-- made before the observer arrived is no longer invisible.
--
-- Three anchors, each required to match exactly once. The rest of the routine is byte-identical.`;

const r = await sql(`select pg_get_functiondef(p.oid) as def from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_phase_d_drive_workflow'`);
let def = r[0].def;
const splice = (anchor, repl, what) => {
  const n = def.split(anchor).length - 1;
  if (n !== 1) throw new Error(`${what}: anchor matched ${n} time(s)`);
  def = def.replace(anchor, repl);
};

// 1. the declaration
splice(`  v_handler_closed int := 0;          -- F38: steps the handler closed through the kernel itself`,
`  v_handler_closed int := 0;          -- F38: steps the handler closed through the kernel itself
  v_seen           bigint[] := '{}';  -- G07: every step run this loop actually observed
  v_unseen         int := 0;          -- G07: handler closures that happened before the loop began`,
  'G07 declaration');

// 2. record every step run the loop observes, immediately after it is selected
splice(`    select * into sr2 from public.phase_c_workflow_step_run where step_run_id = sr.step_run_id;
    if found and sr2.state not in
       ('ready','active','not_ready','waiting_input','waiting_review','blocked') then`,
`    v_seen := v_seen || sr.step_run_id;   -- G07: what this loop saw, so what it did not see is derivable
    select * into sr2 from public.phase_c_workflow_step_run where step_run_id = sr.step_run_id;
    if found and sr2.state not in
       ('ready','active','not_ready','waiting_input','waiting_review','blocked') then`,
  'G07 seen');

// 3. after the loop, add the closures the loop never saw
splice(`    'steps_closed_by_the_handler', v_handler_closed,`,
`    'steps_closed_by_the_handler', v_handler_closed + v_unseen,
    'steps_closed_by_the_handler_before_the_loop_began', v_unseen,`,
  'G07 return');

// 4. compute v_unseen just before the FINAL return object is built. Anchored on the emit that
//    carries steps_closed_by_the_handler, so it can only be the one this file is changing.
const anchorReturn = `  return jsonb_build_object(`;
const at = def.indexOf(`    'steps_closed_by_the_handler', v_handler_closed + v_unseen,`);
const start = def.lastIndexOf(anchorReturn, at);
if (start < 0) throw new Error('G07 compute: could not find the return that carries the counter');
const parts = [def.slice(0, start), def.slice(start + anchorReturn.length)];
def = parts[0] + `  -- G07. THE CLOSURES THIS LOOP NEVER SAW, read from the ledger that already recorded them.
  -- A step run carrying an EXECUTED dispatch and sitting in no open state was closed by the
  -- handler's own call into fn_kernel_step_complete. Excluding the step runs the loop handled makes
  -- the two counts disjoint by construction rather than by argument.
  select count(distinct d.step_run_id) into v_unseen
    from public.phase_d_dispatch d
    join public.phase_c_workflow_step_run x on x.step_run_id = d.step_run_id
   where d.run_id = v_run
     and d.outcome = 'EXECUTED'
     and x.state not in ('ready','active','not_ready','waiting_input','waiting_review','blocked')
     and not (d.step_run_id = any(v_seen));

` + anchorReturn + parts[1];

writeFileSync('scripts/sql/phase_d_g07_a_run_the_kernel_finished_before_the_observer_arrived.sql',
  HEAD + '\n' + def + '\n');
console.log('G07 written');
