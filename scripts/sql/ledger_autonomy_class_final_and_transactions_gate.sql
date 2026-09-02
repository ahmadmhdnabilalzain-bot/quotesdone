-- Ledger follows the manifest: fn_autonomy_class's canonical file is now the latest one that redefines
-- it (approval_chain_close_the_wiring_gaps.sql, the APV-04 executive-gate routing).
begin;
update public.kernel_routine_ownership
   set source_file = 'scripts/sql/approval_chain_close_the_wiring_gaps.sql', source_kind = 'MANIFEST'
 where schema_name = 'public' and routine_name = 'fn_autonomy_class'
   and coalesce(identity_args,'') = 'p_kind text, p_target_table text, p_recommendation text';
commit;
