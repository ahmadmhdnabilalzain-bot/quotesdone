-- Rollback for K35. Restores EXECUTE on every retired Phase C path to service_role — that is, to
-- the role every Edge Function holds. It reopens fn_phase_c_outbox_settle, fn_phase_c_task_create,
-- fn_phase_c_workflow_start and five others to any function with the service key.
--
-- Measured before the revoke: zero database routines call any of them beyond the internal kernel
-- callers, and grepping supabase/functions and src for all eight names returns nothing. Nothing
-- needed the grant then, and restoring it grants something nothing asked for.
begin;
do $r$
declare r record;
begin
  for r in select path_name from public.kernel_retired_path loop
    execute format('grant execute on function public.%I to service_role', r.path_name);
  end loop;
end $r$;
commit;
