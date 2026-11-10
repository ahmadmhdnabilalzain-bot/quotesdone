-- PROBE (pure, no DDL, aborted transaction) for the_month_closes_on_the_books_and_the_recorded_month_end_email_scan.sql.
-- Seat: accountant. Run AFTER the definition in the same transaction; it ends in raise exception, so nothing survives
-- (the October close it makes, its CEO report, its pack and the scan rows all roll back).
--   1. October's status is 'due' (it was 'waiting_for_statement'), and the close tick closes it on the books;
--   2. the founder's close pack for October builds from the closed month, with the book cash and the receipts section;
--   3. a recorded scan moves the due date to two days after it, and a "booked" count the books do not hold is refused.
do $p$
declare v_before jsonb; v_tick jsonb; v_after jsonb; v_pack jsonb; v_fig jsonb; v_doc jsonb; v_refused text; v_rec jsonb; v_s jsonb; v_ok boolean;
begin
  v_before := public.fn_accountant_month_close_status(date '2026-10-01');
  v_tick := public.fn_accountant_month_close_tick();
  v_after := public.fn_accountant_month_close_status(date '2026-10-01');
  v_pack := public.fn_accountant_founder_close_pack_build(date '2026-10-01');
  v_fig := public.fn_accountant_founder_close_pack_figures(date '2026-10-01');
  select figures into v_doc from public.accountant_founder_close_pack where month = date '2026-10-01';
  v_doc := public.fn_accountant_founder_close_pack_document(date '2026-10-01');
  begin
    perform public.fn_accountant_month_scan_record(date '2026-11-01', now() - interval '1 hour', array['management@quotesdone.com'], 5, 5, '[]'::jsonb, 'probe');
  exception when others then v_refused := sqlerrm; end;
  v_rec := public.fn_accountant_month_scan_record(date '2026-11-01', now() - interval '1 hour', array['management@quotesdone.com'], 1, 0,
             '[{"what": "probe receipt", "why": "the attachment could not be read"}]'::jsonb, 'probe');
  v_s := public.fn_accountant_month_close_status(date '2026-11-01', date '2026-12-06');
  -- 10 Nov 2026 (it_engineer): October was really closed on the books at 10:15Z the day this file was applied, so before
  -- reads 'closed' (with its closed_at) from then on, and the tick has nothing left to close. Either state is right; what
  -- must never come back is 'waiting_for_statement'.
  v_ok := (v_before->>'status' = 'due' or (v_before->>'status' = 'closed' and v_before->>'closed_at' is not null))
          and v_after->>'status' = 'closed' and v_fig->'bank'->>'status' = 'book balance'
          and v_fig ? 'receipts' and v_refused like '%no figure without a source row%' and (v_s->'scan'->>'asked')::boolean
          and v_doc::text not like '%Mashreq statement%';
  raise exception '% CHK<<%>>', case when v_ok then 'PROBE OK' else 'PROBE FAILED' end, jsonb_build_object(
    'october_before', v_before - 'scan', 'tick_closed', v_tick->'closed', 'october_after', v_after->>'status', 'late', v_after->'late',
    'pack_built', v_pack is not null, 'book_cash', v_fig->'bank', 'receipts', jsonb_build_object('expenses_in_month', v_fig#>'{receipts,expenses_in_month}',
    'without_receipt_document', jsonb_array_length(v_fig#>'{receipts,without_receipt_document}'), 'scan', v_fig#>'{receipts,scan}'),
    'unusual_items', v_fig->'unusual_items', 'overclaim_refused', v_refused, 'scan_recorded', v_rec, 'november_due_by_with_scan', v_s->'due_by');
end $p$;
