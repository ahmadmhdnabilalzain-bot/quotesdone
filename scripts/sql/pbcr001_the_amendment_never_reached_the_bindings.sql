-- ============================================================================================
-- PBCR-001 REACHED PHASE B AND STOPPED THERE
--
-- 17 Aug 2026, PBCR-001 moved W14-S05 accountability from the relevant_category_overlay
-- placeholder to the canonical role quote_evaluation. Two handoffs were DELETED as a consequence,
-- because both of their ends became the same role and a role cannot hand off to itself:
--
--     H-W14-04-05   quote_evaluation        -> relevant_category_overlay
--     H-W14-05-06   relevant_category_overlay -> quote_evaluation
--
-- phase_b_handoff went 161 -> 159. public.phase_c_handoff_binding did not. It still holds 161 rows,
-- and the two extra ones are those handoffs, still carrying connection_status = 'CONNECTED' and
-- still naming relevant_category_overlay as a sending and receiving role — the exact authority the
-- amendment removed.
--
-- WHY NOTHING CAUGHT IT. fn_phase_c_invariants carried the check
--
--     check_name := 'handoffs_bound'; expected := '161';
--
-- with the pre-amendment number typed in as its own expectation. It compared 161 against 161 and
-- reported ok. An approved amendment moved the architecture and the check kept measuring the
-- architecture as it was before. kernel_k5c_invariant_reads_the_new_types.sql now derives that
-- expectation — and the ten others of the same shape — from the registry that owns it, so the next
-- approved amendment propagates instead of being contradicted in silence.
--
-- SEVERITY, MEASURED RATHER THAN ASSUMED. fn_phase_c_handoff_open reads phase_b_handoff as its
-- authority and returns unknown_handoff for a handoff that is not there. Driven in an aborted
-- transaction during the acceptance audit, both orphans refused:
--
--     fn_phase_c_handoff_open(1,'H-W14-04-05',...) -> {"ok": false, "error": "unknown_handoff"}
--     fn_phase_c_handoff_open(1,'H-W14-05-06',...) -> {"ok": false, "error": "unknown_handoff"}
--
-- So this is registry truth, not a live execution defect. It is still a defect: two rows told every
-- reader that a retired overlay authority was CONNECTED.
--
-- THE DELETE IS DERIVED, NOT NAMED. Deleting `where handoff_id in ('H-W14-04-05','H-W14-05-06')`
-- would fix these two and teach the codebase nothing. The predicate below is the invariant itself —
-- a binding whose handoff is not in the frozen registry has nothing to bind to — so it is correct
-- for the next amendment as well, and it is a no-op once the estate is clean.
--
-- phase_c_handoff_binding is a registry table. It is not one of the eight tables carrying
-- z10_kernel_write_guard (those are the runtime tables: kernel_signal_inbox, kernel_trigger_inbox,
-- phase_c_event_outbox, phase_c_handoff_run, phase_c_refund_decision, phase_c_task,
-- phase_c_workflow_run, phase_c_workflow_step_run) and carries no triggers, so this is a plain
-- delete and needs no kernel write authority.
-- ============================================================================================

do $pbcr1$
declare
  v_orphans   bigint;
  v_deleted   bigint;
  v_bindings  bigint;
  v_handoffs  bigint;
begin
  select count(*) into v_orphans
    from public.phase_c_handoff_binding b
   where not exists (select 1 from public.phase_b_handoff h where h.handoff_id = b.handoff_id);

  delete from public.phase_c_handoff_binding b
   where not exists (select 1 from public.phase_b_handoff h where h.handoff_id = b.handoff_id);
  get diagnostics v_deleted = row_count;

  select count(*) into v_bindings from public.phase_c_handoff_binding;
  select count(*) into v_handoffs from public.phase_b_handoff;

  -- The point of the file, asserted rather than described. If the two registries still disagree
  -- after the delete, something else is wrong and this migration must not report success.
  if v_bindings <> v_handoffs then
    raise exception
      'PBCR-001 propagation incomplete: phase_c_handoff_binding has % rows, phase_b_handoff has %. '
      'Orphans found %, deleted %. A binding count that does not equal the frozen handoff count '
      'means a handoff exists with no binding, which is handoffs_without_binding, a different '
      'defect from the one this file repairs.',
      v_bindings, v_handoffs, v_orphans, v_deleted
      using errcode = '23514';
  end if;

  raise notice 'PBCR-001 propagation: % orphan binding(s) found, % deleted. '
               'phase_c_handoff_binding % = phase_b_handoff %.',
               v_orphans, v_deleted, v_bindings, v_handoffs;
end
$pbcr1$;
