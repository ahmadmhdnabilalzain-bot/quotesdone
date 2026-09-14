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
-- 14 Sep 2026 (section 3b): fn_accountant_book_bank_credits books a transfer from the licence holder's own
-- account as Dr 1000 / Cr 3000 Owner Capital (founder_instruction 357) and the bank's month-end interest as
-- Dr 1000 / Cr 7000 Bank Interest Income (type other_income: no revenue total counts it), under the same hold,
-- and makes every other unmatched credit an accountant finding. Probe: scripts/checks/owner_capital_fixtures.sql.
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
  begin
    insert into public.gl_journal (entry_date, memo, source, source_ref, created_by, status)
    values (p_date, p_memo, p_source, p_ref, 'accountant', 'draft') returning id into jid;
  exception when unique_violation then
    -- a concurrent run wrote it between the check and the insert (gl_journal_one_live_entry_per_bank_or_fee_line)
    select id into jid from public.gl_journal where source = p_source and source_ref = p_ref and status in ('draft', 'posted') limit 1;
    return jid;
  end;
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
        v_items jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(p_bts) is distinct from 'array' then
    raise exception 'fn_accountant_book_stripe_fees(livemode, balance_transactions[]): an array is required';
  end if;
  for x in select e from jsonb_array_elements(p_bts) e loop
    n_seen := n_seen + 1;
    continue when coalesce(x->>'id', '') !~ '^txn_' or x->>'type' not in ('stripe_fee', 'tax');
    -- A FEE IN ANOTHER CURRENCY IS A FINDING, NOT A SILENT SKIP (review of #645): the ledger is AED and
    -- gl_settings carries no rate for it, so it cannot be booked without a guess, and must not vanish.
    if lower(coalesce(x->>'currency', '')) <> 'aed' then
      v_items := v_items || jsonb_build_object('item', 'currency:' || (x->>'id'), 'owner_seat', 'accountant', 'subject', 'stripe_fees',
        'title', 'Stripe charged a ' || (x->>'type') || ' of ' || round(abs((x->>'amount')::numeric) / 100.0, 2) || ' '
                 || upper(coalesce(x->>'currency', '?')) || ' (' || (x->>'id') || ') and the AED ledger has no rate to book it',
        'blast', 'agent_facing', 'affected', 1, 'demo', not p_livemode, 'evidence', x);
      continue;
    end if;
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
  return jsonb_build_object('seen', n_seen, 'posted', n_posted, 'drafted', n_draft, 'livemode', p_livemode,
    'findings', public.fn_accountant_duty_settle('stripe_fees_' || case when p_livemode then 'live' else 'test' end, v_items));
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

-- ── 3b. MONEY THAT COMES INTO THE BANK: OWNER CAPITAL, BANK INTEREST, OR A FINDING (14 Sep 2026) ──
-- Founder, 14 Sep 2026 (founder_instruction 357), on the August 2026 statement's one transfer in, a
-- person-to-person transfer from his own account: "yea capital from my other account". It is not revenue
-- and not a loan, and it is the standing default: a transfer from his own account is capital unless he
-- says loan.
-- MEASURED BEFORE THIS: nothing classified a bank CREDIT at all. fn_accountant_bank_reconcile only matches
-- credits to Stripe payouts; any other credit sat in bank_statement_line with no journal and no finding.
-- WHAT THIS DOES, deterministically, for a credit not matched to a Stripe payout:
--   * OWNER TRANSFER: the description carries a transfer marker (gl_settings.owner_transfer_pattern) AND one
--     of its " - " separated segments (the bank prints the sender as its own segment) IS the licence holder's
--     name from company_registration.owner_name, word for word and nothing else in that segment — a relative
--     who shares his names is a different, longer segment and is refused. Booked Dr 1000 Cash & Bank /
--     Cr 3000 Owner Capital (the chart's existing equity account).
--   * BANK INTEREST: Mashreq's month-end interest row — the description says interest
--     (gl_settings.bank_interest_pattern) AND carries the bank's interest reference type
--     (gl_settings.bank_interest_reference_pattern, CID...AED nnnnn). Booked Dr 1000 / Cr 7000 Bank Interest
--     Income.
--   * bank_line_owner_ruling records his word on one line; 'loan' overrides the default and is a finding
--     (the chart has no owner-loan account), never capital.
--   * anything else still unmatched once the payout window has passed is an accountant finding. Nothing is
--     guessed. Every entry respects the founder's bank-booking hold exactly as bank charges do: while
--     gl_settings.bank_booking_on_hold is 1 it is a DRAFT, prepared and reported, not posted.
-- REVIEW OF b06d251 (four defects, all fixed here):
--   1. 7000 was typed 'revenue', and fn_accountant_month_close_figures sums type='revenue' into the CEO's
--      revenue_aed. MEASURED 14 Sep 2026, every production reader that totals revenue: month close,
--      fn_company_self_knowledge_sync, fn_finance_forecast, fn_ws_finance, and the views gl_pnl and
--      finance_kpis select type = 'revenue'; fn_accountant_vat_threshold_check and fn_ceo_weekly_figures
--      select account_code like '4%'. So 7000 gets its own type, 'other_income', which the type check now
--      allows; 3000 is 'equity' in the 3xxx range. Neither can be counted as revenue by any of them.
--      CEILING, stated: those readers also leave 'other_income' out of net income, so bank interest (fils a
--      month) is in the ledger and the balances but not in their P&L totals until a reader shows other income.
--   2. A pattern read from gl_settings was used unvalidated, and an invalid one raised out of the whole
--      'costs' step of the hourly duty, undoing the business sync and the bank charges. Each pattern is now
--      validated once per run in its own block: a bad one is one accountant finding naming the setting and
--      its rule books nothing; and the tick runs this rule in its own block, so nothing else is undone.
--   3. Idempotency was check-then-insert. MEASURED: 0 duplicate (source, source_ref) pairs among the 58
--      journals. A unique index now holds one live journal per source_ref for the sources booked from the bank
--      and from Stripe's fee lines, whose writers all key one entry per ref. It is NOT table-wide: not every
--      source fn_gl_sync_business writes was proven single-entry-per-ref, and a table-wide index would turn
--      that unproven assumption into a failed posting of real revenue. The bookings tolerate the violation.
--   4. The name match accepted a superset (every owner word plus others). It now needs the whole segment to
--      be the name. unaccent is AVAILABLE on the project but NOT installed (measured 14 Sep 2026); the
--      normaliser uses it the moment it is, and until then compares A-Z/0-9 only (Mashreq prints the sender
--      in ASCII capitals).
insert into public.gl_settings (key, num_value, txt_value) values
  ('owner_transfer_pattern', null, 'transfer|p_?2_?p'),
  ('bank_interest_pattern', null, '(^|[^a-z])interest([^a-z]|$)'),
  ('bank_interest_reference_pattern', null, 'CID[A-Z]*AED [0-9]{5}')
on conflict (key) do nothing;

alter table public.gl_accounts drop constraint if exists gl_accounts_type_check;
alter table public.gl_accounts add constraint gl_accounts_type_check
  check (type in ('asset', 'liability', 'equity', 'revenue', 'expense', 'other_income'));
insert into public.gl_accounts (code, name, type, subtype, normal_balance, description) values
  ('7000', 'Bank Interest Income', 'other_income', 'interest', 'C',
   'Interest the bank credits. Not a taxable supply and not revenue: outside 4xxx and outside type revenue, so no revenue total or the VAT watch counts it.')
on conflict (code) do nothing;

create unique index if not exists gl_journal_one_live_entry_per_bank_or_fee_line on public.gl_journal (source, source_ref)
  where source in ('owner_capital', 'bank_interest', 'bank_charge', 'stripe_fee_bt', 'stripe_fee_bt_test')
    and source_ref is not null and status in ('draft', 'posted');

create table if not exists public.bank_line_owner_ruling (
  line_id                bigint primary key references public.bank_statement_line(id),
  ruling                 text not null check (ruling in ('capital', 'loan')),
  founder_instruction_id bigint,          -- public.founder_instruction.id carrying his words
  noted_at               timestamptz not null default now()
);
comment on table public.bank_line_owner_ruling is
  'The founder''s word on one bank credit from his own account. Default without a row: capital (founder_instruction 357). ''loan'' keeps it out of 3000 Owner Capital and raises an accountant finding.';
alter table public.bank_line_owner_ruling enable row level security;
drop policy if exists bank_line_owner_ruling_service_role_only on public.bank_line_owner_ruling;
create policy bank_line_owner_ruling_service_role_only on public.bank_line_owner_ruling
  as permissive for all to public using (false) with check (false);
revoke all on public.bank_line_owner_ruling from anon, authenticated;

-- A name as comparable words: accents removed when unaccent is installed, then A-Z and 0-9 only.
create or replace function public.fn_name_norm(p text)
returns text language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v text := coalesce(p, '');
begin
  if to_regprocedure('public.unaccent(text)') is not null then execute 'select public.unaccent($1)' into v using v;
  elsif to_regprocedure('extensions.unaccent(text)') is not null then execute 'select extensions.unaccent($1)' into v using v;
  end if;
  return btrim(regexp_replace(upper(v), '[^A-Z0-9]+', ' ', 'g'));
end $fn$;
revoke execute on function public.fn_name_norm(text) from public, anon, authenticated;

drop function if exists public.fn_bank_line_is_owner_transfer(text);
-- Whether a bank line is a transfer from the licence holder's own account. p_pattern is the validated
-- owner_transfer_pattern; the caller validates it (a bad pattern never reaches here).
create or replace function public.fn_bank_line_is_owner_transfer(p_description text, p_pattern text)
returns boolean language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_owner text;
begin
  if p_pattern is null or coalesce(p_description, '') !~* p_pattern then return false; end if;
  select public.fn_name_norm(owner_name) into v_owner from public.company_registration order by recorded_at desc limit 1;
  if v_owner is null or position(' ' in v_owner) = 0 then return false; end if;      -- two words at least
  return exists (select 1 from regexp_split_to_table(p_description, '(^|[[:space:]])-([[:space:]]|$)') seg
                  where public.fn_name_norm(seg) = v_owner);
end $fn$;
revoke execute on function public.fn_bank_line_is_owner_transfer(text, text) from public, anon, authenticated;

create or replace function public.fn_accountant_book_bank_credits()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_hold boolean := coalesce((select num_value from public.gl_settings where key = 'bank_booking_on_hold'), 1) <> 0;
  v_after int := coalesce((select num_value::int from public.gl_settings where key = 'bank_match_days_after'), 5);
  v_today date := (now() at time zone 'Asia/Dubai')::date;
  v_pat jsonb := '{}'::jsonb; k text; v text;
  l record; v_lines jsonb; v_memo text; v_src text; v_booked boolean;
  n_posted int := 0; n_draft int := 0; n_raced int := 0; v_items jsonb := '[]'::jsonb;
begin
  -- Each pattern validated once, in its own block: a bad one is a finding and its rule books nothing.
  foreach k in array array['owner_transfer_pattern', 'bank_interest_pattern', 'bank_interest_reference_pattern'] loop
    v := (select txt_value from public.gl_settings where key = k);
    begin
      if coalesce(btrim(v), '') = '' then raise exception 'the setting is missing or empty'; end if;
      perform ('' ~ v);
      v_pat := v_pat || jsonb_build_object(k, v);
    exception when others then
      v_items := v_items || jsonb_build_object('item', 'setting:' || k, 'owner_seat', 'accountant', 'subject', 'gl_settings',
        'title', 'gl_settings.' || k || ' is not a usable pattern (' || sqlerrm || '), so the rule it drives books nothing until it is corrected',
        'blast', 'agent_facing', 'affected', 1, 'evidence', jsonb_build_object('key', k, 'value', v));
    end;
  end loop;

  for l in select b.*, r.ruling, r.founder_instruction_id
             from public.bank_statement_line b left join public.bank_line_owner_ruling r on r.line_id = b.id
            where b.amount_aed > 0
              and not exists (select 1 from public.stripe_payout p where p.bank_line_id = b.id)
            order by b.value_date, b.id loop
    v_booked := exists (select 1 from public.gl_journal g where g.source in ('owner_capital', 'bank_interest')
                          and g.source_ref = l.id::text and g.status in ('draft', 'posted'));
    if l.ruling = 'loan' then
      v_items := v_items || jsonb_build_object('item', 'loan:' || l.id, 'owner_seat', 'accountant', 'subject', 'bank_statement_line',
        'title', 'A credit of AED ' || l.amount_aed || ' on ' || l.value_date || ' was ruled a loan from the founder, and the chart has no owner-loan account'
                 || case when v_booked then '; the entry already made for it must be reversed' else '' end,
        'blast', 'agent_facing', 'affected', 1, 'demo', l.account = 'zz_demo',
        'evidence', jsonb_build_object('line_id', l.id, 'source_ref', l.source_ref, 'founder_instruction_id', l.founder_instruction_id));
      continue;
    end if;
    continue when v_booked;
    v_src := null;
    if l.ruling = 'capital' or (v_pat ? 'owner_transfer_pattern'
                                and public.fn_bank_line_is_owner_transfer(l.description, v_pat->>'owner_transfer_pattern')) then
      v_src := 'owner_capital';
      v_lines := jsonb_build_array(jsonb_build_object('account', '1000', 'debit', l.amount_aed),
                                   jsonb_build_object('account', '3000', 'credit', l.amount_aed));
      v_memo := 'Owner capital contribution (' || l.account || ', ' || l.value_date
                || '), a transfer from the licence holder''s own account: capital unless he says loan (founder_instruction 357): ' || left(l.description, 120);
    elsif v_pat ? 'bank_interest_pattern' and v_pat ? 'bank_interest_reference_pattern'
          and l.description ~* (v_pat->>'bank_interest_pattern') and l.description ~ (v_pat->>'bank_interest_reference_pattern') then
      v_src := 'bank_interest';
      v_lines := jsonb_build_array(jsonb_build_object('account', '1000', 'debit', l.amount_aed),
                                   jsonb_build_object('account', '7000', 'credit', l.amount_aed));
      v_memo := 'Bank interest credited (' || l.account || ', ' || l.value_date || '): ' || left(l.description, 120);
    elsif l.value_date + v_after < v_today then
      v_items := v_items || jsonb_build_object('item', 'unrecognised:' || l.id, 'owner_seat', 'accountant', 'subject', 'bank_statement_line',
        'title', 'A credit of AED ' || l.amount_aed || ' on ' || l.value_date || ' is neither a Stripe payout, a transfer from the licence holder''s own account nor the bank''s interest, so it is not booked',
        'blast', 'agent_facing', 'affected', 1, 'demo', l.account = 'zz_demo',
        'evidence', jsonb_build_object('line_id', l.id, 'source_ref', l.source_ref, 'description', left(l.description, 200),
                                       'remedy', 'the founder names what it is; an owner transfer is recorded in bank_line_owner_ruling'));
    end if;
    continue when v_src is null;
    if l.account = 'zz_demo' then v_memo := 'ZZ DEMO ' || v_memo; end if;
    begin
      if v_hold or l.account = 'zz_demo' then
        perform public.fn_accountant_draft_entry(l.value_date, v_memo, v_src, l.id::text, v_lines);
        n_draft := n_draft + 1;
      else
        perform public.fn_gl_entry(l.value_date, v_memo, v_src, l.id::text, v_lines, 'accountant');
        n_posted := n_posted + 1;
      end if;
    exception when unique_violation then
      n_raced := n_raced + 1;        -- a concurrent run booked this line first: gl_journal_one_live_entry_per_bank_or_fee_line
    end;
  end loop;
  return jsonb_build_object('posted', n_posted, 'drafted', n_draft, 'booked_by_a_concurrent_run', n_raced, 'hold', v_hold,
    'findings', public.fn_accountant_duty_settle('bank_credits', v_items));
end $fn$;
revoke execute on function public.fn_accountant_book_bank_credits() from public, anon, authenticated;

-- ── 4. THE DUTY ──────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_accountant_cost_booking_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare v_sync int; v_bank jsonb; v_cap jsonb;
begin
  v_sync := public.fn_gl_sync_business();
  v_bank := public.fn_accountant_book_bank_charges();
  -- The bank-credit rule runs in its own block (review of b06d251): whatever fails in it can never undo the
  -- business sync or the bank charges above; the failure is an accountant finding instead.
  begin
    v_cap := public.fn_accountant_book_bank_credits();
    perform public.fn_accountant_duty_settle('bank_credits_run', '[]'::jsonb);
  exception when others then
    v_cap := jsonb_build_object('error', sqlerrm);
    perform public.fn_accountant_duty_settle('bank_credits_run', jsonb_build_array(jsonb_build_object(
      'item', 'run', 'owner_seat', 'accountant', 'subject', 'bank_statement_line',
      'title', 'Booking the bank''s credits failed, so nothing was booked from them this run: ' || sqlerrm,
      'blast', 'agent_facing', 'affected', 1)));
  end;
  return jsonb_build_object('gl_sync_business_entries', v_sync, 'bank_charges', v_bank, 'bank_credits', v_cap);
end $fn$;
revoke execute on function public.fn_accountant_cost_booking_tick() from public, anon, authenticated;
