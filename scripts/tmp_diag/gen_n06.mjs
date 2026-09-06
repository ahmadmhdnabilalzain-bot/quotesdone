// GENERATE N06 — give public.fn_phase_d_gate_evaluate a verdict for "the gate could not READ",
// distinct from the BLOCKED it returns when it read and judged false.
//
// Spliced into the LIVE body; both anchors are asserted to match exactly once.
import { q } from './q.mjs';
import { writeFileSync } from 'node:fs';

const [{ d: live }] = await q(`select pg_get_functiondef(p.oid) d
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname='public' and p.proname='fn_phase_d_gate_evaluate'`);

// ---- 1. wrap the predicate chain -------------------------------------------------------------
const START = `  if p_gate_id = 'GATE-001' then`;
const END = `  state := case when v_ok then 'PASSED' else 'BLOCKED' end;
  passed := coalesce(v_ok, false);
  return next;
end $function$`;

for (const [name, a] of [['START', START], ['END', END]]) {
  const n = live.split(a).length - 1;
  if (n !== 1) { console.error(`${name} anchor matched ${n} times, expected 1. Nothing written.`); process.exit(2); }
}

const PRE = `  -- ============================ N06. READ FAILURE IS NOT REFUSAL ============================
  -- Until this block existed the routine carried ZERO exception handlers, so a read error inside a
  -- predicate -- permission denied, a relation renamed, a statement cancelled -- propagated and
  -- aborted the CALLER'S transaction. There was no state, refusal_code or evidence_absent value
  -- that said "the gate could not read", as distinct from the BLOCKED/false it returns when it
  -- read the evidence and judged it. Those are different facts with different remedies: one is
  -- fixed by correcting the evidence, the other by fixing the estate, and a caller that cannot
  -- tell them apart will retry the wrong one forever.
  --
  -- IT FAILS CLOSED. state BLOCKED, passed false, evidence_absent true -- the gate did not see its
  -- evidence, because it could not read it. A gate that answered PASSED on a read error would be
  -- the far worse defect.
  --
  -- THE FAULT HOOK. A read error cannot be provoked from inside an aborted transaction by revoking
  -- a grant -- the routine pins its own search_path and runs as the owner of every relation it
  -- reads, so nothing a caller sets reaches it. app.phase_d_gate_read_fault names one gate whose
  -- read is made to fail, and it is the ONLY way this branch can be reached deliberately. Said
  -- plainly: the fault is injected, not a revoked production grant. What the test proves is that
  -- the DISTINCTION exists and fails closed -- which is the whole of the defect -- and the control
  -- is the identical call with the hook unset.
  begin
    if coalesce(nullif(current_setting('app.phase_d_gate_read_fault', true),''), '') = p_gate_id then
      perform 1 / (case when true then 0 else 1 end);
    end if;

`;

const POST = `  exception when others then
    -- Anything the predicate chain could not READ. Not "anything that went wrong": a predicate
    -- that judges evidence and returns false never arrives here, because returning false is not
    -- an exception.
    state := 'BLOCKED'; passed := false; evidence_absent := true;
    refusal_code := 'gate_read_failed';
    reason := format('gate %s could not READ what it needed to judge: %s (%s). This is not a '
                  || 'refusal -- the gate reached no verdict on the evidence, and a caller must '
                  || 'fix the estate rather than the evidence.',
                     p_gate_id, left(SQLERRM, 160), SQLSTATE);
    return next; return;
  end;

  state := case when v_ok then 'PASSED' else 'BLOCKED' end;
  passed := coalesce(v_ok, false);
  return next;
end $function$`;

// The chain body sits between the two anchors and is indented for a plpgsql block already; the
// wrapper adds `begin` before it and `exception ... end;` after, so nothing inside moves.
let out = live.replace(START, PRE + START);
out = out.replace(END, POST);

const header = `-- N06. A GATE THAT COULD NOT READ, AND A GATE THAT READ AND REFUSED, GAVE THE SAME ANSWER.
--
-- public.fn_phase_d_gate_evaluate returns (state, passed, gate_type, reason, refusal_code,
-- evidence_absent). Measured on the live body 24 Aug 2026: it contained ZERO 'exception when'
-- handlers. So a read error inside a predicate did not become a verdict -- it propagated and took
-- the caller's transaction with it -- and there was no value in the result that could say "the
-- gate could not read", as distinct from the BLOCKED it returns having read and judged false.
--
-- That was recorded as PD-PROV-002 with the disposition PERMANENT_EXEMPTION and the reason "the
-- distinction the defect asks for is not representable". It was not representable because it had
-- not been built. A defect catalogue entry that says a control cannot be tested because the control
-- does not exist is a product gap wearing an exemption.
--
-- THREE OUTCOMES NOW, WHERE THERE WERE TWO:
--
--   PASSED                          the gate read the evidence and it satisfies the gate
--   BLOCKED  evidence_absent=false  the gate read the evidence and it does not
--   BLOCKED  evidence_absent=true   the gate did not judge -- either the evidence was not named
--            refusal_code=          (the existing E19 case) or it could not be READ (this one,
--            gate_read_failed       carrying its own refusal code and the SQLSTATE)
--
-- It fails CLOSED. A gate that answered PASSED on a read error would be a far worse defect than the
-- one this file closes.
--
-- HOW THE BRANCH IS REACHED, said plainly. The routine is STABLE with search_path pinned to
-- public, pg_temp and runs as the owner of every relation it reads, so no grant a caller can
-- change in an aborted transaction reaches it. app.phase_d_gate_read_fault names one gate whose
-- read is made to fail. The fault is INJECTED, not a revoked production grant -- and what the test
-- proves is that the distinction exists and fails closed, with the control being the identical
-- call with the hook unset. Stated here rather than left to be inferred from a GUC name.
--
-- Generated by scripts/tmp_diag/gen_n06.mjs, which splices into the LIVE body and asserts both
-- anchors match exactly once. CREATE OR REPLACE preserves the ACL, so no REVOKE belongs here.

`;

writeFileSync('scripts/sql/phase_d_n06_a_gate_that_could_not_read_answered_like_one_that_refused.sql',
  header + out + ';\n');
console.log(`written. live ${live.length} -> new ${out.length} chars`);
