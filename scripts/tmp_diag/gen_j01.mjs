// Generates scripts/sql/phase_d_j01_*.sql from the LIVE body of fn_phase_d_drive_workflow,
// splicing in the hold-at-an-open-step mode. Generated, never hand-edited, so the rest of the
// routine is byte-identical to what production runs today.
import { writeFileSync } from 'node:fs';
import { sql } from '../lib/db.mjs';

const [{ prosrc }] = await sql(
  `select prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='fn_phase_d_drive_workflow'`);

let body = prosrc;
const splice = (anchor, replacement) => {
  const n = body.split(anchor).length - 1;
  if (n !== 1) throw new Error(`anchor matched ${n} times: ${anchor.slice(0, 60)}`);
  body = body.replace(anchor, replacement);
};

// ---- 1. the two new inputs and what the drive held ------------------------------------------
const A = `  v_max     int  := coalesce(nullif(p_input->>'max_steps','')::int, 40);`;
splice(A, A + `
  -- HOLD AT AN OPEN STEP. A caller that means to drive a step's FAILURE branch needs that step
  -- open and owned, and cannot get there by asking the kernel to stop: since PCCR-001 the dispatch
  -- fires when the step OPENS, so a handler that can execute closes its step and the kernel opens
  -- the next one before any caller is consulted. max_steps 0 therefore does not leave a step open
  -- -- measured 23 Aug 2026 on all 30 workflows, 19 of them came back with the run in
  -- waiting_handoff or waiting_review and NO open step run at all, because the successor is not
  -- opened until the receiving owner accepts the handoff. The failure and cancellation probes then
  -- had nothing to act on and were refused 22023 for a null step_run_id, which is a fact about the
  -- probe and not about the estate.
  --
  -- These two inputs let the caller drive the canonical path -- the same handoff acceptances, the
  -- same capability results, the same recorded reviews, the same fn_kernel_step_complete for every
  -- earlier step -- and STOP with one named step open, having completed nothing on it. Nothing is
  -- skipped and no state is written by hand: the run is exactly where a real actor would find it.
  v_hold_step text := nullif(btrim(coalesce(p_input->>'hold_at_step_id','')),'');
  v_hold_any  boolean := coalesce((p_input->>'hold_at_first_open_step')::boolean, false);
  v_held_srid bigint := null;
  v_held_step text := null;`);

// ---- 2. the hold itself, the moment an open step run is in hand -------------------------------
const B = `    -- ---- WHAT THE DETERMINISTIC HANDLER DID WITH THIS STEP ------------------------------------`;
splice(B, `    -- ---- THE HOLD ----------------------------------------------------------------------------
    -- Reached only through the doors above: every earlier step was completed through
    -- fn_kernel_step_complete and every earlier handoff through fn_phase_d_handoff_accept. This
    -- step run is open because the kernel opened it and nothing has closed it.
    if v_hold_any or (v_hold_step is not null and sr.step_id = v_hold_step) then
      v_held_srid := sr.step_run_id;
      v_held_step := sr.step_id;
      v_seen := v_seen || sr.step_run_id;
      if v_stopped is null then
        v_stopped := jsonb_build_object('at', sr.step_id, 'refused_with', 'pd_drive_held_open',
          'reason', 'the caller asked this drive to stop with this step open; nothing was completed on it');
      end if;
      exit;
    end if;

` + B);

// ---- 3. say what was held, so a reader never has to infer it ---------------------------------
const C = `    'steps_driven', v_driven,`;
splice(C, `    'held_step_id', v_held_step,
    'held_step_run_id', v_held_srid,
` + C);

const header = `-- J01 — the failure and cancellation branches had no step to act on, because the successor is
-- not opened until the handoff is accepted
--
-- MEASURED 23 Aug 2026 on htdblwldjkcgjvmqkbeh, all 30 frozen workflows, four modes each:
-- failure path exercised 11 of 30, cancellation reached cancelled 21 of 30. Every one of the 19
-- failures was REFUSED:22023 -- "step_run_id ... required (got (null))". Probed directly on W01,
-- W02, W04 and W12 rather than reasoned about:
--
--   W01  run_state=waiting_handoff  open step runs=0  open handoffs=1  W01-S01:completed
--   W02  run_state=waiting_review   open step runs=0  open handoffs=1  W02-S01:completed
--   W12  run_state=waiting_review   open step runs=0  open handoffs=1  S01,S02,S03 completed
--   W04  run_state=active           open step runs=1  open handoffs=0  W04-S01:active
--
-- So the previous diagnosis -- "sixteen workflows execute step 1 without reading the business
-- object, so nothing keeps a step open" -- is right about the first half and wrong about the
-- consequence. The handler DOES execute step 1. What leaves nothing to fail is that the kernel
-- opens no successor step run until the receiving owner accepts the open handoff, which is the
-- frozen model working. W04 is the shape the probe assumed: a step that stayed open.
--
-- A probe cannot fix that by naming a business object that resolves to nothing, because for those
-- 19 workflows step 1 never reads it. It has to do what the person does: accept the handoff.
--
-- This adds two inputs to the driver -- hold_at_step_id and hold_at_first_open_step -- which drive
-- the CANONICAL path (fn_phase_d_handoff_accept, fn_phase_d_capability_result_accept,
-- fn_kernel_review_decide, fn_kernel_step_complete) for every earlier step and then stop with one
-- named step OPEN and nothing done to it. The caller then fails it, or cancels the run, at exactly
-- the point a real actor would. Nothing is bypassed and no state is written by hand; the only new
-- behaviour is that the loop can stop before completing a step it found open.
--
-- It is also what section 1 needs: the frozen model is a linear chain -- next_step_if_pass names
-- the next step for 227 steps and WORKFLOW_COMPLETE for the 30 closure steps, and next_step_if_fail
-- names one of three symbolic outcomes and never a step -- so per-step BRANCH coverage means
-- exercising each step's fail edge, which needs each step held open in turn.
--
-- ROLLBACK: re-apply the previous body of fn_phase_d_drive_workflow (phase_d_h11 is the last file
-- that defines it). No DDL, no grants: CREATE OR REPLACE preserves the ACL.
--
-- GENERATED from the live body by scripts/tmp_diag/gen_j01.mjs; three anchors, each required to
-- match exactly once. Everything else is byte-identical to what production ran before this file.
CREATE OR REPLACE FUNCTION public.fn_phase_d_drive_workflow(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$`;

writeFileSync('scripts/sql/phase_d_j01_the_failure_branch_had_no_step_because_the_handoff_was_unaccepted.sql',
  header + body + '$function$;\n');
console.log('written, body length', body.length, 'was', prosrc.length);
