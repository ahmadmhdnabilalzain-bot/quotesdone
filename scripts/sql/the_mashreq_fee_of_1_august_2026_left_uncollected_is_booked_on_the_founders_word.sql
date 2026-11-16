-- THE MASHREQ FEE OF 1 AUGUST 2026, LEFT UNCOLLECTED BY THE BANK, IS BOOKED ON THE FOUNDER'S WORD.
-- Seat: accountant (agent: L6_BOOKS, accountant seat builder). 16 Nov 2026. Founder rulings 1702 ("bank 210 monthly fee
-- since july") and 1703 ("Mashreq bank / Yes you can"). Data only; needs
-- the_books_hold_a_cost_on_the_founders_word_until_its_document_arrives.sql (live since 15 Nov).
-- DRY RUN FIRST: the_mashreq_fee_of_1_august_2026_left_uncollected_is_booked_on_the_founders_word_dry_run.sql (writes nothing).
-- PROBE AFTER: the_mashreq_fees_of_july_to_november_2026_are_each_in_the_books_once_probe.sql (PROBE OK).
--
-- WHAT THE BOOKS HELD (SELECT 16 Nov 2026). The audit of the open ledger (LEDGER_OPEN #14) read expense_entries only and
-- found "Mashreq only 1 Nov; Jul-Oct not booked". That undercounts: the fees the statements show are booked by
-- fn_accountant_book_bank_charges as 'bank_charge' journals, not expense rows:
--   19 Aug 2026  199.00 + 9.95  statement line 231/232  journals 692/693
--    1 Sep 2026  199.00 + 9.95  statement line 234/233  journals 695/694
--    1 Oct 2026  199.00 + 9.95  statement line 2268/2267  journals 2647/2646
--    1 Nov 2026  199.00 + 9.95  the founder's word (1702), expense 3353/3354, journals 5265/5266, awaiting the statement
-- Four fees in 6300 (835.80). The founder said "since july": July to November is FIVE fees.
--
-- THE FIFTH FEE IS IN A DOCUMENT. The September statement (issued 2 Oct 2026, bank_statement_intake
-- 'chat:mashreq-statement-2026-09 (issued 2026-10-02)') lists AED 208.95 UNCOLLECTED: fee 199 + VAT 9.95 initiated
-- 2026-08-01, 62 days overdue at issue. The accountant filed it on 4 Oct as finding
-- acct:bank_statement_2026_09:uncollected_aug_fee ("not booked until the October statement shows whether it is
-- collected"), and ruling 1559 (no bank-statement reconciliation) closed that finding on 10 Nov without booking the fee.
-- No October statement has arrived. So the bank charged five fees from July, collected four by 2 Oct, and the books hold
-- four: the one the bank charged on 1 Aug and had not yet taken is the gap. The November file's note that "July is not
-- booked, on the evidence" read the August statement's opening balance but not the September statement's uncollected
-- list; its arithmetic is right (no July DEBIT exists), the count of fees is not.
--
-- HOW IT IS BOOKED. Exactly as November: two entries, 199.00 and 9.95, Mashreq, 'Bank charges' -> 6300, dated 1 Aug 2026
-- (the date the bank initiated them), held on ledger 1702 awaiting the bank statement. August 2026 is closed
-- (accountant_month_close), so fn_gl_post books each journal in the open period as a prior-period adjustment
-- (gl_prior_period_adjustment, IFRS for SMEs s.10: an immaterial item is corrected in the current period). When a
-- statement shows the bank taking it, fn_accountant_book_bank_charges attaches that line to the OLDEST held fee of the
-- same amount (this one, before November's) and books no second journal. Credit 1000 like every bank fee: the available
-- balance at 2 Oct was 1,059.25, more than the fee, so the bank most likely took it in October; the statement settles it.
-- The action refuses a second booking (its stated key), so a second apply books nothing.
select public.fn_accountant_expense_on_founder_word('Mashreq', date '2026-08-01', 199.00, 'AED', null, 'Bank charges',
  'Mashreq monthly maintenance fee initiated 1 Aug 2026, listed UNCOLLECTED (62 days overdue) on the September statement issued 2 Oct 2026; the fee is monthly since July (ledger 1702) and the statements show only four of the five July-November fees taken.',
  1702, 'bank_statement', false) as fee;
select public.fn_accountant_expense_on_founder_word('Mashreq', date '2026-08-01', 9.95, 'AED', null, 'Bank charges',
  'Mashreq "Value Added Tax - Output" on the maintenance fee initiated 1 Aug 2026 (5% of 199), listed uncollected on the September statement; a cost because the company is not VAT registered.',
  1702, 'bank_statement', false) as vat;

select case
  when (select count(*) from public.expense_awaiting_document x join public.expense_entries e on e.id = x.expense_entry_id
         where e.vendor = 'Mashreq' and e.charged_on = date '2026-08-01' and x.founder_instruction_id = 1702) <> 2
    then 'PROBE FAILED: expected exactly 2 held Mashreq entries for 1 Aug 2026'
  when exists (select 1 from public.expense_entries e where e.vendor = 'Mashreq' and e.charged_on = date '2026-08-01'
                and (select count(*) from public.gl_journal g where g.source = 'expense' and g.source_ref = e.id::text and g.status = 'posted') <> 1)
    then 'PROBE FAILED: a held 1 Aug 2026 Mashreq entry does not have exactly one posted journal'
  when not exists (select 1 from public.gl_prior_period_adjustment p join public.expense_entries e on p.source = 'expense' and p.source_ref = e.id::text
                    where e.vendor = 'Mashreq' and e.charged_on = date '2026-08-01')
    then 'PROBE FAILED: the 1 Aug 2026 fee was not booked as a prior-period adjustment in the open period'
  else 'PROBE OK: the Mashreq fee initiated 1 Aug 2026 (208.95) is booked to 6300 in the open period and awaits the statement'
end as verdict;
