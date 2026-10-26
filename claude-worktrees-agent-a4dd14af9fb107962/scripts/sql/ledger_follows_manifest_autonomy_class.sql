-- fn_autonomy_class was defined only in ai-organization/db-functions (HISTORICAL_APPLICATION);
-- scripts/sql/refund_within_window_reaches_the_founder.sql brought it into the apply order (the APV-01
-- money-safety fix), so the repository now derives QUOTESDONE_APPLICATION and the ownership ledger has
-- to follow the manifest.
--
--   node scripts/apply_sql.mjs scripts/sql/ledger_follows_manifest_autonomy_class.sql --apply --ddl

begin;

update public.kernel_routine_ownership
   set source_file = 'scripts/sql/refund_within_window_reaches_the_founder.sql', source_kind = 'MANIFEST',
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       evidence = 'refund_within_window_reaches_the_founder.sql redefines it (APV-01: every refund reaches '
               || 'the founder); brought into the apply order 2 Sep 2026.'
 where schema_name = 'public' and routine_name = 'fn_autonomy_class'
   and coalesce(identity_args,'') = 'p_kind text, p_target_table text, p_recommendation text';

commit;
