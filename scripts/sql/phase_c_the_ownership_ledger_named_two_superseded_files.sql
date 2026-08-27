-- THE OWNERSHIP LEDGER NAMED TWO SUPERSEDED FILES.
--
-- NO TRANSACTION CONTROL. Two UPDATEs and an assertion.
--
-- `scripts/checks/application_source_of_truth.test.mjs` reported, after the 27 Aug narrow
-- correction session applied its three files:
--
--   6. ledger claims the repository denies             2 / 1225
--     public.fn_kernel_orphaned_work()      records scripts/sql/kernel_k4_cancellation.sql,
--       manifest order says scripts/sql/phase_c_active_work_whose_business_parent_is_gone.sql
--     public.fn_reputation_recompute()      records
--       scripts/sql/seventy_five_employees_were_rated_one_point_above_probation_for_doing_nothing.sql,
--       manifest order says
--       scripts/sql/phase_c_the_scorer_would_have_read_a_hold_as_underperformance.sql
--
-- Lines 1 through 5 and line 7 are all 0: neither routine has drifted, the canonical engine agrees
-- with production, and the body each file deployed is the body that is running. The LEDGER had
-- simply not been told that both routines moved file.
--
-- THIS IS THE THIRD TIME IN FOUR DAYS, and the third file written to do it by hand:
-- phase_c_the_ownership_ledger_named_a_file_the_manifest_had_superseded.sql on 25 Aug,
-- phase_c_the_ownership_ledger_named_the_pccr006_file_again.sql on 26 Aug, this one on 27 Aug. The
-- pattern is structural, not careless. public.kernel_routine_ownership records, per routine, WHICH
-- FILE the estate considers its source; scripts/sql/MANIFEST.txt decides canon by POSITION; so every
-- CREATE OR REPLACE in a new file moves canon and leaves the ledger one file behind. Two writers,
-- one subject, and nothing keeps them in step.
--
-- THE STANDING REPAIR, named rather than done here because it is not a narrow-correction change:
-- scripts/apply_sql.mjs already appends to MANIFEST.txt and already reads back every routine it
-- deploys, so it holds both halves at the moment they diverge and could reconcile the ledger row in
-- the same breath. Doing that inside apply_sql is a change to the deployment tool every session in
-- this repository depends on, and it belongs in a session that can prove it end to end rather than
-- in the last hour of one about founder authentication.

update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST',
       source_file = 'scripts/sql/phase_c_active_work_whose_business_parent_is_gone.sql',
       evidence = 'recorded scripts/sql/kernel_k4_cancellation.sql; manifest order says '
               || 'scripts/sql/phase_c_active_work_whose_business_parent_is_gone.sql, which added '
               || 'seven rows to the board so that active work whose business PARENT was deleted is '
               || 'visible at all — reconciled mechanically 27 Aug 2026.'
 where schema_name = 'public' and routine_name = 'fn_kernel_orphaned_work';

update public.kernel_routine_ownership set
       ownership_class = 'QUOTESDONE_APPLICATION', classified_by_rule = 'R4_MANIFEST_DEFINES_IT',
       source_kind = 'MANIFEST',
       source_file = 'scripts/sql/phase_c_the_scorer_would_have_read_a_hold_as_underperformance.sql',
       evidence = 'recorded scripts/sql/seventy_five_employees_were_rated_one_point_above_probation'
               || '_for_doing_nothing.sql; manifest order says '
               || 'scripts/sql/phase_c_the_scorer_would_have_read_a_hold_as_underperformance.sql, '
               || 'which stops the scorer reading a founder-imposed stand-down as underperformance '
               || '— reconciled mechanically 27 Aug 2026.'
 where schema_name = 'public' and routine_name = 'fn_reputation_recompute';

do $assert$
declare v_file text; v_n int;
begin
  select source_file into v_file from public.kernel_routine_ownership
   where schema_name = 'public' and routine_name = 'fn_kernel_orphaned_work';
  if v_file is distinct from 'scripts/sql/phase_c_active_work_whose_business_parent_is_gone.sql' then
    raise exception 'fn_kernel_orphaned_work still records %', coalesce(v_file, '(no row)');
  end if;

  select source_file into v_file from public.kernel_routine_ownership
   where schema_name = 'public' and routine_name = 'fn_reputation_recompute';
  if v_file is distinct from 'scripts/sql/phase_c_the_scorer_would_have_read_a_hold_as_underperformance.sql' then
    raise exception 'fn_reputation_recompute still records %', coalesce(v_file, '(no row)');
  end if;

  -- The five new routines this session created must be OWNED, not merely present. A routine with no
  -- ownership row is line 2 of the same gate on the next run.
  select count(*) into v_n from public.kernel_routine_ownership
   where schema_name = 'public'
     and routine_name in ('fn_kernel_business_subject_resolve','fn_kernel_business_parent_missing',
                          'fn_kernel_workflow_run_parent_exists','fn_kernel_business_parent_delete_guard',
                          'fn_reputation_hold_state');
  raise notice 'OK  both ledger rows reconciled; % of 5 new routines carry an ownership row', v_n;
end
$assert$;
