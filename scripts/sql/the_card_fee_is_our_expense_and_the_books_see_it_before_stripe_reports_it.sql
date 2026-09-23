-- THE CARD FEE IS OUR EXPENSE, AND THE BOOKS SEE IT BEFORE STRIPE REPORTS IT (24 Sep 2026, accountant).
--
-- Founder, 24 Sep 2026: "we must be fully compliant with UAE law, and nobody may be able to sue us." Cabinet
-- Resolution 66/2023 Art. 5(3) forbids adding any amount when a card is used, and Federal Law 15/2020 counts a
-- company buying for itself as a consumer, so from this change no buyer pays a card processing fee:
-- transactions.processing_fee is 0 on every new reveal (supabase/functions/_shared/reveal_fee.ts) and QuotesDone
-- bears Stripe's cost in expense 6100.
--
-- WHAT WAS WRONG FOR THAT CASE (read from the live body, supabase/schema/full_schema.sql): the sale's fee is
--   coalesce(stripe_fee_fils / 100, processing_fee, gross x stripe_fee_pct + stripe_fee_fixed)
-- processing_fee was the estimate of Stripe's cost while the customer paid it. At 0 it wins the coalesce, so a
-- reveal synced before the webhook read the balance transaction would post a ZERO fee, once (the journal is
-- write-once per transaction): 6100 understated, revenue overstated.
--
-- WHAT THIS CHANGES: nullif(processing_fee, 0) in the two places (sale, refund) so a zero line falls through to the
-- gl_settings estimate. Every other character is the live definition (last written by
-- test_money_never_reaches_the_books.sql). The revenue booking is unchanged: 4000 is credited with what the
-- customer paid (now the 3% alone) and 6100 debited with Stripe's fee, which is exactly "the fee goes to expense".
--
--   node scripts/apply_sql.mjs scripts/sql/the_card_fee_is_our_expense_and_the_books_see_it_before_stripe_reports_it.sql --apply --ddl

create or replace function public.fn_gl_sync_business()
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare r record; n int := 0; acct text;
        fee_pct numeric; fee_fixed numeric; fee numeric(18,2); gross numeric(18,2); net numeric(18,2);
        fx numeric; amt_aed numeric(18,2); diff numeric(18,2); extra numeric(18,2); lines jsonb; v_orphans jsonb;
