-- PROBE: THE ACCOUNTANT BOOKS A LATE ITEM AS A PRIOR-PERIOD ADJUSTMENT. Seat: accountant.
--
-- Pure probe, never applied. Run it through node scripts/qsql.mjs AFTER
-- the_accountant_books_a_late_item_as_a_prior_period_adjustment.sql and
-- the_accountant_sends_the_founder_one_close_pack_by_the_fifth.sql are live. Before merge it was run as those two
-- files and this one in ONE transaction that the final raise rolls back, so the build was proved without being applied.
--
-- Everything happens inside a block that always raises, so nothing survives and pg_net sends nothing. The months are
-- ZZ DEMO July and August 2020, which no real row touches: ZZ DEMO statements (source_ref zz_demo:...) and lines.
-- One line in each booking routine is poisoned by a trigger that exists only inside this transaction, so the
-- per-line handling is proved against a real failure, not a simulated one.
--
-- VERDICT (in the error text): CHK<<PROBE OK ...>> only if
--   1. July with no statement is waiting_for_statement (not late); with its statement parsed but a line unbooked it
--      still waits; once booked it is due by two days after the statement arrived, and late only after that;
--   2. after July is closed, a late July bank fee books through fn_accountant_book_bank_charges as a prior-period
--      adjustment dated in the open month (31 Aug 2020), its memo naming the original date and the statement line,
--      with its gl_prior_period_adjustment row;
--   3. a poisoned charge and a poisoned credit each become a finding (acct:bank_charges:line:N,
--      acct:bank_credits:line:N) while the other lines still book; once the poison is gone they book and the
--      findings close;
--   4. the lock still refuses a posted journal INSERTED with a July date, and a July draft flipped to posted outside
--      fn_gl_post; fn_gl_post books that draft in August instead; a reopen reason keeps the July date;
--   5. August waits while a line of its statement is unbooked, and is due once all are booked; a fee refund left
--      as bank_charge (a credit no routine books) and a charge whose journal was voided (the charges routine skips
--      it) never hold it;
--   6. the August close pack lists the adjustments under prior_period_adjustments and as explained unusual items
--      naming statement line and original date; the late fee is not an unbooked statement line; the PDF text says so;
--   7. on the real books the close tick and the day-5 check run and read August 2026 as closed and not late.
do $probe$
declare
  v_jul date := date '2020-07-01'; v_aug date := date '2020-08-01';
  l0 bigint; l1 bigint; l2 bigint; l3 bigint; l4 bigint; l5 bigint; l6 bigint; jv bigint; jd bigint; jr bigint; j1 public.gl_journal;
  v_s jsonb; v_c jsonb; v_k jsonb; v_f jsonb; v_doc jsonb; v_err text; v_fail text := ''; v_n int;
