-- A JOURNAL MEMO NEVER CARRIES A BANK OR IBAN NUMBER.
--
-- Assigned: accountant.
--
-- WHAT WAS MEASURED (15 Sep 2026, production htdblwldjkcgjvmqkbeh): the bank booking routines copied
-- Mashreq's full line description into gl_journal.memo. 7 of 66 journals carried an IBAN-shaped token
-- or a run of 8+ digits: 4 bank_charge, 1 bank_interest, 1 owner_capital (all posted 14 Sep 2026) and
-- 1 reversal. The founder's standing rule: the statement's account, IBAN and customer numbers are never
-- repeated in chat, code or commits. Journal memos reach the gl_ledger view, the year-end Ledger.csv
-- (fn_accountant_year_end_pack_document), the OS dashboard and the daily exports, so they may not
-- carry them either.
--
-- WHAT THIS DOES:
--   1. public.fn_mask_bank_text(text) is the ONE masking function. It replaces an IBAN (two letters,
--      two check digits, then 10-30 alphanumerics, compact or printed in groups of four) with [IBAN],
--      and any alphanumeric token holding 8 or more digits (account numbers, transfer and bank
--      reference numbers) with [ref]. Words, the counterparty name, the transaction type and dates
--      survive. It is idempotent: masking masked text changes nothing.
--   2. trg_gl_journal_memo_masked routes EVERY gl_journal memo write through it (bank bookings, the
--      draft writer, fn_gl_entry, fn_gl_reverse, which copies the original memo, and expenses), so no
--      writer can reintroduce the leak. The bank routines also mask before truncating, so a cut can
--      never leave half a number behind, and the unrecognised-credit finding's evidence is masked.
--   3. fn_gl_journal_immutable gains exactly one allowance: a posted journal's memo may change ONLY to
--      public.fn_mask_bank_text(old memo). Date, source, status and the lines stay immutable.
--   4. A one-off signed redaction of the rows already written, memo only, proved to leave every other
--      column untouched.
-- bank_statement_line.description stays raw on purpose: it is the private source record, and the PDF
-- is archived anyway. The classifiers keep reading it.
-- These two routines were canonical in the_companys_own_bank_and_stripe_costs_book_themselves.sql;
-- that file is NOT re-applied because two of its other routines are redefined by later files.
-- Check: scripts/checks/a_journal_memo_never_carries_a_bank_number.test.mjs.
--
--   node scripts/apply_sql.mjs scripts/sql/a_journal_memo_never_carries_a_bank_or_iban_number.sql --apply --ddl

-- ── 1. THE ONE MASKING FUNCTION ───────────────────────────────────────────────────────────────────
create or replace function public.fn_mask_bank_text(p text)
returns text language plpgsql immutable security definer set search_path to 'public', 'pg_temp' as $fn$
declare v text := p; m text;
begin
  if v is null then return null; end if;
  -- An IBAN printed in groups of four, then a compact one.
  v := regexp_replace(v, '\m[A-Z]{2}[0-9]{2} [A-Z0-9]{4}( [0-9]{4}){2,6}( [0-9]{1,4})?\M', '[IBAN]', 'g');
  v := regexp_replace(v, '\m[A-Z]{2}[0-9]{2}[A-Z0-9]{10,30}\M', '[IBAN]', 'g');
  -- Any alphanumeric token holding 8+ digits. A date splits into short tokens and survives.
  for m in select distinct t[1] from regexp_matches(v, '[A-Za-z0-9]+', 'g') t
            where length(regexp_replace(t[1], '[^0-9]', '', 'g')) >= 8
            order by 1 desc loop
    v := replace(v, m, '[ref]');
  end loop;
  return v;
end $fn$;
revoke execute on function public.fn_mask_bank_text(text) from public, anon, authenticated;

-- ── 2. EVERY MEMO WRITE GOES THROUGH IT ───────────────────────────────────────────────────────────
create or replace function public.fn_gl_journal_memo_masked()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  new.memo := public.fn_mask_bank_text(new.memo);
  return new;
end $fn$;
revoke execute on function public.fn_gl_journal_memo_masked() from public, anon, authenticated;

