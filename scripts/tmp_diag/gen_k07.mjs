// K07 — a run could not see the object it had just created, and a gate asked for one before it existed.
//
// Regenerates the committed file from the LIVE bodies. Part 1 (fn_phase_d_step_context) is already
// live and is taken verbatim; part 2 (fn_phase_d_gate_applies) is spliced against whatever is live,
// so re-running this after an amendment produces the amended file rather than a stale one.
import { writeFileSync } from 'node:fs';
import { liveBody, splice } from './splice.mjs';

const HEADER = `-- K07 — the run could not see the object it had just created, and a gate asked for one before it existed
--
-- MEASURED 23 Aug 2026 on htdblwldjkcgjvmqkbeh, with the fixture scenario asked to leave out the
-- objects the workflow under test produces (SKIPPED_PRODUCED_BY_THE_WORKFLOW_UNDER_TEST on all 30
-- workflows rather than on W12 alone). Two more of the four causes that surfaced:
--
--   W17-S07  gate GATE-020 (Refund authority and idempotency) requires [refund_id] and the call
--            names none of it
--   W08-S01  gate GATE-013 (Supplier-safe approval) requires [safe_package_ref] and the call names
--            none of it
--
-- THEY ARE NOT THE SAME DEFECT, and treating them as one would have removed a gate that guards
-- money.
--
-- ---- 1. THE RUN'S OWN OUTPUT WAS INVISIBLE TO IT ------------------------------------------------
--
-- W17-S01 through W17-S06 all EXECUTED and W17-S01's effect created the refund_dispute_case. By
-- W17-S07 the object EXISTED, in this run, written by this run, through fn_phase_d_object_write.
-- fn_phase_d_step_context could not see it: a key that names an object is answered from the run's
-- own business row, from a declared foreign key on it, or -- inside a fixture context only -- from
-- the canonical reference the SCENARIO recorded. There was no source for "the object this run
-- produced a few steps ago", so the answer existed only when a fixture had planted it.
--
-- public.phase_d_effect_ledger is that source and it is not a fixture: every Phase D effect records
-- run_id, effect_object_id and result_reference, and the reference is the canonical identity
-- fn_phase_d_object_write returned. It is asked AFTER the run's own row and its foreign keys and
-- BEFORE the scenario record, because a fact the run produced outranks one a scenario planted; and
-- it runs in production exactly as it runs under a fixture, because it reads no fixture.
--
-- AND ONLY A REFERENCE INTO THE OBJECT'S OWN CANONICAL RELATION IS AN IDENTITY OF IT. The ledger
-- records effect_object_id from the step's DECLARED object, so W15-S01 -- a review step of the
-- comparison workflow -- carries effect_object_id quotation_comparison with result_reference
-- public.review_chain:id=15748. The first version of this block took that, GATE-018 judged a review
-- row as a comparison, and W15-S05 refused with "comparison 15748 does NOT belong to the calling
-- customer" -- true, and about the wrong row. The relation is now matched against
-- phase_d_business_object_binding.canonical_relation.
--
-- ---- 2. A GATE THAT ASKED W08-S01 FOR THE PACKAGE W08 EXISTS TO BUILD ---------------------------
--
-- W08-S01 is the FIRST step of the workflow whose whole purpose is to produce the supplier-safe
-- package, so at that step nothing has produced it and nothing can. GATE-013's subject is
-- supplier_safe_package; public.phase_d_step_effect says W08-S01 is where W08 first produces it.
--
-- fn_phase_d_gate_applies already carries this exact correction four times -- GATE-015, GATE-020,
-- GATE-021 and GATE-026 -- each narrowed because it demanded a condition the workflow itself is
-- what satisfies. The fifth is written here as the general rule those four are instances of, with
-- the subject derived the way fn_phase_d_rule_applies derives it (the gate contract's evidence key
-- against public.phase_d_fixture_stage.contributes_ref) and the producing step read from the frozen
-- effect registry.
--
-- IT IS NEVER A WHOLE-WORKFLOW EXEMPTION, AND IT TURNS ON THE PREDICATE KIND.
--
--   * before the producing step -- every gate. The subject does not exist yet and cannot.
--   * AT the producing step -- only where predicate_kind is EVIDENCE_REQUIRED, i.e. where the gate's
--     test is the PRESENCE of the subject's identity. GATE-013 asks W08-S01 to name the package
--     W08-S01 creates.
--   * a MEASURED gate is untouched at the producing step. GATE-015 exists precisely to judge the
--     creating step -- "no existing assignment for this supplier and inquiry version" -- and
--     exempting it there would leave it governing nothing, which is the D17 whole-workflow
--     exemption this estate tried and discarded.
--
-- Measured after the change: GATE-020 (EVIDENCE_REQUIRED, subject refund_dispute_case, produced at
-- W17-S01) stops applying at W17-S01 and still applies at W17-S02..S11 including the money-movement
-- step W17-S07, where it now passes on the refund_id the run itself created -- resolved by part 1.
--
-- ROLLBACK: scripts/sql/down/phase_d_k07_the_run_could_not_see_the_object_it_had_just_created_down.sql
-- re-applies the previous bodies of fn_phase_d_step_context and fn_phase_d_gate_applies.
--
-- GENERATED from the live bodies by scripts/tmp_diag/gen_k07.mjs.
`;

