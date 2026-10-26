-- OWNERSHIP LEDGER SYNC for decay_opens_a_task_for_its_own_quarantine_only.sql.
--
-- fn_knowledge_decay lived only in migrations history (HISTORICAL_APPLICATION) until this morning's
-- file gave it a canonical scripts/sql definition; the ledger row is moved to the class the
-- repository now derives. Statement emitted by
-- `node scripts/checks/application_source_of_truth.test.mjs --emit-ledger-sync` (line 6 of that gate).
--
--   node scripts/apply_sql.mjs scripts/sql/decay_opens_a_task_for_its_own_quarantine_only_ownership_ledger.sql --apply --ddl

update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = 'scripts/sql/decay_opens_a_task_for_its_own_quarantine_only.sql',
       evidence = 'recorded HISTORICAL_APPLICATION, repository derives QUOTESDONE_APPLICATION — reconciled 6 Sep 2026 after decay_opens_a_task_for_its_own_quarantine_only.sql gave the routine a canonical file.'
 where schema_name = 'public' and routine_name = 'fn_knowledge_decay'
   and coalesce(identity_args,'') = '';
