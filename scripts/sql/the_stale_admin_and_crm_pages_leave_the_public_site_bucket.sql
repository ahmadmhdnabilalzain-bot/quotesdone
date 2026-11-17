-- THE STALE ADMIN AND CRM PAGES LEAVE THE PUBLIC SITE BUCKET (it_engineer, 17 Nov 2026).
--
-- Security audit of 17 Nov 2026 (docs/reports/2026-11-17-security-audit.md, finding 2; 10 Nov open item 4). The public
-- `site` bucket still serves the June/July static site to anyone with the URL, including admin/index.html, app/index.html
-- and the os/ console (internal screens that call functions no longer deployed). The 27 Oct audit (L2) found no secret
-- in them; they describe internal screens, so they go. Nothing in src/ or supabase/functions reads this bucket
-- (/m/brand proxies `brand` only; READ, grep 17 Nov).
--
-- MEASURED (SELECT on storage.objects, 17 Nov 2026 ~11:00 UTC): the bucket holds exactly these 10 objects, last written
-- 19 Jun and 7 Jul 2026, 210,240 bytes in all. Each is in public.doc_backups with status 'done', a dropbox_path and
-- verified_at set, so a verified copy of every file is in Dropbox.
--
-- WHAT THIS CHANGES: deletes those 10 rows of storage.objects, named by id AND bucket AND name, and nothing else. The
-- storage server looks the row up before it serves a public URL, so each URL answers 404 from the commit.
-- WHAT IT DOES NOT CHANGE:
--   * The bucket itself stays (empty and public). `site` is a registered backup source
--     (every_stored_document_source_is_registered_for_backup.sql) and every_storage_path_is_in_the_backup_registry
--     reads the bucket list; dropping it is a separate change with its own registry edit.
--   * The stored bytes. storage.protect_delete refuses a direct delete unless storage.allow_delete_query is 'true' for
--     the transaction, and a direct delete removes the metadata row, not the file in the underlying store: about 210 KB
--     stay there, unreachable by any URL. The Storage API would remove both; this estate changes production through
--     reviewed SQL files, and 210 KB of unreachable bytes is the smaller cost.
--
-- ROLLBACK: for each path below, download doc_backups.dropbox_path (bucket = 'site', path = <name>) from Dropbox and
-- upload it to storage bucket `site` at <name> with the service role (the Storage API creates the row again).
--
-- Data only, no DDL. One transaction; `set local` ends with it.
--   node scripts/apply_sql.mjs scripts/sql/the_stale_admin_and_crm_pages_leave_the_public_site_bucket.sql --apply

set local storage.allow_delete_query = 'true';

create temp table _site_pages(id uuid primary key, name text not null) on commit drop;
insert into _site_pages(id, name) values
  ('998941df-e5da-473e-b8a2-884a3c1b4a38', 'admin/index.html'),
  ('39ec863d-c7e0-4fbf-8bb6-02a494a05442', 'app/index.html'),
  ('eb71d374-f706-4626-9c2f-002b7fd69891', 'index.html'),
  ('597d0b00-e365-4d8d-992a-e6817fbdd059', 'os/app.html'),
  ('015b9727-2f81-4d89-9c1f-60a59386fd5c', 'os/os_components.js'),
  ('ff4fb95f-4b91-4404-96a3-2187ff6efe57', 'os/os_design.css'),
  ('a92dd81f-255c-45ed-9c63-8a87338d40c7', 'privacy/index.html'),
  ('fbe45954-143b-4d54-9900-68a6ec1e71c5', 'supplier-agreement/index.html'),
  ('881c357d-963d-45da-96b5-544befb39be7', 'suppliers/index.html'),
  ('df5a977d-4224-419f-86c1-1586ffdc1b4f', 'terms/index.html');

-- No other bucket is counted: the delete names bucket_id = 'site', and other buckets take live uploads, so a count
-- of them taken twice inside this transaction could differ for reasons that are not this file.
create temp table _site_others_before on commit drop as
  select o.id from storage.objects o where o.bucket_id = 'site' and not exists (select 1 from _site_pages p where p.id = o.id);

delete from storage.objects o
 using _site_pages p
 where o.bucket_id = 'site' and o.id = p.id and o.name = p.name;

-- verdict row
select case
  when exists (select 1 from storage.objects o join _site_pages p on p.id = o.id)
    then 'PROBE FAILED: a listed page is still in storage.objects'
  when exists (select 1 from storage.objects o join _site_pages p on p.name = o.name where o.bucket_id = 'site')
    then 'PROBE FAILED: a listed name is still served from site (a different id: re-uploaded since 17 Nov?)'
  when (select count(*) from storage.objects o where o.bucket_id = 'site')
       <> (select count(*) from _site_others_before)
    then 'PROBE FAILED: an object of site that was not on the list changed'
  when not exists (select 1 from storage.buckets where id = 'site')
    then 'PROBE FAILED: the site bucket itself is gone'
  else 'PROBE OK' end as verdict;
