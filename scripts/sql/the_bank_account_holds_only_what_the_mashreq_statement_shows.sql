-- accountant: the ledger's Cash & Bank (1000) is reconciled to the Mashreq statement, AED 582.96.
--
-- Measured 28 Sep 2026 before this file (posted journals only, which is how every ledger view reads):
--   1000 = -7,967.25.   Statement = 582.96 = capital 1,000.00 - fees 2 x (199.00 + 9.95) + interest 0.86.
-- Every other credit to 1000 is wrong, for two reasons:
--   A. 54 expense journals (8,738.06) credited the bank for vendor charges paid on the founder's
--      personal card (standing rule: subscriptions are on his card until October; the bank account
--      only opened 19 Aug 2026). They belong to 2500 Due to Owner, as journal 2195 already did for
--      OpenAI Sep 2026. Reclassified here: DR 1000 / CR 2500, one adjusting journal per original.
--   B. fn_gl_reverse posts the reversal AND sets the original void, and every reader counts posted
--      only, so the correction is counted with no original to cancel. Journals 98, 131, 140 (bank
--      +187.85 too high) and 690 (1110 at -3,978.30, 6900 and 4400 overstated). Restated here by an
--      adjusting journal carrying the void original's lines, so posted-only readers net to zero.
-- Nothing is deleted or edited; every correction is a new posted journal. Idempotent by source_ref.
do $$
declare r record; v_bank numeric;
begin
  -- A. founder's-card expenses booked against the bank
  for r in
    select j.id, j.entry_date, l.credit amt
      from public.gl_journal j join public.gl_journal_lines l on l.journal_id = j.id
     where j.status = 'posted' and j.source = 'expense' and l.account_code = '1000' and l.credit > 0
       and not exists (select 1 from public.gl_journal o where o.source = 'owner_card_bank_value' and o.source_ref = j.source_ref and o.status = 'posted')
       and not exists (select 1 from public.gl_journal x where x.source = 'bank_reconciliation' and x.source_ref = j.id::text)
  loop
    perform public.fn_gl_entry(r.entry_date,
      'Bank reconciliation: journal ' || r.id || ' was paid on the founder''s personal card, not the Mashreq account; moved from Cash & Bank to Due to Owner',
      'bank_reconciliation', r.id::text,
      jsonb_build_array(jsonb_build_object('account','1000','debit',r.amt),
                        jsonb_build_object('account','2500','credit',r.amt)), 'accountant');
  end loop;

  -- B. void originals whose posted reversal is still counted
  for r in
    select j.id, j.entry_date from public.gl_journal j
     where j.status = 'void'
       and exists (select 1 from public.gl_journal v where v.id = j.reverses and v.status = 'posted')
       and not exists (select 1 from public.gl_journal x where x.source = 'bank_reconciliation' and x.source_ref = j.id::text)
  loop
    perform public.fn_gl_entry(r.entry_date,
      'Restatement of void journal ' || r.id || ': its reversal is posted but the original is void, so readers of posted journals counted the correction twice',
      'bank_reconciliation', r.id::text,
      (select jsonb_agg(jsonb_build_object('account', l.account_code, 'debit', l.debit, 'credit', l.credit) order by l.line_no)
         from public.gl_journal_lines l where l.journal_id = r.id), 'accountant');
  end loop;

  select coalesce(sum(l.debit - l.credit), 0) into v_bank
    from public.gl_journal_lines l join public.gl_journal j on j.id = l.journal_id
   where j.status = 'posted' and l.account_code = '1000';
  if v_bank <> 582.96 then
    raise exception 'bank reconciliation failed: ledger 1000 = %, statement 582.96', v_bank;
  end if;
end $$;

select case when (select sum(l.debit - l.credit) from public.gl_journal_lines l join public.gl_journal j on j.id = l.journal_id
                   where j.status = 'posted' and l.account_code = '1000') = 582.96
            then 'PROBE OK: ledger 1000 = 582.96' else 'PROBE FAILED: ledger 1000 <> 582.96' end as verdict;
