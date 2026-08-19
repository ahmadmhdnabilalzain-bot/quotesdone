-- =================================================================================================
-- Phase D — D13. A refund gate that fired before the case was even opened.
--
-- W17 stopped at its FIRST step with:
--
--   GATE-020: refund 117 has no recorded founder decision  (gate020_refund_unauthorised)
--
-- and it was reported as a blocker only the founder could clear. It is not. It is scope treated as
-- applicability — the third instance of that exact shape in Phase D, after BR-002 and GATE-004.
--
-- WHAT GATE-020 ITSELF SAYS, from the frozen registry:
--
--   gate_name         Refund authority and idempotency
--   required_evidence Approved case decision and unique financial action key exist.
--   pass_result       Execute once.
--   fail_result       Block/return existing.
--
-- "Execute once" guards an EXECUTION. "Approved case decision" is the artefact W17-S06 exists to
-- produce. But the Phase D contract scoped the gate to the WORKFLOW, so `fn_phase_d_gate_applies`
-- returned true for all ELEVEN steps — including W17-S01, which merely opens the case, before
-- evidence is collected (S03), before fraud review (S04), before legal review (S05), and before the
-- decision step that produces the very evidence being demanded.
--
-- Requiring an approved decision at intake is a condition the workflow cannot satisfy, because the
-- workflow is what produces it. A gate that cannot be satisfied is not a strict gate; it is a wall.
--
-- WHERE THE FROZEN MODEL SAYS IT BELONGS, AND IT IS NOT A JUDGEMENT CALL:
-- exactly one of W17's eleven steps carries a `founder_gate` that is not 'none' —
--
--   W17-S07  Execute approved financial action
--            founder_gate: "Money movement beyond approved policy requires founder approval."
--
-- That is the frozen registry naming the step where refund authority applies, and it says *beyond
-- approved policy*. The Terms of Service v6 §5 set the policy: the Reveal Fee is not automatically
-- refundable, there is no self-service refund, a complaint must be raised within seven days, and a
-- refund is due only if the supplier fails to respond to both parties within three working days.
-- Entitlement is determined by those terms; it is money movement beyond them that needs the founder.
--
-- `fn_phase_d_gate_applies` ALREADY refines GATE-005 on this same column, along with GATE-004 on
-- `independent_reviewer_role_id`, GATE-007 on whether the step opens a handoff, and GATE-008 on
-- `is_closure_step`. GATE-020 gets the same treatment, derived the same way, from the same frozen
-- fact. Nothing is matched on prose.
--
-- THIS DOES NOT WEAKEN REFUND AUTHORITY BY ONE INCH, and the reason is that the authority was never
-- GATE-020's to hold. `z00_refund_founder_decision_only` is a trigger on `public.refunds` that
-- RAISES unless a refund reaching status 'approved' was `decided_by` an active founder identity in
-- `phase_c_founder_identity`. It fires on the row, on every path, whether or not any workflow runs.
-- The founder's standing rule — every refund needs him, at any amount — is enforced there, as a
-- mechanism rather than a convention, and this file does not touch it.
--
-- After this change GATE-020 still hard-blocks W17-S07 without an approved case decision and a
-- unique financial action key. It simply stops demanding them from the step that opens the case.
-- =================================================================================================

begin;

create or replace function public.fn_phase_d_gate_applies(p_gate_id text, p_step_id text)
returns table(applies boolean, why text)
language plpgsql stable
set search_path to 'public', 'pg_temp'
as $fn$
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

  applies := true;
  why := format('%s (%s, scope %s) applies to %s', g.gate_id, g.gate_type, g.workflow_scope, p_step_id);
  return next;
end $fn$;

-- ---- positive controls, on this deployment --------------------------------------------------------
-- A gate that was just narrowed has to be shown still refusing where it matters. Zero cannot tell a
-- dead guard from an idle system, so the guard is made to fire.

do $ctl$
declare v record; v_n int;
begin
  -- IT MUST STILL APPLY TO THE MONEY MOVEMENT.
  select * into v from public.fn_phase_d_gate_applies('GATE-020','W17-S07');
  if not v.applies then
    raise exception 'D13 control FAILED: GATE-020 no longer applies to W17-S07, the step that executes the financial action — that is a hole, not a fix';
  end if;

  -- AND IT MUST STILL BLOCK THERE WITH NO EVIDENCE.
  declare ge record;
  begin
    select * into ge from public.fn_phase_d_gate_evaluate('GATE-020','{}'::jsonb);
    if coalesce(ge.passed,false) then
      raise exception 'D13 control FAILED: GATE-020 passes with no evidence at all';
    end if;
  end;

  -- It must NOT apply to the step that opens the case.
  select * into v from public.fn_phase_d_gate_applies('GATE-020','W17-S01');
  if v.applies then
    raise exception 'D13 control FAILED: GATE-020 still demands an approved decision at W17-S01, which opens the case';
  end if;

  -- Exactly one step of W17 carries it, and it is the one the frozen registry gates.
  select count(*) into v_n from public.phase_b_workflow_step s,
       lateral public.fn_phase_d_gate_applies('GATE-020', s.step_id) a
   where s.workflow_id = 'W17' and a.applies;
  if v_n <> 1 then
    raise exception 'D13 control FAILED: GATE-020 applies to % step(s) of W17; the frozen registry carries a founder_gate on exactly one', v_n;
  end if;

  -- The founder rule this gate was wrongly carrying must still be enforced where it really lives.
  if not exists (select 1 from pg_trigger t join pg_proc p on p.oid = t.tgfoid
                  where t.tgrelid = 'public.refunds'::regclass and not t.tgisinternal
                    and p.proname = 'fn_refund_founder_decision_only') then
    raise exception 'D13 control FAILED: z00_refund_founder_decision_only is not on public.refunds — refund authority would rest on nothing';
  end if;

  raise notice 'D13: GATE-020 applies to 1 of 11 W17 steps (W17-S07), still blocks on empty evidence, and the founder trigger is intact.';
end $ctl$;

commit;
