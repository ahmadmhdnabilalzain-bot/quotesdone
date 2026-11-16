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

  -- 3. live: one entry, posted Dr 6300 / Cr 2200 (owed to the bank until the statement shows it taken; since
  --    a_mashreq_fee_the_bank_has_not_taken_is_owed_not_paid_and_the_1_august_fee_is_booked.sql), one awaiting row
  r := public.fn_accountant_expense_on_founder_word('Mashreq', v_d - 2, 77.77, 'AED', null, null, 'probe fee', v_fi, 'bank_statement', false);
  v_held := (r->>'entry_id')::bigint; v_held_j := (r->>'journal_id')::bigint;
  if not coalesce((r->>'booked')::boolean, false) or v_held_j is null
     or (select count(*) from public.gl_journal_lines where journal_id = v_held_j and account_code = '6300' and debit = 77.77) <> 1
     or (select count(*) from public.gl_journal_lines where journal_id = v_held_j and account_code = '2200' and credit = 77.77) <> 1
     or exists (select 1 from public.gl_journal_lines where journal_id = v_held_j and account_code = '1000')
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
  -- the attached line pays the debt: one Dr 2200 / Cr 1000 of 77.77 on the line's date, and attaching again adds none
  perform public.fn_accountant_attach_statement_line(v_line);
  if (select count(*) from public.gl_journal g where g.source = 'bank_charge_settles_accrual' and g.source_ref = v_line::text) <> 1
     or (select count(*) from public.gl_journal g join public.gl_journal_lines jl on jl.journal_id = g.id
          where g.source = 'bank_charge_settles_accrual' and g.source_ref = v_line::text
            and ((jl.account_code = '2200' and jl.debit = 77.77) or (jl.account_code = '1000' and jl.credit = 77.77))) <> 2 then
    v_fail := v_fail || ' statement-did-not-settle-the-accrual;';
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
  v_j := public.fn_expense_post_to_gl((r->>'entry_id')::bigint);   -- its own statement: the check below must see its write
  if v_j is distinct from (r->>'journal_id')::bigint
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

  -- 9. invoice.received (review item 6): none for the receipt row the merge deleted; one for the surviving held entry
  if exists (select 1 from public.company_event where event_type = 'invoice.received' and entity_type = 'expense_entry' and entity_id = v_rcpt::text) then
    v_fail := v_fail || ' event-for-deleted-row;';
  end if;
  if not exists (select 1 from public.company_event where event_type = 'invoice.received' and entity_type = 'expense_entry' and entity_id = v_h2::text
                    and (payload->>'document_entry_folded')::bigint = v_rcpt) then
    v_fail := v_fail || ' no-event-for-survivor;';
  end if;

  -- REVIEW FIXES (15 Nov 2026, evening). Each block below failed on the file before the fixes.
  declare
    v_a bigint; v_b_old bigint; v_b_new bigint; v_l55 bigint; v_l44 bigint; v_l33 bigint; v_c bigint; v_cl bigint; v_doc bigint;
    v_s bigint; v_re bigint; v_short bigint; v_sdoc bigint; v_vat bigint; v_usd bigint; v_ok boolean;
  begin
    -- 10. item 1: a statement line weeks late still attaches; the OLDEST held fee of that amount takes it; a line of another
    --     amount while a fee still waits is not booked and is the accountant's finding
    r := public.fn_accountant_expense_on_founder_word('Mashreq', v_d - 40, 55.55, 'AED', null, null, 'probe late fee', v_fi, 'bank_statement', false);
    v_a := (r->>'entry_id')::bigint;
    r := public.fn_accountant_expense_on_founder_word('Mashreq', v_d - 70, 44.44, 'AED', null, null, 'probe old fee', v_fi, 'bank_statement', false);
    v_b_old := (r->>'entry_id')::bigint;
    r := public.fn_accountant_expense_on_founder_word('Mashreq', v_d - 35, 44.44, 'AED', null, null, 'probe newer fee', v_fi, 'bank_statement', false);
    v_b_new := (r->>'entry_id')::bigint;
    if v_a is null or v_b_old is null or v_b_new is null then v_fail := v_fail || ' late-setup:' || r::text || ';'; end if;
    insert into public.bank_statement_line (account, source_ref, value_date, description, amount_aed, line_hash, kind)
    values ('mashreq', 'probe:held-document', v_d - 2, 'Monthly Maintenance Fee probe late', -55.55, md5('probe-held-55-' || clock_timestamp()), 'bank_charge')
    returning id into v_l55;
    insert into public.bank_statement_line (account, source_ref, value_date, description, amount_aed, line_hash, kind)
    values ('mashreq', 'probe:held-document', v_d - 1, 'Monthly Maintenance Fee probe 44', -44.44, md5('probe-held-44-' || clock_timestamp()), 'bank_charge')
    returning id into v_l44;
    insert into public.bank_statement_line (account, source_ref, value_date, description, amount_aed, line_hash, kind)
    values ('mashreq', 'probe:held-document', v_d - 1, 'Fee probe of another amount', -33.33, md5('probe-held-33-' || clock_timestamp()), 'bank_charge')
    returning id into v_l33;
    r := public.fn_accountant_book_bank_charges();
    if exists (select 1 from public.gl_journal where source = 'bank_charge' and source_ref = v_l55::text)
       or not exists (select 1 from public.expense_bank_match where expense_entry_id = v_a and bank_line_id = v_l55) then
      v_fail := v_fail || ' late-line-double-booked:' || r::text || ';';
    end if;
    if not exists (select 1 from public.expense_bank_match where expense_entry_id = v_b_old and bank_line_id = v_l44)
       or not exists (select 1 from public.expense_awaiting_document where expense_entry_id = v_b_new and state = 'awaiting') then
      v_fail := v_fail || ' oldest-held-not-first;';
    end if;
    if exists (select 1 from public.gl_journal where source = 'bank_charge' and source_ref = v_l33::text)
       or not exists (select 1 from public.it_engineer_finding where issue_key = 'acct:bank_charges:held_fee_ambiguous:line:' || v_l33 and closed_at is null) then
      v_fail := v_fail || ' ambiguous-line-posted:' || r::text || ';';
    end if;

    -- 11. item 2: a receipt never folds into a fee waiting for its BANK STATEMENT; it is not posted, it is a finding,
    --     and the statement line still attaches to the held fee
    r := public.fn_accountant_expense_on_founder_word('Mashreq', v_d - 3, 22.22, 'AED', null, null, 'probe advised fee', v_fi, 'bank_statement', false);
    v_c := (r->>'entry_id')::bigint;
    insert into public.expense_entries (vendor, category, amount, currency, charged_on, source, doc_path, doc_name, doc_kind, source_msg_id, note)
    values ('Mashreq Bank', 'Bank charges', 22.22, 'AED', v_d - 2, 'receipt', 'receipts/probe-advice.pdf', 'advice.pdf', 'vendor_document', 'probe:msg:advice', 'probe advice')
    returning id into v_doc;
    v_j := public.fn_expense_post_to_gl(v_doc);
    if v_j is not null or not exists (select 1 from public.expense_entries where id = v_doc)
       or not exists (select 1 from public.expense_awaiting_document where expense_entry_id = v_c and state = 'awaiting')
       or not exists (select 1 from public.it_engineer_finding where issue_key = 'acct:bank_charges:held_fee_document:' || v_doc and closed_at is null) then
      v_fail := v_fail || ' receipt-folded-into-statement-fee:' || coalesce(v_j::text, 'null') || ';';
    end if;
    insert into public.bank_statement_line (account, source_ref, value_date, description, amount_aed, line_hash, kind)
    values ('mashreq', 'probe:held-document', v_d - 1, 'Monthly Maintenance Fee probe 22', -22.22, md5('probe-held-22-' || clock_timestamp()), 'bank_charge')
    returning id into v_cl;
    r := public.fn_accountant_book_bank_charges();
    if not exists (select 1 from public.expense_bank_match where expense_entry_id = v_c and bank_line_id = v_cl)
       or exists (select 1 from public.gl_journal where source = 'expense' and source_ref = v_doc::text)
       or not exists (select 1 from public.it_engineer_finding where issue_key = 'acct:bank_charges:held_fee_document:' || v_doc and closed_at is null) then
      v_fail := v_fail || ' statement-after-advice:' || r::text || ';';
    end if;
    --     the intake filing a document straight onto a statement-held fee leaves it waiting for the statement
    r := public.fn_accountant_expense_on_founder_word('Mashreq', v_d - 6, 11.11, 'AED', null, null, 'probe same-day advice', v_fi, 'bank_statement', false);
    v_s := (r->>'entry_id')::bigint;
    update public.expense_entries set doc_path = 'receipts/probe-advice2.pdf', doc_kind = 'vendor_document', source_msg_id = 'probe:msg:advice2' where id = v_s;
    perform public.fn_expense_post_to_gl(v_s);
    if not exists (select 1 from public.expense_awaiting_document where expense_entry_id = v_s and state = 'awaiting') then
      v_fail := v_fail || ' same-day-closed-statement-fee;';
    end if;

    -- 12. item 3: the action's guards
    begin   -- a cost waiting for a bank statement is in AED
      perform public.fn_accountant_expense_on_founder_word('Mashreq', v_d - 2, 10.00, 'USD', null, null, 'probe usd fee', v_fi, 'bank_statement', false);
      v_fail := v_fail || ' usd-statement-cost-accepted;';
    exception when others then null; end;
    begin   -- a vendor too short to match
      perform public.fn_accountant_expense_on_founder_word('Ab', v_d - 2, 10.00, 'AED', null, null, 'probe short', v_fi, 'receipt', true);
      v_fail := v_fail || ' short-vendor-accepted;';
    exception when others then null; end;
    if public.fn_expense_same_vendor('', 'Mashreq') or public.fn_expense_same_vendor('Pr', 'Probeshort') or public.fn_expense_same_vendor('Git_ub', 'GitHub')
       or not public.fn_expense_same_vendor('Vercel Inc.', 'vercel') or public.fn_expense_same_vendor('Mash', 'Mashreq') then
      v_fail := v_fail || ' same-vendor;';
    end if;
    --     a document whose vendor is too short never folds into a held receipt entry (the old LIKE matched it)
    r := public.fn_accountant_expense_on_founder_word('Probeshort', v_d - 3, 17.00, 'AED', null, 'Subscription', 'probe short match', v_fi, 'receipt', false);
    v_short := (r->>'entry_id')::bigint;
    insert into public.expense_entries (vendor, category, amount, currency, charged_on, source, source_msg_id, note)
    values ('Pr', 'Usage', 17.00, 'AED', v_d - 2, 'receipt', 'probe:msg:short', 'probe short receipt') returning id into v_sdoc;
    v_j := public.fn_expense_post_to_gl(v_sdoc);
    if not exists (select 1 from public.expense_entries where id = v_sdoc)
       or not exists (select 1 from public.expense_awaiting_document where expense_entry_id = v_short and state = 'awaiting') then
      v_fail := v_fail || ' short-vendor-folded;';
    end if;
    --     VAT on a cost on his word is part of the cost, never 1150 (this run does NOT apply the 1150 file)
    r := public.fn_accountant_expense_on_founder_word('Probevat', v_d - 2, 105.00, 'AED', 5.00, 'Subscription', 'probe vat', v_fi, 'receipt', false);
    v_vat := (r->>'journal_id')::bigint;
    if v_vat is null or exists (select 1 from public.gl_journal_lines where journal_id = v_vat and account_code = '1150')
       or (select sum(debit) from public.gl_journal_lines where journal_id = v_vat and account_code <> '1000') <> 105.00 then
      v_fail := v_fail || ' vat-to-1150:' || r::text || ';';
    end if;
    --     a duplicate in another currency, same vendor and month, within 10% in AED, is refused
    insert into public.expense_entries (vendor, category, amount, currency, charged_on, source, source_msg_id, note)
    values ('Probeanthropic, PBC', 'Subscription', 200.00, 'USD', v_d - 3, 'receipt', 'probe:msg:usd200', 'probe usd 200') returning id into v_usd;
    perform public.fn_expense_post_to_gl(v_usd);
    r := public.fn_accountant_expense_on_founder_word('Probeanthropic', v_d - 3, 799.00, 'AED', null, 'Subscription', 'probe aed 799', v_fi, 'receipt', false);
    if r->>'refused' is distinct from 'already_booked' then v_fail := v_fail || ' cross-currency-duplicate:' || r::text || ';'; end if;
    -- 13. review 2, fix 1: the SAME receipt forwarded again (new email id) after it was folded (step 6, survivor 'Probecloud'
    --     dated v_d - 5, receipt 'Probecloud Inc' dated v_d - 3) is held out too: not posted, a finding, no second journal
    insert into public.expense_entries (vendor, category, amount, currency, charged_on, source, doc_path, doc_name, doc_kind, source_msg_id, note)
    values ('Probecloud Inc', 'Subscription', 20.00, 'USD', v_d - 3, 'receipt', 'receipts/probe-again.pdf', 'probe-again.pdf', 'vendor_document', 'probe:msg:held-again', 'probe forwarded again')
    returning id into v_re;
    v_j := public.fn_expense_post_to_gl(v_re);
    if v_j is not null
       or exists (select 1 from public.gl_journal where source = 'expense' and source_ref = v_re::text)
       or not exists (select 1 from public.it_engineer_finding where issue_key = 'acct:bank_charges:held_fee_document:' || v_re and closed_at is null) then
      v_fail := v_fail || ' receipt-forwarded-again-posted:' || coalesce(v_j::text, 'null') || ';';
    end if;

  end;

  raise exception 'CHK<<%>>', case when v_fail = '' then 'PROBE OK: held on the founder''s word, joined by its statement line and by its receipt, never booked twice'
                                     else 'PROBE FAILED:' || v_fail end;
end $probe$;
