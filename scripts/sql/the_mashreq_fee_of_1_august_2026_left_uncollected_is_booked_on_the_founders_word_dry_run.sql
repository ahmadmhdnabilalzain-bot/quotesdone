-- DRY RUN of the_mashreq_fee_of_1_august_2026_left_uncollected_is_booked_on_the_founders_word.sql. Writes nothing:
-- p_dry_run => true only validates and returns the entry and journal it would post, or why it would not (already booked,
-- a statement line of that amount within 7 days, a Mashreq expense of that amount in August).
-- Seat: accountant. Run on the LOCAL copy, or on production only by the session that applies the data file, right before it
-- (it calls an application routine, so it is not a reviewer's production SELECT).
select public.fn_accountant_expense_on_founder_word('Mashreq', date '2026-08-01', 199.00, 'AED', null, 'Bank charges',
         'dry run', 1702, 'bank_statement', true) as fee,
       public.fn_accountant_expense_on_founder_word('Mashreq', date '2026-08-01', 9.95, 'AED', null, 'Bank charges',
         'dry run', 1702, 'bank_statement', true) as vat;
