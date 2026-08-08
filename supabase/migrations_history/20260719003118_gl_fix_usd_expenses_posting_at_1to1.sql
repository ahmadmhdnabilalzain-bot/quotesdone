-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260719003118   name: gl_fix_usd_expenses_posting_at_1to1
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Fix: USD expenses were posted to an AED general ledger at 1:1.
--
-- THE BUG (found 19 Jul 2026):
-- expense_entries records a currency (13 of 18 rows are USD, 5 are AED), but section 3 of
-- fn_gl_sync_business posted e.amount straight into the GL with no conversion. The GL is
-- denominated in AED - revenue is AED reveal fees - so every USD expense was booked at roughly
-- 27% of its true cost. Measured impact: USD 532.45 posted as 532.45 AED instead of 1,955.41 AED,
-- understating total expenses by 1,422.96 AED (1,934.35 posted vs 3,357.31 actual). Because
-- expenses were understated, reported gross margin was materially overstated.
--
-- THE RATE:
-- The UAE dirham is pegged to the US dollar by the Central Bank of the UAE at USD 1 = AED 3.6725
-- and has been since 1997, held by automatic CBUAE intervention with deviation under 0.01%.
-- Because it is a hard peg rather than a floating rate, the historical rate on each charge date
-- and the current rate are the same number, so restating past entries at a single rate is exact,
-- not an approximation. Stored in gl_settings so it is auditable and changeable in one place if
-- the peg is ever abandoned.
--
-- THE CORRECTION METHOD:
-- Original journal entries are NOT edited or deleted - that would destroy the audit trail. Instead
-- section 3b posts a separate, idempotent correcting entry per affected expense for the FX
-- difference only, under its own source key 'expense_fx_adj'. The original wrong entry and its
-- correction both remain visible, which is how a ledger is supposed to be fixed.

insert into public.gl_settings(key, num_value, txt_value)
values ('usd_to_aed', 3.6725, 'USD->AED. Hard peg set by the Central Bank of the UAE (USD 1 = AED 3.6725, unchanged since 1997). Used to book USD-denominated expenses into the AED general ledger. If the peg is ever abandoned this becomes a date-dependent rate and fn_gl_sync_business must be reworked to look the rate up per charge date.')
on conflict (key) do update set num_value = excluded.num_value, txt_value = excluded.txt_value;

create or replace function public.fn_gl_sync_business()
returns integer
language plpgsql
as $$
declare r record; n int := 0; acct text;
        fee_pct numeric; fee_fixed numeric; fee numeric(18,2); gross numeric(18,2); net numeric(18,2);
        fx numeric; amt_aed numeric(18,2); diff numeric(18,2);
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

  -- 3) Actual expense charges, CONVERTED TO AED (the ledger currency)
  for r in
    select e.id, e.amount, upper(coalesce(e.currency,'AED')) as cur, e.category, e.vendor,
           coalesce(e.charged_on, e.created_at::date) as d
    from public.expense_entries e
    where coalesce(e.amount,0) > 0
      and not exists (select 1 from public.gl_journal g where g.source='expense' and g.source_ref=e.id::text)
  loop
    -- Only AED and USD are convertible. Anything else must NOT be posted at a guessed rate:
    -- booking it at 1:1 is exactly the bug this migration exists to fix. Skip it loudly instead.
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

  -- 3b) One-off correcting entries for USD expenses posted at 1:1 before this fix.
  -- Idempotent via its own source key, so re-running the sync cannot double-correct.
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