drop trigger if exists trg_gl_journal_memo_masked on public.gl_journal;
create trigger trg_gl_journal_memo_masked before insert or update of memo on public.gl_journal
  for each row execute function public.fn_gl_journal_memo_masked();

-- ── 3. IMMUTABILITY, WITH ONE ALLOWANCE: A POSTED MEMO MAY BE MASKED, NOTHING ELSE ─────────────────
-- Body as live (measured 15 Sep 2026) except the memo clause.
create or replace function public.fn_gl_journal_immutable()
returns trigger language plpgsql security definer set search_path to 'public', 'pg_catalog' as $fn$
begin
  if tg_op in ('UPDATE','DELETE') and old.status = 'posted'
     and not (tg_op='UPDATE' and new.status='void' and old.status='posted' and new.reverses is not null) then
    -- allow only the controlled void marking done by fn_gl_reverse (new.status='void'), and a memo
    -- replaced by its own masked form (a journal memo never carries a bank or IBAN number)
    if tg_op='DELETE' or (tg_op='UPDATE' and old.status='posted' and new.status='posted'
         and (new.entry_date<>old.entry_date or new.source<>old.source
              or (new.memo is distinct from old.memo and new.memo is distinct from public.fn_mask_bank_text(old.memo)))) then
      raise exception 'Posted journal % is immutable (reverse it instead)', old.id;
    end if;
  end if;
  return case when tg_op='DELETE' then old else new end;
end $fn$;
revoke execute on function public.fn_gl_journal_immutable() from public, anon, authenticated;

