-- TEST MONEY NEVER REACHES THE BOOKS.
-- Assigned: accountant (15 Sep 2026). The books are the accountant's; the E2E teardown half of this change
-- (scripts/staging/demo_factory.mjs, scripts/e2e/fixtures.mjs) is the it_engineer's.
--
-- MEASURED BEFORE WRITING (production, 15 Sep 2026):
--   gl_journal #690 (source 'commission_accrue', source_ref '272', posted 14 Sep 22:02:50Z by gl_sync the
--   first tick after gl_settings.bank_booking_on_hold went to 0): Dr 1110 3,978.30 / Cr 6900 3,728.30 /
--   Cr 4400 250.00. Its source, supplier_dues #272, was written 14 Sep 16:49:25Z while E2E run e8095fdb
--   was open (quote amount 118,500, status 'due'). Its supplier (lead 123743) and its transaction no longer
--   exist: the teardown deleted the lead and the transaction and never touched supplier_dues. The company
--   has 0 real customers and 0 real suppliers, so this was fictitious money in the real ledger.
--   Read-only scan of every gl_journal row against its source row: #690 is the only live (posted or draft)
--   entry whose source is a fixture or an orphan. Journals 98, 131 and 140 also point at expense rows that
--   no longer exist, but all three are already void and reversed (141, 142, 144). supplier_dues holds 1 row
--   (#272, orphaned both ways); refunds 0 rows; transactions 0 rows.
--
-- WHAT CHANGES
--   1. fn_gl_fixture_or_orphan(transaction, supplier, customer): ONE rule for "is this money test money or
--      money nobody can be billed for". Fixture = the supplier or customer is_demo (the derived marker of
--      demo_identities_are_marked_and_never_reach_a_real_person.sql: demo_factory, @example.invalid, ZZ DEMO,
--      qd_demo). Orphan = the transaction, supplier or customer the row names no longer exists.
--   2. fn_gl_sync_business uses it on every branch that books business money: reveal fees, refunds paid,
--      clawbacks raised, clawbacks settled, subscriptions. Expenses have no supplier, customer or transaction
--      link; a ZZ DEMO expense (the marker the receipt duty already uses) is skipped. Bank lines, bank
--      charges, bank credits and Stripe balance transactions come from the bank or Stripe live mode and
--      carry no fixture link (Stripe test mode already drafts, never posts).
--      A FIXTURE is skipped quietly: it is expected. An ORPHAN is never booked silently: every open one is
--      an accountant finding (fn_it_duty_settle, duty 'ledger_orphan', owner_seat accountant,
--      no_founder_email), closed by the same call once the row is resolved.
--   3. The other writers: fn_expense_post_to_gl skips a ZZ DEMO expense; fn_accountant_applies_incident_fix
--      refuses to book an over-refund loss on a fixture or orphaned transaction (its other fixes do not
--      write the ledger and are left alone). fn_gl_reverse writes only mirrors of posted journals.
--   4. Journal #690 is reversed through fn_gl_reverse (source 'reversal', source_ref '690'; #690 becomes
--      void with reverses = the new journal, the pattern of reversals 141, 142 and 144), and supplier_dues
--      #272 becomes 'reversed' (already in the sync's skip list) with the reason on the row, so it can
--      never post again.
--
--   node scripts/apply_sql.mjs scripts/sql/test_money_never_reaches_the_books.sql --apply --ddl
--   probe (rolled back): scripts/sql/test_money_never_reaches_the_books_probe.sql

-- 1. the reason a due stopped being a claim -------------------------------------------------------------
alter table public.supplier_dues add column if not exists status_reason text;
comment on column public.supplier_dues.status_reason is
  'Why the status is what it is, when it is not the ordinary lifecycle (reversed, cancelled, waived). Written by whoever changed it.';

