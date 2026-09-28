-- A VOID JOURNAL NEVER MOVES A BALANCE.
-- Seat: accountant. 28 Sep 2026. Deep audit 28 Sep: the forecast's cash figure (AED 395.11) differed
-- from the ledger's bank balance (AED 582.96) by AED 187.85.
--
-- ROOT CAUSE (measured on production htdblwldjkcgjvmqkbeh, read-only, 28 Sep 2026)
--   fn_finance_forecast reads cash_now from public.gl_account_balances (codes 1000 + 1050). That view
--   joined gl_journal_lines to gl_accounts with a LEFT JOIN and then LEFT JOINed gl_journal with the
--   status = 'posted' test inside the ON clause. A line of a VOID journal therefore still joined its
--   account and was summed; only the journal columns went NULL. Account 1000 posted lines sum to 582.96;
--   its three void lines (credit 187.85) took the view to 395.11.
--   Void lines leak into six accounts in all: 1000 (-187.85), 1110 (+3,978.30), 1150 (+1.95),
--   4400 (+250.00), 6000 (+185.90), 6900 (-3,728.30). Every reader of the view carried them:
--   finance_kpis, gl_trial_balance, gl_pnl, gl_balance_sheet, marketing_kpis and three routines,
--   fn_finance_forecast among them. The trial balance still balanced (void journals balance too), which
--   is why nothing tripped.
--
-- THE FIX is in the one place every reader goes through: the view now sums only lines whose journal is
-- posted (the line and its journal are joined first, then attached to the account). fn_finance_forecast
-- is not retyped; it reads the corrected view. Same columns, same 32 rows. Read-only rehearsal of the new
-- body on production: account 1000 = 582.96, debits minus credits over all accounts = 0.00.
--
-- Prevented by: scripts/checks/a_void_journal_never_moves_a_balance.test.mjs (fails if the view's posted
-- test goes back to an outer-join ON clause). The verdict row below compares the forecast with the posted
-- journal directly.

create or replace view public.gl_account_balances as
 select a.code,
    a.name,
    a.type,
    a.normal_balance,
    coalesce(sum(pl.debit), 0::numeric) as debit_total,
    coalesce(sum(pl.credit), 0::numeric) as credit_total,
        case
            when a.normal_balance = 'D'::bpchar then coalesce(sum(pl.debit), 0::numeric) - coalesce(sum(pl.credit), 0::numeric)
            else coalesce(sum(pl.credit), 0::numeric) - coalesce(sum(pl.debit), 0::numeric)
        end as balance
   from gl_accounts a
     left join (gl_journal_lines pl
                join gl_journal j on j.id = pl.journal_id and j.status = 'posted'::text)
       on pl.account_code = a.code
  group by a.code, a.name, a.type, a.normal_balance;

select case when (public.fn_finance_forecast() ->> 'cash_now')::numeric
                 = (select coalesce(sum(l.debit - l.credit), 0)
                      from public.gl_journal_lines l join public.gl_journal j on j.id = l.journal_id and j.status = 'posted'
                     where l.account_code in ('1000', '1050'))
       then 'PROBE OK' else 'PROBE FAILED: the forecast cash is not the posted-journal cash' end as verdict;