-- ── 4. THE BANK ROUTINES MASK BEFORE THEY TRUNCATE ────────────────────────────────────────────────
-- Bodies as in the_companys_own_bank_and_stripe_costs_book_themselves.sql except the three
-- fn_mask_bank_text calls.
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
    v_memo := case when l.account = 'zz_demo' then 'ZZ DEMO ' else '' end || 'Bank charge (' || l.account || ', ' || l.value_date || '): ' || left(public.fn_mask_bank_text(l.description), 120);
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
                || '), a transfer from the licence holder''s own account: capital unless he says loan (founder_instruction 357): ' || left(public.fn_mask_bank_text(l.description), 120);
    elsif v_pat ? 'bank_interest_pattern' and v_pat ? 'bank_interest_reference_pattern'
          and l.description ~* (v_pat->>'bank_interest_pattern') and l.description ~ (v_pat->>'bank_interest_reference_pattern') then
      v_src := 'bank_interest';
      v_lines := jsonb_build_array(jsonb_build_object('account', '1000', 'debit', l.amount_aed),
                                   jsonb_build_object('account', '7000', 'credit', l.amount_aed));
      v_memo := 'Bank interest credited (' || l.account || ', ' || l.value_date || '): ' || left(public.fn_mask_bank_text(l.description), 120);
    elsif l.value_date + v_after < v_today then
      v_items := v_items || jsonb_build_object('item', 'unrecognised:' || l.id, 'owner_seat', 'accountant', 'subject', 'bank_statement_line',
        'title', 'A credit of AED ' || l.amount_aed || ' on ' || l.value_date || ' is neither a Stripe payout, a transfer from the licence holder''s own account nor the bank''s interest, so it is not booked',
        'blast', 'agent_facing', 'affected', 1, 'demo', l.account = 'zz_demo',
        'evidence', jsonb_build_object('line_id', l.id, 'source_ref', l.source_ref, 'description', left(public.fn_mask_bank_text(l.description), 200),
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

-- ── 5. PROBE: an invented Mashreq-shaped line is masked; a posted memo still cannot be rewritten ───
-- DDL lives in this file, so the probe cleans up after itself: the journal part runs in a
-- sub-transaction that is always rolled back, and the absence of its rows is asserted afterwards.
do $probe$
declare
  v_line text := 'ZZ DEMO IPP TRANSFER - ZZ DEMO SENDER NAME - AE000000000000000000042 FT0000000042ZZ REF 000000000042 CIDZZAED 00042';
  v_spaced text := 'ZZ DEMO Monthly Maintenance Fee AE00 0000 0000 0000 0000 042 value 2026-08-31 GB00ZZZZ00000000000042';
  m text; s text; v_id bigint;
begin
  m := public.fn_mask_bank_text(v_line);
  s := public.fn_mask_bank_text(v_spaced);
  if m ~ '[0-9]{8,}' or s ~ '[0-9]{8,}' or m ~ '[A-Z]{2}[0-9]{2}[A-Z0-9]{10,30}' or s ~ '[A-Z]{2}[0-9]{2}[A-Z0-9]{10,30}'
     or s ~ 'AE00 0000' then
    raise exception 'CHK<<fn_mask_bank_text left a bank number behind: % | %>>', m, s; end if;
  if m !~ 'IPP TRANSFER' or m !~ 'ZZ DEMO SENDER NAME' or m !~ 'CIDZZAED 00042'
     or s !~ 'Monthly Maintenance Fee' or s !~ '2026-08-31' then
    raise exception 'CHK<<fn_mask_bank_text removed words it must keep: % | %>>', m, s; end if;
  if public.fn_mask_bank_text(m) <> m or public.fn_mask_bank_text(s) <> s then
    raise exception 'CHK<<fn_mask_bank_text is not idempotent>>'; end if;

  begin
    v_id := public.fn_accountant_draft_entry(current_date, v_line, 'bank_charge', 'zz-demo-memo-mask-probe',
              '[{"account":"6300","debit":1},{"account":"1000","credit":1}]'::jsonb);
    if (select memo from public.gl_journal where id = v_id) is distinct from m then
      raise exception 'CHK<<a journal memo was stored unmasked>>'; end if;
    insert into public.gl_journal (entry_date, memo, source, source_ref, created_by, status)
    values (current_date, 'ZZ DEMO posted', 'zz_demo', 'zz-demo-memo-mask-probe-posted', 'probe', 'posted') returning id into v_id;
    begin
      update public.gl_journal set memo = 'ZZ DEMO rewritten' where id = v_id;
      raise exception 'CHK<<a posted memo was rewritten to something other than its masked form>>';
    exception when raise_exception then
      if sqlerrm like 'CHK<<%' then raise; end if;
    end;
    raise exception 'zz_probe_rollback';
  exception when others then
    if sqlerrm <> 'zz_probe_rollback' then raise; end if;
  end;
  if exists (select 1 from public.gl_journal where source_ref like 'zz-demo-memo-mask-probe%') then
    raise exception 'CHK<<the probe left a journal behind>>'; end if;
  raise notice 'memo mask probe passed';
end $probe$;

-- ── 6. ONE-OFF REDACTION OF THE ROWS ALREADY WRITTEN: memo only ───────────────────────────────────
do $redact$
declare
  n_before int; n_after int; n_changed int; v_other_before text; v_other_after text; v_lines_before text; v_lines_after text;
begin
  select count(*) into n_before from public.gl_journal where memo ~ '[0-9]{8,}' or memo ~ '[A-Z]{2}[0-9]{2}[A-Z0-9]{10,30}';
  select md5(string_agg(concat_ws('|', id, entry_date, status, source, source_ref), ',' order by id)) into v_other_before from public.gl_journal;
  select md5(string_agg(concat_ws('|', id, journal_id, line_no, account_code, debit, credit, memo), ',' order by id)) into v_lines_before from public.gl_journal_lines;

  update public.gl_journal set memo = public.fn_mask_bank_text(memo) where memo is distinct from public.fn_mask_bank_text(memo);
  get diagnostics n_changed = row_count;

  select count(*) into n_after from public.gl_journal where memo ~ '[0-9]{8,}' or memo ~ '[A-Z]{2}[0-9]{2}[A-Z0-9]{10,30}';
  select md5(string_agg(concat_ws('|', id, entry_date, status, source, source_ref), ',' order by id)) into v_other_after from public.gl_journal;
  select md5(string_agg(concat_ws('|', id, journal_id, line_no, account_code, debit, credit, memo), ',' order by id)) into v_lines_after from public.gl_journal_lines;
  if n_after <> 0 then raise exception 'CHK<<% journal memos still carry a bank number after the redaction>>', n_after; end if;
  if v_other_before <> v_other_after or v_lines_before <> v_lines_after then
    raise exception 'CHK<<the redaction changed something other than gl_journal.memo>>'; end if;
  raise notice 'memo redaction: % matching before, % rows changed, % matching after', n_before, n_changed, n_after;
end $redact$;