-- 2. the rule ------------------------------------------------------------------------------------------
create or replace function public.fn_gl_fixture_or_orphan(p_transaction uuid, p_supplier bigint, p_customer uuid)
returns text language plpgsql stable
set search_path to 'public', 'pg_temp'
as $fn$
declare v_found boolean; v_sup bigint := p_supplier; v_cust uuid := p_customer; v_demo boolean;
begin
  if p_transaction is not null then
    select true, coalesce(v_sup, t.supplier_id), coalesce(v_cust, t.customer_id)
      into v_found, v_sup, v_cust
      from public.transactions t where t.id = p_transaction;
    if v_found is null then return 'orphan: transaction ' || p_transaction || ' no longer exists'; end if;
  end if;
  if v_sup is not null then
    select coalesce(l.is_demo, false) into v_demo from public.leads l where l.id = v_sup;
    if not found then return 'orphan: supplier ' || v_sup || ' no longer exists'; end if;
    if v_demo then return 'fixture: supplier ' || v_sup || ' is a demo identity'; end if;
  end if;
  if v_cust is not null then
    select coalesce(c.is_demo, false) into v_demo from public.customers c where c.id = v_cust;
    if not found then return 'orphan: customer ' || v_cust || ' no longer exists'; end if;
    if v_demo then return 'fixture: customer ' || v_cust || ' is a demo identity'; end if;
  end if;
  return null;
end $fn$;
revoke execute on function public.fn_gl_fixture_or_orphan(uuid, bigint, uuid) from public, anon, authenticated;
comment on function public.fn_gl_fixture_or_orphan(uuid, bigint, uuid) is
  'NULL when the money row may be booked. Otherwise ''fixture: ...'' (a demo supplier or customer) or ''orphan: ...'' (the transaction, supplier or customer it names is gone). scripts/sql/test_money_never_reaches_the_books.sql';

-- 3. the sync, guarded on every business branch -----------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_gl_sync_business()
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
    fee   := coalesce(round(r.stripe_fee_fils / 100.0, 2), r.processing_fee, round(gross*fee_pct/100 + fee_fixed, 2));
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
           coalesce(round(t.stripe_fee_fils / 100.0, 2), t.processing_fee, round(coalesce(t.total_charged, t.reveal_fee, t.app_fee, 0)*fee_pct/100 + fee_fixed, 2)) as fee_absorbed,
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
      and coalesce(status,'') not in ('waived','cancelled','reversed')
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
           where coalesce(d.amount_due, 0) > 0 and coalesce(d.status, '') not in ('waived', 'cancelled', 'reversed')
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

