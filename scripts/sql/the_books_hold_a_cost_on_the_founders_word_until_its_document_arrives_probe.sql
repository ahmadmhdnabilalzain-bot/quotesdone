-- PROBE, ROLLED BACK: a cost booked on the founder's word waits for its document, and the document joins it.
-- For scripts/sql/the_books_hold_a_cost_on_the_founders_word_until_its_document_arrives.sql. Seat: accountant.
-- Pure probe, no DDL: it always ends in raise exception 'CHK<<...>>', so every row it wrote is gone. Run it on a LOCAL
-- Postgres only (never a production replay), in one transaction after the file:
--   psql -v ON_ERROR_STOP=0 -1 -f <file>.sql -f <file>_probe.sql      (expect CHK<<PROBE OK ...>>)
-- It cannot reach a person: it queues no notification; its founder ledger row, vendors (Probe*) and statement lines
-- (statement 'probe:held-document') are its own, and it asserts only on them.
do $probe$
declare
  v_fi bigint; v_d date := (now() at time zone 'Asia/Dubai')::date; r jsonb; r2 jsonb; n0 int; n1 int;
  v_held bigint; v_held_j bigint; v_line bigint; v_line2 bigint; v_rcpt bigint; v_j bigint; v_h2 bigint; v_h2j bigint; v_plain bigint;
  v_fail text := '';
