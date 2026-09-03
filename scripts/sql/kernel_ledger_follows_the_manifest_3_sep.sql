-- THE OWNERSHIP LEDGER FOLLOWS THE MANIFEST (3 Sep 2026).
--
-- public.kernel_routine_ownership records, per live routine, the file the repository holds as its
-- source. application_source_of_truth (line 6) found seven rows that disagreed with the repository
-- after this session's work: three routines whose canonical file moved (a later manifest file now
-- defines fn_action_invoke_collect, fn_supersede_lesson and fn_undo), and four rows for routines this
-- session retired (scripts/sql/retire_orphaned_phase_governance_routines.sql, recorded in DROPPED.txt)
-- that no longer exist. The three UPDATEs are the statements the check itself emits
-- (--emit-ledger-sync), so the repair is generated from the derivation that found the drift; the four
-- DELETEs remove rows about routines that are gone — a ledger of live ownership has nothing to say
-- about a routine that was measured unused and dropped.

update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = 'scripts/sql/held_executors_are_parked_not_dead_lettered.sql',
       evidence = 'records source_file scripts/sql/the_biggest_producer_spoke_a_word_the_extractor_did_not_know.sql, manifest order says scripts/sql/held_executors_are_parked_not_dead_lettered.sql — reconciled mechanically 3 Sep 2026 (application_source_of_truth --emit-ledger-sync).'
 where schema_name = 'public' and routine_name = 'fn_action_invoke_collect'
   and coalesce(identity_args,'') = '';

update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = 'scripts/sql/fn_supersede_lesson_keeps_the_chain.sql',
       evidence = 'records source_file scripts/sql/v3_learning_and_remediation.sql, manifest order says scripts/sql/fn_supersede_lesson_keeps_the_chain.sql — reconciled mechanically 3 Sep 2026 (application_source_of_truth --emit-ledger-sync).'
 where schema_name = 'public' and routine_name = 'fn_supersede_lesson'
   and coalesce(identity_args,'') = 'p_old bigint, p_new bigint, p_reason text';

update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST', source_file = 'scripts/sql/fn_undo_uses_the_real_primary_key.sql',
       evidence = 'recorded HISTORICAL_APPLICATION, repository derives QUOTESDONE_APPLICATION — reconciled mechanically 3 Sep 2026 (application_source_of_truth --emit-ledger-sync).'
 where schema_name = 'public' and routine_name = 'fn_undo'
   and coalesce(identity_args,'') = 'p_undo_id uuid, p_reason text';

delete from public.kernel_routine_ownership
 where schema_name = 'public'
   and routine_name in ('fn_phase_a_freeze_guard', 'fn_phase_b_freeze_guard', 'fn_phase_b_step_transition_allowed', 'fn_phase_c_trace_coverage')
   and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = kernel_routine_ownership.schema_name and p.proname = kernel_routine_ownership.routine_name);

do $ctl$
begin
  if exists (select 1 from public.kernel_routine_ownership where schema_name = 'public' and routine_name in ('fn_phase_a_freeze_guard', 'fn_phase_b_freeze_guard', 'fn_phase_b_step_transition_allowed', 'fn_phase_c_trace_coverage')) then
    raise exception 'a ledger row for a retired routine survived';
  end if;
end $ctl$;
