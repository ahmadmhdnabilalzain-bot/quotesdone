-- OWNERSHIP LEDGER SYNC for agent_knows_its_own_kpis.sql.
--
-- fn_agent_context_v3 is now canonically defined by agent_knows_its_own_kpis.sql (the KPI-in-identity
-- splice), superseding v3_repair_05_ctx_v3_query.sql. Matches what
-- `node scripts/checks/application_source_of_truth.test.mjs --emit-ledger-sync` would emit; applied to
-- production via the Supabase MCP when the local access token had expired.
--
--   node scripts/apply_sql.mjs scripts/sql/agent_knows_its_own_kpis_ownership_ledger.sql --apply --ddl

update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = 'scripts/sql/agent_knows_its_own_kpis.sql',
       evidence = 'records source_file scripts/sql/v3_repair_05_ctx_v3_query.sql, manifest order says scripts/sql/agent_knows_its_own_kpis.sql — reconciled mechanically 17 Aug 2026 (kernel_s0c).'
 where schema_name = 'public' and routine_name = 'fn_agent_context_v3'
   and coalesce(identity_args,'') = 'p_agent_key text, p_task_class text, p_task_text text, p_category_key text, p_budget_chars integer';
