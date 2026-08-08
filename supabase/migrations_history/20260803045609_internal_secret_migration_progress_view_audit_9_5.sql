-- AUDIT 9.5. How far the withdrawal has actually got.
--
-- This exists because counting by grep already produced one wrong answer today, and produced the
-- wrong answer in WI-001 too. Immediately after moving the first cron across, a naive
-- `command ilike '%inbound_secret%'` still reported 43 - because the new command carries a COMMENT
-- explaining what it was moved off. WI-001 made the same class of error at larger scale, reporting
-- "146 cron jobs (141 active)" by counting every cron rather than the ones passing the secret, and
-- sized its risk estimate off a number 3.4x too big.
--
-- So the count is done on the actual reference - key='inbound_secret' in the body-building
-- expression - not on the presence of a word anywhere in the text.
create or replace view public.v_internal_secret_migration_progress as
with j as (
  select jobid, jobname, active,
         (regexp_match(command, 'functions/v1/([a-z0-9_]+)'))[1]           as target_function,
         command ~ 'key\s*=\s*''inbound_secret'''                          as on_shared_secret,
         (regexp_match(command, 'key\s*=\s*''(cred_[a-z0-9_]+)'''))[1]     as scoped_key
  from cron.job
)
select
  (select count(*) from j)                                                  as cron_jobs_total,
  (select count(*) from j where on_shared_secret)                           as still_on_shared_secret,
  (select count(*) from j where on_shared_secret and active)                as still_on_shared_secret_active,
  (select count(*) from j where scoped_key is not null)                     as moved_to_scoped_credential,
  (select count(distinct target_function) from j
     where on_shared_secret and target_function is not null)                as functions_still_reachable_by_shared_secret,
  (select use_count from public.internal_credential where context = 'legacy.shared')      as shared_secret_use_count,
  (select last_used_at from public.internal_credential where context = 'legacy.shared')   as shared_secret_last_used,
  (select last_function from public.internal_credential where context = 'legacy.shared')  as shared_secret_last_function,
  (select count(*) from public.internal_credential where active and not is_legacy)        as scoped_credentials_issued,
  -- The withdrawal condition from WI-001, made checkable instead of aspirational.
  ((select count(*) from j where on_shared_secret and active) = 0
   and coalesce((select last_used_at from public.internal_credential where context = 'legacy.shared'),
                'epoch'::timestamptz) < now() - interval '7 days')          as safe_to_withdraw_shared_secret;

comment on view public.v_internal_secret_migration_progress is
  'AUDIT 9.5. Progress of the shared-secret withdrawal, counted on the actual key reference rather than on the word appearing anywhere in the cron body - which is how both WI-001 and a check earlier today produced wrong numbers. safe_to_withdraw_shared_secret is the WI-001 acceptance condition, evaluated rather than asserted.';

revoke all on public.v_internal_secret_migration_progress from public, anon, authenticated;
grant select on public.v_internal_secret_migration_progress to service_role;
;
