-- M09 — the seventeenth disposition
--
-- PD-STATE-003 came back from its own execution as NOT_DISCRIMINATED rather than closed, and the
-- register is what makes that a decision rather than a gap. M08's header states the measurement;
-- this states it where fn_phase_d_disposition_state() and the deliverable builder can both see it.
insert into public.phase_d_injected_defect_disposition
  (defect_id, category, disposition, reason, what_would_make_it_executable)
values
  ('PD-STATE-003', 'STATE', 'PERMANENT_EXEMPTION',
   'The injection has an empty population. Measured 24 Aug 2026: 0 of the 257 frozen steps in public.phase_b_workflow_step state their terminality inconsistently — (next_step_if_pass = ''WORKFLOW_COMPLETE'') = is_closure_step holds on every row — so there is no nonterminal step in the estate that any caller could present to the kernel as a closure step, and fn_kernel_step_successor''s closure_flag_disagrees branch cannot be reached with real data. Creating one means editing phase_b_workflow_step, which trigger z90_phase_b_freeze refuses without a Phase B change request. The re-scoped arms that CAN be driven were driven, in the same transaction as PD-STATE-002 and on the same W04 run — completing the non-closure step W04-S06 returned successor kind same_owner and the kernel opened one, and the closure step returned kind closure and opened none — but both are VALID inputs observing no refusal, so recording them as REFUSED_AS_REQUIRED would be a green number measuring something other than what this row names.',
   'A Phase B change request seeding one deliberately inconsistent step — a step whose next_step_if_pass is WORKFLOW_COMPLETE while is_closure_step is false, or the reverse — so that fn_kernel_step_successor has a real row to return closure_flag_disagrees for and fn_kernel_step_complete a real k3_no_valid_successor to raise. That is a frozen-registry edit and the founder''s call, not this session''s.')
on conflict (defect_id) do update
   set category = excluded.category, disposition = excluded.disposition,
       reason = excluded.reason,
       what_would_make_it_executable = excluded.what_would_make_it_executable,
       decided_at = now();
