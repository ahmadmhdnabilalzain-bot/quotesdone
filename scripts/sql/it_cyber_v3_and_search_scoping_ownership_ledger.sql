-- OWNERSHIP LEDGER SYNC for it_cyber_v3_and_search_scoping.sql.
--
-- fn_agent_context_v3 and fn_company_knowledge_search are now canonically defined by
-- it_cyber_v3_and_search_scoping.sql (the Step 3 scoped delivery), superseding
-- every_agent_is_a_twenty_year_veteran.sql. Applied to production via the Supabase MCP; recorded here
-- for a clean deploy.
--
--   node scripts/apply_sql.mjs scripts/sql/it_cyber_v3_and_search_scoping_ownership_ledger.sql --apply --ddl

update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = 'scripts/sql/it_cyber_v3_and_search_scoping.sql',
       evidence = 'records source_file scripts/sql/every_agent_is_a_twenty_year_veteran.sql, manifest order says scripts/sql/it_cyber_v3_and_search_scoping.sql — reconciled mechanically 17 Aug 2026 (kernel_s0c).'
 where schema_name = 'public' and routine_name in ('fn_agent_context_v3','fn_company_knowledge_search');
