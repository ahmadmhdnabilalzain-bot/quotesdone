-- THE WHATSAPP FLUSH IS UNWRAPPED FROM THE KERNEL, NOT DELETED WITH IT.
--
-- The phase file refuses to run while any cron job still calls fn_kernel_cron_exec. Exactly one
-- does: jobid 34, `wa_flush`, `*/2 * * * *`, command `select public.fn_kernel_cron_exec(34);`.
--
-- THE EASY MOVE WOULD HAVE BEEN TO UNSCHEDULE IT, and it would have been wrong. wa_flush is not
-- kernel machinery — it is the customer-support agent's WhatsApp outbox flush, which POSTs to
-- send_whatsapp. The kernel only WRAPPED it: fn_kernel_cron_exec(34) looks up the real command in
-- phase_c_system_execution_wrapper and executes it. Deleting the job because its wrapper is being
-- deleted would quietly remove a support capability the founder is keeping, and it would look like
-- housekeeping rather than a loss.
--
-- So the original command is read back out of the wrapper row and written to the job directly. That
-- table currently holds ONE row; it held the real command for 131 jobs until the evening of 7
-- September, and those are already unrecoverable from it. This is the last one, recovered before the
-- table goes.
--
-- IT STAYS INACTIVE, deliberately. active = false today and this file does not change that. The
-- founder's hold on scheduled work stands, and switching a job back on is a spend decision (this one
-- reaches Twilio) rather than a refactor. Unwrapping is reversible and silent; activating is neither.
--
--   node scripts/apply_sql.mjs scripts/sql/the_whatsapp_flush_is_unwrapped_from_the_kernel.sql --apply --ddl

begin;

do $unwrap$
declare
  v_cmd text;
  v_active boolean;
begin
  select w.original_command into v_cmd
    from public.phase_c_system_execution_wrapper w
   where w.jobid = 34;

  if v_cmd is null or btrim(v_cmd) = '' then
    raise exception 'REFUSED: no original_command recorded for jobid 34; unwrapping would lose the job'
      using hint = 'Do not unschedule it blind — read cron.job and reconstruct the command first.';
  end if;

  select j.active into v_active from cron.job j where j.jobid = 34;

  -- Rewrite the command in place and preserve the schedule and the activation state exactly.
  perform cron.alter_job(job_id := 34, command := v_cmd, active := v_active);
end
$unwrap$;

-- ── THE ALERTER THAT READ THE KERNEL'S BOARDS ──────────────────────────────────────────────────
-- fn_red_view_alert is the other precondition blocker: it calls fn_kernel_all_boards and reads
-- v_cron_stale, which joins phase_c_system_execution_wrapper. It paged on a red board in the OS
-- dashboard — a dashboard that no longer exists, watching boards that are being removed. Its subject
-- is gone, so it goes with its subject rather than being pointed at something else.
-- Signature from pg_get_function_identity_arguments, not guessed: it takes p_boards boolean, and a
-- `drop function if exists` naming the wrong arguments matches nothing and still reports success.
drop function if exists public.fn_red_view_alert(p_boards boolean);

commit;
