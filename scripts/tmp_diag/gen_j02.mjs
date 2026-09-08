// Generates scripts/sql/phase_d_j02_*.sql from the LIVE body of fn_kernel_cancel.
import { writeFileSync } from 'node:fs';
import { sql } from '../lib/db.mjs';

const [{ prosrc }] = await sql(
  `select prosrc from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='fn_kernel_cancel'`);

const MARK = '  -- ---- (a) the command ';
const at = prosrc.indexOf(MARK);
if (at < 0) throw new Error('section (a) marker not found');
let head = prosrc.slice(0, at);
let tail = prosrc.slice(at);

// Every downstream use of the derived command id becomes the SWEEP id, which is null when the
// command is not ours to close.
const before = (tail.match(/v_command/g) || []).length;
if (before !== 23) throw new Error(`expected 12 downstream v_command uses, found ${before}`);
tail = tail.split('v_command').join('v_cmd');
// ... except the returned report, which must still name the command the run belongs to.
const RET = `'command_id', v_cmd,`;
if ((tail.match(/'command_id', v_cmd,/g) || []).length !== 1) throw new Error('return anchor not unique');
tail = tail.replace(RET, `'command_id', v_command, 'command_closed', (v_cmd is not null),
    'command_note', v_cmd_note,`);

// ---- declares --------------------------------------------------------------------------------
const D = `  v_command  bigint;`;
if ((head.match(/  v_command  bigint;/g) || []).length !== 1) throw new Error('declare anchor not unique');
head = head.replace(D, D + `
  -- WHOSE STATE MODEL IS BEING ASKED. v_command is the command the subject BELONGS to; v_cmd is
  -- the command this call is entitled to close. They are the same when the founder named the
  -- command, and they differ when the caller named one workflow run.
  v_cmd      bigint;
  v_cmd_note text;`);

// ---- decide the sweep scope, immediately before section (a) ----------------------------------
head = head + `  -- ---- CAN THIS CALL CLOSE THE COMMAND, AND MUST IT? ---------------------------------------
  -- MEASURED 23 Aug 2026. Driving W01 twice inside one Phase D scenario gives two runs under one
  -- founder command. Failing the first run moves the COMMAND to 'failed'. Cancelling the second
  -- run -- state 'active', and active -> cancelled is declared in phase_b_workflow_transition --
  -- then came back:
  --
  --   {"ok": false, "from": "failed", "to": "cancelled", "error": "transition_not_permitted",
  --    "message": "The command state model does not allow this move. Nothing was cancelled."}
  --
  -- and the run was still active. The caller named a WORKFLOW RUN. The command was derived here,
  -- the command's own model was consulted, and the run's cancellation was abandoned on the
  -- strength of it. That is a guard firing on a subject nobody asked about: the founder's command
  -- is not being cancelled and has no business refusing.
  --
  -- The same derivation made the sweep too wide in the other direction. Sections (e), (g) and (h)
  -- matched derived work on command_id, so cancelling ONE run of a command cancelled the tasks,
  -- outbox rows and traces of its SIBLING runs, while sections (c), (d) and (f) correctly left
  -- those runs themselves alone -- an active run with cancelled tasks underneath it.
  --
  -- So: the command is closed, and its derived work swept, only when this call is entitled to do
  -- it. Naming the command is entitlement. Naming a run is entitlement only when it is the last
  -- open run of that command AND the command's own state model permits the move. Where it is not,
  -- the run is still cancelled -- that was always the thing asked for -- and the report says in
  -- one field what happened to the command instead of returning a refusal for it.
  if v_kind = 'founder_command' then
    v_cmd := v_command;
  elsif v_command is not null then
    if exists (select 1 from public.phase_c_workflow_run
                where command_id = v_command and not (run_id = any(v_runs))
                  and state not in ('cancelled','superseded','completed','failed')) then
      v_cmd_note := 'another workflow run of this command is still open, so the command was left as it is';
    elsif exists (select 1 from public.founder_command
                   where command_id = v_command and state not in ('cancelled','superseded','completed'))
      and not exists (select 1 from public.phase_c_command_transition t
                       join public.founder_command c on c.command_id = v_command
                      where t.from_state = c.state and t.to_state = v_terminal) then
      v_cmd_note := format('the command is %s and the command state model declares no %s -> %s, so the command was left as it is',
        (select state from public.founder_command where command_id = v_command),
        (select state from public.founder_command where command_id = v_command), v_terminal);
    else
      v_cmd := v_command;
    end if;
  end if;

`;

const header = `-- J02 — cancelling one workflow run was refused by the state model of a command nobody named
--
-- MEASURED 23 Aug 2026 on htdblwldjkcgjvmqkbeh. Two Phase D drives of W01 inside one scenario
-- produced runs 47357 and 47358 under founder command 12773. The failure path was driven on the
-- first, which moved the COMMAND to 'failed'. fn_kernel_cancel on the SECOND run -- state
-- 'active', and phase_b_workflow_transition declares active -> cancelled -- returned:
--
--   {"ok": false, "from": "failed", "to": "cancelled", "error": "transition_not_permitted",
--    "message": "The command state model does not allow this move. Nothing was cancelled."}
--
-- and run 47358 was still active afterwards. phase_c_command_transition has no failed -> cancelled
-- and is right not to: a failed command is not cancelled. But the caller asked to cancel a
-- workflow run, and the command was derived inside this routine. The refusal was correct about a
-- subject nobody asked about, and it abandoned the one that was asked about.
--
-- The same derivation made the sweep too WIDE in the other direction: sections (e) tasks, (g)
-- outbox and (h) traces matched on command_id, so cancelling one run of a command closed the
-- derived work of its sibling runs while sections (c), (d) and (f) left those runs open. An active
-- run with cancelled tasks underneath it is not a state the kernel should be able to produce.
--
-- Both are the same root cause: one identifier was doing two jobs. v_command is now the command
-- the subject BELONGS to, reported and never acted on unless entitled; v_cmd is the command this
-- call may close and sweep, and it is set only when the founder named the command, or when the
-- named run is the command's LAST open run and the command's own model permits the move. Where it
-- is not set the run is still cancelled and the report carries command_closed=false with the
-- reason in command_note, instead of a refusal for something the caller never asked for.
--
-- Behaviour for subject_kind = 'founder_command' is unchanged, including the early refusal when
-- the command's state model forbids the move: there the command IS the subject.
--
-- ROLLBACK: re-apply the previous body of fn_kernel_cancel. No DDL, no grants: CREATE OR REPLACE
-- preserves the ACL.
--
-- GENERATED from the live body by scripts/tmp_diag/gen_j02.mjs.
CREATE OR REPLACE FUNCTION public.fn_kernel_cancel(p_input jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$`;

writeFileSync('scripts/sql/phase_d_j02_one_run_was_refused_by_the_state_model_of_a_command_nobody_named.sql',
  header + head + tail + '$function$;\n');
console.log('written; downstream v_command uses rewritten:', before);
