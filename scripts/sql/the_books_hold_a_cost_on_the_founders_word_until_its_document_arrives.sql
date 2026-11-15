-- THE BOOKS HOLD A COST ON THE FOUNDER'S WORD UNTIL ITS DOCUMENT ARRIVES.
-- Seat: accountant (agent: accountant seat builder). 15 Nov 2026. Founder rulings 1702 and 1703 (15 Nov 2026).
--
-- THE FOUNDER, 1702: "Every bill in my email excluding suno and emastered are costs ... We have claude subscription since
-- may. And bank 210 monthly fee since july." 1703: "Mashreq bank / Yes you can" (book it on his word).
--
-- WHAT WAS MISSING (READ + SELECT, 15 Nov 2026)
--   * A cost the founder states, with no document yet, could only be booked by a hand-written data file
--     (the_bills_in_the_founders_gmail_that_never_reached_the_books.sql booked ChatGPT August that way, key 'stated:1538:...').
--     Nothing remembered that the entry was waiting for its document, and nothing joined the document to it when it came:
--       - a Mashreq statement line is booked by fn_accountant_book_bank_charges as its own 'bank_charge' journal, so a fee
--         booked on his word would be booked a second time when the statement arrived;
--       - the receipt intake (resend_inbound/steps/receipts.ts) joins a document to an existing entry only on the SAME date,
--         vendor, amount and currency; a receipt dated a day away booked a second expense.
--   * Mashreq statements on file (bank_statement_intake): August 2026 (opening 0.00) and September 2026 (issued 2 Oct, its
--     last fee line 1 Oct). The books hold the fee pair (199 + 9.95 "Value Added Tax - Output") on 19 Aug, 1 Sep and 1 Oct.
--
-- WHAT THIS FILE ADDS
--   1. public.expense_awaiting_document: one row per expense booked on the founder's word, naming the ledger entry
--      (founder_instruction id), the reason, what document it waits for (a bank statement or a receipt) and, once it came,
--      which document it was. The row IS the held-document flag.
--   2. fn_accountant_expense_on_founder_word(vendor, date, amount, currency, vat, category, reason, ledger id, awaits, dry_run):
--      the accountant's action. Dry run (the default) writes nothing and returns the entry and journal it would post, or why
--      it would not. Live: one expense_entries row (source founder_reported, doc_kind founder_statement), posted through
--      fn_expense_post_to_gl like every other expense, plus its awaiting row. It refuses a cost a document already books
--      (an expense of that vendor and amount within 7 days, or a statement line of that amount within 7 days).
--   3. A document that arrives later JOINS the held entry instead of booking a second time:
--      - statement: fn_accountant_attach_statement_line(line) links a bank-charge line to the held entry of the same bank,
--        amount (AED) and a value date within 7 days, through the existing expense_bank_match table;
--        fn_accountant_book_bank_charges calls it first and books no 'bank_charge' journal for a line it attached;
--        fn_accountant_statement_booked counts an attached line as booked.
--      - receipt: fn_expense_held_document_merge(entry) is called at the top of fn_expense_post_to_gl. A receipt row of the
--        same vendor, currency and amount within 7 days of a held entry is folded into it (its file, kind, note and message
--        key move onto the held entry, the receipt's own row is removed before it is ever posted) and the held entry's
--        journal is returned: one cost, one journal, the document attached. When the intake files the document straight onto
--        the held entry (same date), the awaiting row is closed the same way.
--   4. 'Bank charges' maps to 6300 General & Administrative in gl_expense_map (memory: bank fees are not software).
--
-- WHAT IT DOES NOT DO: it books nothing. The Mashreq fee of 1 Nov 2026 is booked by
-- scripts/sql/the_mashreq_fee_of_1_november_2026_is_booked_on_the_founders_word.sql (dry run first).
-- APPLY ORDER: this file BEFORE the_company_recovers_no_input_vat_so_1150_is_moved_into_cost.sql, which redefines
-- fn_expense_post_to_gl and carries the same merge call.

create table if not exists public.expense_awaiting_document (
  expense_entry_id bigint primary key references public.expense_entries(id) on delete cascade,
  awaits text not null check (awaits in ('bank_statement', 'receipt')),
  founder_instruction_id bigint not null references public.founder_instruction(id),
  reason text not null check (btrim(reason) <> ''),
  stated_key text not null,
  state text not null default 'awaiting' check (state in ('awaiting', 'attached')),
  attached_kind text check (attached_kind in ('bank_statement_line', 'expense_entry')),
  attached_ref text,
  attached_at timestamptz,
  attached_detail jsonb,
  created_at timestamptz not null default now(),
  check ((state = 'awaiting') = (attached_at is null)),
  check ((state = 'attached') = (attached_kind is not null and attached_ref is not null))
);
comment on table public.expense_awaiting_document is
  'An expense booked on the founder''s word (founder_instruction) that waits for its document; attached once the statement line or receipt arrives (scripts/sql/the_books_hold_a_cost_on_the_founders_word_until_its_document_arrives.sql).';
create index if not exists expense_awaiting_document_open_idx on public.expense_awaiting_document (awaits) where state = 'awaiting';
alter table public.expense_awaiting_document enable row level security;
drop policy if exists expense_awaiting_document_service_role_only on public.expense_awaiting_document;
create policy expense_awaiting_document_service_role_only on public.expense_awaiting_document
  as permissive for all to public using (false) with check (false);
revoke all on public.expense_awaiting_document from anon, authenticated;

insert into public.gl_expense_map (category, account_code) values ('Bank charges', '6300') on conflict (category) do nothing;

-- ---------------------------------------------------------------------------------------------------------------
-- 2. THE ACTION
create or replace function public.fn_accountant_expense_on_founder_word(
  p_vendor text, p_charged_on date, p_amount numeric, p_currency text, p_vat_amount numeric, p_category text,
  p_reason text, p_founder_instruction_id bigint, p_awaits text, p_dry_run boolean default true)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
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
  -- a document already books this cost: refuse rather than count it twice
  select e.id, e.charged_on, e.source into v_dup from public.expense_entries e
   where (lower(btrim(e.vendor)) like lower(v_vendor) || '%' or lower(v_vendor) like lower(btrim(e.vendor)) || '%')
     and e.amount = p_amount and upper(e.currency) = v_cur and abs(e.charged_on - p_charged_on) <= 7
   order by abs(e.charged_on - p_charged_on) limit 1;
  if v_dup.id is not null then
    return jsonb_build_object('booked', false, 'refused', 'already_booked', 'key', v_key,
      'reason', 'expense #' || v_dup.id || ' (' || v_dup.source || ', ' || v_dup.charged_on || ') already books ' || v_vendor || ' ' || p_amount || ' ' || v_cur || ' within 7 days');
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
            || case when p_awaits = 'bank_statement' then 'bank statement' else 'receipt' end || ': ' || btrim(p_reason);
  if p_dry_run then
    return jsonb_build_object('booked', false, 'dry_run', true, 'key', v_key,
      'would_book', jsonb_build_object('vendor', v_vendor, 'category', v_cat, 'account', v_acct, 'amount', p_amount, 'currency', v_cur,
                                       'amount_aed', v_aed, 'vat_amount', p_vat_amount, 'charged_on', p_charged_on, 'awaits', p_awaits,
                                       'journal', 'Dr ' || v_acct || ' / Cr 1000 Cash & Bank, AED ' || v_aed),
      'note', v_note);
  end if;

  insert into public.expense_entries (vendor, category, amount, currency, charged_on, vat_amount, source, doc_kind, doc_note, source_msg_id, note)
  values (v_vendor, v_cat, p_amount, v_cur, p_charged_on, p_vat_amount, 'founder_reported', 'founder_statement', v_note, v_key, v_note)
  returning id into v_id;
  insert into public.expense_awaiting_document (expense_entry_id, awaits, founder_instruction_id, reason, stated_key)
  values (v_id, p_awaits, p_founder_instruction_id, btrim(p_reason), v_key);
  v_jid := public.fn_expense_post_to_gl(v_id);
  return jsonb_build_object('booked', true, 'entry_id', v_id, 'journal_id', v_jid, 'key', v_key, 'account', v_acct, 'amount_aed', v_aed,
                            'awaits', p_awaits);
end $fn$;
revoke execute on function public.fn_accountant_expense_on_founder_word(text, date, numeric, text, numeric, text, text, bigint, text, boolean) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------
-- 3a. A RECEIPT JOINS THE HELD ENTRY. Returns the held entry's journal when p_entry_id was folded into it, else null.
create or replace function public.fn_expense_held_document_merge(p_entry_id bigint)
returns bigint
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare d public.expense_entries; h public.expense_entries; a public.expense_awaiting_document; v_jid bigint; v_has_doc boolean;
begin
  select * into d from public.expense_entries where id = p_entry_id;
  if not found then return null; end if;

  -- the held entry itself: the intake filed its document onto it (same vendor, date, amount)
  select * into a from public.expense_awaiting_document where expense_entry_id = d.id for update;
  if found then
    if a.state = 'awaiting' and (coalesce(btrim(d.doc_path), '') <> '' or d.source_msg_id is distinct from a.stated_key) then
      update public.expense_awaiting_document
         set state = 'attached', attached_kind = 'expense_entry', attached_ref = coalesce(d.source_msg_id, d.doc_path), attached_at = now(),
             attached_detail = jsonb_build_object('how', 'the document was filed onto the held entry', 'doc_path', d.doc_path, 'doc_kind', d.doc_kind)
       where expense_entry_id = d.id;
    end if;
    return null;
  end if;

  -- a separate document row: only a document (never another founder statement), only before it is posted
  if d.source = 'founder_reported' then return null; end if;
  if exists (select 1 from public.gl_journal g where g.source = 'expense' and g.source_ref = d.id::text) then return null; end if;
  select x.* into a from public.expense_awaiting_document x join public.expense_entries e on e.id = x.expense_entry_id
   where x.state = 'awaiting' and upper(e.currency) = upper(d.currency) and e.amount = d.amount
     and abs(e.charged_on - d.charged_on) <= 7
     and (lower(btrim(d.vendor)) like lower(btrim(e.vendor)) || '%' or lower(btrim(e.vendor)) like lower(btrim(d.vendor)) || '%')
   order by abs(e.charged_on - d.charged_on), e.id
   limit 1
   for update of x;
  if not found then return null; end if;
  select * into h from public.expense_entries where id = a.expense_entry_id for update;

  v_has_doc := coalesce(btrim(d.doc_path), '') <> '' or d.doc_kind is not null;
  delete from public.expense_entries where id = d.id;
  update public.expense_entries
     set source = case when v_has_doc then d.source else h.source end,
         doc_path = coalesce(d.doc_path, h.doc_path), doc_name = coalesce(d.doc_name, h.doc_name),
         doc_content_type = coalesce(d.doc_content_type, h.doc_content_type),
         doc_kind = coalesce(d.doc_kind, case when d.doc_path is not null then 'vendor_document' end, h.doc_kind),
         doc_note = case when v_has_doc then coalesce(d.doc_note, h.doc_note) else h.doc_note end,
         vendor_trn = coalesce(d.vendor_trn, h.vendor_trn), read_as = coalesce(d.read_as, h.read_as),
         renews_item = coalesce(d.renews_item, h.renews_item),
         source_msg_id = coalesce(d.source_msg_id, h.source_msg_id),
         note = left(coalesce(h.note, '') || ' | Document arrived ' || d.charged_on || ' (' || coalesce(d.source, '?') || '): '
                     || coalesce(d.note, ''), 1000)
   where id = h.id;
  update public.expense_awaiting_document
     set state = 'attached', attached_kind = 'expense_entry', attached_ref = coalesce(d.source_msg_id, 'entry:' || d.id), attached_at = now(),
         attached_detail = jsonb_build_object('how', 'a separate document row was folded into the held entry before it was posted',
                                              'document_entry_id', d.id, 'document_date', d.charged_on, 'document_vendor', d.vendor,
                                              'doc_path', d.doc_path, 'day_gap', d.charged_on - h.charged_on)
   where expense_entry_id = h.id;
  select g.id into v_jid from public.gl_journal g where g.source = 'expense' and g.source_ref = h.id::text limit 1;
  if v_jid is null then v_jid := public.fn_expense_post_to_gl(h.id); end if;
  return v_jid;
end $fn$;
revoke execute on function public.fn_expense_held_document_merge(bigint) from public, anon, authenticated;

-- 3b. fn_expense_post_to_gl: the live body (supabase/schema/full_schema/05_functions_fn_d_to_fn_h.sql), plus the merge call.
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

  -- a document for a cost held on the founder's word joins that entry instead of booking it twice
  -- (scripts/sql/the_books_hold_a_cost_on_the_founders_word_until_its_document_arrives.sql)
  jid := public.fn_expense_held_document_merge(e.id);
  if jid is not null or not exists (select 1 from public.expense_entries x where x.id = e.id) then return jid; end if;

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
revoke execute on function public.fn_expense_post_to_gl(bigint) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------------------------
-- 3c. A STATEMENT LINE JOINS THE HELD ENTRY. Returns the held expense id it attached to, else null.
create or replace function public.fn_accountant_attach_statement_line(p_line_id bigint)
returns bigint
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare l public.bank_statement_line; h record;
begin
  select * into l from public.bank_statement_line where id = p_line_id;
  if not found or l.amount_aed >= 0 or l.kind is distinct from 'bank_charge' then return null; end if;
  if exists (select 1 from public.expense_bank_match m where m.bank_line_id = l.id) then
    return (select m.expense_entry_id from public.expense_bank_match m where m.bank_line_id = l.id);
  end if;
  select e.id, e.amount, e.charged_on into h
    from public.expense_awaiting_document x join public.expense_entries e on e.id = x.expense_entry_id
   where x.state = 'awaiting' and x.awaits = 'bank_statement'
     and upper(e.currency) = 'AED' and e.amount = -l.amount_aed
     and abs(e.charged_on - l.value_date) <= 7
     and lower(split_part(btrim(e.vendor), ' ', 1)) = lower(l.account)
     and not exists (select 1 from public.expense_bank_match m where m.expense_entry_id = e.id)
   order by abs(e.charged_on - l.value_date), e.id
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
  return h.id;
end $fn$;
revoke execute on function public.fn_accountant_attach_statement_line(bigint) from public, anon, authenticated;

-- 3d. fn_accountant_book_bank_charges: the live body, plus the attach step (a line held on his word books no journal).
CREATE OR REPLACE FUNCTION public.fn_accountant_book_bank_charges()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_hold boolean := coalesce((select num_value from public.gl_settings where key = 'bank_booking_on_hold'), 1) <> 0;
  l record; v_lines jsonb; v_memo text; n_posted int := 0; n_draft int := 0; n_failed int := 0; n_attached int := 0; v_items jsonb := '[]'::jsonb;
begin
  for l in select * from public.bank_statement_line b
            where b.amount_aed < 0 and b.kind = 'bank_charge'
              and not exists (select 1 from public.gl_journal g where g.source = 'bank_charge' and g.source_ref = b.id::text)
              and not exists (select 1 from public.expense_bank_match m where m.bank_line_id = b.id)
            order by b.value_date, b.id loop
    -- a fee already booked on the founder's word (expense_awaiting_document) takes this line as its document
    if public.fn_accountant_attach_statement_line(l.id) is not null then
      n_attached := n_attached + 1;
      continue;
    end if;
    v_lines := jsonb_build_array(jsonb_build_object('account', '6300', 'debit', abs(l.amount_aed)),
                                 jsonb_build_object('account', '1000', 'credit', abs(l.amount_aed)));
    v_memo := case when l.account = 'zz_demo' then 'ZZ DEMO ' else '' end || 'Bank charge (' || l.account || ', ' || l.value_date || '): ' || left(public.fn_mask_bank_text(l.description), 120);
    begin
      if v_hold or l.account = 'zz_demo' then
        perform public.fn_accountant_draft_entry(l.value_date, v_memo, 'bank_charge', l.id::text, v_lines);
        n_draft := n_draft + 1;
      else
        perform public.fn_gl_entry(l.value_date, v_memo, 'bank_charge', l.id::text, v_lines, 'accountant');
        n_posted := n_posted + 1;
      end if;
    exception when others then
      n_failed := n_failed + 1;
      v_items := v_items || jsonb_build_object('item', 'line:' || l.id, 'owner_seat', 'accountant', 'subject', 'bank_statement_line',
        'title', 'The bank charge of AED ' || abs(l.amount_aed) || ' on ' || l.value_date || ' (statement line ' || l.id || ') could not be booked: ' || left(sqlerrm, 200),
        'blast', 'agent_facing', 'affected', 1, 'demo', l.account = 'zz_demo',
        'evidence', jsonb_build_object('line_id', l.id, 'source_ref', l.source_ref, 'error', left(sqlerrm, 600)));
    end;
  end loop;
  return jsonb_build_object('posted', n_posted, 'drafted', n_draft, 'failed', n_failed, 'hold', v_hold,
    'attached_to_founder_word', n_attached,
    'awaiting_statement', (select count(*) from public.expense_awaiting_document where state = 'awaiting' and awaits = 'bank_statement'),
    'drafts_waiting', (select count(*) from public.gl_journal where source = 'bank_charge' and status = 'draft'),
    'drafts_waiting_aed', (select coalesce(sum(jl.debit), 0) from public.gl_journal g join public.gl_journal_lines jl on jl.journal_id = g.id
                            where g.source = 'bank_charge' and g.status = 'draft'),
    'findings', public.fn_accountant_duty_settle('bank_charges', v_items),
    'basis', case when v_hold then 'gl_settings.bank_booking_on_hold = 1 (the founder''s 9 Sep 2026 instruction): bank charges are prepared as drafts and reported, not posted.'
                  else 'bank_booking_on_hold = 0: bank charges posted to 6300 against 1000.' end
             || ' A charge line matching a fee held on the founder''s word is linked to that expense (expense_bank_match) and books no second journal.');
end $function$;
revoke execute on function public.fn_accountant_book_bank_charges() from public, anon, authenticated;

-- 3e. fn_accountant_statement_booked: the live body; a charge line linked to a held fee counts as booked.
CREATE OR REPLACE FUNCTION public.fn_accountant_statement_booked(p_month date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_m date := date_trunc('month', p_month)::date; i record; v_unbooked jsonb;
begin
  select * into i from public.bank_statement_intake
   where account = 'mashreq' and statement_month = v_m and state = 'parsed'
   order by received_at limit 1;
  if i.source_ref is null then
    return jsonb_build_object('month', to_char(v_m, 'YYYY-MM'), 'booked', false,
      'reason', 'no readable Mashreq statement for ' || to_char(v_m, 'YYYY-MM') || ' has been received (the founder forwards it monthly)');
  end if;
  -- A line counts only when a booking routine WOULD book it, under the same sign and kind rules:
  -- fn_accountant_book_bank_charges takes a debit of kind bank_charge; fn_accountant_book_bank_credits takes a
  -- credit that is no Stripe payout and not ruled a loan, as owner capital (ruled capital, or kind owner_transfer)
  -- or bank interest. Anything else (a fee refund left as bank_charge, an unrecognised credit) is that routine's
  -- finding, and never holds the close at waiting_for_statement (re-review of #1063).
  select coalesce(jsonb_agg(jsonb_build_object('line_id', b.id, 'value_date', b.value_date, 'amount_aed', b.amount_aed, 'kind', b.kind,
                                               'books_as', x.src) order by b.value_date, b.id), '[]'::jsonb)
    into v_unbooked
    from public.bank_statement_line b
    left join public.bank_line_owner_ruling r on r.line_id = b.id
    cross join lateral (select case
             when b.amount_aed < 0 and b.kind = 'bank_charge' then 'bank_charge'
             when b.amount_aed > 0 and coalesce(r.ruling, '') <> 'loan'
                  and not exists (select 1 from public.stripe_payout p where p.bank_line_id = b.id) then
               case when r.ruling = 'capital' or b.kind = 'owner_transfer' then 'owner_capital'
                    when b.kind = 'bank_interest' then 'bank_interest' end
           end as src) x
   where b.account = 'mashreq'
     and b.source_ref in (select i2.source_ref from public.bank_statement_intake i2 where i2.account = 'mashreq' and i2.statement_month = v_m)
     and x.src is not null
     -- fn_accountant_book_bank_charges skips a charge line with ANY journal (a voided one included); the credits
     -- routine re-books a credit whose journal was voided. Each is counted exactly as its routine treats it.
     and not exists (select 1 from public.gl_journal g
                      where g.source_ref = b.id::text and g.source = x.src
                        and (x.src = 'bank_charge' or g.status in ('draft', 'posted')))
     -- a charge line linked to a fee booked on the founder's word is booked by that expense's journal
     and not (x.src = 'bank_charge' and exists (select 1 from public.expense_bank_match m where m.bank_line_id = b.id));
  return jsonb_build_object('month', to_char(v_m, 'YYYY-MM'), 'booked', jsonb_array_length(v_unbooked) = 0,
    'statement', i.source_ref, 'received_at', i.received_at, 'unbooked_lines', v_unbooked,
    'reason', case when jsonb_array_length(v_unbooked) > 0
                   then jsonb_array_length(v_unbooked) || ' line(s) of the statement are not booked yet' end);
end $function$;
revoke execute on function public.fn_accountant_statement_booked(date) from public, anon, authenticated;
