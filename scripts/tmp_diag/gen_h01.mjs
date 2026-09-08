// H01 generator: splice four corrections into the live fn_phase_d_handler_execute and write the
// migration file. Anchors must each match exactly once; the rest of the routine is byte-identical.
import { writeFileSync } from 'node:fs';
import { sql } from '../lib/db.mjs';

const HEAD = `-- H01 — the handler asked the kernel for a verdict it could have asked the estate for, and handed
--        the effect a review it had already read
--
-- Four corrections to fn_phase_d_handler_execute, each measured on the 30-workflow drive of 23 Aug
-- 2026 (scripts/tmp_diag/reason_census.txt), none of them a weakening of any rule or gate.
--
-- 1. THIRTY REVIEW STEPS REFUSED BR-002 FOR A REVIEWER THE HANDLER HAD ALREADY READ.
--    F34 made the handler read the recorded canonical review -- phase_c_task.reviewer_role_id,
--    stamped by fn_kernel_review_decide, and the sealed TRACE-ROLE-ACTION verdict -- and put both
--    into the handler OUTPUT. It never put them into the effect PAYLOAD. fn_phase_d_effect_produce
--    judges BR-002 on the payload, saw reviewer_role_id absent, and refused:
--
--        fn_phase_d_effect_produce: step W02-S02 is accountable to data_intelligence_director and
--        names (none) as reviewer; those resolve to one effective identity (BR-002).
--
--    Measured on W02-S02, W04-S02, W07-S03/S06, W08-S03/S04, W09-S02/S07, W10-S02/S03, W12-S04/S05,
--    W15-S01/S03, W17-S10, W21-S04, W22-S06, W23-S05/S07, W24-S02..S05/S08, W27-S03..S05/S07,
--    W29-S04/S06, W30-S02/S06. The recorded review now travels into the payload for every
--    REVIEW_VERDICT effect, LAST in the concatenation, so the sealed verdict and the stamped
--    reviewer outrank anything a caller or the catalogue could say. BR-002 is still evaluated by
--    fn_phase_d_effect_produce on exactly that reviewer, and still refuses a creator.
--
-- 2. SEVENTEEN STEPS REACHED THE KERNEL AND WERE REFUSED k3_reviewer_verdict_missing.
--    The frozen registry names an independent reviewer on 28 steps; only the REVIEW_HANDLER class
--    asked whether a review had been recorded before executing. An EXECUTION, DECISION or CLOSURE
--    step naming a reviewer built its output, produced its effect (in a subtransaction) and was
--    refused by fn_kernel_step_complete 3g -- correctly -- at which point the kernel's refusal was
--    the dispatch outcome and the driver closed the step as an ACTOR instead. Measured on W01-S06,
--    W02-S06, W04-S07, W06-S05, W08-S06, W10-S05, W12-S09, W19-S07, W20-S09, W21-S05, W23-S08,
--    W24-S06/S09 and W27-S09 among others.
--
--    The handler now asks the SAME question the kernel asks, with the same predicate over
--    phase_c_trace, before it builds anything, and refuses with pd_review_not_recorded. That is
--    the code the F35 driver answers by recording the review through fn_kernel_review_decide and
--    dispatching the step again. The kernel check at 3g is untouched and still decides.
--
-- 3. A DECISION STEP COULD NOT SAY WHO DECIDED OR WHEN.
--    public.refunds.decided_by / decided_at are mapped columns of refund_dispute_case, and
--    GATE-020 reads both at W17-S07. Nothing in the handler supplied them. For a DECISION_HANDLER
--    the decider is the accountable role of the deciding step -- read off the step run, not chosen
--    -- and the time is now(). They are added to the payload only for that class; a write map
--    that carries neither key ignores them.
--
-- 4. THE EFFECT STATE WAS WHATEVER THE CALLER SAID, AND THE KERNEL DISPATCH SAYS NOTHING.
--    p_input->>'effect_state' is never passed by fn_phase_d_dispatch_step, so every DOMAIN_MUTATION
--    reached fn_phase_d_object_write with no state, and the writer defaulted it to 'open' -- onto
--    public.refunds (CHECK refuses 'open'), public.department_objective and public.org_tasks (same),
--    and onto rows the scenario had built at a LATER state: an inquiry at quote_ready went back to
--    open and GATE-011 refused W05-S04..S09; a transaction at payment_reconciled went back to open
--    and BR-033 / GATE-019 refused W16-S02..S09. The state a step leaves an object in is a fact the
--    committed catalogue may state per step (EFFECT_PAYLOAD key 'state', scoped to the step_id);
--    where it states none the handler passes none, and H02 makes the writer keep the row's own
--    state on an update and the relation's own default on an insert. No state is invented here.
--
-- ROLLBACK: re-apply the previous body of fn_phase_d_handler_execute (phase_d_g14 is the last file
-- that defines it). No DDL.
--
-- Four anchors, each required to match exactly once. The rest of the routine is byte-identical.`;

