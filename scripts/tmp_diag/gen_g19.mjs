import { writeFileSync } from 'node:fs';
import { sql } from '../lib/db.mjs';

const HEAD = `-- G19 — a founder command born without the trace that lets it ever move
--
-- G05 made a founder-gated run arise FROM the fixture founder command, which is how a
-- founder-instructed run really starts and is what let BR-003 resolve. What it did not do is give
-- that command the root trace the real router opens one statement later.
--
-- fn_founder_command_trace_guard is explicit about the deal: a command may be BORN at 'received'
-- with no trace, and 'received -> interpreting' is the single move allowed without one, "the
-- transition the router makes in order to open the trace, in the same transaction, on the very next
-- statement". Every state after that must carry it. TRACE-FOUNDER-COMMAND declares
-- trace_required=YES.
--
-- fn_phase_d_founder_authority_fixture inserted at 'received' and stopped. So the command existed,
-- satisfied "a founder command is behind this run", and could never legally leave the state it was
-- created in. MEASURED, driving W09's failure path with the step deliberately left open:
--
--     founder_command 11676: cannot leave received without a root trace   (23514)
--
-- and the same refusal on every founder-gated workflow's failure and cancellation arm. The four-mode
-- result reported failure path exercised 6 of 30 and cancellation 13 of 30 largely because of it.
--
-- THE GUARD IS RIGHT AND IS NOT TOUCHED. What was wrong is a fixture that created half of a founder
-- command: the row without the evidence root that makes it a command rather than a record. The
-- fixture now opens the root trace through fn_phase_c_trace_write under the TRACE-FOUNDER-COMMAND
-- policy and stamps it on the command, exactly as the router does, so the kernel can move it for
-- the same reasons it moves a real one.
--
-- IT STILL AUTHORISES NOTHING. founder_initiated_only false, refund_semantics false,
-- founder_identity resolving to nobody, and founder AUTHENTICATION remains fn_phase_c_require_founder
-- reading a verified auth subject. A trace is evidence of what happened, not permission.
--
-- ROLLBACK: re-apply the previous body of fn_phase_d_founder_authority_fixture. No DDL.`;

const r = await sql(`select pg_get_functiondef(p.oid) as def from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
  and p.proname='fn_phase_d_founder_authority_fixture'`);
let def = r[0].def;

const anchorDecl = `  v_text  text;`;
if (def.split(anchorDecl).length - 1 !== 1) throw new Error('G19 decl anchor');
def = def.replace(anchorDecl, `  v_text  text;
  v_trace bigint;   -- G19: the root trace the guard requires before the command may move`);

const anchor = `  returning command_id into v_id;`;
if (def.split(anchor).length - 1 !== 1) throw new Error('G19 anchor');
def = def.replace(anchor, `  returning command_id into v_id;

  -- G19. THE ROOT TRACE, OPENED THE WAY THE ROUTER OPENS IT.
  -- Without this the command is stuck at 'received' for the rest of its life:
  -- fn_founder_command_trace_guard refuses every later transition with "cannot leave received
  -- without a root trace", and that refusal is correct. The command is created at received above
  -- (the one state the guard allows trace-less at birth) and the trace is stamped on it here, in
  -- the same transaction, which is the sequence the guard's own comment describes.
  v_trace := public.fn_phase_c_trace_write('TRACE-FOUNDER-COMMAND', jsonb_build_object(
    'subject_kind',   'founder_command',
    'subject_ref',    v_id::text,
    'command_id',     v_id,
    'actor_role_id',  'chief_of_staff',
    'system_actor_id','fn_phase_d_founder_authority_fixture',
    'state_before',   '',
    'state_after',    'received',
    'status',         'open',
    'evidence_refs',  jsonb_build_array(jsonb_build_object(
      'phase_d_fixture_run', v_run, 'label', v_label,
      'note', 'PHASE_D_FIXTURE_DO_NOT_PUBLISH — the root trace of a Phase D fixture founder command. It records that this command exists inside an aborted fixture transaction and authorises nothing.'))));

  update public.founder_command set trace_id = v_trace where command_id = v_id;`);

writeFileSync('scripts/sql/phase_d_g19_a_founder_command_born_without_the_trace_that_lets_it_move.sql',
  HEAD + '\n' + def + '\n');
console.log('G19 written');
