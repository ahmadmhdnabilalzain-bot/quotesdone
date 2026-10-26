-- Rehearses supabase/rollback/phase1_containment_down.sql inside a transaction that is
-- deliberately aborted by a final RAISE. Nothing is restored; containment stays in force.
-- Run:  node scripts/qsql.mjs scripts/sql/containment_rollback_rehearse.sql
-- A successful rehearsal ends with an ERROR whose message begins ROLLBACK_REHEARSAL OK.
--
-- Result recorded 2026-08-02:
--   ROLLBACK_REHEARSAL OK -> triggers_remaining=0 storage_policies_restored=2
--   cron_jobs_reactivated=18/18 agent_autonomy_enabled=true cos_frozen=false
--   (transaction aborted, containment still in force)

do $REHEARSE$
declare r record; v_left int; v_pol int; v_cron int; v_sec text;
begin
  drop trigger if exists zz_containment_customer_registration on public.customers;
  drop trigger if exists zz_containment_supplier_registration on public.leads;
  drop trigger if exists zz_containment_sensitive_upload      on storage.objects;
  drop function if exists public.trg_containment_block_customer_registration();
  drop function if exists public.trg_containment_block_supplier_registration();
  drop function if exists public.trg_containment_block_sensitive_upload();
  drop function if exists public.fn_containment_maintenance();
  update public.app_secrets set value='false' where key='containment_maintenance';

  for r in select * from containment.policy_removed where restored_at is null loop
    execute r.rollback_sql;
    update containment.policy_removed set restored_at = now() where id = r.id;
  end loop;

  for r in select * from containment.cron_disabled where restored_at is null loop
    perform cron.alter_job(r.jobid, active := r.was_active);
    update containment.cron_disabled set restored_at = now() where jobid = r.jobid;
  end loop;

  for r in select * from containment.change_log
            where area='A_autonomy' and change like 'app_secrets.%' and rollback_sql not like '-- no change%' loop
    execute r.rollback_sql;
  end loop;

  select count(*) into v_left from pg_trigger t join pg_class c on c.oid=t.tgrelid
   where t.tgname in ('zz_containment_customer_registration','zz_containment_supplier_registration','zz_containment_sensitive_upload')
     and not t.tgisinternal;
  select count(*) into v_pol  from pg_policies where schemaname='storage';
  select count(*) into v_cron from cron.job j join containment.cron_disabled d using (jobid) where j.active;
  select value into v_sec from public.app_secrets where key='agent_autonomy_enabled';

  raise exception 'ROLLBACK_REHEARSAL OK -> triggers_remaining=% storage_policies_restored=% cron_jobs_reactivated=%/18 agent_autonomy_enabled=% cos_frozen=% (transaction aborted, containment still in force)',
    v_left, v_pol, v_cron, v_sec, (select value from public.app_secrets where key='cos_frozen');
end
$REHEARSE$;
