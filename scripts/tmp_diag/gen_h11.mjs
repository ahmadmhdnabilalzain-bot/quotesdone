import { writeFileSync } from 'node:fs';
import { sql } from '../phase_c/lib/db.mjs';
const HEAD = `-- H11 — a gate that needed a reviewer refused before the reviewer could be recorded
--
-- GATE-021 (marketing artifact approval, W03;W20) and GATE-026 (knowledge validation, W26) declare
-- reviewer_role_id among their evidence keys. On the FIRST review step of each workflow -- W03-S06,
-- W20-S04, W26-S05, and the steps after them W20-S05, W26-S06 -- the gate is evaluated in
-- fn_phase_d_handler_execute section 2b, BEFORE the review-recording refusal a REVIEW_HANDLER raises
-- in section 5a. So the dispatch outcome was pd_evidence_absent naming reviewer_role_id, and this
-- driver's review-recording block only fired on pd_review_not_recorded -- it never recorded a review,
-- so the reviewer never resolved, so the gate refused again. Measured 23 Aug 2026: 5 steps.
--
-- The block now also fires when the dispatch refusal is a gate evidence-absent (pd_evidence_absent
-- or pd_gate_refused) whose reason names reviewer_role_id. It records exactly the same review,
-- through fn_kernel_review_decide, with the step's own frozen reviewer or an independent candidate
-- the kernel allows, and re-dispatches. H03 then resolves reviewer_role_id -- from this step's own
-- recorded review for the review step, from the run's earlier review for a later step -- and the
-- gate has its evidence. Nothing is bypassed: fn_kernel_review_decide still refuses a non-independent
-- reviewer, and a gate whose reviewer cannot be recorded still refuses.
--
-- ROLLBACK: re-apply the previous body of fn_phase_d_drive_workflow (phase_d_h06 is the last file
-- that defines it). No DDL.
--
-- One anchor, required to match exactly once. The rest of the routine is byte-identical.`;
const r = await sql(`select pg_get_functiondef(p.oid) as def from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_phase_d_drive_workflow'`);
let def = r[0].def;
const a1 = `    if found and d.refusal_code = 'pd_review_not_recorded' then`;
if (def.split(a1).length - 1 !== 1) throw new Error('A1 matched ' + (def.split(a1).length - 1));
def = def.replace(a1, `    -- H11. Also record a review when a gate refused for want of the reviewer, not only when the
    -- REVIEW_HANDLER raised pd_review_not_recorded. Same review, same door, same independence check.
    if found and (d.refusal_code = 'pd_review_not_recorded'
                  or (d.refusal_code in ('pd_evidence_absent','pd_gate_refused')
                      and coalesce(d.reason,'') ilike '%reviewer_role_id%')) then`);
writeFileSync('scripts/sql/phase_d_h11_the_gate_that_needed_a_reviewer_refused_before_one_was_recorded.sql', HEAD + '\n' + def + '\n');
console.log('H11 written');
