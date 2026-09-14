-- PROBE: bank credits are classified deterministically (14 Sep 2026; review of b06d251). A transfer from the
-- licence holder's own account is Dr 1000 / Cr 3000 Owner Capital (founder_instruction 357); the bank's
-- month-end interest is Dr 1000 / Cr 7000 Bank Interest Income; nothing is guessed; no revenue total counts
-- either; a bad pattern is a finding that leaves the rest of the tick running; a line is booked once.
-- PURE PROBE: no DDL; it ends in raise exception, so every row it writes rolls back. Invented values only: a
-- ZZ DEMO licence holder (a newer company_registration row, rolled back with the rest), ZZ DEMO lines on
-- account zz_demo, and one ZZ DEMO posted journal for the revenue readers.
--   node scripts/qsql.mjs scripts/checks/owner_capital_fixtures.sql      -> expect CHK<<ok ...>>
do $probe$
declare
  v_a bigint; v_b bigint; v_c bigint; v_d bigint; v_e bigint; v_f bigint; v_g bigint; v_h bigint; v_i bigint; v_j bigint;
  r jsonb; r2 jsonb; t jsonb; v_codes text; v_icodes text; v_n int; v_id1 bigint; v_id2 bigint; v_real_before int; v_real_after int;
  mc0 numeric; mc1 numeric; fk0 numeric; fk1 numeric; pn0 numeric; pn1 numeric; vt0 numeric; vt1 numeric; v_m date := date_trunc('month', current_date)::date;
  ins text := 'insert into public.bank_statement_line (account, source_ref, value_date, description, amount_aed, reference, line_hash) values (''zz_demo'', ''zz_probe_owner_capital'', $1, $2, $3, null, md5($4)) returning id';
