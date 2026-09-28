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
-- journal directly (re-pointed 29 Sep, see THE CHECK).

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


-- THE CHECK (re-pointed 29 Sep 2026, after #1013 made the bank the forecast's one cash truth):
-- (1) the view's debit and credit totals equal the posted journals', account by account, so no void
--     line reaches any balance; (2) the forecast's cash_now is the accountant's cash position.
-- It raises on failure, so a wrong result can never sit in an apply log as a quiet verdict row.
do $chk$
declare
  v_leak numeric;
  v_fc   numeric := (public.fn_finance_forecast() ->> 'cash_now')::numeric;
  v_cp   numeric := (public.fn_accountant_cash_position(current_date, null) #>> '{cash_in_bank,aed}')::numeric;
begin
  select coalesce(sum(abs(v.debit_total - coalesce(p.d, 0)) + abs(v.credit_total - coalesce(p.c, 0))), 0)
    into v_leak
    from public.gl_account_balances v
    left join (select l.account_code, sum(l.debit) d, sum(l.credit) c
                 from public.gl_journal_lines l
                 join public.gl_journal j on j.id = l.journal_id and j.status = 'posted'
                group by l.account_code) p on p.account_code = v.code;
  if v_leak <> 0 then
    raise exception 'PROBE FAILED: gl_account_balances differs from the posted journals by %', v_leak;
  end if;
  if v_fc is distinct from v_cp then
    raise exception 'PROBE FAILED: forecast cash_now % is not the cash position %', v_fc, v_cp;
  end if;
  raise notice 'PROBE OK: no void line moves a balance; forecast cash = cash position = %', v_fc;
end $chk$;
