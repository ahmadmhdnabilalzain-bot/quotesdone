-- Q05. THREE COVERAGE CLAIMS THAT BROKE THE PARSER THAT READS THEM.
--
-- NO TRANSACTION CONTROL. One implicit transaction under a simple-query batch; rehearsable.
--
-- phase_d_q03 wrote prose into `public.phase_c_source_cutover.disposition_evidence`. That column is
-- not prose. `fn_kernel_cutover_measure` parses it as `<kind>:<ref>`:
--
--   split_part(disposition_evidence, ':', 1)  ->  ev_kind    retired | read_only | inactive
--                                                            | routine | trigger
--   split_part(disposition_evidence, ':', 2)  ->  ev_ref     the routine or trigger name
--
-- and a `routine:` claim is only honoured when that routine exists AND reaches a kernel door.
-- Two boards read it, and both went red:
--
--   fn_kernel_cutover_measure.coverage_claims_with_nothing_behind_them   0 -> 2
--   fn_kernel_cutover_measure.active_sources_bypassing_the_kernel        1 -> 3
--
-- Q03 broke three rows:
--
--   edge:customer_api      `routine:trg_inquiry_received` became
--   edge:inquiry_intake    `routine:trg_inquiry_received; routine:trg_customer_registered_kernel`.
--                          split_part(…,':',2) reads `trg_inquiry_received; routine`, which is not
--                          a routine, so a claim that was TRUE and PROVEN became a claim with
--                          nothing behind it. The second fact is true and belongs in
--                          `cutover_action`, which is prose and where Q03 also wrote it — this file
--                          leaves that sentence exactly where it is and takes it out of the column
--                          a machine reads.
--
--   edge:drawing_redact    `routine:none — no adapter, by classification`. `none` is not a routine.
--                          The row is class C READ_ONLY_MONITOR and the parser has a kind for
--                          exactly that: `read_only`. A class C row judged `read_only` is
--                          READ_ONLY and is out of the bypass population, which is the correct
--                          answer for a function that writes one derived provenance record and
--                          starts no work.
--
-- THIS IS NOT A RELAXATION. Not one predicate of `fn_kernel_cutover_measure` changes; the rows it
-- reads are corrected to the shape it has always required. After this file both boards agree with
-- `fn_kernel_trigger_state`, which is the disagreement
-- docs/phase-d/PHASE_D_AUTONOMOUS_SOURCE_BYPASS_TABLE.md finding F5 recorded.
--
-- THE LESSON, WRITTEN DOWN WHERE THE NEXT SESSION WILL SEE IT: `disposition_evidence` is a KEYED
-- FIELD and `cutover_action` is the prose one. Appending to the first reads as editing a document
-- and is editing a machine's input.
--
-- ROLLBACK: scripts/sql/down/phase_d_q05_three_coverage_claims_that_broke_the_parser_that_reads_them_down.sql
-- restores the three strings Q03 left. Applying it turns both boards red again.

-- ------------------------------------------------------------------------------------------------
-- 1. The two rows whose true, proven claim was broken by having a second true fact appended.

UPDATE public.phase_c_source_cutover
   SET disposition_evidence = 'routine:trg_inquiry_received'
 WHERE source_component_id = 'edge:customer_api';

-- edge:inquiry_intake IS THE ORIGINAL BYPASS OF ONE, and this is where it closes.
--
-- Its disposition_evidence has never been machine-readable. It read
--   'measured 2026-08-18: writes public.inquiry_intake (a draft table with no triggers) and
--    public.customers (a work table with no kernel discharge). ...'
-- so split_part(...,':',1) returned 'measured 2026-08-18', which is not one of the five kinds, so
-- the row fell through to the bypass count. That is exactly why fn_kernel_cutover_measure read
--   active_sources_bypassing_the_kernel = 1 [edge:inquiry_intake]
-- and it was RIGHT: the sentence says the customers write had no kernel discharge, and it did not.
--
-- It does now. z50_customer_registered_kernel_emit on public.customers discharges it for this
-- function and for the other ten that write that table. The claim is written in the shape the
-- parser requires -- kind 'trigger', whose ev_routine resolves through pg_trigger to
-- trg_customer_registered_kernel, which is a kernel caller -- and the measurement that used to sit
-- in this column is moved verbatim into cutover_action, which is the prose one, so nothing is lost.
UPDATE public.phase_c_source_cutover
   SET cutover_action = cutover_action
         || E'\n\nMEASURED 2026-08-18, moved here verbatim by phase_d_q05 out of '
         || 'disposition_evidence, which is a keyed field and not prose: "writes '
         || 'public.inquiry_intake (a draft table with no triggers) and public.customers (a work '
         || 'table with no kernel discharge). The previous claim, routine:trg_inquiry_received, '
         || 'names a trigger on public.inquiries, which this function never references in code - '
         || 'only in two comments. Wiring is owed through W04 customer.registered, which has an '
         || 'adapter and no live sender." That wiring is what phase_d_q03 built.',
       disposition_evidence = 'trigger:z50_customer_registered_kernel_emit'
 WHERE source_component_id = 'edge:inquiry_intake';

-- ------------------------------------------------------------------------------------------------
-- 2. The class C row that claimed a routine in order to say it has none.

UPDATE public.phase_c_source_cutover
   SET disposition_evidence =
         'read_only:public.drawing_redaction_runs — one bounded INSERT of a derived provenance '
         || 'record plus storage objects. No work table, no workflow, no task. The business event on '
         || 'this path is the document arriving, carried by customer.document_uploaded from '
         || 'edge:attach_photos and edge:customer_documents; a second emit here would open a second '
         || 'W07 run for one upload.'
 WHERE source_component_id = 'edge:drawing_redact';

-- ------------------------------------------------------------------------------------------------
-- 3. ASSERTIONS. Counted from the boards themselves, not from this file's intentions.

DO $assert$
DECLARE
  v_claims  text;
  v_bypass  text;
  v_red     int;
BEGIN
  SELECT actual INTO v_claims FROM public.fn_kernel_cutover_measure()
   WHERE check_name = 'coverage_claims_with_nothing_behind_them';
  SELECT actual INTO v_bypass FROM public.fn_kernel_cutover_measure()
   WHERE check_name = 'active_sources_bypassing_the_kernel';
  SELECT count(*) INTO v_red FROM public.fn_kernel_cutover_measure() WHERE NOT ok;

  IF v_claims IS DISTINCT FROM '0' THEN
    RAISE EXCEPTION 'Q05: coverage_claims_with_nothing_behind_them reads %L, expected 0', v_claims
      USING errcode = '23514';
  END IF;

  -- The bypass count is REPORTED, not asserted to a literal: an expectation typed into the check it
  -- guards is a defect this estate has already paid for. What is asserted is that this file left no
  -- red row on the board it repaired.
  IF v_red <> 0 THEN
    RAISE EXCEPTION 'Q05: fn_kernel_cutover_measure still has % red row(s)', v_red
      USING errcode = '23514';
  END IF;

  RAISE NOTICE 'Q05 OK: coverage claims with nothing behind them 0; active sources bypassing the '
    'kernel %; fn_kernel_cutover_measure 0 red', v_bypass;
END $assert$;
