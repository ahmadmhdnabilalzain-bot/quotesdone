-- Schedule the deterministic supplier-suspension signal (CHAIN-02) as a daily traced cron, so the
-- expired-licence check runs autonomously like a real Trust & Safety function. fn_kernel_wrap_and_enable_cron
-- wraps it (command -> fn_kernel_cron_exec) so active_state_changing_cron_components_not_wrapped stays 0,
-- and it is registered in the committed-scenario cron registry. Daily 02:30 UTC, idempotent per lead,
-- 0 suppliers qualify today.
--
--   node scripts/apply_sql.mjs scripts/sql/schedule_supplier_suspension_emitter.sql --apply --ddl

begin;

do $$
declare v_job bigint;
begin
  -- cron.schedule upserts on the job name, so this is idempotent.
  v_job := cron.schedule('supplier_suspension_proposed_daily', '30 2 * * *',
                         'select public.fn_emit_supplier_suspension_proposed(0);');
  perform public.fn_kernel_wrap_and_enable_cron(v_job, 'trust_and_safety_manager', 'legal');
  insert into public.phase_d_committed_scenario_cron (jobid, jobname, reaches, quarantine)
  values (v_job, 'supplier_suspension_proposed_daily',
          'INSERTs public.company_event (supplier.suspension_proposed) for approved suppliers whose trade licence has expired; reads public.leads.',
          'Daily 02:30 UTC, outside any scenario window this session opens; idempotent per lead/licence-expiry episode; writes only company_event rows about real approved suppliers (approval_status=''approved''), never a ZZ DEMO scenario fixture; runs in its own transaction and close() asserts scenario rows are gone by id/marker, so it does not move the watermark.')
  on conflict (jobid) do update set jobname = excluded.jobname, reaches = excluded.reaches, quarantine = excluded.quarantine;
end $$;

commit;
