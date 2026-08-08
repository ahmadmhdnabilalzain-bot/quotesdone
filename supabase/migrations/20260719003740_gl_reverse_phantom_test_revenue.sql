-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260719003740   name: gl_reverse_phantom_test_revenue
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- Reverse phantom revenue left in the ledger by deleted QA test transactions.
--
-- THE PROBLEM (found 19 Jul 2026):
-- gl_journal carried 13 'reveal_fee' entries (AED 3,514.50) and 1 'commission_accrue' entry
-- (AED 200.00) = AED 3,714.50 of revenue. The transactions and supplier_dues rows that produced
-- them no longer exist - transactions, customers, inquiries and supplier_dues are all empty. The
-- founder confirms the business has had NO revenue to date; everything to date is expenses only.
--
-- Cause: those entries were posted 8-16 Jul from QA test transactions, which a later test-data
-- cleanup deleted WITHOUT reversing the journal entries they had generated. The ledger kept the
-- revenue side of data that no longer exists. (Verified this was not caused by the 19 Jul auth
-- account cleanup: public.customers has no foreign key to auth.users, and transactions.customer_id
-- is NO ACTION, so deleting auth users cannot cascade into either table.)
--
-- Impact: the books overstated revenue by AED 3,714.50 and reported a profit where there is a
-- loss. Combined with the USD expense understatement fixed in the previous migration, the P&L was
-- wrong in both directions at once.
--
-- METHOD: post a balanced REVERSING entry against each phantom journal, linked via
-- gl_journal.reverses, rather than deleting rows. Both the original and its reversal stay visible.
-- Idempotent: an entry that already has a reversal is skipped. fn_gl_sync_business cannot re-post
-- these because it only iterates rows that exist in transactions / supplier_dues, and both are empty.

do $$
declare j record; ln jsonb; jid bigint; n int := 0;
begin
  for j in
    select g.id, g.entry_date, g.source, g.source_ref
    from public.gl_journal g
    where g.source in ('reveal_fee','commission_accrue')
      and not exists (select 1 from public.gl_journal r where r.reverses = g.id)
    order by g.id
  loop
    -- Swap debit and credit on every line to build the exact reversal.
    select jsonb_agg(jsonb_build_object(
             'account', l.account_code,
             'debit',   l.credit,
             'credit',  l.debit,
             'memo',    'reversal of line '||l.line_no)
           order by l.line_no)
      into ln
    from public.gl_journal_lines l
    where l.journal_id = j.id;

    if ln is null then continue; end if;

    jid := public.fn_gl_entry(
      j.entry_date,
      'REVERSAL of journal #'||j.id||' ('||j.source||'): source record no longer exists - QA test data deleted without reversing its ledger entries. The business has had no revenue to date.',
      'revenue_reversal',
      j.source_ref,
      ln,
      'gl_phantom_revenue_fix');

    update public.gl_journal set reverses = j.id where id = jid;
    n := n + 1;
  end loop;

  raise notice 'reversed % phantom revenue entries', n;
end $$;