begin
  select num_value into fee_pct   from public.gl_settings where key='stripe_fee_pct';
  select num_value into fee_fixed from public.gl_settings where key='stripe_fee_fixed';
  select num_value into fx        from public.gl_settings where key='usd_to_aed';
  fee_pct   := coalesce(fee_pct,0);
  fee_fixed := coalesce(fee_fixed,0);
  fx        := coalesce(fx, 3.6725);

  -- TEST MONEY NEVER REACHES THE BOOKS (15 Sep 2026). Every business branch below books only a row that
  -- fn_gl_fixture_or_orphan passes. Journal #690 was an E2E fixture due whose supplier and transaction the
  -- teardown had deleted; it posted the first tick after the bank-booking hold was lifted.

  -- 1) Reveal-fee revenue with Stripe fee split (refunded transactions excluded)
  for r in
    select id, reveal_fee, total_charged, processing_fee, stripe_fee_fils, coalesce(revealed_at::date, current_date) as d
    from public.transactions
    where fee_status='paid' and coalesce(reveal_fee,0) > 0
      and coalesce(refund_status,'') not in ('refunded','refund_approved','succeeded')
      and not exists (select 1 from public.gl_journal g where g.source='reveal_fee' and g.source_ref=transactions.id::text)
      and public.fn_gl_fixture_or_orphan(transactions.id, null, null) is null
  loop
    gross := round(coalesce(r.total_charged, r.reveal_fee),2);
    fee   := coalesce(round(r.stripe_fee_fils / 100.0, 2), nullif(r.processing_fee, 0), round(gross*fee_pct/100 + fee_fixed, 2));
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

  -- 1b) REFUND PAID OUT: everything the customer paid (total_charged) goes back. Stripe keeps its
  --     processing fee and QuotesDone absorbs it (founder, 14 Sep 2026). 'succeeded' is the status the
  --     refunds-table path writes, and it was missing here, so a Stripe-settled refund never posted.
  --     If the sale was booked, the refund reverses it through 6900 and the fee booked at sale stays in
  --     6100 as the absorbed cost. If it was not, the only real movement is the fee: 6100 / 1050.
  for r in
    select t.id, coalesce(t.total_charged, t.reveal_fee, t.app_fee, 0) as amt,
           coalesce(round(t.stripe_fee_fils / 100.0, 2), nullif(t.processing_fee, 0), round(coalesce(t.total_charged, t.reveal_fee, t.app_fee, 0)*fee_pct/100 + fee_fixed, 2)) as fee_absorbed,
           exists (select 1 from public.gl_journal g where g.source='reveal_fee' and g.source_ref=t.id::text) as sale_booked,
           coalesce(t.refund_resolved_at::date, t.revealed_at::date, current_date) as d
    from public.transactions t
    where coalesce(t.refund_status,'') in ('refunded','refund_approved','succeeded')
      and coalesce(t.total_charged, t.reveal_fee, t.app_fee, 0) > 0
      and not exists (select 1 from public.gl_journal g where g.source='refund_paid' and g.source_ref=t.id::text)
      and public.fn_gl_fixture_or_orphan(t.id, null, null) is null
  loop
    gross := round(r.amt,2);
    if r.sale_booked then
      perform public.fn_gl_entry(r.d, 'Reveal charge refunded in full to the customer; the Stripe fee booked at sale stays in 6100, absorbed',
        'refund_paid', r.id::text,
        jsonb_build_array(jsonb_build_object('account','6900','debit',gross),
                          jsonb_build_object('account','1050','credit',gross)), 'gl_sync');
      n := n + 1;
    else
      fee := least(round(coalesce(r.fee_absorbed,0),2), gross);
      if fee > 0 then
        perform public.fn_gl_entry(r.d, 'Stripe processing fee absorbed on a reveal refunded in full before its sale was booked',
          'refund_paid', r.id::text,
          jsonb_build_array(jsonb_build_object('account','6100','debit',fee),
                            jsonb_build_object('account','1050','credit',fee)), 'gl_sync');
        n := n + 1;
      end if;
    end if;
  end loop;

  -- 2) Clawback RAISED on the supplier. Credits 6900 (recovering the refund), NOT 4100.
  --    Any admin fee / interest assessed at the same time is genuine income -> 4400.
  --    A due with no supplier is judged as one whose supplier is gone (-1 is never a lead id).
  for r in
    select id, amount_due,
           coalesce(admin_fee,0) + coalesce(interest_amount,0) as extra_owed,
           coalesce(reveal_date, created_at::date, current_date) as d
    from public.supplier_dues
    where coalesce(amount_due,0) > 0
      and coalesce(status,'') not in ('waived','cancelled','reversed','void')
      and not exists (select 1 from public.gl_journal g where g.source='commission_accrue' and g.source_ref=supplier_dues.id::text)
      and public.fn_gl_fixture_or_orphan(supplier_dues.transaction_id, coalesce(supplier_dues.supplier_id, -1), null) is null
  loop
    extra := round(coalesce(r.extra_owed,0),2);
    lines := jsonb_build_array(
      jsonb_build_object('account','1110','debit', round(r.amount_due,2) + extra),
      jsonb_build_object('account','6900','credit', round(r.amount_due,2)));
    if extra > 0 then lines := lines || jsonb_build_array(jsonb_build_object('account','4400','credit', extra)); end if;
    perform public.fn_gl_entry(r.d,
      'Refund clawback raised on supplier' || case when extra > 0 then ' (incl. ' || extra || ' admin fee/interest)' else '' end,
      'commission_accrue', r.id::text, lines, 'gl_sync');
    n := n + 1;
  end loop;

  -- 2b) Supplier SETTLES via Stripe.
  for r in
    select id, amount_due,
           coalesce(fine_amount,0) + coalesce(interest_amount,0) + coalesce(admin_fee,0) as extra_owed,
           paid_at::date as d
    from public.supplier_dues
    where status in ('paid','settled') and paid_at is not null and coalesce(amount_due,0) > 0
      and not exists (select 1 from public.gl_journal g where g.source='commission_collect' and g.source_ref=supplier_dues.id::text)
      and public.fn_gl_fixture_or_orphan(supplier_dues.transaction_id, coalesce(supplier_dues.supplier_id, -1), null) is null
  loop
    extra := round(coalesce(r.extra_owed,0),2);
    gross := round(r.amount_due,2) + extra;
    fee   := round(gross*fee_pct/100 + fee_fixed, 2);
    if fee >= gross then fee := 0; end if;
    net   := gross - fee;

    lines := jsonb_build_array(jsonb_build_object('account','1050','debit',net));
    if fee > 0 then lines := lines || jsonb_build_array(jsonb_build_object('account','6100','debit',fee)); end if;
    lines := lines || jsonb_build_array(jsonb_build_object('account','1110','credit', gross));

    perform public.fn_gl_entry(r.d,
      'Refund clawback settled by supplier via Stripe' || case when extra > 0 then ' (incl. ' || extra || ' admin fee/interest)' else '' end,
      'commission_collect', r.id::text, lines, 'gl_sync');
    n := n + 1;
  end loop;

  -- 2c) SUBSCRIPTION revenue (RULE 1). Previously never posted - 4200 sat unused.
  for r in
    select l.id, l.registration_fee_due, l.registration_paid_at::date as d
    from public.leads l
    where l.registration_status = 'paid'
      and l.registration_paid_at is not null
      and coalesce(l.registration_fee_due,0) >= 0
      and coalesce(l.subscription_exempt,false) = false
      and not exists (select 1 from public.gl_journal g
                      where g.source='subscription' and g.source_ref = l.id::text || ':' || l.registration_paid_at::date)
      and public.fn_gl_fixture_or_orphan(null, l.id, null) is null
  loop
    gross := round(coalesce(r.registration_fee_due,0),2);
    if gross <= 0 then continue; end if;
    fee := round(gross*fee_pct/100 + fee_fixed, 2);
    if fee >= gross then fee := 0; end if;
    net := gross - fee;
    lines := jsonb_build_array(jsonb_build_object('account','1050','debit',net));
    if fee > 0 then lines := lines || jsonb_build_array(jsonb_build_object('account','6100','debit',fee)); end if;
    lines := lines || jsonb_build_array(jsonb_build_object('account','4200','credit',gross));
    perform public.fn_gl_entry(r.d, 'Annual supplier subscription', 'subscription',
      r.id::text || ':' || r.d::text, lines, 'gl_sync');
    n := n + 1;
  end loop;

  -- 3) Expense charges, converted to AED (the ledger currency). A ZZ DEMO expense is a rehearsal's, never
  --    the company's (the same marker the receipt duty uses).
  for r in
    select e.id, e.amount, upper(coalesce(e.currency,'AED')) as cur, e.category, e.vendor,
           coalesce(e.charged_on, e.created_at::date) as d
    from public.expense_entries e
    where coalesce(e.amount,0) > 0
      and not exists (select 1 from public.gl_journal g where g.source='expense' and g.source_ref=e.id::text)
      and not ((coalesce(e.vendor, '') || ' ' || coalesce(e.note, '')) ~* 'zz[ _-]?demo')
  loop
    if r.cur not in ('AED','USD') then
      begin
        insert into public.founder_alerts(level, event, detail, channel)
        values ('warn', 'gl_unconvertible_currency',
                'Expense #'||r.id||' from '||coalesce(r.vendor,'?')||' is in '||r.cur||
                ', which has no rate in gl_settings, so it was NOT posted. Expenses are understated by '||
                r.amount||' '||r.cur||' until a rate is added. Skipped rather than booked at 1:1.', 'system');
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
      and not ((coalesce(e.vendor, '') || ' ' || coalesce(e.note, '')) ~* 'zz[ _-]?demo')
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

  -- 4) AN ORPHAN IS NEVER BOOKED SILENTLY. Every open money row whose transaction, supplier or customer is
  --    gone is an accountant finding; the same call closes it once the row is reversed, cancelled or
  --    waived. Fixtures are expected and raise nothing.
  select coalesce(jsonb_agg(jsonb_build_object('item', x.item, 'owner_seat', 'accountant', 'subject', x.subject,
           'title', x.subject || ' #' || x.id || ' (' || x.amount || ' AED) was not booked: ' || x.why,
           'blast', 'internal', 'affected', 0, 'demo', false,
           'evidence', jsonb_build_object('row', x.id, 'amount_aed', x.amount, 'why', x.why, 'no_founder_email', true,
             'remedy', 'find what created it; reverse any journal already posted from it (fn_gl_reverse), then set the row reversed or cancelled with status_reason'))
           order by x.item), '[]'::jsonb)
    into v_orphans
    from (select 'supplier_dues:' || d.id as item, 'supplier_dues' as subject, d.id::text as id,
                 round(coalesce(d.total_claim, d.amount_due), 2) as amount,
                 public.fn_gl_fixture_or_orphan(d.transaction_id, coalesce(d.supplier_id, -1), null) as why
            from public.supplier_dues d
           where coalesce(d.amount_due, 0) > 0 and coalesce(d.status, '') not in ('waived', 'cancelled', 'reversed', 'void')
          union all
          select 'transactions:' || t.id, 'transactions', t.id::text,
                 round(coalesce(t.total_charged, t.reveal_fee, t.app_fee, 0), 2),
                 public.fn_gl_fixture_or_orphan(t.id, null, null)
            from public.transactions t
           where t.fee_status = 'paid' or coalesce(t.refund_status, '') in ('refunded', 'refund_approved', 'succeeded')) x
   where x.why like 'orphan:%';
  perform public.fn_it_duty_settle('ledger_orphan', v_orphans);

  return n;
end
$function$;

-- PROBE (no write): the live body carries the fall-through in both places. Verdict row, read by apply_sql.mjs.
select case
  when (select count(*) from regexp_matches(pg_get_functiondef('public.fn_gl_sync_business()'::regprocedure), 'nullif((r|t).processing_fee, 0)', 'g')) <> 2
    then 'PROBE FAILED: a zero card-processing line still wins the fee coalesce'
  else 'PROBE OK' end as verdict;
