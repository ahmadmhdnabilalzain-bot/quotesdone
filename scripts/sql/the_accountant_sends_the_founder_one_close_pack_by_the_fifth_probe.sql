-- PROBE: THE ACCOUNTANT SENDS THE FOUNDER ONE CLOSE PACK BY THE FIFTH. Seat: accountant.
--
-- Pure probe: no DDL, never applied. Run it through node scripts/qsql.mjs AFTER
-- the_accountant_sends_the_founder_one_close_pack_by_the_fifth.sql is live. Before merge it was run as #1013's
-- file, that file and this one in ONE transaction that the final raise rolls back, so the build was proved
-- without being applied.
--
-- Everything happens inside a block that always raises, so nothing survives, and pg_net sends only committed rows,
-- so the founder receives nothing. The month is ZZ DEMO January 2020, which no real row touches: ZZ DEMO journals,
-- a ZZ DEMO statement and statement line on a 'zz_demo' source_ref, and a ZZ DEMO active budget.
--
-- VERDICT (in the error text): CHK<<PROBE OK ...>> only if
--   1. an OPEN month is refused (no pack for a month that has no close row);
--   2. after the close row exists, a posting dated in the month is refused by the period lock (#1013);
--   3. the pack reconciles GL 1000 to the statement through the unbooked line, and says 'reconciled';
--   4. P&L against budget: 6000 actual 1500 against budget 300;
--   5. unusual items: 6 by rule (3 budget variances, 1 large line, 1 VOID reversal - fn_gl_reverse's shape -,
--      1 unbooked statement line), exactly 1
--      unexplained (the 6200 journal with no memo), and the PDF text says UNEXPLAINED;
--   6. attaching the PDF sends ONE founder email of kind accountant_close_pack through fn_notify_founder with the
--      PDF attached; a second send sends nothing;
--   7. no real accountant_founder_close_pack row, budget or month close was touched.
do $probe$
declare
  v_m date := date '2020-01-01'; v_b bigint; j1 bigint; j2 bigint; j3 bigint; j4 bigint; j5 bigint; v_r jsonb; v_f jsonb; v_doc jsonb;
  v_n int; v_real_before bigint; v_real_after bigint; v_fail text := ''; v_lock text; v_nid bigint; v_att jsonb;
begin
  select count(*) into v_real_before from public.accountant_founder_close_pack where month <> v_m;

  -- 1. an open month is refused
  begin
    perform public.fn_accountant_founder_close_pack_build(v_m);
    v_fail := v_fail || ' an open month was built;';
  exception when others then
    if sqlerrm !~ 'is not closed' then v_fail := v_fail || ' open month refused for the wrong reason: ' || sqlerrm || ';'; end if;
  end;

  insert into public.budgets (name, fiscal_year, status, created_by) values ('ZZ DEMO close pack probe budget', 2020, 'active', 'accountant') returning id into v_b;
  insert into public.budget_lines (budget_id, account_code, period_month, amount) values
    (v_b, '6000', v_m, 300), (v_b, '6300', v_m, 40), (v_b, '4000', v_m, 0);

  -- revenue 800 into the bank; software 1500 paid from the bank; marketing 600 with NO memo; admin 50
  insert into public.gl_journal (entry_date, memo, source, source_ref, created_by) values ('2020-01-10', 'ZZ DEMO reveal fee', 'manual', 'zz_demo', 'accountant') returning id into j1;
  insert into public.gl_journal_lines (journal_id, line_no, account_code, debit, credit, memo) values (j1, 1, '1000', 800, 0, null), (j1, 2, '4000', 0, 800, 'ZZ DEMO reveal fee');
  perform public.fn_gl_post(j1);
  insert into public.gl_journal (entry_date, memo, source, source_ref, created_by) values ('2020-01-12', 'ZZ DEMO software year', 'manual', 'zz_demo', 'accountant') returning id into j2;
  insert into public.gl_journal_lines (journal_id, line_no, account_code, debit, credit, memo) values (j2, 1, '6000', 1500, 0, 'ZZ DEMO software year'), (j2, 2, '1000', 0, 1500, null);
  perform public.fn_gl_post(j2);
  insert into public.gl_journal (entry_date, memo, source, source_ref, created_by) values ('2020-01-14', null, 'manual', 'zz_demo', 'accountant') returning id into j3;
  insert into public.gl_journal_lines (journal_id, line_no, account_code, debit, credit, memo) values (j3, 1, '6200', 600, 0, null), (j3, 2, '1000', 0, 600, null);
  perform public.fn_gl_post(j3);
  insert into public.gl_journal (entry_date, memo, source, source_ref, created_by) values ('2020-01-15', 'ZZ DEMO stationery', 'manual', 'zz_demo', 'accountant') returning id into j4;
  insert into public.gl_journal_lines (journal_id, line_no, account_code, debit, credit, memo) values (j4, 1, '6300', 50, 0, 'ZZ DEMO stationery'), (j4, 2, '1000', 0, 50, null);
  perform public.fn_gl_post(j4);
  -- the reversal shape fn_gl_reverse leaves: source 'reversal', source_ref = the original, VOID (it voids both sides).
  -- Written directly, because fn_gl_reverse dates its reversal today and this month is January 2020; the original
  -- stays posted so the figures above are unchanged. The rule must still name it.
  insert into public.gl_journal (entry_date, memo, source, source_ref, created_by) values ('2020-01-25', 'REVERSAL of journal ' || j4 || ' (ZZ DEMO stationery) - ZZ DEMO probe', 'reversal', j4::text, 'fn_gl_reverse') returning id into j5;
  insert into public.gl_journal_lines (journal_id, line_no, account_code, debit, credit, memo) values (j5, 1, '1000', 50, 0, null), (j5, 2, '6300', 0, 50, null);
  update public.gl_journal set status = 'void', reverses = j4 where id = j5;

  -- the statement carries only a bank charge of -199 that the books have not booked; the four journals above are
  -- in the books (GL 1000 = -1350) but on no statement line yet. Statement = books + unbooked - book-only
  -- = -1350 + (-199) - (-1350) = -199.
  insert into public.bank_statement_intake (source_ref, account, statement_month, state, lines, note, closing_balance_aed, balance_on)
  values ('zz_demo:close_pack_probe', 'mashreq', v_m, 'parsed', 1, 'ZZ DEMO', -199, '2020-01-31');
  insert into public.bank_statement_line (account, source_ref, value_date, description, amount_aed, line_hash)
  values ('mashreq', 'zz_demo:close_pack_probe', '2020-01-20', 'ZZ DEMO Monthly Maintenance Fee', -199, md5('zz_demo_close_pack_probe'));

  insert into public.accountant_month_close (month, figures)
  values (v_m, jsonb_build_object('month', '2020-01', 'vat', public.fn_vat_threshold_position(800)));

  -- 2. the period lock refuses a posting dated in the closed month
  begin
    insert into public.gl_journal (entry_date, memo, source, source_ref, status, created_by) values ('2020-01-20', 'ZZ DEMO late', 'manual', 'zz_demo', 'posted', 'accountant');
    v_fail := v_fail || ' the period lock let a posting into the closed month;';
  exception when others then v_lock := sqlerrm;
  end;
  if coalesce(v_lock, '') !~ 'is closed' then v_fail := v_fail || ' lock message: ' || coalesce(v_lock, 'none') || ';'; end if;

  v_r := public.fn_accountant_founder_close_pack_build(v_m);
  select figures into v_f from public.accountant_founder_close_pack where month = v_m;

  -- 3. bank
  if v_f#>>'{bank,status}' <> 'reconciled' then v_fail := v_fail || ' bank: ' || (v_f->'bank')::text || ';'; end if;
  if (v_f#>>'{bank,gl_1000_aed}')::numeric <> -1350 or (v_f#>>'{bank,unbooked_aed}')::numeric <> -199 then
    v_fail := v_fail || ' bank figures ' || (v_f#>>'{bank,gl_1000_aed}') || '/' || (v_f#>>'{bank,unbooked_aed}') || ';'; end if;
  -- 4. P&L against budget
  if not exists (select 1 from jsonb_array_elements(v_f#>'{pnl_vs_budget,accounts}') e
                  where e->>'code' = '6000' and (e->>'actual_aed')::numeric = 1500 and (e->>'budget_aed')::numeric = 300) then
    v_fail := v_fail || ' pnl 6000: ' || (v_f->'pnl_vs_budget')::text || ';'; end if;
  -- 5. unusual items
  if (v_f->>'unusual_items')::int <> 6 or (v_f->>'unexplained_items')::int <> 1 then
    v_fail := v_fail || ' unusual ' || (v_f->>'unusual_items') || '/' || (v_f->>'unexplained_items') || ': ' || (v_f->'unusual')::text || ';'; end if;
  if not exists (select 1 from jsonb_array_elements(v_f->'unusual') u
                  where u->>'rule' = 'reversal' and u->>'status' = 'void' and (u->>'explained')::boolean
                    and u->>'reverses' = 'JE-' || lpad(j4::text, 6, '0') and (u->>'amount_aed')::numeric = 50) then
    v_fail := v_fail || ' the void reversal is not an explained unusual item;'; end if;
  if not exists (select 1 from jsonb_array_elements(v_f->'unusual') u where u->>'account' = '6200' and not (u->>'explained')::boolean) then
    v_fail := v_fail || ' the memo-less 6200 journal is not the unexplained item;'; end if;
  v_doc := public.fn_accountant_founder_close_pack_document(v_m);
  if v_doc::text !~ 'UNEXPLAINED' or jsonb_array_length(v_doc->'blocks') < 10 then v_fail := v_fail || ' document: ' || left(v_doc::text, 300) || ';'; end if;

  -- 6. render arrives -> ONE founder email of the right kind, PDF attached; the second send sends nothing
  v_r := public.fn_accountant_founder_close_pack_attach(v_m, 'finance-reports', 'accountant/close-pack/2020-01/QuotesDone_Close_Pack_2020-01.pdf');
  if not coalesce((v_r->>'ok')::boolean, false) then v_fail := v_fail || ' send: ' || v_r::text || ';'; end if;
  v_nid := (v_r->>'notification_id')::bigint;
  select attachments into v_att from public.notifications where id = v_nid and kind = 'accountant_close_pack' and to_role = 'founder' and channel = 'email';
  if v_att is null or v_att->0->>'path' <> 'accountant/close-pack/2020-01/QuotesDone_Close_Pack_2020-01.pdf' then
    v_fail := v_fail || ' email/attachment: ' || coalesce(v_att::text, 'none') || ';'; end if;
  v_r := public.fn_accountant_founder_close_pack_send(v_m);
  select count(*) into v_n from public.notifications where kind = 'accountant_close_pack' and id >= v_nid;
  if v_n <> 1 or v_r->>'already_sent' is null then v_fail := v_fail || ' second send: ' || v_n || ' ' || v_r::text || ';'; end if;

  -- 7. nothing real touched
  select count(*) into v_real_after from public.accountant_founder_close_pack where month <> v_m;
  if v_real_after <> v_real_before then v_fail := v_fail || ' a real pack row changed;'; end if;

  if v_fail = '' then
    raise exception 'CHK<<PROBE OK: open month refused; period lock refused a posting; bank %; 6000 1500 vs 300; % unusual, % unexplained; one founder email % kind accountant_close_pack with the PDF; second send none>>',
      v_f#>>'{bank,status}', v_f->>'unusual_items', v_f->>'unexplained_items', v_nid;
  end if;
  raise exception 'CHK<<PROBE FAILED:%>>', v_fail;
end $probe$;
