-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260708110544   name: erp_ws_finance_cfo
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

create or replace function public.fn_ws_finance()
returns jsonb language plpgsql security definer set search_path=public,pg_catalog as $$
declare
  cash_total numeric(18,2); rev_total numeric(18,2); exp_total numeric(18,2);
  rev30 numeric(18,2); exp30 numeric(18,2); monthly_burn numeric(18,2); runway numeric(18,1);
  j jsonb;
begin
  select coalesce(sum(balance),0) into cash_total from public.gl_account_balances where code in ('1000','1050');
  select coalesce(sum(balance),0) into rev_total from public.gl_account_balances where type='revenue';
  select coalesce(sum(balance),0) into exp_total from public.gl_account_balances where type='expense';

  -- 30-day run-rate (posted activity)
  select
    coalesce(sum(case when ga.type='revenue' then l.credit-l.debit else 0 end),0),
    coalesce(sum(case when ga.type='expense' then l.debit-l.credit else 0 end),0)
    into rev30, exp30
  from public.gl_journal_lines l
  join public.gl_journal j2 on j2.id=l.journal_id and j2.status='posted'
  join public.gl_accounts ga on ga.code=l.account_code
  where j2.entry_date >= current_date - 30;

  monthly_burn := exp30 - rev30;                       -- net cash burn (positive = burning)
  runway := case when monthly_burn > 0 and cash_total > 0 then round(cash_total/monthly_burn,1) else null end;

  j := jsonb_build_object(
    'as_of', now(),
    'cash', jsonb_build_object(
      'total', cash_total,
      'accounts', coalesce((select jsonb_agg(jsonb_build_object('code',code,'name',name,'balance',balance) order by code)
                   from public.gl_account_balances where code in ('1000','1050','1100','1110','1150','1500','1600')),'[]'::jsonb)
    ),
    'pnl', jsonb_build_object(
      'revenue', rev_total, 'expenses', exp_total, 'net_income', rev_total-exp_total,
      'margin_pct', case when rev_total>0 then round(100.0*(rev_total-exp_total)/rev_total,1) else null end
    ),
    'run_rate', jsonb_build_object(
      'revenue_30d', rev30, 'expense_30d', exp30, 'net_30d', rev30-exp30,
      'arr_estimate', round(rev30*12,2), 'monthly_burn', monthly_burn,
      'runway_months', runway
    ),
    'monetization', jsonb_build_object(
      'reveal_fees', (select coalesce(balance,0) from public.gl_account_balances where code='4000'),
      'commissions', (select coalesce(balance,0) from public.gl_account_balances where code='4100'),
      'registration', (select coalesce(balance,0) from public.gl_account_balances where code='4200'),
      'stripe_fees', (select coalesce(balance,0) from public.gl_account_balances where code='6100')
    ),
    'revenue_breakdown', coalesce((select jsonb_agg(jsonb_build_object('code',code,'name',name,'amount',balance) order by balance desc)
        from public.gl_account_balances where type='revenue' and balance<>0),'[]'::jsonb),
    'expense_breakdown', coalesce((select jsonb_agg(jsonb_build_object('code',code,'name',name,'amount',balance) order by balance desc)
        from public.gl_account_balances where type='expense' and balance<>0),'[]'::jsonb),
    'receivables', jsonb_build_object(
      'commission_receivable', (select coalesce(balance,0) from public.gl_account_balances where code='1110'),
      'trade_receivable', (select coalesce(balance,0) from public.gl_account_balances where code='1100'),
      'overdue_commissions', (select coalesce(sum(amount_due),0) from public.supplier_dues
                              where status not in ('paid','settled') and coalesce(due_date,reveal_date) < current_date)
    ),
    'payables', jsonb_build_object(
      'ap_open', (select coalesce(sum(total-amount_paid),0) from public.ap_bills where status in ('open','partial')),
      'aging', coalesce((select jsonb_agg(to_jsonb(a)) from public.ap_aging a),'[]'::jsonb)
    ),
    'cashflow', coalesce((
      select jsonb_agg(x order by x->>'month')
      from (
        select jsonb_build_object(
          'month', to_char(date_trunc('month',j3.entry_date),'YYYY-MM'),
          'inflow', sum(l.debit), 'outflow', sum(l.credit), 'net', sum(l.debit-l.credit)
        ) x
        from public.gl_journal_lines l
        join public.gl_journal j3 on j3.id=l.journal_id and j3.status='posted'
        where l.account_code in ('1000','1050')
          and j3.entry_date >= (date_trunc('month',current_date) - interval '5 months')
        group by date_trunc('month',j3.entry_date)
      ) s
    ),'[]'::jsonb),
    'budgets', coalesce((select jsonb_agg(to_jsonb(b)) from public.budget_vs_actual_summary b),'[]'::jsonb)
  );
  return j;
end $$;

revoke execute on function public.fn_ws_finance() from anon, authenticated, public;
