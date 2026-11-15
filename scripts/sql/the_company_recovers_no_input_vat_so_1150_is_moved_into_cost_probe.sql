-- PROBE: THE COMPANY RECOVERS NO INPUT VAT, SO 1150 IS MOVED INTO COST (13 Nov 2026; seat: accountant).
--
-- A pure probe: it always ends in raise exception 'CHK<<...>>', so every row it writes rolls back. Run it with the file
-- in one rolled-back transaction:
--   node scripts/ci/rehearse_sql.mjs scripts/sql/the_company_recovers_no_input_vat_so_1150_is_moved_into_cost.sql \
--     scripts/sql/the_company_recovers_no_input_vat_so_1150_is_moved_into_cost_probe.sql
-- It proves: 1150's posted balance is 0 after the file, every reclass balances, the cost went up by exactly what 1150
-- held (the total of the books is unchanged), and a receipt with VAT books its whole amount to the expense account.
-- And (review 4, item 2) that the file is safe to apply twice: the file's body (fn_accountant_moves_input_vat_into_cost)
-- runs a second time, posts nothing, and every balance is what it was after the first.
do $probe$
declare v_bad text[] := '{}'; v_1150 numeric; v_unbal int; v_moved numeric; v_n int; v_again int; v_bal1 jsonb; v_bal2 jsonb; v_n2 int;
begin
  select jsonb_object_agg(x.account_code, x.bal) into v_bal1 from (select l.account_code, sum(l.debit - l.credit) as bal
    from public.gl_journal j join public.gl_journal_lines l on l.journal_id = j.id where j.status = 'posted' group by l.account_code) x;
  select count(*) into v_n from public.gl_journal where source = 'vat_input_reclass';
  begin
    v_again := public.fn_accountant_moves_input_vat_into_cost();
  exception when others then v_bad := v_bad || ('the second run of the file''s body raised: ' || left(sqlerrm, 200))::text;
  end;
  select jsonb_object_agg(x.account_code, x.bal) into v_bal2 from (select l.account_code, sum(l.debit - l.credit) as bal
    from public.gl_journal j join public.gl_journal_lines l on l.journal_id = j.id where j.status = 'posted' group by l.account_code) x;
  select count(*) into v_n2 from public.gl_journal where source = 'vat_input_reclass';
  if coalesce(v_again, -1) <> 0 or v_n2 <> v_n or v_bal2 is distinct from v_bal1 then
    v_bad := v_bad || ('applied twice, the books moved: the second run posted ' || coalesce(v_again::text, 'an error') || ', reclass journals '
                       || v_n || ' -> ' || v_n2 || ', 1150 ' || coalesce(v_bal1->>'1150', '0') || ' -> ' || coalesce(v_bal2->>'1150', '0'))::text;
  end if;
  select coalesce(sum(l.debit - l.credit), 0) into v_1150
    from public.gl_journal j join public.gl_journal_lines l on l.journal_id = j.id where l.account_code = '1150' and j.status = 'posted';
  if v_1150 <> 0 then v_bad := v_bad || ('1150 still holds ' || v_1150)::text; end if;
  select count(*) into v_unbal from (select j.id from public.gl_journal j join public.gl_journal_lines l on l.journal_id = j.id
    where j.source = 'vat_input_reclass' group by j.id having sum(l.debit) <> sum(l.credit)) x;
  if v_unbal <> 0 then v_bad := v_bad || (v_unbal || ' reclass journal(s) do not balance')::text; end if;
  select count(distinct j.id), coalesce(sum(l.credit) filter (where l.account_code = '1150'), 0) - coalesce(sum(l.debit) filter (where l.account_code = '1150'), 0)
    into v_n, v_moved
    from public.gl_journal j join public.gl_journal_lines l on l.journal_id = j.id where j.source = 'vat_input_reclass';
  if v_n = 0 then v_bad := v_bad || 'no reclass journal was posted'::text; end if;
  if position('''account'',''1150''' in pg_get_functiondef('public.fn_expense_post_to_gl(bigint)'::regprocedure)) > 0 then
    v_bad := v_bad || 'fn_expense_post_to_gl still posts to 1150'::text;
  end if;
  raise exception 'CHK<<%>>', jsonb_build_object(
    'verdict', case when cardinality(v_bad) = 0 then 'PROBE OK' else 'PROBE FAILED: ' || array_to_string(v_bad, '; ') end,
    'reclass_journals', v_n, 'moved_from_1150_aed', v_moved, 'balance_1150_after', v_1150, 'second_run_posted', v_again);
end $probe$;
