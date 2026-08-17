-- ============================================================================================
-- ROLLBACK — KERNEL S3 (system-execution trace coverage)
--
-- WHAT COMES OUT, IN THIS ORDER
--   1. Every wrapped cron job gets its ORIGINAL command back, verbatim, from
--      phase_c_system_execution_wrapper. This is the only behaviour S3 changed, and restoring it
--      is exact: the wrapper stored the command text as it stood, it never edited it, and the
--      not-self CHECK guarantees no stored original is itself a wrapper call.
--   2. The 23 exempted components go back to TRACE-SYSTEM-EXECUTION. The move is reversed while
--      a00_phase_c_readonly_exemption_guard is still installed, which is deliberate: the guard has
--      no opinion about a move TOWARDS TRACE-SYSTEM-EXECUTION, and proving that on the way out is
--      cheaper than discovering it later.
--   3. The writer, the wrapper, the guard, the state function and the exemption table.
--
-- WHAT STAYS, AND WHY — READ THIS BEFORE ASKING FOR A FULLER REVERT
--
--   a. Any phase_c_trace rows written under TRACE-SYSTEM-EXECUTION STAY, and so do their
--      phase_c_system_execution records. Each one is the record of a scheduled execution that
--      really happened, with the instants it happened between. Deleting them would not undo the
--      executions; it would only delete the evidence, and that is the one thing this increment
--      exists to stop.
--
--   b. public.phase_c_system_execution and its append-only trigger STAY, because (a) stays.
--
--   c. public.phase_c_kernel_epoch STAYS. It is a recorded instant, not a switch. If S3 is applied
--      again the epoch must be the SAME instant, otherwise executions that were new become
--      historical by nothing more than a re-apply.
--
--   d. fn_kernel_trace_integrity STAYS as S3 left it — with the 'system_execution' subject_kind
--      branch and orphan_traces_system_execution. Reverting it to K6's body while any
--      system-execution trace exists would push those traces into the else-branch and turn
--      traces_with_unmapped_subject_kind red for traces the function simply has not been told
--      about. The added branch is correct whether or not S3 is installed.
--
-- Apply AFTER any later increment that calls fn_kernel_system_execution_trace has been rolled
-- back. Nothing in the estate called it before S3.
-- ============================================================================================

begin;

-- ---- 1. give every wrapped cron job its own command back -----------------------------------
do $s3_unwrap$
declare r record;
begin
  for r in select jobid, original_command from public.phase_c_system_execution_wrapper order by jobid
  loop
    perform cron.alter_job(r.jobid, command => r.original_command);
  end loop;
end
$s3_unwrap$;

-- ---- 2. put the 23 exempted components back on TRACE-SYSTEM-EXECUTION -----------------------
update public.phase_c_component c
   set trace_policy_id = 'TRACE-SYSTEM-EXECUTION',
       measured_at     = now()
  from public.phase_c_component_trace_exemption e
 where e.component_id = c.component_id
   and c.trace_policy_id = e.exempt_to_policy;

-- ---- 3. the guard, the writer, the wrapper, the state function, the exemption record ---------
drop trigger  if exists a00_phase_c_readonly_exemption_guard on public.phase_c_component;
drop function if exists public.fn_phase_c_readonly_exemption_guard();
drop function if exists public.fn_kernel_system_trace_state();
drop function if exists public.fn_kernel_cron_exec(bigint);
drop function if exists public.fn_kernel_system_execution_trace(jsonb);
drop table    if exists public.phase_c_system_execution_wrapper;
drop table    if exists public.phase_c_component_trace_exemption;

commit;

-- ============================================================================================
-- AFTER APPLYING, CHECK — these are the numbers that say the rollback landed:
--
--   select count(*) from cron.job where active and command ~ 'fn_kernel_cron_exec';   -- 0
--   select count(*) from public.phase_c_component
--    where trace_policy_id = 'TRACE-SYSTEM-EXECUTION';                                -- 656
--   select count(*) from public.phase_c_component
--    where trace_policy_id in ('TRACE-MONITORING','TRACE-INFRASTRUCTURE');            -- 0
--   select count(*) from public.phase_c_trace
--    where trace_policy_id = 'TRACE-SYSTEM-EXECUTION';        -- whatever was written; NOT zero,
--                                                             -- and deliberately not deleted
-- ============================================================================================
