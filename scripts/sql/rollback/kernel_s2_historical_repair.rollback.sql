-- ROLLBACK for kernel_s2_historical_repair.sql
--
-- Drops the two views, the invariant and the append-only guard that Section 2 created.
--
-- IT DOES NOT UNDO THE REPAIRS, AND IT DOES NOT DROP THE CLASSIFICATION LEDGER. Both refusals are
-- deliberate, and each one has a reason that is specific rather than general:
--
--   * The two cancelled founder commands (their runs, step runs, tasks, plans and undelivered
--     outbox rows). Un-cancelling them would put the company back to executing one instruction
--     twice — the exact defect — and it would have to invent the state each row was in before, in
--     a table where 'queued' and 'assigned' are not interchangeable. Every one of those closures
--     carries a sealed trace naming the reason and the actor
--     (migration:kernel_s2_historical_repair). If the closure was wrong, the correct answer is a
--     new founder command, not a rewrite of the one that was closed.
--
--   * The seals applied to open traces on terminal subjects. Removing a seal returns those rows
--     to being rewritable in place while presenting as finished work — which is what made them a
--     defect. Each carries an appended evidence_ref keyed 's2_retrofit' saying the seal was
--     applied by this repair and not observed when the subject closed. Nothing recorded was
--     overwritten; only the seal and that note were added. Removing them would delete the note
--     as well as the seal.
--
--   * public.phase_c_historical_repair itself. It is the only place that says WHY 24 historical
--     records are the way they are — which orphan traces were proven unlinkable and on what
--     evidence, which commands were executed twice, which retrofits were made and by whom. A
--     rollback that destroys the explanation is not a rollback, it is an erasure. The DROP TABLE
--     is written below and is commented out on purpose: read the two queries above it first, and
--     if the table really must go, take an export.
--
-- The append-only trigger IS dropped, because leaving a guard behind for a table whose owning
-- migration has been rolled back is how a later session finds a refusal it cannot explain. The
-- table stays readable and stays honest; it just stops being enforced until the migration is
-- re-applied, which re-creates the trigger.

begin;

-- ---- 1. the invariant ----------------------------------------------------------------------
drop function if exists public.fn_kernel_historical_repair_state();

-- ---- 2. the views, after the function that reads them ---------------------------------------
drop view if exists public.v_phase_c_trace_subject;
drop view if exists public.v_phase_c_object_terminal;

-- ---- 3. the append-only enforcement on the ledger --------------------------------------------
drop trigger if exists a00_phase_c_historical_repair_append_only on public.phase_c_historical_repair;
drop function if exists public.fn_phase_c_historical_repair_append_only();

commit;


-- ============================================================================================
-- WHAT WAS DONE, READABLE AFTER THE ROLLBACK. Run these before deciding anything else.
--
--   -- every record Section 2 judged, with the class and the evidence that decided it
--   select entry_kind, record_kind, record_ref, classification, retrofit_label,
--          frozen_state, repair_action, evidence, classified_at
--     from public.phase_c_historical_repair
--    order by entry_kind desc, record_kind, record_ref::bigint;
--
--   -- every trace this repair sealed, with the note it appended
--   select trace_id, subject_kind, subject_ref, status, sealed_at,
--          jsonb_path_query_first(evidence_refs, '$[*] ? (exists(@.s2_retrofit))') as s2_note
--     from public.phase_c_trace
--    where evidence_refs @> '[{"s2_retrofit":"sealed_open_trace_on_terminal_subject"}]'
--    order by trace_id;
--
--   -- every object this repair closed, through the reason recorded on its cancellation trace
--   select trace_id, subject_kind, subject_ref, state_before, state_after, sealed_at
--     from public.phase_c_trace
--    where evidence_refs::text like '%kernel_s2_historical_repair%'
--    order by trace_id;
--
-- DELIBERATELY NOT EXECUTED. Uncomment only with an export in hand and a reason written down.
--   -- drop table public.phase_c_historical_repair;
-- ============================================================================================