const r = await sql(`select pg_get_functiondef(p.oid) as def from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='fn_phase_d_handler_execute'`);
let def = r[0].def;
const once = (anchor, label) => { const n = def.split(anchor).length - 1; if (n !== 1) throw new Error(`${label}: anchor matched ${n} times`); };

// ---- 2. the frozen-reviewer pre-check, placed after the provider boundary, before section 5 ----
const a1 = `  -- ---- 5. THE FAMILY HANDLER ---------------------------------------------------------------
  -- F34. The recorded canonical review for this step run, read once.
  v_review := public.fn_phase_d_recorded_review(v_step_run);`;
once(a1, 'A1');
def = def.replace(a1, `  -- ---- 4b. H01. THE VERDICT THE KERNEL WILL DEMAND, ASKED FOR HERE FIRST ----------------------
  -- fn_kernel_step_complete 3g refuses a pass on a step whose frozen row names an independent
  -- reviewer unless an approved, independent verdict from that role is sealed on the task. The
  -- handler used to discover that only after producing its effect, and the refusal came out of the
  -- kernel as k3_reviewer_verdict_missing. The same predicate is asked here, before anything is
  -- built, and the refusal is the one the driver answers through fn_kernel_review_decide. Nothing
  -- about the kernel check changes; it still decides at 3g.
  if coalesce(btrim(s.independent_reviewer_role_id),'') <> ''
     and not exists (
       select 1
         from public.phase_c_task t
         join public.phase_c_trace tr on tr.task_id = t.task_id
        where t.run_id = sr.run_id and t.step_id = sr.step_id
          and tr.trace_policy_id = 'TRACE-ROLE-ACTION'
          and tr.evidence_refs @> '[{"review_decision":"approved"}]'::jsonb
          and public.fn_kernel_reviewer_independent(sr.accountable_role_id, tr.reviewer_role_id)
          and (select role_id from public.fn_phase_c_resolve_actor(tr.reviewer_role_id))
              = (select role_id from public.fn_phase_c_resolve_actor(s.independent_reviewer_role_id)))
  then
    raise exception 'fn_phase_d_handler_execute: step % names % as its independent reviewer and no approved, independent verdict from that role has been recorded on its task. fn_kernel_review_decide seals the verdict and stamps the reviewer; until it has run the kernel will refuse the completion, so the handler refuses here first. (pd_review_not_recorded)',
      sr.step_id, s.independent_reviewer_role_id using errcode = '23514';
  end if;

` + a1);

// ---- 4. the effect state: caller, then the committed catalogue for this step, then nothing ------
const a2 = `      'state',        p_input->>'effect_state',`;
once(a2, 'A2');
def = def.replace(a2, `      -- H01 (4). The caller's stated state, else the state the committed catalogue declares for
      -- THIS step (EFFECT_PAYLOAD key 'state', step-scoped, fixture context only), else none -- and
      -- none means the writer keeps the row's state or takes the relation's default. Never 'open'.
      'state',        coalesce(p_input->>'effect_state',
                               (select fi.value #>> '{}'
                                  from public.fn_phase_d_fixture_input(v_step_run, 'EFFECT_PAYLOAD', 'state') fi)),`);

// ---- 1 + 3. the payload: recorded review for REVIEW_VERDICT, decider for DECISION_HANDLER ----
const a3 = `    || jsonb_build_object('payload',
         public.fn_phase_d_fixture_effect_payload(v_step_run)
         || coalesce(p_input->'effect_payload', v_inputs)
         || case when v_cap is null then '{}'::jsonb
                 else coalesce(v_cap->'payload','{}'::jsonb) end));`;
once(a3, 'A3');
def = def.replace(a3, `    || jsonb_build_object('payload',
         public.fn_phase_d_fixture_effect_payload(v_step_run)
         || coalesce(p_input->'effect_payload', v_inputs)
         || case when v_cap is null then '{}'::jsonb
                 else coalesce(v_cap->'payload','{}'::jsonb) end
         -- H01 (1). THE RECORDED REVIEW, LAST, FOR A REVIEW_VERDICT EFFECT. F34 read it into the
         -- output and never into the payload, and BR-002 is judged on the payload. The sealed
         -- verdict and the stamped reviewer outrank the catalogue and any caller, so they close
         -- the concatenation. Absent, nothing is added and fn_phase_d_effect_produce still refuses.
         || case when ec.expected_effect_type = 'REVIEW_VERDICT'
                 then jsonb_strip_nulls(jsonb_build_object(
                        'verdict',          v_review->>'verdict',
                        'reviewer_role_id', v_review->>'reviewer_role_id'))
                 else '{}'::jsonb end
         -- H01 (3). WHO DECIDED AND WHEN, FOR A DECISION STEP. The decider is the accountable role
         -- of the deciding step run, read off the kernel's row; the time is now(). A write map that
         -- carries neither key ignores both.
         || case when b.handler_class = 'DECISION_HANDLER'
                 then jsonb_build_object('decided_by', v_actor, 'decided_at', now())
                 else '{}'::jsonb end));`);

writeFileSync('scripts/sql/phase_d_h01_the_verdict_the_handler_read_and_never_handed_on.sql', HEAD + '\n' + def + '\n');
console.log('H01 written');
