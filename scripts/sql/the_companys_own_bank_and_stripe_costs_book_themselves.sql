-- THE COMPANY'S OWN BANK AND STRIPE COSTS BOOK THEMSELVES — AND THE BANK'S, AS DRAFTS, WHILE THE
-- FOUNDER'S BANK-BOOKING HOLD STANDS.
--
-- Assigned: accountant (duty 11, founder 14 Sep 2026: "yea add them").
--
-- WHAT WAS MEASURED (14 Sep 2026, production htdblwldjkcgjvmqkbeh):
--   * fn_gl_sync_business already posts every reveal net of the card fee Stripe actually took
--     (transactions.stripe_fee_fils, which carries the VAT Stripe charges on that fee), refunds, supplier
--     charges, subscriptions and expense receipts. NOTHING SCHEDULES IT: the accountant runtime's own
--     comment says so, and no pg_cron job or tick calls it. The P&L moved only when a person ran it.
--   * Stripe bills its Invoicing fee (0.5% per paid invoice) and the VAT on it SEPARATELY from the card
--     fee (_shared/reveal_fee.ts says so), as their own balance transactions. Nothing books those.
--   * Mashreq's AED 200 monthly charge: the founder, 9 Sep 2026, "you dont have to record that now for
--     mashreq bank. later i will share the bank statement." The hold is on BOOKING FROM THE BANK. It is
--     configuration here (gl_settings.bank_booking_on_hold = 1), and while it is 1 a bank charge is
--     prepared as a DRAFT journal and reported, never posted.
--
-- WHAT THIS BUILDS: fn_accountant_book_stripe_fees posts each Stripe fee or tax balance transaction the
-- runtime reads (6100 Payment Processing Fees against 1050 Stripe Clearing; the company is not VAT
-- registered, so the VAT is a cost, not recoverable input tax), once per balance transaction.
-- fn_accountant_book_bank_charges prepares the bank's own charges from the statement lines as drafts
-- (6300 General & Administrative against 1000 Cash & Bank). fn_accountant_cost_booking_tick runs both
-- and fn_gl_sync_business, so the P&L is complete without anyone running anything. TEST-mode Stripe
-- fees and ZZ DEMO statements are only ever drafts.
--
--   node scripts/apply_sql.mjs scripts/sql/the_companys_own_bank_and_stripe_costs_book_themselves.sql --apply --ddl

insert into public.gl_settings (key, num_value, txt_value) values
  ('bank_booking_on_hold', 1,
   'Founder, 9 Sep 2026: "you dont have to record that now for mashreq bank. later i will share the bank statement." While 1, entries read from the bank statement are prepared as DRAFT journals and reported, never posted. Set to 0 only on his word.'),
  ('bank_charge_pattern', null,
   'charge|fee|maint|commission|vat on')
on conflict (key) do nothing;

-- ── 1. A DRAFT JOURNAL: prepared and balanced, never posted ──────────────────────────────────────
-- fn_gl_entry always posts; a draft is the same journal and lines with fn_gl_post never called.
-- gl_journal.status defaults to 'draft', and fn_gl_lines_immutable lets a draft's lines be written.
create or replace function public.fn_accountant_draft_entry(p_date date, p_memo text, p_source text, p_ref text, p_lines jsonb)
returns bigint language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare jid bigint; ln jsonb; i int := 0; v_dr numeric; v_cr numeric;
begin
  select sum(round(coalesce((e->>'debit')::numeric, 0), 2)), sum(round(coalesce((e->>'credit')::numeric, 0), 2))
    into v_dr, v_cr from jsonb_array_elements(p_lines) e;
  if coalesce(v_dr, 0) = 0 or v_dr <> v_cr then
    raise exception 'fn_accountant_draft_entry: a draft must balance (debits %, credits %)', v_dr, v_cr;
  end if;
  select id into jid from public.gl_journal where source = p_source and source_ref = p_ref and status in ('draft', 'posted') limit 1;
  if jid is not null then return jid; end if;
  insert into public.gl_journal (entry_date, memo, source, source_ref, created_by, status)
  values (p_date, p_memo, p_source, p_ref, 'accountant', 'draft') returning id into jid;
  for ln in select e from jsonb_array_elements(p_lines) e loop
    i := i + 1;
    insert into public.gl_journal_lines (journal_id, line_no, account_code, debit, credit, memo)
    values (jid, i, ln->>'account', round(coalesce((ln->>'debit')::numeric, 0), 2), round(coalesce((ln->>'credit')::numeric, 0), 2), ln->>'memo');
  end loop;
  return jid;
end $fn$;
revoke execute on function public.fn_accountant_draft_entry(date, text, text, text, jsonb) from public, anon, authenticated;

