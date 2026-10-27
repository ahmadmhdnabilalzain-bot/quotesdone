-- THE HANDOFF REPLY WINDOWS COME BACK AFTER THE LOOP FILE WAS REAPPLIED (it_engineer, 27 Oct 2026).
-- Seat: it_engineer (release operator).
--
-- MEASURED 27 Oct 2026 (production, read-only audit): at 00:00:35 UTC the release operator re-applied the whole of
-- the_it_engineer_closes_every_loop_it_opens.sql for #1587. Its 34-row seat_handoff_kind upsert (on conflict do update)
-- rewrote reply_within and originator_closes on 15 accountant/sales_engineer kinds back to NULL / false, undoing
-- the_ceo_decides_every_sales_engineer_report_and_every_sender_closes_its_handoff.sql (MANIFEST 1449), the only later
-- file that writes those keys. The 5 rows 1449 changed that the loop file does not carry still read 24 hours / true.
-- This file puts the 15 rows back to 1449's values. meaning, handler and owner_file were not touched by any later file.
-- A count mismatch refuses the whole file (no DDL here, so the raise only protects the restore).
-- Prevented by: the loop file's upserts are made do-nothing in the same PR as its it_new_bug line
-- (the_new_bug_email_stays_off_when_the_loop_file_is_reapplied.sql), and an applied multi-routine file is never re-run.
do $restore$
declare n int;
begin
  update public.seat_handoff_kind k set reply_within = v.win, originator_closes = true
    from (values
      ('refund.requested','sales_engineer','accountant',interval '1 hour'),
      ('billing.question','sales_engineer','accountant',interval '1 hour'),
      ('charge.disputed','sales_engineer','accountant',interval '1 hour'),
      ('reveal.paid','accountant','sales_engineer',interval '24 hours'),
      ('payment.failed','accountant','sales_engineer',interval '24 hours'),
      ('payment.received','accountant','sales_engineer',interval '24 hours'),
      ('refund.request_checked','accountant','sales_engineer',interval '24 hours'),
      ('refund.declined','accountant','sales_engineer',interval '24 hours'),
      ('refund.in_progress','accountant','sales_engineer',interval '24 hours'),
      ('subscription.due','accountant','sales_engineer',interval '24 hours'),
      ('billing.answer','accountant','sales_engineer',interval '24 hours'),
      ('charge.dispute_answer','accountant','sales_engineer',interval '24 hours')
    ) v(type, from_seat, to_seat, win)
   where k.type = v.type and k.from_seat = v.from_seat and k.to_seat = v.to_seat;
  get diagnostics n = row_count;
  if n <> 12 then raise exception 'expected 12 originator-closes rows, found %', n; end if;

  update public.seat_handoff_kind set reply_within = interval '24 hours', originator_closes = false
   where from_seat = 'accountant' and to_seat = 'sales_engineer'
     and type in ('refund.paid','nonresponse.charge_raised','charge.corrected');
  get diagnostics n = row_count;
  if n <> 3 then raise exception 'expected 3 verify-only rows, found %', n; end if;
end
$restore$;

select case when (select count(*) from public.seat_handoff_kind
                   where originator_closes and from_seat in ('accountant','sales_engineer')
                     and to_seat in ('accountant','sales_engineer')) = 17
            then 'PROBE OK: 17 originator-closes accountant/sales_engineer kinds'
            else 'PROBE FAILED: originator-closes count is not 17' end as verdict;
