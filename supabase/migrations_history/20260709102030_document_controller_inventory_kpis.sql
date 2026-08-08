-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260709102030   name: document_controller_inventory_kpis
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- retention policy per storage bucket (null = keep / permanent)
create table if not exists public.retention_policy (
  bucket text primary key,
  retention_days int,           -- null = permanent
  class text not null,          -- tax, compliance, legal, operational, temporary, permanent
  notes text
);
insert into public.retention_policy(bucket,retention_days,class,notes) values
('finance-reports',2555,'tax','UAE 7-year record-keeping'),
('receipt-files',2555,'tax','UAE 7-year record-keeping'),
('supplier-docs',2555,'compliance','Supplier compliance docs — 7y'),
('signed-terms',null,'legal','Signed agreements — permanent'),
('compliance-docs',null,'compliance','Authority codes/regs — keep current'),
('quote-files',1095,'operational','Quotes — 3y'),
('drawing-files',1095,'operational','Customer drawings — 3y'),
('agent-docs',365,'operational','Agent-generated — 1y'),
('backups',365,'operational','Rolling 1-year backups'),
('brand',null,'permanent','Brand assets'),
('site',null,'permanent','Site assets')
on conflict (bucket) do update set retention_days=excluded.retention_days, class=excluded.class, notes=excluded.notes;
revoke all on public.retention_policy from anon, authenticated;

-- full inventory of every stored document across all buckets, with retention + processing status
create or replace view public.document_inventory as
select o.bucket_id as bucket, o.name as path,
  coalesce((o.metadata->>'size')::bigint,0) as bytes,
  coalesce(o.metadata->>'mimetype','') as mime,
  o.created_at,
  rp.retention_days, rp.class as retention_class,
  (rp.retention_days is not null and o.created_at < now() - (rp.retention_days||' days')::interval) as past_retention,
  exists(select 1 from documents d where d.bucket=o.bucket_id and d.path=o.name) as registered,
  exists(select 1 from documents d where d.bucket=o.bucket_id and d.path=o.name and d.extracted is not null) as ocr_done
from storage.objects o
left join retention_policy rp on rp.bucket=o.bucket_id
where o.name is not null and right(o.name,1) <> '/';
revoke all on public.document_inventory from anon, authenticated;

-- consolidated document KPIs
create or replace view public.document_kpis as
select
  (select count(*) from document_inventory) as total_documents,
  (select coalesce(sum(bytes),0) from document_inventory) as total_bytes,
  (select count(distinct bucket) from document_inventory) as buckets,
  (select count(*) from document_inventory where past_retention) as past_retention,
  (select count(*) from document_inventory where bytes > 30*1024*1024) as oversized,
  (select count(*) from documents) as registered_docs,
  (select count(*) from documents where extracted is not null) as ocr_done,
  (select count(*) from documents where coalesce(status,'') not in ('done','skipped') or coalesce(error,'')<>'') as ocr_backlog,
  round(100.0*(select count(*) from documents where extracted is not null)/nullif((select count(*) from documents),0),1) as ocr_coverage_pct,
  (select count(*) from doc_versions) as version_records,
  (select max(created_at) from storage.objects where bucket_id='backups') as last_backup_at,
  (select (extract(epoch from (now()-max(created_at)))/86400)::int from storage.objects where bucket_id='backups') as days_since_backup,
  (select count(*) from legal_documents) as legal_documents;

create table if not exists public.document_kpi_snapshots (
  id bigint generated always as identity primary key,
  snapshot_date date not null default current_date, kpis jsonb not null, created_at timestamptz not null default now()
);
create unique index if not exists document_kpi_snap_day on public.document_kpi_snapshots(snapshot_date);
revoke all on public.document_kpis, public.document_kpi_snapshots from anon, authenticated;