begin
  select count(*) into v_real_before from public.gl_journal where source in ('owner_capital', 'bank_interest');
  insert into public.company_registration (recorded_at, authority, license_type, license_no, trade_name, issued_on, expires_on,
    owner_name, owner_share, activities, registered_email, registered_mobile, e_stores, license_class_note, source_file)
  values (now() + interval '100 years', 'ZZ DEMO', 'ZZ DEMO', 'ZZ0', 'zz demo', current_date, current_date,
    'Zz Demo Owner Person', '100%', 'ZZ DEMO', 'zz@example.invalid', '+0', 'ZZ DEMO', 'ZZ DEMO', 'ZZ DEMO');
  insert into public.bank_statement_intake (source_ref, account, statement_month, state, lines)
  values ('zz_probe_owner_capital', 'zz_demo', date '2026-07-01', 'parsed', 10);
  execute ins into v_a using date '2026-07-07', 'TRANSFER IN 000000000000ZZ000 - ZZ DEMO OWNER PERSON - P_2_P - 000000000000Z000 000ZZZZ00000000ZZZ', 2500.00, 'zz_probe_oc_a';
  execute ins into v_b using date '2026-07-08', 'TRANSFER IN - ZZ DEMO SOMEONE ELSE - P_2_P -', 300.00, 'zz_probe_oc_b';
  execute ins into v_c using date '2026-07-09', 'TRANSFER IN - ZZ DEMO OWNER PERSON - P_2_P -', 400.00, 'zz_probe_oc_c';
  execute ins into v_d using date '2026-07-10', 'CASH DEPOSIT ZZ DEMO OWNER PERSON', 50.00, 'zz_probe_oc_d';
  execute ins into v_e using date '2026-08-01', 'Interest 000111222333 0ZZCIDAED 00001', 12.34, 'zz_probe_oc_e';
  execute ins into v_f using date '2026-07-11', 'TRANSFER IN - ZZ DEMO SHOP INTEREST REFUND', 20.00, 'zz_probe_oc_f';
  -- review 4: a relative who shares every one of the owner's names, and one more, is NOT the owner
  execute ins into v_g using date '2026-07-12', 'TRANSFER IN - ZZ DEMO OWNER PERSON JUNIOR - P_2_P -', 700.00, 'zz_probe_oc_g';
  execute ins into v_h using date '2026-07-13', 'TRANSFER IN - MRS ZZ DEMO OWNER PERSON - P_2_P -', 800.00, 'zz_probe_oc_h';
  insert into public.bank_line_owner_ruling (line_id, ruling) values (v_c, 'loan');

  r := public.fn_accountant_book_bank_credits();
  r2 := public.fn_accountant_book_bank_credits();   -- review 3: a double run books nothing more

  select string_agg(l.account_code || ':' || l.debit || '/' || l.credit, ',' order by l.line_no) into v_codes
    from public.gl_journal g join public.gl_journal_lines l on l.journal_id = g.id
   where g.source = 'owner_capital' and g.source_ref = v_a::text and g.status = 'draft';
  if v_codes is distinct from '1000:2500.00/0.00,3000:0.00/2500.00' then raise exception 'owner transfer booked as %', v_codes; end if;
  select string_agg(l.account_code || ':' || l.debit || '/' || l.credit, ',' order by l.line_no) into v_icodes
    from public.gl_journal g join public.gl_journal_lines l on l.journal_id = g.id
   where g.source = 'bank_interest' and g.source_ref = v_e::text and g.status = 'draft';
  if v_icodes is distinct from '1000:12.34/0.00,7000:0.00/12.34' then raise exception 'bank interest booked as %', v_icodes; end if;
  if exists (select 1 from public.gl_journal where source in ('owner_capital', 'bank_interest')
              and source_ref in (v_b::text, v_c::text, v_d::text, v_f::text, v_g::text, v_h::text)) then
    raise exception 'a credit that is not a recognised owner transfer or bank interest (a superset name, a loan ruling) was booked';
  end if;
  if (select count(*) from public.gl_journal where source in ('owner_capital', 'bank_interest') and source_ref in (v_a::text, v_e::text)) <> 2 then
    raise exception 'a credit was booked more than once';
  end if;
  -- review 3: the index refuses a second live journal for the same line, and the draft writer returns the first
  begin
    insert into public.gl_journal (entry_date, memo, source, source_ref, created_by, status)
    values (current_date, 'ZZ DEMO duplicate', 'owner_capital', v_a::text, 'probe', 'draft');
    raise exception 'a second live journal for the same bank line was accepted';
  exception when unique_violation then null;
  end;
  v_id1 := public.fn_accountant_draft_entry(current_date, 'ZZ DEMO', 'bank_interest', v_e::text, '[{"account":"1000","debit":1},{"account":"7000","credit":1}]');
  select id into v_id2 from public.gl_journal where source = 'bank_interest' and source_ref = v_e::text and status in ('draft', 'posted');
  if v_id1 is distinct from v_id2 then raise exception 'the draft writer made a second journal (% vs %)', v_id1, v_id2; end if;
  if not exists (select 1 from public.it_engineer_finding where issue_key = 'acct:bank_credits:unrecognised:' || v_b and closed_at is null)
     or not exists (select 1 from public.it_engineer_finding where issue_key = 'acct:bank_credits:unrecognised:' || v_d and closed_at is null)
     or not exists (select 1 from public.it_engineer_finding where issue_key = 'acct:bank_credits:unrecognised:' || v_f and closed_at is null)
     or not exists (select 1 from public.it_engineer_finding where issue_key = 'acct:bank_credits:unrecognised:' || v_g and closed_at is null)
     or not exists (select 1 from public.it_engineer_finding where issue_key = 'acct:bank_credits:unrecognised:' || v_h and closed_at is null)
     or not exists (select 1 from public.it_engineer_finding where issue_key = 'acct:bank_credits:loan:' || v_c and closed_at is null)
     or exists (select 1 from public.it_engineer_finding where issue_key = 'acct:bank_credits:unrecognised:' || v_e) then
    raise exception 'the findings are wrong: %', r;
  end if;

  -- review 2: a bad pattern is ONE finding naming the setting; that rule books nothing; the tick still books
  -- the bank charges and the interest.
  update public.gl_settings set txt_value = '(' where key = 'owner_transfer_pattern';
  execute ins into v_i using date '2026-07-31', 'ZZ DEMO MONTHLY MAINTENANCE FEE', -15.00, 'zz_probe_oc_i';
  execute ins into v_j using date '2026-07-31', 'Interest 000111222333 0ZZCIDAED 00002', 1.11, 'zz_probe_oc_j';
  execute ins into v_n using date '2026-07-30', 'TRANSFER IN - ZZ DEMO OWNER PERSON - P_2_P - SECOND', 90.00, 'zz_probe_oc_k';
  t := public.fn_accountant_cost_booking_tick();
  if not exists (select 1 from public.it_engineer_finding where issue_key = 'acct:bank_credits:setting:owner_transfer_pattern' and closed_at is null) then
    raise exception 'a bad owner_transfer_pattern raised no finding: %', t;
  end if;
  if not exists (select 1 from public.gl_journal where source = 'bank_charge' and source_ref = v_i::text) then
    raise exception 'a bad pattern stopped the bank charges: %', t;
  end if;
  if not exists (select 1 from public.gl_journal where source = 'bank_interest' and source_ref = v_j::text) then
    raise exception 'a bad owner pattern stopped the interest rule: %', t;
  end if;
  if exists (select 1 from public.gl_journal where source = 'owner_capital' and source_ref = v_n::text) then
    raise exception 'the owner rule booked with its pattern invalid';
  end if;
  update public.gl_settings set txt_value = 'transfer|p_?2_?p' where key = 'owner_transfer_pattern';

  -- review 1: POSTED interest and capital change no revenue total — month close, finance_kpis, gl_pnl, VAT watch
  mc0 := (public.fn_accountant_month_close_figures(v_m)->'profit_and_loss'->>'revenue_aed')::numeric;
  select revenue_total into fk0 from public.finance_kpis;
  select coalesce(sum(amount), 0) into pn0 from public.gl_pnl where type = 'revenue';
  select coalesce(sum(l.credit - l.debit), 0) into vt0 from public.gl_journal_lines l join public.gl_journal j on j.id = l.journal_id
   where l.account_code like '4%' and j.status = 'posted';
  perform public.fn_gl_entry(current_date, 'ZZ DEMO probe interest', 'zz_probe_reader', 'zz1',
    '[{"account":"1000","debit":1234.56},{"account":"7000","credit":1234.56}]'::jsonb, 'probe');
  perform public.fn_gl_entry(current_date, 'ZZ DEMO probe capital', 'zz_probe_reader', 'zz2',
    '[{"account":"1000","debit":5000},{"account":"3000","credit":5000}]'::jsonb, 'probe');
  mc1 := (public.fn_accountant_month_close_figures(v_m)->'profit_and_loss'->>'revenue_aed')::numeric;
  select revenue_total into fk1 from public.finance_kpis;
  select coalesce(sum(amount), 0) into pn1 from public.gl_pnl where type = 'revenue';
  select coalesce(sum(l.credit - l.debit), 0) into vt1 from public.gl_journal_lines l join public.gl_journal j on j.id = l.journal_id
   where l.account_code like '4%' and j.status = 'posted';
  if mc1 is distinct from mc0 or fk1 is distinct from fk0 or pn1 is distinct from pn0 or vt1 is distinct from vt0 then
    raise exception 'interest or capital reached a revenue total: month close % -> %, finance_kpis % -> %, gl_pnl % -> %, VAT % -> %',
      mc0, mc1, fk0, fk1, pn0, pn1, vt0, vt1;
  end if;
  if exists (select 1 from jsonb_array_elements(public.fn_accountant_month_close_figures(v_m)->'profit_and_loss'->'accounts') a
              where a->>'code' in ('3000', '7000')) then
    raise exception 'the month close lists 3000 or 7000 among revenue and expense accounts';
  end if;

  select count(*) into v_real_after from public.gl_journal where source in ('owner_capital', 'bank_interest')
     and source_ref not in (v_a::text, v_e::text, v_j::text);
  raise exception 'CHK<<ok first=% second=% tick_bank_credits=% revenue_unchanged=% real_journals_before=% after_excluding_probe=%>>',
    r, r2, t->'bank_credits', mc0 = mc1, v_real_before, v_real_after;
end $probe$;
