-- THE INQUIRY AND THE SUPPLIER'S OWN QUOTATION ARE CACHED AS DOCUMENTS
--
-- Assigned: sales_engineer. 21 Sep 2026. Founder instruction 435 (15 Sep 2026): each inquiry opens
-- the sales engineer's template with all requirements; BOQ and drawings downloadable, redacted.
--
-- MEASURED (21 Sep 2026, repository):
--   * The customer's quotation PDF is cached in public.quote_pdf_cache, primary key (quote_id, lang),
--     invalidated by quotes.updated_at (customer_api quote_pdf). 41 customers held rows there on
--     15 Sep 2026 (every_stored_document_source_is_registered_for_backup.sql, review note).
--   * supplier_api quote_pdf printed the supplier's own quotation on every call and cached nothing.
--   * No inquiry document existed at all: "Inquiries received" drew the template as a web page only.
--
-- WHAT WAS WRONG: the supplier's two documents cannot share quote_pdf_cache's key -- the same quote
-- prints differently for each side (letter 'S', no request text, for the supplier), and an inquiry
-- is not a quote. And public.inquiries has no updated_at column, so "cached after the last edit"
-- cannot be decided the way quote_pdf decides it.
--
-- WHAT CHANGES:
--   1. public.supplier_document_cache: one row per (kind, subject, supplier, lang) naming the stored
--      file and the SHA-256 of the input that produced it. supplier_api compares the hash of what it
--      would print now with the row's; equal -> the stored file is signed and served, different ->
--      printed again and the row replaced. An edited inquiry, an edited quote, and a reveal (which
--      changes what the inbox serves) all change the hash. Service-role only: RLS on, a policy that
--      says so, anon and authenticated revoked. supplier_api writes it under the service role.
--   2. The write map (public.phase_c_edge_function_writes) gains the row for this write where that
--      table still exists (its CSV mirror was retired 3 Sep 2026 with the mirror gates).
--
-- NOT CHANGED: quote_pdf_cache and customer_api are untouched. The files themselves sit in the
-- agent-docs bucket under supplier/<id>/, which fn_enqueue_doc_backups' storage sweep already
-- registers for backup (every_stored_document_source_is_registered_for_backup.sql, 'agent-docs').
-- Nothing here reads or grants anything to a supplier session: the cache row is never returned.
--
-- PROBE (self-cleaning, in the same transaction as the DDL, so it ends in a verdict row and never
-- in raise exception): a ZZ DEMO row is written, read back by its key, replaced through the same
-- conflict target supplier_api uses, deleted, and proved gone.

begin;

create table if not exists public.supplier_document_cache (
  kind          text        not null check (kind in ('inquiry', 'quotation')),
  subject_id    uuid        not null,
  supplier_id   bigint      not null,
  lang          text        not null check (lang in ('en', 'ar')),
  content_hash  text        not null,
  bucket        text        not null,
  path          text        not null,
  created_at    timestamptz not null default now(),
  primary key (kind, subject_id, supplier_id, lang)
);
comment on table public.supplier_document_cache is
  'The supplier''s inquiry and quotation PDFs, one file per (kind, subject, supplier, lang); content_hash is the SHA-256 of the input that produced it and decides whether the file is reused. Written by supplier_api only. 21 Sep 2026, sales_engineer.';

alter table public.supplier_document_cache enable row level security;
drop policy if exists supplier_document_cache_service_role_only on public.supplier_document_cache;
create policy supplier_document_cache_service_role_only on public.supplier_document_cache
  as permissive for all to public using (false) with check (false);
revoke all on public.supplier_document_cache from public, anon, authenticated;

-- The per-hour ceiling supplier_api applies reads this: rows by supplier, newest first.
create index if not exists supplier_document_cache_supplier_time_idx on public.supplier_document_cache (supplier_id, created_at);

-- The write map's CSV was retired with the mirror gates (docs/agents/RETIRED_MIRROR_GATES.md); the
-- table it loaded may or may not still exist, so the row is added only where there is a map to add it to.
do $do$
begin
  if to_regclass('public.phase_c_edge_function_writes') is not null then
    insert into public.phase_c_edge_function_writes (edge_function, table_name, write_kind, unbounded)
    values ('supplier_api', 'supplier_document_cache', 'upsert', false)
    on conflict (edge_function, table_name) do nothing;
  end if;
end $do$;

-- PROBE. Cannot reach a real person: no e-mail, no send, no row that any surface reads back.
create temp table probe_scdc on commit drop as
with ins as (
  insert into public.supplier_document_cache (kind, subject_id, supplier_id, lang, content_hash, bucket, path)
  values ('inquiry', '00000000-0000-4000-8000-0000000000dd'::uuid, -1, 'en', 'zz-demo-hash-1', 'agent-docs', 'supplier/-1/ZZ_DEMO_probe.pdf')
  returning 1
) select count(*) as inserted from ins;
insert into public.supplier_document_cache (kind, subject_id, supplier_id, lang, content_hash, bucket, path)
  values ('inquiry', '00000000-0000-4000-8000-0000000000dd'::uuid, -1, 'en', 'zz-demo-hash-2', 'agent-docs', 'supplier/-1/ZZ_DEMO_probe2.pdf')
  on conflict (kind, subject_id, supplier_id, lang) do update set content_hash = excluded.content_hash, path = excluded.path, created_at = now();
create temp table probe_scdc_read on commit drop as
  select content_hash, path from public.supplier_document_cache where supplier_id = -1 and kind = 'inquiry' and lang = 'en';
delete from public.supplier_document_cache where supplier_id = -1;
select case
  when (select inserted from probe_scdc) = 1
   and (select count(*) from probe_scdc_read) = 1
   and (select content_hash from probe_scdc_read) = 'zz-demo-hash-2'
   and (select path from probe_scdc_read) = 'supplier/-1/ZZ_DEMO_probe2.pdf'
   and not exists (select 1 from public.supplier_document_cache where supplier_id = -1)
  then 'PROBE OK' else 'PROBE FAILED' end as verdict;

commit;
