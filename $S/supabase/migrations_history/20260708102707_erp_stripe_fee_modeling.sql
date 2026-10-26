-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260708102707   name: erp_stripe_fee_modeling
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Configurable GL settings (editable any time)
create table if not exists public.gl_settings (
  key text primary key,
  num_value numeric,
  txt_value text,
  updated_at timestamptz not null default now()
);
insert into public.gl_settings(key,num_value,txt_value) values
 ('stripe_fee_pct', 2.9, 'Stripe processing % per successful charge (UAE standard)'),
 ('stripe_fee_fixed', 1.00, 'Stripe fixed fee per charge, AED')
on conflict (key) do nothing;

-- Rebuild the business-event sync to split Stripe processing fees out of reveal-fee revenue.
-- Reveal fee entry (per paid transaction):
--   Dr 1050 Stripe Clearing (net = gross - fee)
--   Dr 6100 Payment Processing Fees (fee)
--   Cr 4000 Reveal Fee Revenue (gross)
create or replace function public.fn_gl_sync_business()
returns int language plpgsql security definer set search_path=public,pg_catalog as $$
declare r record; n int := 0; acct text;
        fee_pct numeric; fee_fixed numeric; fee numeric(18,2); gross numeric(18,2); net numeric(18,2);
begin
  select num_value into fee_pct   from public.gl_settings where key='stripe_fee_pct';
  select num_value into fee_fixed from public.gl_settings where key='stripe_fee_fixed';
  fee_pct   := coalesce(fee_pct,0);
  fee_fixed := coalesce(fee_fixed,0);

  -- 1) Reveal-fee revenue with Stripe fee split
  for r in
    select id, reveal_fee, coalesce(revealed_at::date, current_date) as d
    from public.transactions
    where fee_status='paid' and coalesce(reveal_fee,0) > 0
      and coalesce(refund_status,'') not in ('refunded','refund_approved')
      and not exists (select 1 from public.gl_journal g where g.source='reveal_fee' and g.source_ref=transactions.id::text)
  loop
    gross := round(r.reveal_fee,2);
    fee   := round(gross*fee_pct/100 + fee_fixed, 2);
    if fee >= gross then fee := 0; end if;                 -- guard tiny fees / bad config
    net   := gross - fee;
    perform public.fn_gl_entry(r.d, 'Reveal fee (net of Stripe fee)', 'reveal_fee', r.id::text,
      case when fee > 0 then
        jsonb_build_array(
          jsonb_build_object('account','1050','debit',net),
          jsonb_build_object('account','6100','debit',fee),
          jsonb_build_object('account','4000','credit',gross))
      else
        jsonb_build_array(
          jsonb_build_object('account','1050','debit',gross),
          jsonb_build_object('account','4000','credit',gross))
      end, 'gl_sync');
    n := n + 1;
  end loop;

  -- 2) Supplier commission earned
  for r in
    select id, amount_due, coalesce(reveal_date, current_date) as d
    from public.supplier_dues
    where coalesce(amount_due,0) > 0
      and not exists (select 1 from public.gl_journal g where g.source='commission_accrue' and g.source_ref=supplier_dues.id::text)
  loop
    perform public.fn_gl_entry(r.d, 'Supplier commission earned', 'commission_accrue', r.id::text,
      jsonb_build_array(jsonb_build_object('account','1110','debit',round(r.amount_due,2)),
                        jsonb_build_object('account','4100','credit',round(r.amount_due,2))), 'gl_sync');
    n := n + 1;
  end loop;

  -- 2b) Supplier commission collected
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

  -- 3) Actual expense charges
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

