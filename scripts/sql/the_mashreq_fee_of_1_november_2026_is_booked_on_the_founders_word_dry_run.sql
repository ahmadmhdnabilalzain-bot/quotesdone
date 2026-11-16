-- DRY RUN of the_mashreq_fee_of_1_november_2026_is_booked_on_the_founders_word.sql. Writes nothing: p_dry_run => true only
-- validates and returns the entry and journal it would post, or why it would not (already booked, the statement shows it).
-- Seat: accountant. Run: node SP/q.mjs scripts/sql/the_mashreq_fee_of_1_november_2026_is_booked_on_the_founders_word_dry_run.sql
select public.fn_accountant_expense_on_founder_word('Mashreq', date '2026-11-01', 199.00, 'AED', null, 'Bank charges',
         'dry run', 1702, 'bank_statement', true) as fee,
       public.fn_accountant_expense_on_founder_word('Mashreq', date '2026-11-01', 9.95, 'AED', null, 'Bank charges',
         'dry run', 1702, 'bank_statement', true) as vat;