-- 4. the other writers of gl_journal ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_expense_post_to_gl(p_entry_id bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare e record; fx numeric; acct text; amt_aed numeric(18,2); vat_aed numeric(18,2);
        net_aed numeric(18,2); jid bigint; lines jsonb;
begin
  select id, vendor, category, amount, upper(coalesce(currency,'AED')) as cur, vat_amount,
         coalesce(charged_on, created_at::date) as d, note
    into e
    from public.expense_entries where id = p_entry_id;
  if not found or coalesce(e.amount,0) <= 0 then return null; end if;
  -- a ZZ DEMO expense is a rehearsal's, never the company's (same marker as fn_gl_sync_business)
  if (coalesce(e.vendor, '') || ' ' || coalesce(e.note, '')) ~* 'zz[ _-]?demo' then return null; end if;

  -- already posted (by this routine or by fn_gl_sync_business): return it, never post twice
  select g.id into jid from public.gl_journal g
   where g.source='expense' and g.source_ref = e.id::text limit 1;
  if jid is not null then return jid; end if;

  select num_value into fx from public.gl_settings where key='usd_to_aed';
  fx := coalesce(fx, 3.6725);

  -- Same refusal as fn_gl_sync_business: a currency with no rate is NOT booked at 1:1. An
  -- understated ledger that says so beats a wrong one that does not.
  if e.cur not in ('AED','USD') then
    begin
      insert into public.founder_alerts(level, event, detail, channel)
      values ('warn','gl_unconvertible_currency',
              'Expense #'||e.id||' from '||coalesce(e.vendor,'?')||' is in '||e.cur||
              ', which has no rate in gl_settings, so it was NOT posted to the ledger.','system');
    exception when others then null; end;
    return null;
  end if;

  amt_aed := round(e.amount * case when e.cur='USD' then fx else 1 end, 2);
  vat_aed := round(coalesce(e.vat_amount,0) * case when e.cur='USD' then fx else 1 end, 2);
  if vat_aed <= 0 or vat_aed >= amt_aed then vat_aed := 0; end if;
  net_aed := amt_aed - vat_aed;

  acct := coalesce((select m.account_code from public.gl_expense_map m where m.category = e.category), '6300');

  lines := jsonb_build_array(jsonb_build_object('account', acct, 'debit', net_aed,
             'memo', coalesce(e.vendor,'')||' '||coalesce(e.category,'G&A')));
  if vat_aed > 0 then
    lines := lines || jsonb_build_array(jsonb_build_object('account','1150','debit',vat_aed,
               'memo','Input VAT stated on the receipt'));
  end if;
  lines := lines || jsonb_build_array(jsonb_build_object('account','1000','credit',amt_aed));

  return public.fn_gl_entry(e.d,
    'Expense: '||coalesce(e.vendor,'?')||' - '||coalesce(e.category,'G&A')
      ||case when e.cur='USD' then ' ('||e.amount||' USD @ '||fx||')' else '' end
      ||case when vat_aed > 0 then ' incl VAT '||vat_aed||' AED' else '' end,
    'expense', e.id::text, lines, 'expenses_inbox');
end
$function$;

CREATE OR REPLACE FUNCTION public.fn_accountant_applies_incident_fix(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare d jsonb; v_fix text; v_tx uuid; v_old bigint; v_orig bigint; v jsonb; v_j bigint; v_amt numeric; v_res jsonb; v_du public.supplier_dues;
        v_why text;
begin
  select detail into d from public.agent_actions where id = p_id;
  v_fix := d->>'fix'; v_tx := (d->>'transaction_id')::uuid;
  if v_fix in ('refund_difference', 'retry_refund', 'cancel_duplicate') then
    return jsonb_build_object('waiting', 'stripe: the accountant runtime executes ' || v_fix || ' (accountant action execute_refunds)');
  end if;

  perform set_config('app.qd_incident_fix', 'on', true);
  if v_fix = 'book_over_refund_loss' then
    -- test money never reaches the books: a fixture or orphaned transaction's loss is not the company's
    v_why := public.fn_gl_fixture_or_orphan(v_tx, null, null);
    if v_why is not null then
      perform set_config('app.qd_incident_fix', '', true);
      return jsonb_build_object('refused', 'not booked: ' || v_why);
    end if;
    v_amt := round((d->>'amount_aed')::numeric, 2);
    select g.id into v_j from public.gl_journal g where g.source = 'refund_over_loss' and g.source_ref = v_tx || ':' || (d->>'incident_id');
    if v_j is null and v_amt > 0 then
      v_j := public.fn_gl_entry(current_date,
        'Over-refund on reveal ' || left(v_tx::text, 8) || ' booked as company loss (incident #' || (d->>'incident_id') || '); the supplier charge stays at the approved amount',
        'refund_over_loss', v_tx || ':' || (d->>'incident_id'),
        jsonb_build_array(jsonb_build_object('account', '6900', 'debit', v_amt), jsonb_build_object('account', '1050', 'credit', v_amt)), 'accountant');
    end if;
    v_res := jsonb_build_object('journal_id', v_j, 'amount_aed', v_amt);
  elsif v_fix = 'reissue_charge' then
    -- supplier_dues holds ONE row per transaction (supplier_dues_transaction_id_key), so the charge is
    -- reissued IN PLACE: the figures become the routine's, and the old ones are kept in the evidence.
    select * into v_du from public.supplier_dues where transaction_id = v_tx order by id limit 1;
    v_old := v_du.id;
    select (a.evidence->>'notification_id')::bigint into v_orig from public.agent_actions a
     where a.kind = 'handoff' and a.agent = 'customer_support' and a.target_id = 'delivery.request:nonresponse_charge:' || v_old
     order by a.id desc limit 1;
    v := public.fn_accountant_nonresponse_charge(v_tx, null);
    if not coalesce((v->>'ok')::boolean, false) then
      perform set_config('app.qd_incident_fix', '', true);
      return jsonb_build_object('waiting', 'the charge cannot be recomputed: ' || coalesce(v->>'reason', '?'));
    end if;
    update public.supplier_dues
       set amount_due = (v->>'refunded_aed')::numeric, admin_fee = (v->>'admin_fee_aed')::numeric,
           interest_amount = (v->>'interest_aed')::numeric, total_claim = (v->>'total_aed')::numeric,
           due_date = (v->>'due_date')::date, due_date_30 = (v->>'due_date')::date + 23,
           status = case when status = 'cancelled' then 'due' else status end
     where id = v_old;
    v := v || jsonb_build_object('due_id', v_old, 'transaction_id', v_tx, 'supplier_id', v_du.supplier_id,
                                 'inquiry_id', (select inquiry_id from public.transactions where id = v_tx),
                                 'quote_id', (select quote_id from public.transactions where id = v_tx));
    if coalesce((d->>'sent')::boolean, false) then
      -- Already in the supplier's hands: a correction that supersedes it, to whoever got the original.
      perform public.fn_seat_handoff('accountant', 'sales_engineer', 'charge.corrected', 'supplier_dues', v_old::text,
        v || jsonb_build_object('original_notification_id', v_orig));
    else
      -- Not sent yet: withdraw it from the outbox and send the right one instead.
      update public.notifications set status = 'cancelled', last_error = 'withdrawn before sending: the charge was reissued with the correct figures'
       where id = v_orig and status in ('queued', 'pending', 'held');
      update public.agent_actions set status = 'failed', detail = detail || jsonb_build_object('superseded_by_incident', d->>'incident_id')
       where kind = 'handoff' and status = 'done'
         and target_id in ('nonresponse.charge_raised:' || v_old, 'delivery.request:nonresponse_charge:' || v_old);
      perform public.fn_seat_handoff('accountant', 'sales_engineer', 'nonresponse.charge_raised', 'supplier_dues', v_old::text, v);
    end if;
    v_res := jsonb_build_object('reissued_due', v_old,
      'was', jsonb_build_object('amount_due', v_du.amount_due, 'admin_fee', v_du.admin_fee, 'due_date', v_du.due_date),
      'now', v, 'correction_sent_to_original_recipients', coalesce((d->>'sent')::boolean, false));
  elsif v_fix = 'raise_charge' then
    v_res := public.fn_accountant_raise_nonresponse_charge(v_tx, true);
  else
    v_res := jsonb_build_object('waiting', 'no handler for fix ' || coalesce(v_fix, '?'));
  end if;
  perform set_config('app.qd_incident_fix', '', true);
  return v_res;
end $function$;

-- 5. reverse, never delete: journal #690 and its source due #272 -----------------------------------------
do $rev$
declare v_new bigint;
begin
  if exists (select 1 from public.gl_journal
              where id = 690 and status = 'posted' and source = 'commission_accrue' and source_ref = '272') then
    v_new := public.fn_gl_reverse(690,
      'An E2E fixture due, orphaned by teardown, never a real claim. supplier_dues #272 was written 14 Sep 2026 16:49Z '
      || 'during E2E run e8095fdb; the run''s teardown deleted its supplier (lead 123743) and its transaction but not the due, '
      || 'and the 22:02:50Z booking tick posted it once the bank-booking hold was lifted. founder_instruction 407. '
      || 'scripts/sql/test_money_never_reaches_the_books.sql');
    raise notice 'journal 690 reversed by journal %', v_new;
  end if;
  update public.supplier_dues
     set status = 'reversed',
         status_reason = 'An E2E fixture due (run e8095fdb, 14 Sep 2026) orphaned when the teardown deleted its supplier and '
                      || 'transaction. Journal 690 reversed. founder_instruction 407; scripts/sql/test_money_never_reaches_the_books.sql'
   where id = 272 and status = 'due';
end $rev$;
