-- Q05 DOWN. RESTORE THE THREE disposition_evidence STRINGS phase_d_q03 LEFT.
--
-- NO TRANSACTION CONTROL. Three statements.
--
-- Read out of production before Q05 ran. APPLYING THIS TURNS BOTH BOARDS RED AGAIN:
--
--   fn_kernel_cutover_measure.coverage_claims_with_nothing_behind_them   0 -> 2
--   fn_kernel_cutover_measure.active_sources_bypassing_the_kernel        0 -> 3
--
-- because two of the three strings are unparseable by the routine that reads them and the third
-- claims a routine called `none`. It exists so Q05 is reversible, not because reverting is
-- advisable.
--
-- edge:inquiry_intake's cutover_action keeps the sentence Q05 moved into it. Removing it would make
-- the reversal look like the measurement of 18 Aug was never taken, and it was.

UPDATE public.phase_c_source_cutover
   SET disposition_evidence = 'routine:trg_inquiry_received; routine:trg_customer_registered_kernel'
 WHERE source_component_id = 'edge:customer_api';

UPDATE public.phase_c_source_cutover
   SET disposition_evidence =
         'measured 2026-08-18: writes public.inquiry_intake (a draft table with no triggers) and '
         || 'public.customers (a work table with no kernel discharge). The previous claim, '
         || 'routine:trg_inquiry_received, names a trigger on public.inquiries, which this function '
         || 'never references in code — only in two comments. Wiring is owed through W04 '
         || 'customer.registered, which has an adapter and no live sender.'
         || '; routine:trg_customer_registered_kernel'
 WHERE source_component_id = 'edge:inquiry_intake';

UPDATE public.phase_c_source_cutover
   SET disposition_evidence = 'routine:none — no adapter, by classification'
 WHERE source_component_id = 'edge:drawing_redact';
