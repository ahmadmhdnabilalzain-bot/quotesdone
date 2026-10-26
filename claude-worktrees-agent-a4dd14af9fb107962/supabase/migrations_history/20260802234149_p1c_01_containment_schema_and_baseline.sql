-- Applied version: 20260802234149
-- Recovered from production, byte-for-byte as applied.

-- Phase 1 emergency containment, step 1 of 4.
-- Records the pre-change state so every containment change is reversible.
-- No behaviour changes in this migration.

create schema if not exists containment;
revoke all on schema containment from public;
revoke all on schema containment from anon, authenticated;
grant usage on schema containment to postgres, service_role;

create table if not exists containment.baseline (
  id            bigint generated always as identity primary key,
  captured_at   timestamptz not null default now(),
  label         text not null,
  payload       jsonb not null
);

create table if not exists containment.cron_disabled (
  jobid         bigint primary key,
  jobname       text not null,
  schedule      text not null,
  command       text not null,
  was_active    boolean not null,
  class         text not null,
  disabled_at   timestamptz not null default now(),
  restored_at   timestamptz,
  rollback_sql  text not null
);

create table if not exists containment.policy_removed (
  id            bigint generated always as identity primary key,
  schemaname    text not null,
  tablename     text not null,
  policyname    text not null,
  cmd           text,
  permissive    text,
  roles         text,
  qual          text,
  with_check    text,
  removed_at    timestamptz not null default now(),
  restored_at   timestamptz,
  rollback_sql  text not null
);

create table if not exists containment.change_log (
  id            bigint generated always as identity primary key,
  area          text not null,
  change        text not null,
  before_value  text,
  after_value   text,
  applied_at    timestamptz not null default now(),
  rollback_sql  text not null
);

alter table containment.baseline        enable row level security;
alter table containment.cron_disabled   enable row level security;
alter table containment.policy_removed  enable row level security;
alter table containment.change_log      enable row level security;

-- Full pre-change snapshot, computed live at apply time.
insert into containment.baseline (label, payload)
select 'pre_containment_2026_08_02', jsonb_build_object(
  'captured_at', now(),
  'branch', 'hotfix/phase1-emergency-containment',
  'from_commit', '658e67506bc8401bf92c78d143687e8e99e65241',
  'app_secrets', (select jsonb_object_agg(key, value) from public.app_secrets
     where key in ('agent_autonomy_enabled','agent_autonomy_from','cos_frozen','ai_kill_switch',
                   'auto_approve_suppliers','containment_maintenance')),
  'cron_jobs', (select jsonb_agg(jsonb_build_object('jobid',jobid,'jobname',jobname,
                  'schedule',schedule,'active',active,'command',command) order by jobid) from cron.job),
  'cron_totals', (select jsonb_build_object('total',count(*),'active',count(*) filter (where active)) from cron.job),
  'storage_policies', (select jsonb_agg(jsonb_build_object('schemaname',schemaname,'tablename',tablename,
                  'policyname',policyname,'cmd',cmd,'permissive',permissive,'roles',roles::text,
                  'qual',qual,'with_check',with_check)) from pg_policies where schemaname='storage'),
  'control_mode_action_count', (select count(*) from public.control_mode_action),
  'live_counts', jsonb_build_object(
     'customers',(select count(*) from public.customers),
     'inquiries',(select count(*) from public.inquiries),
     'leads_total',(select count(*) from public.leads),
     'leads_claimed',(select count(*) from public.leads where claimed is true),
     'refunds',(select count(*) from public.refunds),
     'supplier_docs_objects',(select count(*) from storage.objects where bucket_id='supplier-docs')),
  'holdout_v1_seal', (select checksum_sha from public.p2c1_holdout_seal limit 1),
  'holdout_v2_seal', (select checksum_sha256 from holdout_v2.seal where id=1)
);;