begin
  -- 1. the close waits for July's statement
  v_s := public.fn_accountant_month_close_status(v_jul, date '2020-08-06');
  if v_s->>'status' <> 'waiting_for_statement' or (v_s->>'late')::boolean then v_fail := v_fail || ' 1a no statement: ' || v_s::text || ';'; end if;
  v_s := public.fn_accountant_month_close_status(v_jul, date '2020-08-02');
  if v_s->>'status' <> 'not_due' then v_fail := v_fail || ' 1b before day 3: ' || (v_s->>'status') || ';'; end if;

  insert into public.bank_statement_intake (source_ref, account, statement_month, state, lines, note, received_at, closing_balance_aed, balance_on)
  values ('zz_demo:late_item_probe:2020-07', 'mashreq', v_jul, 'parsed', 1, 'ZZ DEMO', '2020-08-10 10:00+04', -199, '2020-07-31');
  insert into public.bank_statement_line (account, source_ref, value_date, description, amount_aed, line_hash, kind)
  values ('mashreq', 'zz_demo:late_item_probe:2020-07', '2020-07-15', 'ZZ DEMO Monthly Maintenance Fee Jul', -199, md5('zz_demo_late_item_probe_l0'), 'bank_charge')
  returning id into l0;
  v_s := public.fn_accountant_month_close_status(v_jul, date '2020-08-11');
  if v_s->>'status' <> 'waiting_for_statement' or jsonb_array_length(v_s#>'{statement,unbooked_lines}') <> 1 then
    v_fail := v_fail || ' 1c parsed but unbooked: ' || v_s::text || ';'; end if;

  v_c := public.fn_accountant_book_bank_charges();
  if not exists (select 1 from public.gl_journal where source = 'bank_charge' and source_ref = l0::text and status = 'posted' and entry_date = '2020-07-15') then
    v_fail := v_fail || ' 1d the July fee did not post in open July: ' || v_c::text || ';'; end if;
  v_s := public.fn_accountant_month_close_status(v_jul, date '2020-08-11');
  if v_s->>'status' <> 'due' or v_s->>'due_by' <> '2020-08-12' or (v_s->>'late')::boolean then v_fail := v_fail || ' 1e due: ' || v_s::text || ';'; end if;
  v_s := public.fn_accountant_month_close_status(v_jul, date '2020-08-13');
  if not (v_s->>'late')::boolean then v_fail := v_fail || ' 1f not late after due_by;'; end if;

  -- July closes (as the tick would, without the CEO report the real close files)
  insert into public.accountant_month_close (month, figures, closed_at) values (v_jul, '{"month":"2020-07"}'::jsonb, '2020-08-11 10:00+04');
  v_s := public.fn_accountant_month_close_status(v_jul, date '2020-08-20');
  if v_s->>'status' <> 'closed' or (v_s->>'late')::boolean then v_fail := v_fail || ' 1g closed on time: ' || v_s::text || ';'; end if;

  -- 2 + 3. the late July fee arrives on the August statement, with a poisoned charge and a poisoned credit
  create function public.zz_probe_poison() returns trigger language plpgsql as $p$ begin raise exception 'ZZ DEMO poisoned line (probe)'; end $p$;
  create trigger a00_zz_probe_poison before insert on public.gl_journal
    for each row when (new.memo like '%ZZ DEMO POISON%') execute function public.zz_probe_poison();

  insert into public.bank_statement_intake (source_ref, account, statement_month, state, lines, note, received_at, closing_balance_aed, balance_on)
  values ('zz_demo:late_item_probe:2020-08', 'mashreq', v_aug, 'parsed', 4, 'ZZ DEMO', '2020-09-02 10:00+04', null, '2020-08-31');
  insert into public.bank_statement_line (account, source_ref, value_date, description, amount_aed, line_hash, kind)
  values ('mashreq', 'zz_demo:late_item_probe:2020-08', '2020-07-31', 'ZZ DEMO Late Maintenance Fee Jul', -199, md5('zz_demo_late_item_probe_l1'), 'bank_charge')
  returning id into l1;
  insert into public.bank_statement_line (account, source_ref, value_date, description, amount_aed, line_hash, kind)
  values ('mashreq', 'zz_demo:late_item_probe:2020-08', '2020-07-30', 'ZZ DEMO POISON charge', -10, md5('zz_demo_late_item_probe_l2'), 'bank_charge')
  returning id into l2;
  insert into public.bank_statement_line (account, source_ref, value_date, description, amount_aed, line_hash, kind)
  values ('mashreq', 'zz_demo:late_item_probe:2020-08', '2020-07-29', 'ZZ DEMO POISON transfer', 500, md5('zz_demo_late_item_probe_l3'), 'owner_transfer')
  returning id into l3;
  insert into public.bank_statement_line (account, source_ref, value_date, description, amount_aed, line_hash, kind)
  values ('mashreq', 'zz_demo:late_item_probe:2020-08', '2020-08-20', 'ZZ DEMO Monthly Maintenance Fee Aug', -199, md5('zz_demo_late_item_probe_l4'), 'bank_charge')
  returning id into l4;
  -- a fee refund the bank marked as a charge: a CREDIT of kind bank_charge, which no booking routine books, so it
  -- must never hold the close (re-review of #1063)
  insert into public.bank_statement_line (account, source_ref, value_date, description, amount_aed, line_hash, kind)
  values ('mashreq', 'zz_demo:late_item_probe:2020-08', '2020-08-21', 'ZZ DEMO Fee refund', 199, md5('zz_demo_late_item_probe_l5'), 'bank_charge')
  returning id into l5;
  -- a charge whose journal was voided: fn_accountant_book_bank_charges skips a line with ANY journal, so it is booked
  -- as far as the close is concerned and must never hold August (follow-up review of #1063)
  insert into public.bank_statement_line (account, source_ref, value_date, description, amount_aed, line_hash, kind)
  values ('mashreq', 'zz_demo:late_item_probe:2020-08', '2020-08-22', 'ZZ DEMO charge voided', -50, md5('zz_demo_late_item_probe_l6'), 'bank_charge')
  returning id into l6;
  insert into public.gl_journal (entry_date, memo, source, source_ref, created_by) values ('2020-08-22', 'ZZ DEMO voided charge', 'bank_charge', l6::text, 'accountant')
  returning id into jv;
  insert into public.gl_journal_lines (journal_id, line_no, account_code, debit, credit) values (jv, 1, '6300', 50, 0), (jv, 2, '1000', 0, 50);
  update public.gl_journal set status = 'void' where id = jv;

  begin
    v_c := public.fn_accountant_book_bank_charges();
    v_k := public.fn_accountant_book_bank_credits();
  exception when others then v_fail := v_fail || ' 3a a booking routine raised: ' || sqlerrm || ';';
  end;
  select * into j1 from public.gl_journal where source = 'bank_charge' and source_ref = l1::text and status = 'posted';
  if j1.id is null or j1.entry_date <> '2020-08-31' or j1.memo !~ ('^Prior-period adjustment: originally dated 2020-07-31 in the closed period 2020-07, statement line ' || l1 || '\.') then
    v_fail := v_fail || ' 2a late fee journal: ' || coalesce(to_jsonb(j1)::text, 'none') || ';'; end if;
  if not exists (select 1 from public.gl_prior_period_adjustment a where a.journal_id = j1.id and a.original_date = '2020-07-31'
                   and a.closed_month = v_jul and a.posted_on = '2020-08-31' and a.statement_line_id = l1 and a.amount_aed = 199) then
    v_fail := v_fail || ' 2b no adjustment row;'; end if;
  if not exists (select 1 from public.gl_journal where source = 'bank_charge' and source_ref = l4::text and status = 'posted' and entry_date = '2020-08-20') then
    v_fail := v_fail || ' 3b the August fee after the poisoned line did not post;'; end if;
  if exists (select 1 from public.gl_journal where source_ref in (l2::text, l3::text)) then v_fail := v_fail || ' 3c a poisoned line booked;'; end if;
  if not exists (select 1 from public.it_engineer_finding where issue_key = 'acct:bank_charges:line:' || l2 and closed_at is null)
     or not exists (select 1 from public.it_engineer_finding where issue_key = 'acct:bank_credits:line:' || l3 and closed_at is null)
     or coalesce((v_c->>'failed')::int, 0) < 1 or coalesce((v_k->>'failed')::int, 0) < 1 then
    v_fail := v_fail || ' 3d findings: charges ' || coalesce(v_c::text, 'none') || ' credits ' || coalesce(v_k::text, 'none') || ';'; end if;

  -- 5a. August waits while its statement has unbooked lines
  v_s := public.fn_accountant_month_close_status(v_aug, date '2020-09-03');
  if v_s->>'status' <> 'waiting_for_statement' or jsonb_array_length(v_s#>'{statement,unbooked_lines}') <> 2
     or exists (select 1 from jsonb_array_elements(v_s#>'{statement,unbooked_lines}') u where (u->>'line_id')::bigint in (l5, l6)) then
    v_fail := v_fail || ' 5a August with two unbooked lines (neither the fee refund nor the voided charge among them): ' || v_s::text || ';'; end if;
  if exists (select 1 from public.gl_journal where source_ref = l6::text and id <> jv) then v_fail := v_fail || ' 5d the voided charge was booked again;'; end if;
  if exists (select 1 from public.gl_journal where source_ref = l5::text) then v_fail := v_fail || ' 5c the fee refund was booked;'; end if;

  -- 4. the lock still refuses a direct back-dated posting
  begin
    insert into public.gl_journal (entry_date, memo, source, source_ref, status, created_by) values ('2020-07-20', 'ZZ DEMO direct', 'manual', 'zz_demo', 'posted', 'accountant');
    v_fail := v_fail || ' 4a a posted journal was inserted into closed July;';
  exception when others then v_err := sqlerrm;
  end;
  if coalesce(v_err, '') !~ 'period 2020-07 is closed' then v_fail := v_fail || ' 4a lock message: ' || coalesce(v_err, 'none') || ';'; end if;
  insert into public.gl_journal (entry_date, memo, source, source_ref, created_by) values ('2020-07-21', 'ZZ DEMO draft', 'manual', 'zz_demo', 'accountant') returning id into jd;
  insert into public.gl_journal_lines (journal_id, line_no, account_code, debit, credit) values (jd, 1, '6300', 25, 0), (jd, 2, '1000', 0, 25);
  v_err := null;
  begin
    update public.gl_journal set status = 'posted' where id = jd;
    v_fail := v_fail || ' 4b a July draft was flipped to posted outside fn_gl_post;';
  exception when others then v_err := sqlerrm;
  end;
  if coalesce(v_err, '') !~ 'period 2020-07 is closed' then v_fail := v_fail || ' 4b lock message: ' || coalesce(v_err, 'none') || ';'; end if;
  perform public.fn_gl_post(jd);
  if not exists (select 1 from public.gl_journal where id = jd and status = 'posted' and entry_date = '2020-08-31')
     or not exists (select 1 from public.gl_prior_period_adjustment where journal_id = jd and statement_line_id is null) then
    v_fail := v_fail || ' 4c fn_gl_post did not book the draft in August;'; end if;
  insert into public.gl_journal (entry_date, memo, source, source_ref, created_by) values ('2020-07-22', 'ZZ DEMO reopen', 'manual', 'zz_demo', 'accountant') returning id into jr;
  insert into public.gl_journal_lines (journal_id, line_no, account_code, debit, credit) values (jr, 1, '6300', 5, 0), (jr, 2, '1000', 0, 5);
  perform set_config('app.period_reopen_reason', 'ZZ DEMO probe reopen', true);
  perform public.fn_gl_post(jr);
  perform set_config('app.period_reopen_reason', '', true);
  if not exists (select 1 from public.gl_journal where id = jr and status = 'posted' and entry_date = '2020-07-22')
     or exists (select 1 from public.gl_prior_period_adjustment where journal_id = jr) then
    v_fail := v_fail || ' 4d a reopen reason did not keep the July date;'; end if;

  -- 3e + 5b. the poison is gone: both lines book (July-dated, so as adjustments), the findings close, August is due
  drop trigger a00_zz_probe_poison on public.gl_journal;
  drop function public.zz_probe_poison();
  v_c := public.fn_accountant_book_bank_charges();
  v_k := public.fn_accountant_book_bank_credits();
  if (select count(*) from public.gl_prior_period_adjustment where statement_line_id in (l2, l3) and posted_on = '2020-08-31') <> 2 then
    v_fail := v_fail || ' 3e the healed lines did not book as adjustments: ' || v_c::text || ' ' || v_k::text || ';'; end if;
  if exists (select 1 from public.it_engineer_finding where issue_key in ('acct:bank_charges:line:' || l2, 'acct:bank_credits:line:' || l3) and closed_at is null) then
    v_fail := v_fail || ' 3f a healed line''s finding is still open;'; end if;
  v_s := public.fn_accountant_month_close_status(v_aug, date '2020-09-03');
  if v_s->>'status' <> 'due' or v_s->>'due_by' <> '2020-09-05' then v_fail := v_fail || ' 5b August due: ' || v_s::text || ';'; end if;

  -- 6. August closes; its pack lists the adjustments
  insert into public.accountant_month_close (month, figures, closed_at)
  values (v_aug, jsonb_build_object('month', '2020-08', 'vat', public.fn_vat_threshold_position(0)), '2020-09-03 10:00+04');
  perform public.fn_accountant_founder_close_pack_build(v_aug);
  select figures into v_f from public.accountant_founder_close_pack where month = v_aug;
  if jsonb_array_length(coalesce(v_f->'prior_period_adjustments', '[]'::jsonb)) <> 4
     or not exists (select 1 from jsonb_array_elements(v_f->'prior_period_adjustments') a
                     where (a->>'statement_line_id')::bigint = l1 and a->>'original_date' = '2020-07-31' and a->>'closed_month' = '2020-07'
                       and (a->>'amount_aed')::numeric = 199) then
    v_fail := v_fail || ' 6a prior_period_adjustments: ' || coalesce((v_f->'prior_period_adjustments')::text, 'none') || ';'; end if;
  select count(*) into v_n from jsonb_array_elements(v_f->'unusual') u
   where u->>'rule' = 'prior_period_adjustment' and (u->>'explained')::boolean
     and u->>'explanation' ~ ('dated 2020-07-31 in 2020-07, which was already closed \(statement line ' || l1 || '\)');
  if v_n <> 1 then v_fail := v_fail || ' 6b unusual item for the late fee: ' || (v_f->'unusual')::text || ';'; end if;
  if exists (select 1 from jsonb_array_elements(v_f#>'{bank,unbooked_statement_lines}') b where (b->>'line_id')::bigint = l1) then
    v_fail := v_fail || ' 6c the booked late fee reads as an unbooked statement line;'; end if;
  v_doc := public.fn_accountant_founder_close_pack_document(v_aug);
  if v_doc::text !~ 'prior-period adjustment' or v_doc::text !~ '2020-07-31' then v_fail := v_fail || ' 6d document: ' || left(v_doc::text, 400) || ';'; end if;

  -- 7. the real books: the tick and the day-5 check run and read the previous month
  begin
    v_c := public.fn_accountant_month_close_tick();
    v_k := public.fn_accountant_close_by_day_5();
    v_s := public.fn_accountant_owner_card_tick();
  exception when others then v_fail := v_fail || ' 7a a tick raised: ' || sqlerrm || ';';
  end;
  if (v_k->>'status') is null then v_fail := v_fail || ' 7b day-5 check: ' || coalesce(v_k::text, 'none') || ';'; end if;

  if v_fail = '' then
    raise exception 'CHK<<PROBE OK: July waited for its statement then was due by 2020-08-12; late July fee (line %) posted % as a prior-period adjustment; poisoned charge and credit were findings and the rest booked, then healed and closed; lock refused the direct insert and the direct flip, fn_gl_post moved the draft to August, a reopen kept July; August waited on 2 unbooked lines (a fee refund left as a charge and a voided charge did not count) then was due by 2020-09-05; the August pack lists % adjustments and explains the late fee; real close tick: % / day-5: % (late %)>>',
      l1, j1.entry_date, jsonb_array_length(v_f->'prior_period_adjustments'), coalesce(v_c->>'status', v_c->>'closed'), v_k->>'status', v_k->>'late';
  end if;
  raise exception 'CHK<<PROBE FAILED:%>>', v_fail;
end $probe$;
