-- PROBE: THE MASHREQ FEES OF JULY TO NOVEMBER 2026 ARE EACH IN THE BOOKS ONCE, AND A FEE THE BANK HAS NOT TAKEN IS OWED.
-- Seat: accountant (agent: L6_BOOKS, accountant seat builder). 16 Nov 2026. Ledger 1702 ("bank 210 monthly fee since
-- july"), 1703 ("Mashreq bank / Yes you can"). Pure read: tables only, no routine is called, nothing is written, so it is
-- safe as a production SELECT (SP/q.mjs) and on the local copy. Prints one verdict row: PROBE OK or PROBE FAILED: <why>.
--
-- WHAT IT HOLDS THE BOOKS TO. Five fee pairs (199 + 9.95 "Value Added Tax - Output" = 208.95), July to November 2026:
--   collected, on the statements (bank_statement_line, kind bank_charge): 19 Aug, 1 Sep, 1 Oct;
--   initiated 1 Aug, UNCOLLECTED on the September statement (closed at 59.25), and 1 Nov, in no statement yet: both held
--     on the founder's word (expense_awaiting_document, ledger 1702), written by
--     a_mashreq_fee_the_bank_has_not_taken_is_owed_not_paid_and_the_1_august_fee_is_booked.sql.
-- So: 6300 holds 5 x 208.95 = 1,044.75, each fee once. A held fee still waiting is OWED: its journals credit 2200 Accrued
-- Expenses by its amount and move 1000 by 0.00. A held fee whose statement line attached is PAID: that line has no
-- bank_charge journal (no second cost) and exactly one 'bank_charge_settles_accrual' journal (Dr 2200 / Cr 1000), so the
-- fee's 2200 nets to 0.00 and 1000 falls by the fee. Every posted journal balances.
with fee_lines as (            -- the fee lines on the statements, Jul-Nov 2026
  select b.id, b.value_date, -b.amount_aed as aed
    from public.bank_statement_line b
   where b.account = 'mashreq' and b.kind = 'bank_charge' and b.amount_aed < 0
     and b.value_date between date '2026-07-01' and date '2026-11-30'
), line_books as (
  select l.id, l.aed,
         (select count(*) from public.gl_journal g where g.source = 'bank_charge' and g.source_ref = l.id::text and g.status = 'posted') as journals,
         (select count(*) from public.expense_bank_match m where m.bank_line_id = l.id) as matches,
         (select count(*) from public.gl_journal g where g.source = 'bank_charge_settles_accrual' and g.source_ref = l.id::text and g.status = 'posted') as settles
    from fee_lines l
), held as (                   -- every Mashreq expense row of Jul-Nov 2026 (the fees on his word, and any other)
  select e.id, e.charged_on, e.amount, x.state, x.founder_instruction_id, x.awaits,
         (select count(*) from public.gl_journal g where g.source = 'expense' and g.source_ref = e.id::text and g.status = 'posted') as journals,
         (select m.bank_line_id from public.expense_bank_match m where m.expense_entry_id = e.id limit 1) as line_id
    from public.expense_entries e left join public.expense_awaiting_document x on x.expense_entry_id = e.id
   where lower(btrim(e.vendor)) ~ '^mashreq( |$)' and e.charged_on between date '2026-07-01' and date '2026-11-30'
), held_money as (             -- what each held fee's own journals, and its paying line's settlement, do to 2200 and 1000
  select h.*,
         (select coalesce(sum(jl.credit - jl.debit), 0) from public.gl_journal g join public.gl_journal_lines jl on jl.journal_id = g.id and jl.account_code = '2200'
           where g.status = 'posted' and ((g.source in ('expense', 'expense_accrual') and g.source_ref = h.id::text)
                                       or (g.source = 'bank_charge_settles_accrual' and g.source_ref = h.line_id::text))) as owed,
         (select coalesce(sum(jl.credit - jl.debit), 0) from public.gl_journal g join public.gl_journal_lines jl on jl.journal_id = g.id and jl.account_code = '1000'
           where g.status = 'posted' and ((g.source in ('expense', 'expense_accrual') and g.source_ref = h.id::text)
                                       or (g.source = 'bank_charge_settles_accrual' and g.source_ref = h.line_id::text))) as cash_out
    from held h
), mashreq_6300 as (           -- every 6300 debit those sources carry
  select coalesce(sum(jl.debit - jl.credit), 0) as aed
    from public.gl_journal g join public.gl_journal_lines jl on jl.journal_id = g.id and jl.account_code = '6300'
   where g.status = 'posted'
     and ((g.source = 'bank_charge' and g.source_ref in (select id::text from fee_lines))
       or (g.source in ('expense', 'expense_accrual') and g.source_ref in (select id::text from held))
       or (g.source = 'bank_charge_settles_accrual' and g.source_ref in (select id::text from fee_lines)))
), unbalanced as (
  select count(*) as n from (
    select g.id from public.gl_journal g join public.gl_journal_lines jl on jl.journal_id = g.id
     where g.status = 'posted' group by g.id having sum(jl.debit) <> sum(jl.credit)) u
)
select case
  when (select count(*) from held where charged_on = date '2026-08-01' and founder_instruction_id = 1702 and awaits = 'bank_statement') <> 2
    or (select string_agg(amount::text, ',' order by amount) from held where charged_on = date '2026-08-01') is distinct from '9.95,199.00'
    then 'PROBE FAILED: the fee initiated 1 Aug 2026 (uncollected on the September statement) is not held as 199.00 + 9.95 on ledger 1702'
  when (select count(*) from held where charged_on = date '2026-11-01' and founder_instruction_id = 1702) <> 2
    then 'PROBE FAILED: the 1 Nov 2026 fee pair is not held on ledger 1702'
  when exists (select 1 from held where journals <> 1)
    then 'PROBE FAILED: a Mashreq expense row of July-November 2026 has ' || (select min(journals) from held where journals <> 1) || ' posted journals, not 1'
  when exists (select 1 from line_books where journals + matches <> 1)
    then 'PROBE FAILED: statement fee line ' || (select min(id) from line_books where journals + matches <> 1)
         || ' is booked ' || (select journals + matches from line_books where journals + matches <> 1 order by id limit 1) || ' times (journal + attached), not once'
  when exists (select 1 from line_books where settles <> matches)
    then 'PROBE FAILED: statement fee line ' || (select min(id) from line_books where settles <> matches)
         || ' attached to a held fee without exactly one settlement (Dr 2200 / Cr 1000), or settled without attaching'
  when (select count(*) from fee_lines where value_date <= date '2026-10-01') <> 6
    then 'PROBE FAILED: the statements carry ' || (select count(*) from fee_lines where value_date <= date '2026-10-01')
         || ' fee lines up to 1 Oct 2026, expected the 6 of 19 Aug, 1 Sep and 1 Oct'
  when exists (select 1 from held_money where state = 'awaiting' and awaits = 'bank_statement' and (owed <> amount or cash_out <> 0))
    then 'PROBE FAILED: held fee #' || (select min(id) from held_money where state = 'awaiting' and awaits = 'bank_statement' and (owed <> amount or cash_out <> 0))
         || ' still waiting for its statement is not owed in 2200 by its amount, or moves cash (1000)'
  when exists (select 1 from held_money where state = 'attached' and (owed <> 0 or cash_out <> amount))
    then 'PROBE FAILED: held fee #' || (select min(id) from held_money where state = 'attached' and (owed <> 0 or cash_out <> amount))
         || ' was taken by the bank but its debt in 2200 is not cleared to 1000 exactly once'
  when (select aed from mashreq_6300) <> 1044.75
    then 'PROBE FAILED: 6300 holds AED ' || (select aed from mashreq_6300) || ' of Mashreq fees for July-November 2026, expected 1044.75 (5 x 208.95)'
  when (select n from unbalanced) <> 0
    then 'PROBE FAILED: ' || (select n from unbalanced) || ' posted journal(s) are out of balance'
  else 'PROBE OK: the five Mashreq fees of July-November 2026 are each in 6300 once (AED 1,044.75); '
       || (select count(*) from held_money where state = 'awaiting') || ' held lines not yet taken are owed in 2200 (AED '
       || (select coalesce(sum(owed), 0) from held_money where state = 'awaiting') || ') with cash untouched; every posted journal balances'
end as verdict;
