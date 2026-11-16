-- A MASHREQ FEE THE BANK HAS NOT TAKEN IS OWED, NOT PAID; AND THE FEE OF 1 AUGUST 2026 IS BOOKED.
-- Seat: accountant (agent: L6_BOOKS, accountant seat builder). 16 Nov 2026. Founder rulings 1702 ("bank 210 monthly fee
-- since july") and 1703 ("Mashreq bank / Yes you can"). Review SP/show/REVIEW_L6_L7.md (L6 items 1 and 2 and the
-- coordinator's ask: an uncollected fee is an accrued liability, cleared to cash when a statement shows the debit).
-- Needs the_books_hold_a_cost_on_the_founders_word_until_its_document_arrives.sql (live since 15 Nov).
-- DRY RUN FIRST: ..._dry_run.sql (writes nothing). PROBE AFTER: the_mashreq_fees_of_july_to_november_2026_are_each_in_the_books_once_probe.sql.
--
-- WHAT THE BOOKS HELD (SELECT 16 Nov 2026). The audit of the open ledger (LEDGER_OPEN #14) read expense_entries only:
-- "Mashreq only 1 Nov; Jul-Oct not booked". The statements' fees are booked by fn_accountant_book_bank_charges as
-- 'bank_charge' journals, not expense rows:
--   19 Aug 2026  199.00 + 9.95  statement lines 231/232    journals 692/693
--    1 Sep 2026  199.00 + 9.95  statement lines 234/233    journals 695/694
--    1 Oct 2026  199.00 + 9.95  statement lines 2268/2267  journals 2647/2646
--    1 Nov 2026  199.00 + 9.95  the founder's word (1702): expense 3353/3354, journals 5265/5266 (Dr 6300 / Cr 1000)
-- Four fees in 6300 (835.80). "Since july" is FIVE fees, July to November.
--
-- THE FIFTH FEE IS IN A DOCUMENT. The September statement (issued 2 Oct 2026, bank_statement_intake
-- 'chat:mashreq-statement-2026-09 (issued 2026-10-02)') lists AED 208.95 UNCOLLECTED: fee 199 + VAT 9.95 initiated
-- 2026-08-01, 62 days overdue. That statement CLOSED AT AED 59.25, less than the fee: that is why the bank had not taken it.
-- Finding acct:bank_statement_2026_09:uncollected_aug_fee said so on 4 Oct; ruling 1559 closed it on 10 Nov unbooked. No
-- later statement has arrived. No separate July DEBIT exists in any document, so no sixth fee is booked.
--
-- WHY NOT CASH. fn_accountant_expense_on_founder_word posted every held fee Dr cost / Cr 1000 Cash & Bank. A fee the bank
-- has not taken is money OWED to the bank, not cash paid: crediting 1000 would show the books' bank 208.95 below the bank
-- until a statement arrived. The chart has 2200 Accrued Expenses (liability, unused: balance 0.00 on 16 Nov). So:
--   1. fn_accountant_expense_on_founder_word: a cost waiting for its BANK STATEMENT posts Dr cost / Cr 2200 (a cost waiting
--      for a receipt is unchanged: it was paid by card and posts through fn_expense_post_to_gl as before).
--   2. fn_accountant_attach_statement_line: when the statement line that pays a held fee attaches to it (no second cost,
--      as before), it now also posts Dr 2200 / Cr 1000 on the line's date (source 'bank_charge_settles_accrual', the line
--      id), which moves the debt to cash. One cost, one payment, nothing twice; idempotent (one per line).
--   3. THE 1 NOV FEE HAD THE SAME FAULT: 3353/3354 credited 1000 although no statement shows them taken. Each fee still
--      awaiting its statement whose journal credited 1000 gets one reclass, Dr 1000 / Cr 2200 (source 'expense_accrual',
--      the expense id), today. Its cost is untouched.
--   4. The 1 Aug fee is booked: two entries, 199.00 and 9.95, Mashreq, 'Bank charges' -> 6300, dated 1 Aug 2026 (the date
--      the bank initiated them), held on ledger 1702, Dr 6300 / Cr 2200. August is closed (accountant_month_close), so
--      fn_gl_post books the journals in the open period as a prior-period adjustment (gl_prior_period_adjustment; IFRS for
--      SMEs s.10: an immaterial item is corrected in the current period). A later statement line attaches to the OLDEST
--      held fee of its amount (this one before November's) and settles it.
-- After this file: 6300 holds 1,044.75 (5 x 208.95) of these fees; 2200 holds 417.90 (the 1 Aug and 1 Nov fees, owed);
-- 1000 is unchanged by the 1 Aug fee and is 208.95 higher than before for the 1 Nov fee (its cash credit moves to 2200).
-- Both routines are rebuilt from production's bodies (md5 40b0e0c8... and 956a3cc7..., 16 Nov 2026) with only the
-- changes above. CREATE OR REPLACE keeps their grants; the revokes below restate them.
CREATE OR REPLACE FUNCTION public.fn_accountant_expense_on_founder_word(p_vendor text, p_charged_on date, p_amount numeric, p_currency text, p_vat_amount numeric, p_category text, p_reason text, p_founder_instruction_id bigint, p_awaits text, p_dry_run boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_vendor text := btrim(coalesce(p_vendor, ''));
  v_cur text := upper(btrim(coalesce(p_currency, 'AED')));
  v_cat text := coalesce(nullif(btrim(p_category), ''), case when p_awaits = 'bank_statement' then 'Bank charges' else 'Subscription' end);
  v_key text; v_acct text; v_dup record; v_line record; v_id bigint; v_jid bigint; v_note text; v_fx numeric; v_aed numeric;
begin
  if v_vendor = '' then raise exception 'fn_accountant_expense_on_founder_word: a vendor is required'; end if;
  if p_charged_on is null or p_charged_on > (now() at time zone 'Asia/Dubai')::date then
    raise exception 'fn_accountant_expense_on_founder_word: the date must be given and not in the future (%)', p_charged_on;
  end if;
  if p_amount is null or p_amount <= 0 or p_amount <> round(p_amount, 2) then
    raise exception 'fn_accountant_expense_on_founder_word: the amount must be positive, to the fils (%)', p_amount;
  end if;
  if v_cur not in ('AED', 'USD') then raise exception 'fn_accountant_expense_on_founder_word: currency % has no rate in gl_settings', v_cur; end if;
  if p_vat_amount is not null and (p_vat_amount < 0 or p_vat_amount >= p_amount) then
    raise exception 'fn_accountant_expense_on_founder_word: the VAT must be below the amount (%)', p_vat_amount;
  end if;
  if coalesce(btrim(p_reason), '') = '' then raise exception 'fn_accountant_expense_on_founder_word: the reason is required'; end if;
  if p_awaits is null or p_awaits not in ('bank_statement', 'receipt') then
    raise exception 'fn_accountant_expense_on_founder_word: awaits is bank_statement or receipt, not %', p_awaits;
  end if;
  -- a statement line is in AED: a cost in another currency could never attach to it and would wait for ever
  if p_awaits = 'bank_statement' and v_cur <> 'AED' then
    raise exception 'fn_accountant_expense_on_founder_word: a cost waiting for a bank statement is in AED (statement lines are AED), not %', v_cur;
  end if;
  if length(btrim(regexp_replace(lower(v_vendor), '[^a-z0-9]+', ' ', 'g'))) < 3 then
    raise exception 'fn_accountant_expense_on_founder_word: the vendor % is too short to match its document (3 letters or digits at least)', v_vendor;
  end if;
  if not exists (select 1 from public.founder_instruction where id = p_founder_instruction_id) then
    raise exception 'fn_accountant_expense_on_founder_word: founder ledger entry % does not exist; a cost on his word names the entry', p_founder_instruction_id;
  end if;

  v_key := 'stated:' || p_founder_instruction_id || ':' || lower(regexp_replace(v_vendor, '[^A-Za-z0-9]+', '-', 'g'))
           || ':' || p_charged_on || ':' || p_amount;
  v_acct := coalesce((select account_code from public.gl_expense_map where category = v_cat), '6300');
  select num_value into v_fx from public.gl_settings where key = 'usd_to_aed';
  v_aed := round(p_amount * case when v_cur = 'USD' then coalesce(v_fx, 3.6725) else 1 end, 2);

  -- already booked by this action: say so, never twice
  select e.id, g.id as jid into v_dup from public.expense_entries e
    left join public.gl_journal g on g.source = 'expense' and g.source_ref = e.id::text
   where e.source_msg_id = v_key limit 1;
  if v_dup.id is not null then
    return jsonb_build_object('booked', false, 'already', true, 'entry_id', v_dup.id, 'journal_id', v_dup.jid, 'key', v_key);
  end if;
  -- a document already books this cost: refuse rather than count it twice. The same vendor in the same month (or within
  -- 7 days across a month end), in ANY currency, whose AED equivalent is within 10% of this one (card FX and fees).
  select e.id, e.charged_on, e.source, e.amount, e.currency, x.aed into v_dup
    from public.expense_entries e
    cross join lateral (select round(e.amount * case when upper(coalesce(e.currency, 'AED')) = 'USD' then coalesce(v_fx, 3.6725) else 1 end, 2) as aed) x
   where public.fn_expense_same_vendor(e.vendor, v_vendor)
     and upper(coalesce(e.currency, 'AED')) in ('AED', 'USD')
     and (date_trunc('month', e.charged_on) = date_trunc('month', p_charged_on) or abs(e.charged_on - p_charged_on) <= 7)
     and abs(x.aed - v_aed) <= greatest(0.10 * greatest(x.aed, v_aed), 0.01)
   order by abs(x.aed - v_aed), abs(e.charged_on - p_charged_on) limit 1;
  if v_dup.id is not null then
    return jsonb_build_object('booked', false, 'refused', 'already_booked', 'key', v_key,
      'reason', 'expense #' || v_dup.id || ' (' || v_dup.source || ', ' || v_dup.charged_on || ', ' || v_dup.amount || ' ' || v_dup.currency
                || ' = AED ' || v_dup.aed || ') already books ' || v_vendor || ' in that month within 10% of AED ' || v_aed);
  end if;
  if p_awaits = 'bank_statement' then
    select b.id, b.value_date into v_line from public.bank_statement_line b
     where lower(b.account) = lower(split_part(v_vendor, ' ', 1)) and b.amount_aed = -v_aed and abs(b.value_date - p_charged_on) <= 7
     order by abs(b.value_date - p_charged_on) limit 1;
    if v_line.id is not null then
      return jsonb_build_object('booked', false, 'refused', 'statement_shows_it', 'key', v_key,
        'reason', 'statement line ' || v_line.id || ' (' || v_line.value_date || ') already carries AED ' || v_aed || '; the statement books it');
    end if;
  end if;

  v_note := 'Booked on the founder''s word (ledger ' || p_founder_instruction_id || '), awaiting the '
            || case when p_awaits = 'bank_statement' then 'bank statement' else 'receipt' end || ': ' || btrim(p_reason)
            || case when coalesce(p_vat_amount, 0) > 0 then ' (VAT ' || p_vat_amount || ' ' || v_cur || ' is part of the cost: the company is not VAT-registered)' else '' end;
  if p_dry_run then
    return jsonb_build_object('booked', false, 'dry_run', true, 'key', v_key,
      'would_book', jsonb_build_object('vendor', v_vendor, 'category', v_cat, 'account', v_acct, 'amount', p_amount, 'currency', v_cur,
                                       'amount_aed', v_aed, 'vat_amount', p_vat_amount, 'charged_on', p_charged_on, 'awaits', p_awaits,
                                       'journal', 'Dr ' || v_acct || ' / Cr ' || case when p_awaits = 'bank_statement' then '2200 Accrued Expenses' else '1000 Cash & Bank' end || ', AED ' || v_aed),
      'note', v_note);
  end if;

  insert into public.expense_entries (vendor, category, amount, currency, charged_on, vat_amount, source, doc_kind, doc_note, source_msg_id, note)
  values (v_vendor, v_cat, p_amount, v_cur, p_charged_on, p_vat_amount, 'founder_reported', 'founder_statement', v_note, v_key, v_note)
  returning id into v_id;
  insert into public.expense_awaiting_document (expense_entry_id, awaits, founder_instruction_id, reason, stated_key)
  values (v_id, p_awaits, p_founder_instruction_id, btrim(p_reason), v_key);
  if p_awaits = 'bank_statement' then
    -- OWED, NOT PAID (16 Nov 2026, review of the 1 Aug fee): a fee waiting for its statement is a debt to the bank until a
    -- statement shows it taken, so it is credited to 2200 Accrued Expenses, never to 1000 (the bank had not taken the 1 Aug
    -- fee: the September statement closed at 59.25). fn_accountant_attach_statement_line moves it to 1000 when it is taken.
    v_jid := public.fn_gl_entry(p_charged_on, 'Expense: ' || v_vendor || ' - ' || v_cat || ', owed to the bank until its statement shows it taken',
      'expense', v_id::text,
      jsonb_build_array(jsonb_build_object('account', v_acct, 'debit', v_aed, 'memo', v_vendor || ' ' || v_cat),
                        jsonb_build_object('account', '2200', 'credit', v_aed, 'memo', 'owed to ' || v_vendor)),
      'accountant');
  else
    v_jid := public.fn_expense_post_to_gl(v_id);
  end if;
  return jsonb_build_object('booked', true, 'entry_id', v_id, 'journal_id', v_jid, 'key', v_key, 'account', v_acct, 'amount_aed', v_aed,
                            'awaits', p_awaits);
end $function$;
revoke execute on function public.fn_accountant_expense_on_founder_word(text, date, numeric, text, numeric, text, text, bigint, text, boolean) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.fn_accountant_attach_statement_line(p_line_id bigint)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare l public.bank_statement_line; h record; v_owed numeric;
begin
  select * into l from public.bank_statement_line where id = p_line_id;
  if not found or l.amount_aed >= 0 or l.kind is distinct from 'bank_charge' then return null; end if;
  if exists (select 1 from public.expense_bank_match m where m.bank_line_id = l.id) then
    return (select m.expense_entry_id from public.expense_bank_match m where m.bank_line_id = l.id);
  end if;
  -- the OLDEST held fee of this bank and amount that the line can be: dated at most 7 days after the line, and NO upper
  -- limit on how late the line comes (Mashreq takes the fee when the account has money; review item 1)
  select e.id, e.amount, e.charged_on into h
    from public.expense_awaiting_document x join public.expense_entries e on e.id = x.expense_entry_id
   where x.state = 'awaiting' and x.awaits = 'bank_statement'
     and upper(e.currency) = 'AED' and e.amount = -l.amount_aed
     and e.charged_on <= l.value_date + 7
     and lower(split_part(btrim(e.vendor), ' ', 1)) = lower(l.account)
     and not exists (select 1 from public.expense_bank_match m where m.expense_entry_id = e.id)
   order by e.charged_on, e.id
   limit 1
   for update of x;
  if h.id is null then return null; end if;
  insert into public.expense_bank_match (expense_entry_id, bank_line_id, receipt_aed, bank_aed, day_gap, vendor_in_text)
  values (h.id, l.id, h.amount, -l.amount_aed, l.value_date - h.charged_on, false);
  update public.expense_awaiting_document
     set state = 'attached', attached_kind = 'bank_statement_line', attached_ref = l.id::text, attached_at = now(),
         attached_detail = jsonb_build_object('how', 'the statement line was linked to the held entry; no second journal',
                                              'statement', l.source_ref, 'value_date', l.value_date, 'amount_aed', l.amount_aed,
                                              'day_gap', l.value_date - h.charged_on)
   where expense_entry_id = h.id;
  -- THE BANK HAS NOW TAKEN IT (16 Nov 2026): a fee held as owed (2200 Accrued Expenses, by fn_accountant_expense_on_founder_word
  -- or the reclass of the 1 Nov fee) is paid by this line: Dr 2200 / Cr 1000 on the line's date. The cost was booked once,
  -- when it was owed; this moves only the debt to cash. A fee held against 1000 (none since this file) settles nothing here.
  select coalesce(sum(jl.credit - jl.debit), 0) into v_owed
    from public.gl_journal g join public.gl_journal_lines jl on jl.journal_id = g.id and jl.account_code = '2200'
   where g.status = 'posted' and g.source in ('expense', 'expense_accrual') and g.source_ref = h.id::text;
  if v_owed > 0 and not exists (select 1 from public.gl_journal g where g.source = 'bank_charge_settles_accrual' and g.source_ref = l.id::text and g.status <> 'void') then
    perform public.fn_gl_entry(l.value_date,
      'Bank charge (' || l.account || ', ' || l.value_date || ') pays the fee #' || h.id || ' owed since ' || h.charged_on || ': '
        || left(public.fn_mask_bank_text(l.description), 100),
      'bank_charge_settles_accrual', l.id::text,
      jsonb_build_array(jsonb_build_object('account', '2200', 'debit', least(v_owed, -l.amount_aed)),
                        jsonb_build_object('account', '1000', 'credit', least(v_owed, -l.amount_aed))),
      'accountant');
  end if;
  return h.id;
end $function$;
revoke execute on function public.fn_accountant_attach_statement_line(bigint) from public, anon, authenticated;

-- 3. the fees still waiting for their statement and held against cash move to 2200 (the 1 Nov pair on 16 Nov 2026)
do $do$
declare e record; v_cash numeric;
begin
  for e in select x.expense_entry_id as id, ee.vendor, ee.charged_on, ee.amount
             from public.expense_awaiting_document x join public.expense_entries ee on ee.id = x.expense_entry_id
            where x.awaits = 'bank_statement' and x.state = 'awaiting' order by ee.charged_on, ee.id loop
    select coalesce(sum(jl.credit - jl.debit), 0) into v_cash
      from public.gl_journal g join public.gl_journal_lines jl on jl.journal_id = g.id and jl.account_code = '1000'
     where g.status = 'posted' and g.source in ('expense', 'expense_accrual') and g.source_ref = e.id::text;
    continue when v_cash <= 0;
    perform public.fn_gl_entry((now() at time zone 'Asia/Dubai')::date,
      'Accrual: the fee #' || e.id || ' (' || e.vendor || ', ' || e.charged_on || ') is owed to the bank until its statement shows it taken; its credit moves from 1000 to 2200',
      'expense_accrual', e.id::text,
      jsonb_build_array(jsonb_build_object('account', '1000', 'debit', v_cash), jsonb_build_object('account', '2200', 'credit', v_cash)),
      'accountant');
  end loop;
end $do$;

-- 4. the fee of 1 Aug 2026; the action refuses a second booking (its stated key), so a second apply books nothing
select public.fn_accountant_expense_on_founder_word('Mashreq', date '2026-08-01', 199.00, 'AED', null, 'Bank charges',
  'Mashreq monthly maintenance fee initiated 1 Aug 2026, listed UNCOLLECTED (62 days overdue) on the September statement issued 2 Oct 2026, which closed at 59.25; the fee is monthly since July (ledger 1702) and the statements show four of the five July-November fees taken.',
  1702, 'bank_statement', false) as fee;
select public.fn_accountant_expense_on_founder_word('Mashreq', date '2026-08-01', 9.95, 'AED', null, 'Bank charges',
  'Mashreq "Value Added Tax - Output" on the maintenance fee initiated 1 Aug 2026 (5% of 199), listed uncollected on the September statement; a cost because the company is not VAT registered.',
  1702, 'bank_statement', false) as vat;

select case
  when (select count(*) from public.expense_awaiting_document x join public.expense_entries e on e.id = x.expense_entry_id
         where e.vendor = 'Mashreq' and e.charged_on = date '2026-08-01' and x.founder_instruction_id = 1702) <> 2
    then 'PROBE FAILED: expected exactly 2 held Mashreq entries for 1 Aug 2026'
  when exists (select 1 from public.expense_entries e where e.vendor = 'Mashreq' and e.charged_on = date '2026-08-01'
                and (select count(*) from public.gl_journal g where g.source = 'expense' and g.source_ref = e.id::text and g.status = 'posted') <> 1)
    then 'PROBE FAILED: a held 1 Aug 2026 Mashreq entry does not have exactly one posted journal'
  when exists (select 1 from public.expense_awaiting_document x
                where x.awaits = 'bank_statement' and x.state = 'awaiting'
                  and (select coalesce(sum(jl.credit - jl.debit), 0) from public.gl_journal g join public.gl_journal_lines jl on jl.journal_id = g.id and jl.account_code = '1000'
                        where g.status = 'posted' and g.source in ('expense', 'expense_accrual') and g.source_ref = x.expense_entry_id::text) <> 0)
    then 'PROBE FAILED: a fee still waiting for its statement moves cash (1000)'
  else 'PROBE OK: the 1 Aug 2026 fee (208.95) is booked; every fee waiting for its statement is owed in 2200, not paid from 1000'
end as verdict;
