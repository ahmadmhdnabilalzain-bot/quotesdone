-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260708101918   name: erp_gl_sync_business_events
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Optional category -> GL account map (editable; defaults applied if unmapped)
create table if not exists public.gl_expense_map (
  category text primary key,
  account_code text not null references public.gl_accounts(code)
);
insert into public.gl_expense_map(category,account_code) values
 ('Subscription','6000'), ('Usage','6000'), ('AI & Tools','6000'),
 ('Data','6300'), ('Marketing','6200'), ('Payment','6100')
on conflict (category) do nothing;

-- ------------------------------------------------------------------
-- Idempotent sync of live business events into the GL.
-- Safe to re-run (guards on gl_journal.source + source_ref).
-- Returns number of new journal entries posted.
-- ------------------------------------------------------------------
create or replace function public.fn_gl_sync_business()
returns int language plpgsql security definer set search_path=public,pg_catalog as $$
declare r record; n int := 0; acct text; ddate date;
begin
  -- 1) Reveal-fee revenue: paid transactions  -> Dr Stripe Clearing / Cr Reveal Fee Revenue
  for r in
    select id, reveal_fee, coalesce(revealed_at::date, current_date) as d
    from public.transactions
    where fee_status='paid' and coalesce(reveal_fee,0) > 0
      and coalesce(refund_status,'') not in ('refunded','refund_approved')
      and not exists (select 1 from public.gl_journal g where g.source='reveal_fee' and g.source_ref=transactions.id::text)
  loop
    perform public.fn_gl_entry(r.d, 'Reveal fee revenue', 'reveal_fee', r.id::text,
      jsonb_build_array(jsonb_build_object('account','1050','debit',round(r.reveal_fee,2)),
                        jsonb_build_object('account','4000','credit',round(r.reveal_fee,2))), 'gl_sync');
    n := n + 1;
  end loop;

  -- 2) Supplier commission earned -> Dr Commission Receivable / Cr Commission Revenue
  for r in
    select id, amount_due, coalesce(reveal_date, current_date) as d, status, paid_at
    from public.supplier_dues
    where coalesce(amount_due,0) > 0
      and not exists (select 1 from public.gl_journal g where g.source='commission_accrue' and g.source_ref=supplier_dues.id::text)
  loop
    perform public.fn_gl_entry(r.d, 'Supplier commission earned', 'commission_accrue', r.id::text,
      jsonb_build_array(jsonb_build_object('account','1110','debit',round(r.amount_due,2)),
                        jsonb_build_object('account','4100','credit',round(r.amount_due,2))), 'gl_sync');
    n := n + 1;
  end loop;

  -- 2b) Supplier commission collected -> Dr Cash / Cr Commission Receivable
  for r in
    select id, amount_due, paid_at::date as d
    from public.supplier_dues
    where status in ('paid','settled') and paid_at is not null and coalesce(amount_due,0) > 0
      and not exists (select 1 from public.gl_journal g where g.source='commission_collect' and g.source_ref=supplier_dues.id::text)
  loop
    perform public.fn_gl_entry(r.d, 'Supplier commission collected', 'commission_collect', r.id::text,
      jsonb_build_array(jsonb_build_object('account','1000','debit',round(r.amount_due,2)),
                        jsonb_build_object('account','1110','credit',round(r.amount_due,2))), 'gl_sync');
    n := n + 1;
  end loop;

  -- 3) Actual expense charges -> Dr expense account / Cr Cash
  for r in
    select e.id, e.amount, e.category, coalesce(e.charged_on, e.created_at::date) as d
    from public.expense_entries e
    where coalesce(e.amount,0) > 0
      and not exists (select 1 from public.gl_journal g where g.source='expense' and g.source_ref=e.id::text)
  loop
    acct := coalesce((select account_code from public.gl_expense_map m where m.category=r.category), '6300');
    perform public.fn_gl_entry(r.d, 'Expense: '||coalesce(r.category,'G&A'), 'expense', r.id::text,
      jsonb_build_array(jsonb_build_object('account',acct,'debit',round(r.amount,2)),
                        jsonb_build_object('account','1000','credit',round(r.amount,2))), 'gl_sync');
    n := n + 1;
  end loop;

  return n;
end $$;

