-- ============================================================================================
-- KERNEL K5b — THE CLOCK POINTS AT THE KERNEL
--
-- K5 built fn_kernel_outbox_deliver and K2 built fn_kernel_workflow_start. Neither of them is
-- reached by anything until this line changes:
--
--   cron.job 278 phase_c_outbox_deliver_1min
--     select public.fn_phase_c_outbox_deliver(25, 'cron:phase_c_outbox_deliver_1min');
--
-- The old worker's consumer is fn_phase_c_event_consume, which calls fn_phase_c_event_ingress,
-- which emits unconditionally — the self-emission the audit measured three times in production
-- (outbox 250, 251, 317). Leaving the cron pointed at it would have left the whole defect running
-- underneath a kernel that was merely present. A capability with no entry point is the shape this
-- estate has paid for more than once; this file is the entry point.
--
-- Same job id, same schedule, same name: the job's history stays continuous rather than starting
-- again under a new id.
-- ============================================================================================

select cron.alter_job(
  job_id  => 278,
  command => $cmd$select public.fn_kernel_outbox_deliver(25, 'cron:phase_c_outbox_deliver_1min');$cmd$
);
