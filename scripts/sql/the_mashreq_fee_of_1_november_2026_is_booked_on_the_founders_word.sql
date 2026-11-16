-- THE MASHREQ FEE OF 1 NOVEMBER 2026 IS BOOKED ON THE FOUNDER'S WORD, AWAITING THE STATEMENT.
-- Seat: accountant (agent: accountant seat builder). 15 Nov 2026. Founder rulings 1702 ("bank 210 monthly fee since july")
-- and 1703 ("Mashreq bank / Yes you can"). Data only; needs the_books_hold_a_cost_on_the_founders_word_until_its_document_arrives.sql.
-- DRY RUN FIRST: the_mashreq_fee_of_1_november_2026_is_booked_on_the_founders_word_dry_run.sql (writes nothing).
--
-- WHAT THE STATEMENTS SHOW (SELECT 15 Nov 2026, bank_statement_line, account mashreq)
--   August statement: opening 0.00; 19 Aug owner transfer 1,000; 19 Aug fee 199 + 9.95 "Value Added Tax - Output".
--   September statement (issued 2 Oct): 1 Sep fee pair, 1 Oct fee pair. The fee is charged on the 1st of the month.
--   No statement after the one issued 2 Oct has been received, so the 1 Nov fee pair is in no document yet. Booked here.
--
-- JULY IS NOT BOOKED, ON THE EVIDENCE. The August statement OPENS AT 0.00 and its first fee is 19 Aug, the day the
-- founder's first AED 1,000 arrived; the founder said on 9 Sep (memory: the bank is Mashreq) "so far they deducted that
-- twice" (19 Aug and 1 Sep). A July debit would have made August open at -208.95. So the fee "since July" is the July
-- month charged on 19 Aug, when the account first held money, and it is already in the books (journals 692/693). Booking a
-- separate July fee would put AED 208.95 in the books that the bank never took. If a July statement ever shows a July
-- debit, fn_accountant_expense_on_founder_word books it the same way (awaits bank_statement) or the statement books it.
--
-- HOW IT IS BOOKED. Two entries, exactly as the bank books them (two statement lines a month), so each later statement line
-- joins its own entry by amount and date (fn_accountant_attach_statement_line) and no second journal is booked:
--   199.00  'Mashreq' Bank charges -> 6300 (monthly maintenance fee)
--     9.95  'Mashreq' Bank charges -> 6300 (the bank's VAT on the fee; the company is not VAT registered, so it is a cost,
--           booked with the fee to 6300 as the statement lines are, never to 1150)
select public.fn_accountant_expense_on_founder_word('Mashreq', date '2026-11-01', 199.00, 'AED', null, 'Bank charges',
  'Mashreq monthly maintenance fee, 1 Nov 2026 (charged on the 1st, as on 1 Sep and 1 Oct); no statement after the one issued 2 Oct 2026 has arrived.',
  1702, 'bank_statement', false) as fee;
select public.fn_accountant_expense_on_founder_word('Mashreq', date '2026-11-01', 9.95, 'AED', null, 'Bank charges',
  'Mashreq "Value Added Tax - Output" on the 1 Nov 2026 maintenance fee (5% of 199), a cost because the company is not VAT registered.',
  1702, 'bank_statement', false) as vat;

select case
  when (select count(*) from public.expense_awaiting_document x join public.expense_entries e on e.id = x.expense_entry_id
         where e.vendor = 'Mashreq' and e.charged_on = date '2026-11-01' and x.founder_instruction_id = 1702) <> 2
    then 'PROBE FAILED: expected 2 held Mashreq entries for 1 Nov 2026'
  when exists (select 1 from public.expense_entries e where e.vendor = 'Mashreq' and e.charged_on = date '2026-11-01'
                and not exists (select 1 from public.gl_journal g where g.source = 'expense' and g.source_ref = e.id::text and g.status = 'posted'))
    then 'PROBE FAILED: a held Mashreq entry has no posted journal'
  else 'PROBE OK: the 1 Nov 2026 Mashreq fee pair (208.95) is booked to 6300 and awaits the statement'
end as verdict;
