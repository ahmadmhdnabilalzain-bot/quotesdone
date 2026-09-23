-- EVERY MASHREQ LINE OF THE AUGUST STATEMENT IS RULED AND RECONCILED (accountant, 23 Sep 2026).
--
-- The readiness audit read "1 bank statement, 6 lines, 0 owner rulings, nothing reconciled". Measured 23 Sep:
-- all six lines already carry a kind and a POSTED journal (gl_journal 692-697), and the statement reconciles
-- to the fils (0.00 + 1000 - 199 - 9.95 - 9.95 - 199 + 0.86 = 582.96, the closing balance on 31 Aug).
-- What was missing is the founder's ruling on the one owner transfer: line 230 (AED 1,000, 19 Aug) was booked
-- to 3000 capital from its reasoned kind 'owner_transfer', while his own words — founder_instruction 357,
-- "yea capital from my other account" (14 Sep 2026) — sat in no row that names the line. This records it, so
-- the capital entry rests on his ruling and a later re-reasoning of the line cannot turn it into income.
--
-- The rest are ruled by kind, not by the founder, and need no ruling row (bank_line_owner_ruling admits only
-- capital | loan): 231/234 Monthly Maintenance Fee AED 199 -> 6300; 232/233 Value Added Tax - Output AED 9.95
-- -> 6300 with the fee, as we are not VAT registered; 235 interest AED 0.86 -> 7000, outside revenue.
--
-- DATA, so it is committed PENDING (see scripts/sql/pending/) and applied by the release operator:
--   node scripts/apply_sql.mjs scripts/sql/every_mashreq_line_of_august_is_ruled_and_reconciled.sql --apply
insert into public.bank_line_owner_ruling (line_id, ruling, founder_instruction_id)
select 230, 'capital', 357
 where exists (select 1 from public.bank_statement_line where id = 230 and amount_aed = 1000 and value_date = '2026-08-19')
   and exists (select 1 from public.founder_instruction where id = 357)
on conflict (line_id) do nothing;

-- The verdict: each line has exactly one posted journal of its own amount, the ruling is in place, and the
-- lines sum to the closing balance the statement printed.
with l as (
  select b.id, abs(b.amount_aed) amt,
         (select count(*) from public.gl_journal g where g.source_ref = b.id::text and g.status = 'posted'
             and g.source in ('owner_capital', 'bank_charge', 'bank_interest')) n_je,
         (select sum(jl.debit) from public.gl_journal g join public.gl_journal_lines jl on jl.journal_id = g.id
           where g.source_ref = b.id::text and g.status = 'posted' and g.source in ('owner_capital', 'bank_charge', 'bank_interest')) je_amt
    from public.bank_statement_line b where b.source_ref = 'resend:4073be03-2dfa-4fd2-8a7a-100ce089fcad')
select case
  when (select count(*) from l) <> 6 then 'PROBE FAILED: expected 6 August lines, found ' || (select count(*) from l)
  when exists (select 1 from l where n_je <> 1 or je_amt <> amt) then 'PROBE FAILED: a line without exactly one posted journal of its amount'
  when not exists (select 1 from public.bank_line_owner_ruling where line_id = 230 and ruling = 'capital') then 'PROBE FAILED: the capital ruling is not recorded'
  when (select sum(amount_aed) from public.bank_statement_line where source_ref = 'resend:4073be03-2dfa-4fd2-8a7a-100ce089fcad')
       <> (select closing_balance_aed from public.bank_statement_intake where source_ref = 'resend:4073be03-2dfa-4fd2-8a7a-100ce089fcad')
       then 'PROBE FAILED: the lines do not sum to the closing balance'
  else 'PROBE OK: 6 lines, 6 posted journals of equal amount, line 230 ruled capital (instruction 357), sum = closing 582.96' end as verdict;
