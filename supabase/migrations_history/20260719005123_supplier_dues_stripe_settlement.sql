-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260719005123   name: supplier_dues_stripe_settlement
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Supplier commission settlement via Stripe.
--
-- GAP BEING CLOSED (19 Jul 2026): fn_gl_sync_business already had a "commission collected" branch,
-- but NOTHING in the system ever set supplier_dues.paid_at or status='paid'. Commission therefore
-- accrued forever as a receivable (1110) that could never convert to cash. Suppliers will pay by
-- Stripe, so this adds the missing settlement path end to end.

-- 1) Audit + idempotency columns so a Stripe payment can be traced back to its session.
alter table public.supplier_dues
  add column if not exists payment_ref text,
  add column if not exists stripe_session_id text;

comment on column public.supplier_dues.payment_ref is
  'Stripe payment_intent (or session id) that settled this due. Set by stripe_webhook.';

create unique index if not exists supplier_dues_stripe_session_key
  on public.supplier_dues (stripe_session_id) where stripe_session_id is not null;

-- 2) Fines and interest are NOT commission - they must not be credited to 4100, or the
--    commission receivable would never clear cleanly. Give them their own revenue account.
insert into public.gl_accounts(code, name, type, subtype, normal_balance, is_active, description)
values ('4400','Late Payment Fines & Interest','revenue','other','C',true,
        'Non-response fines, late interest and admin fees recovered from suppliers. Kept separate from 4100 Supplier Commission Revenue so the commission receivable clears exactly.')
on conflict (code) do nothing;

-- 3) Rewrite the collection branch so a Stripe settlement books correctly:
--    money lands in Stripe Clearing (1050) net of the Stripe fee (6100), the commission
--    receivable (1110) clears by exactly amount_due, and any fine/interest goes to 4400.
create or replace function public.fn_gl_sync_business()
returns integer
language plpgsql
as $$
declare r record; n int := 0; acct text;
        fee_pct numeric; fee_fixed numeric; fee numeric(18,2); gross numeric(18,2); net numeric(18,2);
        fx numeric; amt_aed numeric(18,2); diff numeric(18,2); extra numeric(18,2); lines jsonb;
begin
  select num_value into fee_pct   from public.gl_settings where key='stripe_fee_pct';
  select num_value into fee_fixed from public.gl_settings where key='stripe_fee_fixed';
  select num_value into fx        from public.gl_settings where key='usd_to_aed';
  fee_pct   := coalesce(fee_pct,0);
  fee_fixed := coalesce(fee_fixed,0);
  fx        := coalesce(fx, 3.6725);

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
    if fee >= gross then fee := 0; end if;
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

  -- 2) Supplier commission earned (accrual)
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

  -- 2b) Supplier commission COLLECTED via Stripe.
  for r in
    select id, amount_due,
           coalesce(fine_amount,0) + coalesce(interest_amount,0) + coalesce(admin_fee,0) as extra_owed,
           paid_at::date as d
    from public.supplier_dues
    where status in ('paid','settled') and paid_at is not null and coalesce(amount_due,0) > 0
      and not exists (select 1 from public.gl_journal g where g.source='commission_collect' and g.source_ref=supplier_dues.id::text)
  loop
    extra := round(coalesce(r.extra_owed,0),2);
    gross := round(r.amount_due,2) + extra;          -- what the supplier actually paid
    fee   := round(gross*fee_pct/100 + fee_fixed, 2); -- Stripe takes its cut before we see it
    if fee >= gross then fee := 0; end if;
    net   := gross - fee;

    lines := jsonb_build_array(jsonb_build_object('account','1050','debit',net));
    if fee > 0 then lines := lines || jsonb_build_array(jsonb_build_object('account','6100','debit',fee)); end if;
    -- clear the receivable by EXACTLY the accrued commission, so 1110 nets to zero
    lines := lines || jsonb_build_array(jsonb_build_object('account','1110','credit',round(r.amount_due,2)));
    if extra > 0 then lines := lines || jsonb_build_array(jsonb_build_object('account','4400','credit',extra)); end if;

    perform public.fn_gl_entry(r.d,
      'Supplier commission collected via Stripe' || case when extra > 0 then ' (incl. ' || extra || ' fine/interest)' else '' end,
      'commission_collect', r.id::text, lines, 'gl_sync');
    n := n + 1;
  end loop;

  -- 3) Actual expense charges, CONVERTED TO AED (the ledger currency)
  for r in
    select e.id, e.amount, upper(coalesce(e.currency,'AED')) as cur, e.category, e.vendor,
           coalesce(e.charged_on, e.created_at::date) as d
    from public.expense_entries e
    where coalesce(e.amount,0) > 0
      and not exists (select 1 from public.gl_journal g where g.source='expense' and g.source_ref=e.id::text)
  loop
    if r.cur not in ('AED','USD') then
      begin
        insert into public.founder_alerts(level, event, detail, channel)
        values ('warn', 'gl_unconvertible_currency',
                'Expense #'||r.id||' from '||coalesce(r.vendor,'?')||' is in '||r.cur||
                ', which has no rate in gl_settings, so it was NOT posted to the ledger. Expenses are understated by '||
                r.amount||' '||r.cur||' until a rate is added. It was skipped rather than booked at 1:1, which is what previously caused USD costs to be understated by ~73%.',
                'system');
      exception when others then null; end;
      continue;
    end if;

    amt_aed := round(r.amount * case when r.cur='USD' then fx else 1 end, 2);
    acct := coalesce((select account_code from public.gl_expense_map m where m.category=r.category), '6300');
    perform public.fn_gl_entry(r.d,
      'Expense: '||coalesce(r.category,'G&A')||case when r.cur='USD' then ' ('||r.amount||' USD @ '||fx||')' else '' end,
      'expense', r.id::text,
      jsonb_build_array(jsonb_build_object('account',acct,'debit',amt_aed),
                        jsonb_build_object('account','1000','credit',amt_aed)), 'gl_sync');
    n := n + 1;
  end loop;

  -- 3b) One-off FX correction for USD expenses posted at 1:1 before the 19 Jul 2026 fix.
  for r in
    select e.id, e.amount, e.category, e.vendor,
           coalesce(e.charged_on, e.created_at::date) as d,
           (select sum(jl.debit) from public.gl_journal g
              join public.gl_journal_lines jl on jl.journal_id = g.id
             where g.source='expense' and g.source_ref = e.id::text and jl.debit > 0) as posted_aed
    from public.expense_entries e
    where upper(coalesce(e.currency,'AED')) = 'USD'
      and coalesce(e.amount,0) > 0
      and exists (select 1 from public.gl_journal g where g.source='expense' and g.source_ref=e.id::text)
      and not exists (select 1 from public.gl_journal g where g.source='expense_fx_adj' and g.source_ref=e.id::text)
  loop
    diff := round(r.amount * fx, 2) - coalesce(r.posted_aed, 0);
    if diff is null or diff = 0 then continue; end if;
    acct := coalesce((select account_code from public.gl_expense_map m where m.category=r.category), '6300');
    perform public.fn_gl_entry(r.d,
      'FX correction: expense #'||r.id||' ('||coalesce(r.vendor,'?')||') was booked at 1:1; restated at USD/AED '||fx,
      'expense_fx_adj', r.id::text,
      jsonb_build_array(jsonb_build_object('account',acct,'debit',diff),
                        jsonb_build_object('account','1000','credit',diff)), 'gl_fx_fix');
    n := n + 1;
  end loop;

  return n;
end
$$;
