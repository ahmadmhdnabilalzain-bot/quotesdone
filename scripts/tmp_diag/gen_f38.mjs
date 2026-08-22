import { writeFileSync } from 'node:fs';
import { sql } from '../phase_c/lib/db.mjs';

const [{ def }] = await sql(
  `select pg_get_functiondef('public.fn_phase_d_drive_workflow(jsonb)'::regprocedure) as def`);

const ANCHOR = `    -- ---- A STEP THAT NEEDS AN INDEPENDENT VERDICT GETS ONE, THROUGH THE KERNEL'S OWN DOOR ------`;

const INSERT = `    -- ---- F38. THE HANDLER MAY HAVE ALREADY COMPLETED THIS STEP -----------------------------
    -- fn_phase_d_handler_execute section 7 hands the completed step to the FROZEN KERNEL itself.
    -- When it succeeds, the kernel closes the step run, opens the successor, and -- where the step
    -- ends in a handoff -- moves the whole run to waiting_handoff. The driver then arrived at its
    -- own fn_kernel_step_complete for a step that was already closed, against a run that was no
    -- longer active, and was refused:
    --
    --   k3_run_not_active: workflow run N is in state waiting_handoff, not active
    --
    -- and the drive stopped there. MEASURED, and it is the reason a fix made the headline fall:
    -- after F36 let the five capability steps execute, total EXECUTED across the estate went from
    -- 45 to 36, because every workflow whose handler succeeded early now died at the next
    -- iteration. Success in one place was being converted into an earlier stop.
    --
    -- The kernel is right on both counts and neither is touched. What was wrong is that this
    -- driver assumed every step needs an actor to close it. A step the HANDLER closed is closed;
    -- the driver re-reads the step run and, if the kernel has moved it out of every open state,
    -- takes the next piece of work instead of trying to close it twice.
    --
    -- This is also the §4 distinction the founder asked for: a step closed here is
    -- CANONICAL_HANDLER_EFFECT, and a step closed below is CANONICAL_ACTOR_INPUT. They are counted
    -- apart because they are different claims.
    select * into sr2 from public.phase_c_workflow_step_run where step_run_id = sr.step_run_id;
    if found and sr2.state not in
       ('ready','active','not_ready','waiting_input','waiting_review','blocked') then
      v_handler_closed := v_handler_closed + 1;
      v_steps := v_steps || jsonb_build_array(jsonb_build_object(
        'step_id', sr.step_id, 'step_run_id', sr.step_run_id,
        'closed_by', 'CANONICAL_HANDLER_EFFECT', 'step_run_state', sr2.state));
      continue;
    end if;

${ANCHOR}`;

const DECL_OLD = `  v_rtask     bigint;                 -- F35: the task the internal review decides`;
const DECL_NEW = `  sr2         public.phase_c_workflow_step_run%rowtype;  -- F38: the step run, re-read after dispatch
  v_handler_closed int := 0;          -- F38: steps the handler closed through the kernel itself
  v_rtask     bigint;                 -- F35: the task the internal review decides`;

const RET_OLD = `    'internal_reviews_recorded', v_revn,`;
const RET_NEW = `    'steps_closed_by_the_handler', v_handler_closed,
    'internal_reviews_recorded', v_revn,`;

const parts = [
  ['review section', ANCHOR, INSERT],
  ['declarations', DECL_OLD, DECL_NEW],
  ['returned report', RET_OLD, RET_NEW],
];

let body = def;
for (const [name, oldText, newText] of parts) {
  const n = body.split(oldText).length - 1;
  if (n !== 1) { console.error(`ANCHOR "${name}" matched ${n} time(s)`); process.exit(1); }
  body = body.replace(oldText, newText);
}

const HEADER = `-- F38 - a fix made the headline fall, because success was being converted into an earlier stop
--
-- MEASURED, and this is the whole finding. F36 let the five capability-dependent first steps
-- actually execute. Total EXECUTED dispatches across the thirty workflows then went DOWN, 45 -> 36,
-- and the five workflows that had just been fixed drove FEWER steps than before:
--
--   W11  steps_driven 0 of 7   run state waiting_handoff
--        stopped at W11-S01 :: k3_run_not_active -- "workflow run N is in state waiting_handoff,
--        not active - a step cannot be completed against a run that is not running"
--
-- fn_phase_d_handler_execute section 7 hands its completed step to the frozen kernel. When the
-- handler succeeds the kernel closes that step run itself, opens the successor, and where the step
-- ends in a handoff moves the run to waiting_handoff. This driver then called
-- fn_kernel_step_complete for the step that had just been closed, was refused -- correctly -- and
-- treated the refusal as the end of the drive.
--
-- So every handler success cost the drive the remainder of its workflow. The better Phase D got,
-- the worse this number looked, which is the most misleading shape an instrument can have.
--
-- NOTHING IN THE KERNEL CHANGES. fn_kernel_step_complete is right to refuse a completed step and
-- right to refuse a run that is not active. What was wrong is the driver's assumption that every
-- step needs an actor to close it. It now re-reads the step run after the dispatch and, when the
-- kernel has already moved it out of every open state, takes the next piece of work.
--
-- AND IT COUNTS THE TWO APART. The founder's ruling of 22 Aug 2026 section 4 asks for the
-- execution-input classes to be reported separately. A step closed by the handler's own effect is
-- CANONICAL_HANDLER_EFFECT and is now counted in steps_closed_by_the_handler; a step closed through
-- fn_kernel_step_complete by this driver standing in for its owner is CANONICAL_ACTOR_INPUT and
-- stays in steps_driven. Folding them was how "0 of 30 closed unaided" and "30 of 30 completed"
-- could both be true and neither be useful.
--
-- THE REST OF THE ROUTINE IS BYTE-IDENTICAL. Three anchors, each required to match exactly once.

`;

writeFileSync('scripts/sql/phase_d_f38_a_fix_made_the_headline_fall_because_success_stopped_the_drive.sql',
  HEADER + body + ';\n');
console.log('written');
