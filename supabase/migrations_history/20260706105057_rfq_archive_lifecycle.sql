-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260706105057   name: rfq_archive_lifecycle
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- ============ ARCHIVE LIFECYCLE: searchable metadata in Postgres ============
create table if not exists public.rfq_archives(
  id bigserial primary key,
  rfq_id text not null unique,
  customer_id text,
  supplier_ids text[] default '{}',
  category text,
  status text,
  dates jsonb,
  bucket text default 'backups',
  archive_path text,          -- folder path of the case package
  checksum text,              -- sha256 of case.json
  archive_version int default 1,
  ai_summary jsonb,           -- {summary, lessons[]}
  size_bytes int,
  created_at timestamptz default now(),
  restored_at timestamptz);
create index if not exists idx_rfq_arch_cat on public.rfq_archives(category);
create index if not exists idx_rfq_arch_customer on public.rfq_archives(customer_id);
alter table public.rfq_archives enable row level security;
revoke all on public.rfq_archives from anon, authenticated;

-- daily lifecycle: archive RFQs completed > 90 days ago, not yet archived (batch of 5)
select cron.schedule('archive_completed_daily','20 4 * * *', $$
do $inner$
declare i int;
begin
  for i in 1..5 loop
    perform net.http_post(
      url := 'https://htdblwldjkcgjvmqkbeh.supabase.co/functions/v1/archive_rfq',
      headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||(select value from app_secrets where key='anon_key')),
      body := jsonb_build_object('__secret',(select value from app_secrets where key='inbound_secret')),
      timeout_milliseconds := 60000);
  end loop;
end $inner$;
$$);
select 'ok';
