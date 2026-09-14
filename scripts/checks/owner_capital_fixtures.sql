-- PROBE: a transfer from the licence holder's own account is booked Dr 1000 / Cr 3000 and nothing else is
-- guessed (founder_instruction 357, 14 Sep 2026). PURE PROBE: no DDL; it ends in raise exception, so every
-- row it writes rolls back. Invented values only: a ZZ DEMO licence holder (a newer company_registration row,
-- rolled back with the rest), ZZ DEMO lines on account zz_demo.
--   node scripts/qsql.mjs scripts/checks/owner_capital_fixtures.sql      -> expect CHK<<ok ...>>
do $probe$
declare v_a bigint; v_b bigint; v_c bigint; v_d bigint; r jsonb; r2 jsonb; v_codes text; v_rev int; v_real_before int; v_real_after int;
begin
  select count(*) into v_real_before from public.gl_journal where source = 'owner_capital';
  insert into public.company_registration (recorded_at, authority, license_type, license_no, trade_name, issued_on, expires_on,
    owner_name, owner_share, activities, registered_email, registered_mobile, e_stores, license_class_note, source_file)
  values (now() + interval '100 years', 'ZZ DEMO', 'ZZ DEMO', 'ZZ0', 'zz demo', current_date, current_date,
    'Zz Demo Owner Person', '100%', 'ZZ DEMO', 'zz@example.invalid', '+0', 'ZZ DEMO', 'ZZ DEMO', 'ZZ DEMO');
  insert into public.bank_statement_intake (source_ref, account, statement_month, state, lines)
  values ('zz_probe_owner_capital', 'zz_demo', date '2026-07-01', 'parsed', 4);
  insert into public.bank_statement_line (account, source_ref, value_date, description, amount_aed, reference, line_hash) values
    ('zz_demo', 'zz_probe_owner_capital', date '2026-07-07',
     'TRANSFER IN 000000000000ZZ000 - ZZ DEMO OWNER PERSON - P_2_P - 000000000000Z000 000ZZZZ00000000ZZZ', 2500.00, null, md5('zz_probe_oc_a'))
    returning id into v_a;
  insert into public.bank_statement_line (account, source_ref, value_date, description, amount_aed, reference, line_hash) values
    ('zz_demo', 'zz_probe_owner_capital', date '2026-07-08', 'TRANSFER IN - ZZ DEMO SOMEONE ELSE - P_2_P -', 300.00, null, md5('zz_probe_oc_b'))
    returning id into v_b;
  insert into public.bank_statement_line (account, source_ref, value_date, description, amount_aed, reference, line_hash) values
    ('zz_demo', 'zz_probe_owner_capital', date '2026-07-09', 'TRANSFER IN - ZZ DEMO OWNER PERSON - P_2_P -', 400.00, null, md5('zz_probe_oc_c'))
    returning id into v_c;
  insert into public.bank_statement_line (account, source_ref, value_date, description, amount_aed, reference, line_hash) values
    ('zz_demo', 'zz_probe_owner_capital', date '2026-07-10', 'CASH DEPOSIT ZZ DEMO OWNER PERSON', 50.00, null, md5('zz_probe_oc_d'))
    returning id into v_d;
  insert into public.bank_line_owner_ruling (line_id, ruling) values (v_c, 'loan');

  r := public.fn_accountant_book_owner_capital();
  r2 := public.fn_accountant_book_owner_capital();   -- idempotent: nothing booked twice

  select string_agg(l.account_code || ':' || l.debit || '/' || l.credit, ',' order by l.line_no) into v_codes
    from public.gl_journal g join public.gl_journal_lines l on l.journal_id = g.id
   where g.source = 'owner_capital' and g.source_ref = v_a::text;
  if v_codes is distinct from '1000:2500.00/0.00,3000:0.00/2500.00' then raise exception 'owner transfer booked as %', v_codes; end if;
  if exists (select 1 from public.gl_journal where source = 'owner_capital' and source_ref in (v_b::text, v_c::text, v_d::text)) then
    raise exception 'a credit that is not a recognised owner transfer, or one ruled a loan, was booked as capital';
  end if;
  select count(*) into v_rev from public.gl_journal g join public.gl_journal_lines l on l.journal_id = g.id
   where g.source = 'owner_capital' and l.account_code like '4%';
  if v_rev <> 0 then raise exception 'owner capital touched a revenue account (%), which the VAT watch counts', v_rev; end if;
  if (select count(*) from public.gl_journal where source = 'owner_capital' and source_ref = v_a::text) <> 1 then
    raise exception 'the owner transfer was booked more than once';
  end if;
  if not exists (select 1 from public.it_engineer_finding where issue_key = 'acct:bank_credits:unrecognised:' || v_b and closed_at is null)
     or not exists (select 1 from public.it_engineer_finding where issue_key = 'acct:bank_credits:unrecognised:' || v_d and closed_at is null)
     or not exists (select 1 from public.it_engineer_finding where issue_key = 'acct:bank_credits:loan:' || v_c and closed_at is null) then
    raise exception 'an unrecognised credit or a loan ruling raised no finding: %', r;
  end if;
  if public.fn_bank_line_is_owner_transfer('TRANSFER IN - ZZ DEMO OWNER - P_2_P -') then
    raise exception 'a description naming only part of the licence holder matched';
  end if;
  select count(*) into v_real_after from public.gl_journal where source = 'owner_capital' and source_ref not in (v_a::text);
  raise exception 'CHK<<ok first=% second=% real_owner_capital_journals_before=% after_excluding_probe=%>>', r, r2, v_real_before, v_real_after;
end $probe$;