begin
  insert into public.founder_instruction (said_at, instruction, subject, status)
  values (now(), 'probe: book a cost on my word', 'probe', 'open') returning id into v_fi;
  insert into public.gl_settings (key, num_value) values ('bank_booking_on_hold', 0)
  on conflict (key) do update set num_value = 0;

  -- 1. validation: an unknown ledger entry is refused
  begin
    perform public.fn_accountant_expense_on_founder_word('Mashreq', v_d - 2, 77.77, 'AED', null, null, 'probe', -1, 'bank_statement', true);
    v_fail := v_fail || ' unknown-ledger-accepted;';
  exception when others then null; end;

  -- 2. dry run writes nothing
  select count(*) into n0 from public.expense_entries;
  r := public.fn_accountant_expense_on_founder_word('Mashreq', v_d - 2, 77.77, 'AED', null, null, 'probe fee', v_fi, 'bank_statement', true);
  select count(*) into n1 from public.expense_entries;
  if n1 <> n0 or (r->>'dry_run')::boolean is not true or r #>> '{would_book,account}' <> '6300' then
    v_fail := v_fail || ' dry-run:' || r::text || ';';
  end if;

  -- 3. live: one entry, posted Dr 6300 / Cr 1000, one awaiting row
  r := public.fn_accountant_expense_on_founder_word('Mashreq', v_d - 2, 77.77, 'AED', null, null, 'probe fee', v_fi, 'bank_statement', false);
  v_held := (r->>'entry_id')::bigint; v_held_j := (r->>'journal_id')::bigint;
  if not coalesce((r->>'booked')::boolean, false) or v_held_j is null
     or (select count(*) from public.gl_journal_lines where journal_id = v_held_j and account_code = '6300' and debit = 77.77) <> 1
     or (select count(*) from public.gl_journal_lines where journal_id = v_held_j and account_code = '1000' and credit = 77.77) <> 1
     or not exists (select 1 from public.expense_awaiting_document where expense_entry_id = v_held and state = 'awaiting' and founder_instruction_id = v_fi)
     or not exists (select 1 from public.expense_entries where id = v_held and source = 'founder_reported' and doc_kind = 'founder_statement') then
    v_fail := v_fail || ' live:' || r::text || ';';
  end if;
  -- 4. the same call again books nothing
  r := public.fn_accountant_expense_on_founder_word('Mashreq', v_d - 2, 77.77, 'AED', null, null, 'probe fee', v_fi, 'bank_statement', false);
  if not coalesce((r->>'already')::boolean, false) then v_fail := v_fail || ' twice:' || r::text || ';'; end if;

  -- 5. the statement arrives: the line joins the held entry; no bank_charge journal; the month reads booked
  insert into public.bank_statement_intake (source_ref, account, statement_month, state, lines)
  values ('probe:held-document', 'mashreq', date_trunc('month', v_d)::date, 'parsed', 2);
  insert into public.bank_statement_line (account, source_ref, value_date, description, amount_aed, line_hash, kind)
  values ('mashreq', 'probe:held-document', v_d - 1, 'Monthly Maintenance Fee probe', -77.77, md5('probe-held-1-' || clock_timestamp()), 'bank_charge')
  returning id into v_line;
  insert into public.bank_statement_line (account, source_ref, value_date, description, amount_aed, line_hash, kind)
  values ('mashreq', 'probe:held-document', v_d - 1, 'Another probe charge', -66.66, md5('probe-held-2-' || clock_timestamp()), 'bank_charge')
  returning id into v_line2;
  r := public.fn_accountant_book_bank_charges();
  if exists (select 1 from public.gl_journal where source = 'bank_charge' and source_ref = v_line::text) then
    v_fail := v_fail || ' statement-double-booked;';
  end if;
  if not exists (select 1 from public.expense_bank_match where expense_entry_id = v_held and bank_line_id = v_line)
     or not exists (select 1 from public.expense_awaiting_document where expense_entry_id = v_held and state = 'attached'
                     and attached_kind = 'bank_statement_line' and attached_ref = v_line::text) then
    v_fail := v_fail || ' statement-not-attached:' || r::text || ';';
  end if;
  -- the unheld line books as before
  if not exists (select 1 from public.gl_journal where source = 'bank_charge' and source_ref = v_line2::text) then
    v_fail := v_fail || ' unheld-line-not-booked;';
  end if;
  r2 := public.fn_accountant_statement_booked(v_d);
  if exists (select 1 from jsonb_array_elements(coalesce(r2->'unbooked_lines', '[]'::jsonb)) u where (u->>'line_id')::bigint in (v_line, v_line2)) then
    v_fail := v_fail || ' statement-booked:' || r2::text || ';';
  end if;
  -- a cost the statement already shows is refused
  r := public.fn_accountant_expense_on_founder_word('Mashreq', v_d - 1, 66.66, 'AED', null, null, 'probe late word', v_fi, 'bank_statement', false);
  if r->>'refused' is distinct from 'statement_shows_it' then v_fail := v_fail || ' statement-shows-it:' || r::text || ';'; end if;

  -- 6. receipt two days later, separate row: folded into the held entry, one journal
  r := public.fn_accountant_expense_on_founder_word('Probecloud', v_d - 5, 20.00, 'USD', null, 'Subscription', 'probe plan', v_fi, 'receipt', false);
  v_h2 := (r->>'entry_id')::bigint; v_h2j := (r->>'journal_id')::bigint;
  insert into public.expense_entries (vendor, category, amount, currency, charged_on, source, doc_path, doc_name, doc_kind, source_msg_id, note)
  values ('Probecloud Inc', 'Subscription', 20.00, 'USD', v_d - 3, 'receipt', 'receipts/probe.pdf', 'probe.pdf', 'vendor_document', 'probe:msg:held-1', 'probe receipt')
  returning id into v_rcpt;
  v_j := public.fn_expense_post_to_gl(v_rcpt);
  if v_j is distinct from v_h2j then v_fail := v_fail || ' receipt-journal ' || coalesce(v_j::text, 'null') || ' vs ' || v_h2j || ';'; end if;
  if exists (select 1 from public.expense_entries where id = v_rcpt) then v_fail := v_fail || ' receipt-row-kept;'; end if;
  if exists (select 1 from public.gl_journal where source = 'expense' and source_ref = v_rcpt::text) then v_fail := v_fail || ' receipt-double-booked;'; end if;
  if not exists (select 1 from public.expense_entries where id = v_h2 and source_msg_id = 'probe:msg:held-1' and doc_path = 'receipts/probe.pdf'
                  and doc_kind = 'vendor_document' and source = 'receipt')
     or not exists (select 1 from public.expense_awaiting_document where expense_entry_id = v_h2 and state = 'attached' and attached_kind = 'expense_entry') then
    v_fail := v_fail || ' receipt-not-attached;';
  end if;
  -- a redelivery of the same receipt finds the held entry by its key and posts nothing new
  if public.fn_expense_post_to_gl(v_h2) is distinct from v_h2j then v_fail := v_fail || ' redelivery;'; end if;

  -- 7. the intake files the document straight onto the held entry (same date): the awaiting row closes
  r := public.fn_accountant_expense_on_founder_word('Probemail', v_d - 4, 30.00, 'AED', null, 'Subscription', 'probe mailbox', v_fi, 'receipt', false);
  update public.expense_entries set doc_path = 'receipts/probe2.pdf', doc_kind = 'vendor_document', source_msg_id = 'probe:msg:held-2'
   where id = (r->>'entry_id')::bigint;
  if public.fn_expense_post_to_gl((r->>'entry_id')::bigint) is distinct from (r->>'journal_id')::bigint
     or not exists (select 1 from public.expense_awaiting_document where expense_entry_id = (r->>'entry_id')::bigint and state = 'attached') then
    v_fail := v_fail || ' same-day-attach;';
  end if;

  -- 8. an ordinary receipt that matches nothing still posts as before
  insert into public.expense_entries (vendor, category, amount, currency, charged_on, source, source_msg_id, note)
  values ('Probeplain', 'Usage', 12.34, 'AED', v_d - 1, 'receipt', 'probe:msg:plain', 'probe plain') returning id into v_plain;
  v_j := public.fn_expense_post_to_gl(v_plain);
  if v_j is null or not exists (select 1 from public.gl_journal where id = v_j and source = 'expense' and source_ref = v_plain::text) then
    v_fail := v_fail || ' plain-not-posted;';
  end if;

  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK: held on the founder''s word, joined by its statement line and by its receipt, never booked twice'
                                     else 'PROBE FAILED:' || v_fail end;
end $probe$;
