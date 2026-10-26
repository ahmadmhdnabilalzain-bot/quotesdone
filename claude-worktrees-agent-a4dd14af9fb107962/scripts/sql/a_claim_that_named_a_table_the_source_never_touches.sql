-- ============================================================================================
-- A CLAIM THAT NAMED A TABLE THE SOURCE NEVER TOUCHES
--
-- public.phase_c_source_cutover recorded, for edge:inquiry_intake:
--
--     status               COVERED_BY_A_CUT_OVER_TABLE_TRIGGER
--     disposition_evidence routine:trg_inquiry_received
--
-- trg_inquiry_received is the trigger on public.inquiries. supabase/functions/inquiry_intake/
-- index.ts writes public.inquiry_intake — a draft table carrying NO triggers at all — and
-- public.customers. It never references `inquiries` in code; the only two occurrences in the whole
-- file are inside `//` comments.
--
-- So the discharge claim named a path this source does not take, and
-- fn_kernel_cutover_measure.coverage_claims_with_nothing_behind_them reported 0 the entire time.
-- That check resolves the named routine and verifies it reaches the kernel — the FAR end of the
-- chain. It never asks whether the source reaches the routine, which is the near end.
--
-- WHAT THIS SOURCE ACTUALLY DOES. It writes public.customers, and customers is on the estate's own
-- work-table list (phase_b_business_object.customer_account, governed by W04). No trigger on
-- customers reaches the kernel: fn_emit_customer_registered calls fn_emit, the legacy event bus,
-- not fn_kernel_source_emit. Measured by execution in an aborted transaction — inserting a customer
-- moved phase_c_workflow_run 18 -> 18 and phase_c_task 52 -> 52. W04 has 0 runs, ever.
--
-- THIS MAKES A GREEN NUMBER GO RED, AND THAT IS THE POINT.
-- fn_kernel_cutover_measure.active_sources_bypassing_the_kernel moves 0 -> 1, because the old zero
-- rested on a claim with nothing behind it. A fix that makes a check harder because the previous
-- pass was false is the correct outcome, and it is recorded here rather than smoothed over.
--
-- WHAT THIS FILE DOES NOT DO. It does not wire W04. Doing that means reclassifying
-- dbtrigger:public.customers:trg_emit_customer_registered, which the estate has deliberately
-- recorded as NOT_A_BUSINESS_TRIGGER, adding a row to the source register, and amending
-- kernel_trigger_type.customer.registered.allowed_source_systems — after which every customer
-- signup opens a W04 onboarding run with an accountable owner and an SLA. That is an architecture
-- and operating decision for the founder, not a wiring fix, and overriding a recorded disposition
-- to move a gate is the one thing this audit refused throughout.
-- ============================================================================================

do $ii$
declare v_before text; v_rows bigint;
begin
  select status || ' / ' || coalesce(disposition_evidence,'(none)') into v_before
    from public.phase_c_source_cutover where source_component_id = 'edge:inquiry_intake';

  if v_before is null then
    raise exception 'edge:inquiry_intake is not in phase_c_source_cutover; this file has no subject'
      using errcode = '23503';
  end if;

  update public.phase_c_source_cutover
     set status = 'NOT_DISCHARGED_WIRING_OWED',
         disposition_evidence =
           'measured 2026-08-18: writes public.inquiry_intake (a draft table with no triggers) and '
           || 'public.customers (a work table with no kernel discharge). The previous claim, '
           || 'routine:trg_inquiry_received, names a trigger on public.inquiries, which this '
           || 'function never references in code — only in two comments. Wiring is owed through '
           || 'W04 customer.registered, which has an adapter and no live sender.',
         classification_reason = coalesce(classification_reason,'')
           || ' | 2026-08-18 final acceptance: coverage claim corrected. It named a table the source '
           || 'does not touch, so active_sources_bypassing_the_kernel was 0 on a false basis.'
   where source_component_id = 'edge:inquiry_intake';
  get diagnostics v_rows = row_count;

  if v_rows <> 1 then
    raise exception 'expected to correct exactly 1 row, corrected %', v_rows using errcode = '23514';
  end if;

  raise notice 'edge:inquiry_intake was [%]; now NOT_DISCHARGED_WIRING_OWED. '
               'fn_kernel_cutover_measure.active_sources_bypassing_the_kernel will read 1, not 0.',
               v_before;
end
$ii$;
