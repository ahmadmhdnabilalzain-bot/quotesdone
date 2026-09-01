-- OWNERSHIP LEDGER SYNC for every_agent_is_a_twenty_year_veteran.sql.
--
-- fn_agent_context_v3 is now canonically defined by every_agent_is_a_twenty_year_veteran.sql (the
-- whole-company recall fold), superseding agent_knows_its_own_kpis.sql. Applied to production via the
-- Supabase MCP; recorded here for a clean deploy.
--
--   node scripts/apply_sql.mjs scripts/sql/every_agent_is_a_twenty_year_veteran_ownership_ledger.sql --apply --ddl

update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = 'scripts/sql/every_agent_is_a_twenty_year_veteran.sql',
       evidence = 'records source_file scripts/sql/agent_knows_its_own_kpis.sql, manifest order says scripts/sql/every_agent_is_a_twenty_year_veteran.sql — reconciled mechanically 17 Aug 2026 (kernel_s0c).'
 where schema_name = 'public' and routine_name = 'fn_agent_context_v3'
   and coalesce(identity_args,'') = 'p_agent_key text, p_task_class text, p_task_text text, p_category_key text, p_budget_chars integer';
