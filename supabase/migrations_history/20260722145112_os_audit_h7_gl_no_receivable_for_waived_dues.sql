-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260722145112   name: os_audit_h7_gl_no_receivable_for_waived_dues
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- H7 (OS audit): fn_gl_sync_business block 2 books a clawback receivable (debit 1110) for ANY due with
-- amount_due>0, with no status filter, so waived/cancelled dues create phantom receivables that never clear
-- (block 2b only settles paid/settled). Add a status filter to block 2's WHERE, patched server-side to avoid
-- reproducing the whole function. The guard aborts (rolls back) if the anchor isn't found.
DO $mig$
DECLARE def text; newdef text;
BEGIN
  SELECT pg_get_functiondef(oid) INTO def
    FROM pg_proc WHERE proname='fn_gl_sync_business' AND pronamespace='public'::regnamespace LIMIT 1;
  newdef := regexp_replace(def,
    '(where coalesce\(amount_due,0\) > 0)(\s+and not exists \(select 1 from public\.gl_journal g where g\.source=''commission_accrue'')',
    E'\\1\n      and coalesce(status,'''') not in (''waived'',''cancelled'',''reversed'')\\2');
  IF newdef = def OR newdef NOT LIKE '%not in (''waived'',''cancelled'',''reversed'')%' THEN
    RAISE EXCEPTION 'H7: block-2 WHERE anchor not matched — aborting with no change';
  END IF;
  EXECUTE newdef;
END
$mig$;