// ---- 1. the run's own output, narrowed to the object's OWN relation -----------------------------
const ctxLive = await liveBody('fn_phase_d_step_context');
if (!ctxLive.includes('K07. THE OBJECT THIS RUN ALREADY CREATED')) {
  throw new Error('fn_phase_d_step_context does not carry the K07 block; regenerate part 1 first');
}
const ctx = ctxLive.includes('bb.canonical_relation') && ctxLive.includes('el.effect_relation') ? ctxLive : splice(ctxLive, [
  [`          from public.phase_d_effect_ledger el
         where el.run_id = sr.run_id
           and el.effect_object_id = v_key_obj
           and coalesce(btrim(el.result_reference),'') <> ''
           and position('=' in el.result_reference) > 0
         order by el.effect_id desc limit 1;`,
   `          from public.phase_d_effect_ledger el
          join public.phase_d_business_object_binding bb on bb.object_id = el.effect_object_id
         where el.run_id = sr.run_id
           and el.effect_object_id = v_key_obj
           -- AN EFFECT NAMED FOR AN OBJECT IS NOT ALWAYS A REFERENCE TO ONE. phase_d_effect_ledger
           -- records effect_object_id from the step's DECLARED object, so a REVIEW_VERDICT step of
           -- W15 carries effect_object_id quotation_comparison and result_reference
           -- public.review_chain:id=15748 -- the identity of the review, not of the comparison.
           -- Taking it made GATE-018 judge a review row as a comparison and refuse W15-S05 for
           -- 'comparison 15748 does NOT belong to the calling customer', which was true and was
           -- about the wrong row. Only a reference into the object's OWN canonical relation is an
           -- identity of that object.
           and el.effect_relation = bb.canonical_relation
           and coalesce(btrim(el.result_reference),'') <> ''
           and position('=' in el.result_reference) > 0
         order by el.effect_id desc limit 1;`],
]);

// ---- 2. the gate rule, amended for the predicate kind -------------------------------------------
const live = await liveBody('fn_phase_d_gate_applies');
const gate = live.includes('v_predicate') ? live : splice(live, [
  [`        v_subject text; v_producer text;   -- K07`,
   `        v_subject text; v_producer text; v_predicate text;   -- K07`],
  [`  select st.object_id into v_subject
    from public.phase_d_gate_contract gc
    join public.phase_d_fixture_stage st on st.contributes_ref = any(gc.evidence_keys)
   where gc.gate_id = p_gate_id
   limit 1;`,
   `  select st.object_id, gc.predicate_kind into v_subject, v_predicate
    from public.phase_d_gate_contract gc
    join public.phase_d_fixture_stage st on st.contributes_ref = any(gc.evidence_keys)
   where gc.gate_id = p_gate_id
   limit 1;`],
  [`    if v_producer is not null and p_step_id < v_producer then
      applies := false;
      why := format('%s judges %s and %s runs before %s, the step of %s that produces it; the gate '
                 || 'governs its use from the producing step onward, not before it exists',
                    p_gate_id, v_subject, p_step_id, v_producer, s.workflow_id);
      return next; return;
    end if;`,
   `    if v_producer is not null
       and (p_step_id < v_producer
            -- AT the producing step too, but only where the gate's test is the PRESENCE of the
            -- subject's identity. A MEASURED gate is untouched: GATE-015 exists to judge the
            -- creating step, and exempting it there would leave it governing nothing.
            or (p_step_id = v_producer and v_predicate = 'EVIDENCE_REQUIRED')) then
      applies := false;
      why := format('%s judges %s and %s runs %s %s, the step of %s that produces it; the gate '
                 || 'governs its use %s, not before it exists',
                    p_gate_id, v_subject, p_step_id,
                    case when p_step_id = v_producer then 'at' else 'before' end,
                    v_producer, s.workflow_id,
                    case when v_predicate = 'EVIDENCE_REQUIRED'
                         then 'after the producing step' else 'from the producing step onward' end);
      return next; return;
    end if;`],
]);

writeFileSync('scripts/sql/phase_d_k07_the_run_could_not_see_the_object_it_had_just_created.sql',
  HEADER + ctx + ';\n\n' + gate + ';\n');
console.log('written');
