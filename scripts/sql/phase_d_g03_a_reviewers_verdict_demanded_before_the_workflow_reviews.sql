-- G03 — a reviewer's verdict demanded before the workflow has reviewed anything
--
-- GATE-021 "Marketing artifact approval" (pass_result: "Publish approved revision.") is scoped to
-- W03;W20 and, being scoped to the workflow rather than to a step, applied to W03-S01 "Set
-- acquisition objective" and W20-S01 "Define content objective and hypothesis". GATE-026
-- "Knowledge validation" (pass_result: "Publish runtime-eligible version.") applied to W26-S01
-- "Open knowledge gap or change", an INTAKE step. All three refused for want of a reviewer of
-- something the workflow had not yet produced, and all three were the first refusal of a workflow
-- that then produced no effect at all.
--
-- fn_phase_d_gate_applies already refines exactly this shape twice — GATE-020, which demanded an
-- approved case decision at the step that opens the case, and GATE-015, which refused a workflow
-- for having done its own job one step earlier. This is the third instance, stated as a derived
-- rule rather than a third named exception: a gate whose evidence_keys name reviewer_role_id does
-- not apply to a step that runs before the workflow's first review step.
--
-- The gate still governs W03-S06..S09, W20-S04..S09 and W26-S05..S09 — the artifact, the review
-- and the publication — and still refuses there without a recorded reviewer.
--
-- One anchor, required to match exactly once. The rest of the routine is byte-identical.
CREATE OR REPLACE FUNCTION public.fn_phase_d_gate_applies(p_gate_id text, p_step_id text)
 RETURNS TABLE(applies boolean, why text)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare g public.phase_b_gate%rowtype; s public.phase_b_workflow_step%rowtype;
