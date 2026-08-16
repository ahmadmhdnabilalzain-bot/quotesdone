-- ============================================================================================
-- KERNEL S0b — THE OWNERSHIP LEDGER FOLLOWS THE MANIFEST
--
-- S0's ledger records, per routine, which file is its canonical source. Seven of those rows went
-- stale the moment K3, K13 and K3c redefined routines that earlier kernel files had defined: the
-- ledger still named kernel_k5, kernel_k6, kernel_k13a, phase_c_31, phase_c_32 and phase_c_39.
--
-- application_source_of_truth.test.mjs caught every one by name under "ledger claims the repository
-- denies", which is the check earning its place. A ledger that drifts from the manifest is a SECOND
-- OPINION about what the canonical source is, and a second opinion is the exact shape this rebuild
-- exists to remove — it is how fn_phase_c_event_ingress ran an unfixed body for a day under a green
-- instrument.
--
-- The values below are the check's own output: the file MANIFEST order resolves each routine to,
-- today. Re-running the check after this file is what proves it, not this comment.
-- ============================================================================================

update public.kernel_routine_ownership set source_file = 'scripts/sql/kernel_k3_step_engine.sql', source_kind = 'MANIFEST'
 where schema_name = 'public' and routine_name = 'fn_kernel_event_consume'
   and coalesce(identity_args,'') = 'p_outbox_id bigint';

-- Also reclassified: it was recorded HISTORICAL_APPLICATION when only a non-manifest file defined
-- it. K3 brought it into the apply order, so the repository now derives QUOTESDONE_APPLICATION and
-- the ledger has to agree or the guard is measuring the wrong subject.
update public.kernel_routine_ownership
   set source_file = 'scripts/sql/kernel_s3_system_execution_traces.sql',
       source_kind = 'MANIFEST',
       ownership_class = 'QUOTESDONE_APPLICATION',
       classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       evidence = 'kernel_k3 and kernel_s3 both redefine it; kernel_s3 is later in MANIFEST order '
               || 'and is therefore canonical. Brought into the apply order 17 Aug 2026.'
 where schema_name = 'public' and routine_name = 'fn_kernel_trace_integrity'
   and coalesce(identity_args,'') = '';

update public.kernel_routine_ownership set source_file = 'scripts/sql/kernel_k3_step_engine.sql', source_kind = 'MANIFEST'
 where schema_name = 'public' and routine_name = 'fn_phase_c_task_trace_guard'
   and coalesce(identity_args,'') = '';

update public.kernel_routine_ownership set source_file = 'scripts/sql/kernel_k13_retire_old_runtime.sql', source_kind = 'MANIFEST'
 where schema_name = 'public' and routine_name = 'fn_phase_c_event_consume'
   and coalesce(identity_args,'') = 'p_outbox_id bigint';

update public.kernel_routine_ownership set source_file = 'scripts/sql/kernel_k13_retire_old_runtime.sql', source_kind = 'MANIFEST'
 where schema_name = 'public' and routine_name = 'fn_phase_c_event_ingress'
   and coalesce(identity_args,'') = 'p_event_id text, p_business_object_id text, p_ctx jsonb';

update public.kernel_routine_ownership set source_file = 'scripts/sql/kernel_k13_retire_old_runtime.sql', source_kind = 'MANIFEST'
 where schema_name = 'public' and routine_name = 'fn_phase_c_outbox_deliver'
   and coalesce(identity_args,'') = 'p_limit integer, p_worker text';

update public.kernel_routine_ownership set source_file = 'scripts/sql/kernel_k13_retire_old_runtime.sql', source_kind = 'MANIFEST'
 where schema_name = 'public' and routine_name = 'fn_phase_c_step_advance'
   and coalesce(identity_args,'') = 'p_run_id bigint, p_step_id text, p_actor text, p_body jsonb';