-- ── 2. STRIPE'S OWN FEES, FROM ITS BALANCE TRANSACTIONS ──────────────────────────────────────────
-- p_bts: Stripe balance transaction objects of type stripe_fee or tax (amount negative, in fils).
create or replace function public.fn_accountant_book_stripe_fees(p_livemode boolean, p_bts jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare x jsonb; v_amt numeric; v_date date; v_memo text; n_posted int := 0; n_draft int := 0; n_seen int := 0; v_lines jsonb;
begin
  if jsonb_typeof(p_bts) is distinct from 'array' then
    raise exception 'fn_accountant_book_stripe_fees(livemode, balance_transactions[]): an array is required';
  end if;
  for x in select e from jsonb_array_elements(p_bts) e loop
    n_seen := n_seen + 1;
    continue when coalesce(x->>'id', '') !~ '^txn_' or x->>'type' not in ('stripe_fee', 'tax') or lower(coalesce(x->>'currency', '')) <> 'aed';
    continue when exists (select 1 from public.gl_journal g where g.source in ('stripe_fee_bt', 'stripe_fee_bt_test') and g.source_ref = x->>'id');
    v_amt := abs((x->>'amount')::numeric) / 100.0;
    continue when v_amt = 0;
    v_date := (to_timestamp((x->>'created')::bigint) at time zone 'Asia/Dubai')::date;
    v_memo := case x->>'type' when 'tax' then 'VAT Stripe charged on its own fees (not recoverable: QuotesDone is not VAT-registered)'
                               else 'Stripe fee billed separately: ' || coalesce(x->>'description', 'stripe_fee') end || ' [' || (x->>'id') || ']';
    v_lines := jsonb_build_array(jsonb_build_object('account', '6100', 'debit', v_amt),
                                 jsonb_build_object('account', '1050', 'credit', v_amt));
    if p_livemode then
      perform public.fn_gl_entry(v_date, v_memo, 'stripe_fee_bt', x->>'id', v_lines, 'accountant');
      n_posted := n_posted + 1;
    else
      perform public.fn_accountant_draft_entry(v_date, 'TEST MODE, never posted: ' || v_memo, 'stripe_fee_bt_test', x->>'id', v_lines);
      n_draft := n_draft + 1;
    end if;
  end loop;
  return jsonb_build_object('seen', n_seen, 'posted', n_posted, 'drafted', n_draft, 'livemode', p_livemode);
end $fn$;
revoke execute on function public.fn_accountant_book_stripe_fees(boolean, jsonb) from public, anon, authenticated;

-- ── 3. THE BANK'S OWN CHARGES, FROM THE STATEMENT ────────────────────────────────────────────────
create or replace function public.fn_accountant_book_bank_charges()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_hold boolean := coalesce((select num_value from public.gl_settings where key = 'bank_booking_on_hold'), 1) <> 0;
  v_pat text := coalesce((select txt_value from public.gl_settings where key = 'bank_charge_pattern'), 'charge|fee');
  l record; v_lines jsonb; v_memo text; n_posted int := 0; n_draft int := 0;
begin
  for l in select * from public.bank_statement_line b
            where b.amount_aed < 0 and b.description ~* v_pat
              and not exists (select 1 from public.gl_journal g where g.source = 'bank_charge' and g.source_ref = b.id::text)
            order by b.value_date, b.id loop
    v_lines := jsonb_build_array(jsonb_build_object('account', '6300', 'debit', abs(l.amount_aed)),
                                 jsonb_build_object('account', '1000', 'credit', abs(l.amount_aed)));
    v_memo := case when l.account = 'zz_demo' then 'ZZ DEMO ' else '' end || 'Bank charge (' || l.account || ', ' || l.value_date || '): ' || left(l.description, 120);
    if v_hold or l.account = 'zz_demo' then
      perform public.fn_accountant_draft_entry(l.value_date, v_memo, 'bank_charge', l.id::text, v_lines);
      n_draft := n_draft + 1;
    else
      perform public.fn_gl_entry(l.value_date, v_memo, 'bank_charge', l.id::text, v_lines, 'accountant');
      n_posted := n_posted + 1;
    end if;
  end loop;
  return jsonb_build_object('posted', n_posted, 'drafted', n_draft, 'hold', v_hold,
    'drafts_waiting', (select count(*) from public.gl_journal where source = 'bank_charge' and status = 'draft'),
    'drafts_waiting_aed', (select coalesce(sum(jl.debit), 0) from public.gl_journal g join public.gl_journal_lines jl on jl.journal_id = g.id
                            where g.source = 'bank_charge' and g.status = 'draft'),
    'basis', case when v_hold then 'gl_settings.bank_booking_on_hold = 1 (the founder''s 9 Sep 2026 instruction): bank charges are prepared as drafts and reported, not posted.'
                  else 'bank_booking_on_hold = 0: bank charges posted to 6300 against 1000.' end);
end $fn$;
revoke execute on function public.fn_accountant_book_bank_charges() from public, anon, authenticated;

-- ── 4. THE DUTY ──────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_accountant_cost_booking_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_sync int; v_bank jsonb;
begin
  v_sync := public.fn_gl_sync_business();
  v_bank := public.fn_accountant_book_bank_charges();
  return jsonb_build_object('gl_sync_business_entries', v_sync, 'bank_charges', v_bank);
end $fn$;
revoke execute on function public.fn_accountant_cost_booking_tick() from public, anon, authenticated;