begin
  select * into g from public.phase_b_gate where gate_id = p_gate_id;
  if not found then applies := false; why := format('unknown gate %s', p_gate_id); return next; return; end if;
  select * into s from public.phase_b_workflow_step where step_id = p_step_id;
  if not found then applies := false; why := format('unknown step %s', p_step_id); return next; return; end if;

  if upper(g.workflow_scope) <> 'ALL'
     and not (s.workflow_id = any (string_to_array(replace(g.workflow_scope,' ',''), ';'))) then
    applies := false;
    why := format('%s is scoped to %s and %s is in %s', g.gate_id, g.workflow_scope, p_step_id, s.workflow_id);
    return next; return;
  end if;

  if p_gate_id = 'GATE-004' and coalesce(btrim(s.independent_reviewer_role_id),'') = '' then
    applies := false;
    why := format('GATE-004 governs the independence of a named reviewer and %s names none', p_step_id);
    return next; return;
  end if;

  if p_gate_id = 'GATE-005' and lower(coalesce(btrim(s.founder_gate),'none')) = 'none' then
    applies := false;
    why := format('GATE-005 governs a founder-reserved decision and %s declares founder_gate none', p_step_id);
    return next; return;
  end if;

  -- GATE-020 — "Refund authority and idempotency", pass_result "Execute once". It guards the money
  -- movement, and the frozen registry names that step by carrying a founder_gate on it and on no
  -- other step of W17: "Money movement beyond approved policy requires founder approval." Demanding
  -- an approved case decision at the step that OPENS the case is a condition the workflow itself is
  -- what satisfies, four steps later. Refund authority is unaffected: it is held by the trigger
  -- z00_refund_founder_decision_only on public.refunds, which raises unless an approved refund was
  -- decided by an active founder identity, on every path, workflow or not.
  -- D28. GATE-015 — "No existing assignment for same supplier, inquiry version and dispatch scope."
  --
  -- It prevents a DUPLICATE dispatch, so it governs every step up to AND INCLUDING the one that
  -- creates the assignment. That is where a duplicate is actually stopped. A step running AFTER the
  -- creating step in the same workflow is premised on the assignment EXISTING: W12-S07 is "Create
  -- exactly one notification per assignment", and refusing it because an assignment exists refuses
  -- the workflow for having done its own job one step earlier.
  --
  -- THIS IS NOT THE WHOLE-WORKFLOW EXEMPTION THAT WAS TRIED AS D17 AND DISCARDED. GATE-015 is
  -- scoped to W12 alone, so exempting W12 would leave it governing nothing — the session brief says
  -- exactly that and it is right. This exempts only the steps that come after the assignment has
  -- been legitimately created, and the gate still governs W12-S01 through S06, the creating step
  -- included. Its purpose survives intact.
  --
  -- THE PRODUCING STEP IS DERIVED, NEVER NAMED HERE. The object the gate measures is resolved by
  -- matching the gate contract's own evidence_source against the canonical relation of the object,
  -- and the producing step is then read from phase_d_step_effect. Renaming a step or moving the
  -- effect moves this with it.
  --
  -- The same shape as the GATE-020 refinement immediately below, which the estate already accepted:
  -- a condition that the workflow itself is what satisfies, demanded before the workflow satisfies it.
  if p_gate_id = 'GATE-015'
     and exists (
       select 1
         from public.phase_d_step_effect e
         join public.phase_d_business_object_binding bb on bb.object_id = e.effect_object_id
         join public.phase_d_gate_contract gc on gc.gate_id = p_gate_id
        where e.workflow_id = s.workflow_id
          and e.step_id < p_step_id
          and bb.canonical_relation is not null
          and gc.evidence_source ilike '%' || bb.canonical_relation || '%')
  then
    applies := false;
    why := format('GATE-015 stops a DUPLICATE dispatch, so it governs up to and including the step that creates the assignment; %s runs after it and is premised on the assignment existing', p_step_id);
    return next; return;
  end if;

  if p_gate_id = 'GATE-020' and lower(coalesce(btrim(s.founder_gate),'none')) = 'none' then
    applies := false;
    why := format('GATE-020 guards the execution of an approved financial action; %s declares founder_gate none and is not the money-movement step', p_step_id);
    return next; return;
  end if;

  if p_gate_id = 'GATE-007'
     and not exists (select 1 from public.phase_b_handoff h where h.from_step_id = p_step_id) then
    applies := false;
    why := format('GATE-007 governs a handoff packet and %s opens no handoff', p_step_id);
    return next; return;
  end if;

  if p_gate_id = 'GATE-008' and not coalesce(s.is_closure_step, false) then
    applies := false;
    why := format('GATE-008 is a closure gate and %s is not the closure step', p_step_id);
    return next; return;
  end if;

  -- G03. A GATE THAT DEMANDS A REVIEWER'S VERDICT AT A STEP THAT RUNS BEFORE ANY REVIEW.
  --
  -- Measured, on the three gates whose evidence_keys name reviewer_role_id:
  --
  --   GATE-021 "Marketing artifact approval", pass_result "Publish approved revision.", scope W03;W20
  --            refused W03-S01 "Set acquisition objective" and W20-S01 "Define content objective
  --            and hypothesis" for want of the reviewer of a final asset the workflow has not yet
  --            produced. W03 first reviews at S06; W20 at S04.
  --   GATE-026 "Knowledge validation", pass_result "Publish runtime-eligible version.", scope W26
  --            refused W26-S01 "Open knowledge gap or change", an INTAKE step. W26 first reviews
  --            at S05.
  --
  -- Both are the shape this function already refines twice. GATE-020 was narrowed because it
  -- demanded an approved case decision at the step that OPENS the case; GATE-015 because it
  -- refused a workflow for having done its own job one step earlier. This is the same sentence:
  -- a condition that the workflow itself is what satisfies, demanded before the workflow
  -- satisfies it.
  --
  -- NOTHING IS WEAKENED. The gate still applies from the workflow's first review step to its last
  -- step, which is where the artifact exists, where the review happens, and where publication is
  -- decided -- W03-S06..S09, W20-S04..S09, W26-S05..S09. A step at or after that point with no
  -- recorded reviewer still refuses.
  --
  -- NO GATE AND NO STEP IS NAMED. The condition is derived: the gate's own evidence_keys carry
  -- reviewer_role_id, and the frozen registry says which of this workflow's steps are reviews.
  -- A workflow with no review step at all is untouched -- there is no point before which to be
  -- early -- and GATE-004 keeps its own, narrower, earlier exemption.
  if exists (select 1 from public.phase_d_gate_contract gc
              where gc.gate_id = p_gate_id
                and 'reviewer_role_id' = any(gc.evidence_keys))
     and p_step_id < (select min(rs.step_id) from public.phase_b_workflow_step rs
                       where rs.workflow_id = s.workflow_id and rs.step_type = 'review')
  then
    applies := false;
    why := format('%s requires an independent reviewer''s verdict and %s runs before %s, the first review step of %s; the review this gate reads is produced by the workflow itself, later',
                  p_gate_id, p_step_id,
                  (select min(rs.step_id) from public.phase_b_workflow_step rs
                    where rs.workflow_id = s.workflow_id and rs.step_type = 'review'),
                  s.workflow_id);
    return next; return;
  end if;

  applies := true;
  why := format('%s (%s, scope %s) applies to %s', g.gate_id, g.gate_type, g.workflow_scope, p_step_id);
  return next;
end $function$

