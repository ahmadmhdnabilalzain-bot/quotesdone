-- OWNERSHIP LEDGER SYNC for reputation_tier_gates_every_decision.sql.
--
-- fn_decide and fn_decision_gate are now canonically defined by reputation_tier_gates_every_decision.sql,
-- superseding the_files_were_stale_not_the_database.sql and fn_decision_gate_authority_register.sql
-- respectively. Emitted by `node scripts/checks/application_source_of_truth.test.mjs --emit-ledger-sync`.
--
--   node scripts/apply_sql.mjs scripts/sql/reputation_tier_gates_every_decision_ownership_ledger.sql --apply --ddl

update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = 'scripts/sql/reputation_tier_gates_every_decision.sql',
       evidence = 'records source_file scripts/sql/the_files_were_stale_not_the_database.sql, manifest order says scripts/sql/reputation_tier_gates_every_decision.sql — reconciled mechanically 17 Aug 2026 (kernel_s0c).'
 where schema_name = 'public' and routine_name = 'fn_decide'
   and coalesce(identity_args,'') = 'p_kind text, p_ctx jsonb, p_actor text';

update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = 'scripts/sql/reputation_tier_gates_every_decision.sql',
       evidence = 'records source_file scripts/sql/fn_decision_gate_authority_register.sql, manifest order says scripts/sql/reputation_tier_gates_every_decision.sql — reconciled mechanically 17 Aug 2026 (kernel_s0c).'
 where schema_name = 'public' and routine_name = 'fn_decision_gate'
   and coalesce(identity_args,'') = '';
