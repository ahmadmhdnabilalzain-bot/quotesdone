-- The ownership ledger (kernel_routine_ownership) records, per routine, which file is its canonical
-- source. Lifting the phase freezes and wiring the loop redefined four routines in new scripts/sql
-- files, so the ledger's source_file rows went stale — application_source_of_truth.test.mjs names each
-- under "ledger claims the repository denies". The ledger must follow the MANIFEST order or it becomes
-- a second opinion about what the canonical source is. Values below are the check's own output.
--
--   node scripts/apply_sql.mjs scripts/sql/ledger_follows_the_manifest_freeze_lift.sql --apply --ddl

begin;

update public.kernel_routine_ownership
   set source_file = 'scripts/sql/raise_operational_limits.sql', source_kind = 'MANIFEST'
 where schema_name = 'public' and routine_name = 'fn_event_dispatch'
   and coalesce(identity_args,'') = 'p_lookback_minutes integer';

-- Reclassified: recorded HISTORICAL_APPLICATION when only a migrations_history file defined it;
-- lift_all_phase_freezes.sql brought it into the apply order, so the repository now derives
-- QUOTESDONE_APPLICATION and the ledger has to agree.
update public.kernel_routine_ownership
   set source_file = 'scripts/sql/lift_all_phase_freezes.sql', source_kind = 'MANIFEST',
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       evidence = 'lift_all_phase_freezes.sql redefines it to honor the phase_freezes_lifted switch; '
               || 'brought into the apply order 2 Sep 2026.'
 where schema_name = 'public' and routine_name = 'fn_phase_a_freeze_guard'
   and coalesce(identity_args,'') = '';

update public.kernel_routine_ownership
   set source_file = 'scripts/sql/lift_all_phase_freezes.sql', source_kind = 'MANIFEST'
 where schema_name = 'public' and routine_name = 'fn_phase_b_freeze_guard'
   and coalesce(identity_args,'') = '';

update public.kernel_routine_ownership
   set source_file = 'scripts/sql/director_placeholder_always_resolves.sql', source_kind = 'MANIFEST'
 where schema_name = 'public' and routine_name = 'fn_workflow_actor_resolve'
   and coalesce(identity_args,'') = 'p_run uuid, p_actor text';

commit;
