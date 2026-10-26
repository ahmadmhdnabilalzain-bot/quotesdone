-- =====================================================================================
-- Phase 1 emergency containment — ROLLBACK
-- Branch: hotfix/phase1-emergency-containment (from 658e675)
-- Reverses every change made by p1c_01 .. p1c_05 and the two edge-function deploys.
--
-- Every value restored below was recorded in the `containment` schema BEFORE the change
-- was made. Nothing here is typed from memory.
--
-- Run order: this file first (database), then the two edge-function steps at the bottom.
-- Idempotent: safe to re-run. Verifies its own result and raises if anything is left behind.
--
-- REHEARSE FIRST:  psql -f phase1_containment_down.sql  is NOT how you rehearse.
--   Use scripts/sql/containment_rollback_rehearse.sql, which runs this same logic inside a
--   transaction that is deliberately aborted.
-- =====================================================================================

do $ROLLBACK$
declare
  r record;
  v_left int;
begin
  ---------------------------------------------------------------- D. maintenance mode
  drop trigger if exists zz_containment_customer_registration on public.customers;
  drop trigger if exists zz_containment_supplier_registration on public.leads;
  drop trigger if exists zz_containment_sensitive_upload      on storage.objects;

  drop function if exists public.trg_containment_block_customer_registration();
  drop function if exists public.trg_containment_block_supplier_registration();
  drop function if exists public.trg_containment_block_sensitive_upload();
  drop function if exists public.fn_containment_maintenance();

  update public.app_secrets set value = 'false' where key = 'containment_maintenance';

  ---------------------------------------------------------------- B. supplier-docs policies
  for r in select * from containment.policy_removed where restored_at is null loop
    execute r.rollback_sql;
    update containment.policy_removed set restored_at = now() where id = r.id;
  end loop;

  ---------------------------------------------------------------- A. cron jobs
  for r in select * from containment.cron_disabled where restored_at is null loop
    perform cron.alter_job(r.jobid, active := r.was_active);
    update containment.cron_disabled set restored_at = now() where jobid = r.jobid;
  end loop;

  ---------------------------------------------------------------- A. autonomy secrets
  for r in select * from containment.change_log
            where area = 'A_autonomy' and change like 'app_secrets.%'
              and rollback_sql not like '-- no change%' loop
    execute r.rollback_sql;
  end loop;

  ---------------------------------------------------------------- self-verification
  select count(*) into v_left from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
   where t.tgname in ('zz_containment_customer_registration',
                      'zz_containment_supplier_registration',
                      'zz_containment_sensitive_upload')
     and not t.tgisinternal;
  if v_left <> 0 then raise exception 'ROLLBACK INCOMPLETE: % containment trigger(s) remain', v_left; end if;

  select count(*) into v_left from containment.cron_disabled where restored_at is null;
  if v_left <> 0 then raise exception 'ROLLBACK INCOMPLETE: % cron job(s) not restored', v_left; end if;

  select count(*) into v_left from containment.policy_removed where restored_at is null;
  if v_left <> 0 then raise exception 'ROLLBACK INCOMPLETE: % storage policy/policies not restored', v_left; end if;

  select count(*) into v_left from cron.job j
    join containment.cron_disabled d using (jobid) where j.active <> d.was_active;
  if v_left <> 0 then raise exception 'ROLLBACK INCOMPLETE: % cron job(s) do not match their recorded state', v_left; end if;

  insert into containment.change_log (area, change, before_value, after_value, rollback_sql)
  values ('ROLLBACK', 'phase1_containment_down.sql executed', 'contained', 'restored to pre-containment state',
          '-- re-apply p1c_01..p1c_05 to contain again');

  raise notice 'CONTAINMENT ROLLBACK COMPLETE: triggers dropped, % policies restored, % cron jobs restored, autonomy secrets restored.',
    (select count(*) from containment.policy_removed),
    (select count(*) from containment.cron_disabled);
end
$ROLLBACK$;

-- =====================================================================================
-- EDGE FUNCTIONS — not reversible in SQL. Two steps, from the repository:
--
--   git checkout 658e675 -- supabase/functions/os_ops/index.ts supabase/functions/refunds_api/index.ts
--   supabase functions deploy os_ops      --project-ref htdblwldjkcgjvmqkbeh --use-api
--   supabase functions deploy refunds_api --project-ref htdblwldjkcgjvmqkbeh --use-api --no-verify-jwt
--
-- The --no-verify-jwt flag on refunds_api is REQUIRED: it was verify_jwt=false before containment
-- and must stay that way. os_ops is verify_jwt=true and takes the default.
--
-- Pre-containment versions, for confirmation: os_ops v13, refunds_api v6.
-- =====================================================================================

-- Optional final step, only once containment is no longer wanted at all:
--   drop schema containment cascade;
-- Keeping it costs nothing and preserves the record of what was contained and why.
