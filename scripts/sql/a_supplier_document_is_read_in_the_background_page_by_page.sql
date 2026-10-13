-- a_supplier_document_is_read_in_the_background_page_by_page
-- Seat: sales_engineer (the reading); it_engineer (the build). 13 Oct 2026, after #1412.
-- A supplier's company profile or catalogue is no longer read inside the upload request: process_docs and
-- save_documents mark it 'reading' (supplier_doc_trades.markReading) and hand it to supplier_api's read_docs_job,
-- which reads it a budgeted slice of pages per step, each step its own edge worker (CPU cap) and its own wall time
-- (the model calls). public.supplier_doc_read holds the text read so far between steps, one row per document, and
-- is deleted when the document is read. A document whose steps stop is still 'reading' and is swept after 30 minutes
-- (fn_supplier_doc_reading_escalate, #1404). Service role only: RLS on with a service_role_only policy, no grant to anon or authenticated.
-- Applied at merge (release operator).
create table if not exists public.supplier_doc_read (
  supplier_id bigint not null references public.leads(id) on delete cascade,
  path        text   not null,
  pages_read  integer not null default 0,
  pages_total integer,
  text        text   not null default '',
  steps       integer not null default 0,
  updated_at  timestamptz not null default now(),
  primary key (supplier_id, path)
);
alter table public.supplier_doc_read enable row level security;
drop policy if exists supplier_doc_read_service_role_only on public.supplier_doc_read;
create policy supplier_doc_read_service_role_only on public.supplier_doc_read for all to service_role using (true) with check (true);
revoke all on table public.supplier_doc_read from public, anon, authenticated;
grant select, insert, update, delete on table public.supplier_doc_read to service_role;
comment on table public.supplier_doc_read is 'Text of a supplier profile or catalogue read so far by supplier_api read_docs_job, between its budgeted steps. Deleted when the read finishes. Seat: sales_engineer.';

select case
  when not exists (select 1 from pg_class where oid = 'public.supplier_doc_read'::regclass and relrowsecurity) then 'PROBE FAILED: RLS is off'
  when has_table_privilege('anon', 'public.supplier_doc_read', 'select') or has_table_privilege('authenticated', 'public.supplier_doc_read', 'select') then 'PROBE FAILED: anon or authenticated can read it'
  else 'PROBE OK' end as verdict;
