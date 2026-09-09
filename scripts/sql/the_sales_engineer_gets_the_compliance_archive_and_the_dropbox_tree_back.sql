-- THE SALES ENGINEER GETS THE COMPLIANCE ARCHIVE AND THE DROPBOX TREE BACK
--
-- agent: sales_engineer
--
-- The founder, 9 September 2026: "compliance belong to sales engineer cause those signed t&c
-- eventually belongs to customers and suppliers. also he is responsible about the organized folders
-- back up in dropbox". Two duties, one seat.
--
-- WHAT WAS BROKEN. Commit 182308b (8 Sep) deleted 137 edge functions. It took compliance_archive and
-- dropbox_backup with them, and this file's three routines went in the same sweep:
--   fn_dbx_safe             MISSING   (measured: 0 rows in pg_proc)
--   fn_dbx_category         MISSING
--   fn_enqueue_doc_backups  MISSING
-- public.doc_backups still holds 193 rows from 10 Jul to 6 Sep 2026 — 167 done, 26 error, 144
-- distinct entities — so the backup was working right up to the sweep. The last successful upload
-- was 6 Sep 07:45 UTC. public.qd_sign_customer and public.qd_sign_supplier are STILL LIVE triggers
-- net.http_post-ing to compliance_archive and discarding the result, so every T&C signature since
-- 8 Sep has failed to archive with nothing anywhere recording that it had.
--
-- These are CREATE, not CREATE OR REPLACE, in effect: all three are gone, so each one is a fresh
-- SECURITY DEFINER routine and each gets its own `revoke execute ... from public` below.
--
-- THE QUOTE-COMPARISON DOCUMENT IS NOT COMING BACK. fn_enqueue_doc_backups v3 enqueued a
-- gen_kind='comparison' row per inquiry with >=2 live quotes, which dropbox_backup rendered by
-- calling quote_compare — a model call. All 8 llm_route_health routes are held and
-- fn_kernel_paid_provider_gate denies globally, by the founder's instruction, for the duration of
-- this build. That path was ALREADY the largest failure in the live queue before the model hold:
-- 15 of the 26 error rows are gen_kind='comparison', every one at attempts=5, error
-- 'compare parse_failed'. Re-enqueuing rows a deployed function cannot render is manufacturing
-- guaranteed failures, so the block is dropped here and the renderer is dropped in the function.
-- Current exposure is nil either way: public.quotes holds 0 non-draft rows.
--
-- NOTHING IN DROPBOX MOVES. doc_backups.dedupe_key does not contain dropbox_path and every insert
-- below is ON CONFLICT (dedupe_key) DO NOTHING, so rows already enqueued keep the paths they were
-- uploaded under. This file adds; it never renames, moves or deletes anything in the founder's
-- Dropbox.

begin;

-- ---------------------------------------------------------------------------------------------
-- 1. Path helpers. Verbatim from migration 20260710155830 / 20260729141623, which are the versions
--    that produced the 193 live rows — the folder shapes visible in doc_backups.dropbox_path today.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_dbx_safe(x text) returns text
language sql immutable set search_path to 'public','pg_catalog' as $$
  select btrim(regexp_replace(regexp_replace(coalesce(x,''),'[\\/:*?"<>|\r\n\t]+',' ','g'),'\s+',' ','g'))
$$;
revoke execute on function public.fn_dbx_safe(text) from public;

comment on function public.fn_dbx_safe(text) is
  'Strips characters Dropbox forbids in a path segment and collapses whitespace. Used to build every folder and file name in the organized backup tree.';

-- The supplier's Dropbox folder sits inside its category. Derived from the real 86-category taxonomy
-- in catalog_supplier_categories via lead_category (18,536 mapping rows live), NOT from the
-- free-text leads.categories / leads.sector, which matched the taxonomy for 0 of 20,464 leads and
-- grew folders like 'flooring', 'cctv-security' and 'Suppliers/dj zaino' (a supplier whose
-- free-text category was its own trading name).
create or replace function public.fn_dbx_category(p_lead_id bigint) returns text
language sql stable set search_path to 'public','pg_catalog' as $$
  select public.fn_dbx_safe(coalesce(
    (select c.name from public.lead_category lc
       join public.catalog_supplier_categories c on c.slug = lc.slug
      where lc.lead_id = p_lead_id and lc.is_primary
      order by lc.score desc nulls last limit 1),
    (select c.name from public.lead_category lc
       join public.catalog_supplier_categories c on c.slug = lc.slug
      where lc.lead_id = p_lead_id
      order by lc.score desc nulls last limit 1),
    (select c.name from public.leads l
       join public.catalog_supplier_categories c
         on c.slug = btrim(split_part(coalesce(l.categories,''),',',1))
         or lower(c.name) = lower(btrim(split_part(coalesce(l.categories,''),',',1)))
         or c.slug = btrim(coalesce(l.sector,''))
      where l.id = p_lead_id limit 1),
    'Uncategorized'));
$$;
revoke execute on function public.fn_dbx_category(bigint) from public;

comment on function public.fn_dbx_category(bigint) is
  'Resolves a supplier''s Dropbox category folder from catalog_supplier_categories (the 86 real categories) via lead_category. Used by fn_enqueue_doc_backups.';

-- ---------------------------------------------------------------------------------------------
-- 2. The organized tree. This function IS the "organized folders" the founder asked for: it decides
--    where every document lives in Dropbox, and it is the only thing that does.
--
--      /QuotesDone Backup/
--        Suppliers/<category>/<company> (<lead id>)/
--            Trade licence - <file>            Company profile - <file>
--            Bank IBAN - <file>                Signed Terms & Conditions - <file>
--            Establishment card - <file>       Catalogue - <file>        (one per catalogue)
--            Insurance - <file>                Company Details.pdf       (generated)
--            VAT certificate - <file>          ISO certificate - <file>
--            Manufacturer authorization - <file>
--        Customers/
--            customers-register.xlsx           (whole-of-register, written by compliance_archive)
--            <full name> (<id8>)/
--                Signed Terms & Conditions - <file>
--                Customer Details.pdf          (generated)
--                Inquiries/<YYYY-MM-DD> <inquiry id8> - <status>/
--                    Drawing - <original file name>
--                    Inquiry Summary.pdf       (generated)
--
--    Entity, then type, then date: a person can find one customer's signed T&C, or everything about
--    one inquiry, without knowing an id. Suppliers are scoped to REAL registrants — never the 20k
--    directory leads — by the approved_at/registration_submitted_at/claimed predicate.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_enqueue_doc_backups() returns integer
language plpgsql security definer set search_path to 'public','pg_catalog' as $$
declare n integer := 0; m integer;
begin
  -- ============ SUPPLIERS ============
  with s as (
    select l.*,
      '/QuotesDone Backup/Suppliers/' || public.fn_dbx_category(l.id)
        || '/' || public.fn_dbx_safe(coalesce(l.company_name,'Supplier')) || ' (' || l.id || ')/' as base
    from public.leads l
    where l.approved_at is not null or l.registration_submitted_at is not null
       or l.signed_terms_path is not null or l.company_profile_doc_path is not null
       or l.license_doc_path is not null or coalesce(l.claimed,false)
  ),
  sd as (
    select s.id, s.base, v.doc_type, v.bucket, v.path
    from s cross join lateral (values
      ('Trade licence','supplier-docs', s.license_doc_path),
      ('Bank IBAN','supplier-docs', s.iban_doc_path),
      ('Establishment card','supplier-docs', s.egr_doc_path),
      ('Insurance','supplier-docs', s.insurance_doc_path),
      ('VAT certificate','supplier-docs', s.vat_doc_path),
      ('ISO certificate','supplier-docs', s.iso_doc_path),
      ('Manufacturer authorization','supplier-docs', s.manufacturer_auth_doc_path),
      ('Company profile','supplier-docs', s.company_profile_doc_path),
      ('Signed Terms & Conditions','signed-terms', s.signed_terms_path)
    ) v(doc_type,bucket,path)
    where v.path is not null and length(v.path)>0
  )
  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'supplier', sd.id::text, sd.doc_type, sd.bucket, sd.path,
         regexp_replace(sd.path,'^.*/',''),
         sd.base || sd.doc_type || ' - ' || regexp_replace(sd.path,'^.*/',''),
         'storage', 'S:'||sd.id||':'||sd.doc_type||':'||sd.path
  from sd on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'supplier', s.id::text, 'Catalogue', 'supplier-docs', cat,
         regexp_replace(cat,'^.*/',''), s.base || 'Catalogue - ' || regexp_replace(cat,'^.*/',''),
         'storage', 'S:'||s.id||':cat:'||cat
  from ( select l.id,
      '/QuotesDone Backup/Suppliers/' || public.fn_dbx_category(l.id)
        || '/' || public.fn_dbx_safe(coalesce(l.company_name,'Supplier')) || ' (' || l.id || ')/' as base,
      l.catalog_doc_paths
    from public.leads l
    where (l.approved_at is not null or l.registration_submitted_at is not null
       or l.signed_terms_path is not null or l.company_profile_doc_path is not null
       or l.license_doc_path is not null or coalesce(l.claimed,false)) and l.catalog_doc_paths is not null ) s,
    unnest(s.catalog_doc_paths) cat
  where cat is not null and length(cat)>0 on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,source,gen_kind,gen_ref,dropbox_path,dedupe_key)
  select 'supplier', s.id::text, 'Company Details','generated','supplier_details', s.id::text,
         s.base || 'Company Details.pdf', 'S:'||s.id||':details'
  from ( select l.id,
      '/QuotesDone Backup/Suppliers/' || public.fn_dbx_category(l.id)
        || '/' || public.fn_dbx_safe(coalesce(l.company_name,'Supplier')) || ' (' || l.id || ')/' as base
    from public.leads l
    where l.approved_at is not null or l.registration_submitted_at is not null
       or l.signed_terms_path is not null or l.company_profile_doc_path is not null
       or l.license_doc_path is not null or coalesce(l.claimed,false) ) s
  on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  -- ============ CUSTOMERS ============
  -- This is the row that carries a signed T&C certificate into Dropbox. compliance_archive writes
  -- customers.signed_terms_path and stops; the file is placed here, in one folder, once.
  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'customer', c.id::text, 'Signed Terms & Conditions','signed-terms', c.signed_terms_path,
         regexp_replace(c.signed_terms_path,'^.*/',''),
         '/QuotesDone Backup/Customers/'||public.fn_dbx_safe(coalesce(c.full_name,'Customer'))||' ('||left(c.id::text,8)||')/Signed Terms & Conditions - '||regexp_replace(c.signed_terms_path,'^.*/',''),
         'storage', 'C:'||c.id||':terms:'||c.signed_terms_path
  from public.customers c where c.signed_terms_path is not null and length(c.signed_terms_path)>0
  on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,source,gen_kind,gen_ref,dropbox_path,dedupe_key)
  select 'customer', c.id::text, 'Customer Details','generated','customer_details', c.id::text,
         '/QuotesDone Backup/Customers/'||public.fn_dbx_safe(coalesce(c.full_name,'Customer'))||' ('||left(c.id::text,8)||')/Customer Details.pdf',
         'C:'||c.id||':details'
  from public.customers c on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  -- ============ INQUIRIES (under their customer) ============
  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'inquiry', i.id::text, 'RFQ drawing','drawing-files', i.drawing_file_path,
         coalesce(i.drawing_file_name, regexp_replace(i.drawing_file_path,'^.*/','')),
         '/QuotesDone Backup/Customers/'||public.fn_dbx_safe(coalesce(c.full_name,'Customer'))||' ('||left(c.id::text,8)||')/Inquiries/'
           || to_char(i.created_at,'YYYY-MM-DD')||' '||left(i.id::text,8)||' - '||public.fn_dbx_safe(coalesce(i.status,'inquiry'))
           || '/Drawing - '||coalesce(i.drawing_file_name, regexp_replace(i.drawing_file_path,'^.*/','')),
         'storage', 'I:'||i.id||':drawing:'||i.drawing_file_path
  from public.inquiries i join public.customers c on c.id=i.customer_id
  where i.drawing_file_path is not null and length(i.drawing_file_path)>0
  on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,source,gen_kind,gen_ref,dropbox_path,dedupe_key)
  select 'inquiry', i.id::text, 'Inquiry Summary','generated','inquiry_summary', i.id::text,
         '/QuotesDone Backup/Customers/'||public.fn_dbx_safe(coalesce(c.full_name,'Customer'))||' ('||left(c.id::text,8)||')/Inquiries/'
           || to_char(i.created_at,'YYYY-MM-DD')||' '||left(i.id::text,8)||' - '||public.fn_dbx_safe(coalesce(i.status,'inquiry'))
           || '/Inquiry Summary.pdf', 'I:'||i.id||':summary'
  from public.inquiries i join public.customers c on c.id=i.customer_id
  on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  -- The gen_kind='comparison' block that stood here is deliberately absent. See the header.

  return n;
end $$;
revoke execute on function public.fn_enqueue_doc_backups() from public;

comment on function public.fn_enqueue_doc_backups() is
  'Builds the organized Dropbox backup tree under /QuotesDone Backup: entity, then document type, then date. Idempotent on doc_backups.dedupe_key; it only ever adds rows and never changes the dropbox_path of a row already uploaded. Called by dropbox_backup, which is ticked by resilience_ping.';

-- ---------------------------------------------------------------------------------------------
-- 3. Once per local day, in Postgres, because Postgres knows what Asia/Dubai means.
--
--    pg_cron is dead by the founder's 7 Sep instruction: cron.job holds one inactive row and 234
--    jobs were deleted, so a cron string here would never fire. The live path is Vercel cron ->
--    /api/resilience-ping -> resilience_ping every 15 minutes, which already carries the CEO digest
--    tick and support's rating tick. This is the third tick on that same path.
--
--    "Due" is two conditions, not one. A daily backup that runs once and stops leaves a queue: the
--    function processes at most 25 documents per invocation, so a day with 200 new documents would
--    take eight days to drain on a strictly once-a-day gate. So it is due when today's Asia/Dubai
--    sweep has not run yet, OR when a previous sweep left work behind. Both are read from state that
--    already exists — agent_runs and doc_backups — so there is no new table and no new secret to go
--    stale. Attempts>=5 rows are excluded because dropbox_backup will not pick them up either, and a
--    permanently-failing row must not hold the tick open forever.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_dropbox_backup_due() returns jsonb
language sql stable security definer set search_path to 'public','pg_catalog' as $$
  select jsonb_build_object(
    'due', (not exists (
              select 1 from public.agent_runs r
               where r.agent = 'dropbox_backup' and r.status = 'ok'
                 and (r.started_at at time zone 'Asia/Dubai')::date
                     = (now() at time zone 'Asia/Dubai')::date))
           or exists (
              select 1 from public.doc_backups d
               where d.status in ('pending','error') and coalesce(d.attempts,0) < 5),
    'local_date', (now() at time zone 'Asia/Dubai')::date,
    'ran_today', exists (
              select 1 from public.agent_runs r
               where r.agent = 'dropbox_backup' and r.status = 'ok'
                 and (r.started_at at time zone 'Asia/Dubai')::date
                     = (now() at time zone 'Asia/Dubai')::date),
    'queued', (select count(*) from public.doc_backups d
                where d.status in ('pending','error') and coalesce(d.attempts,0) < 5));
$$;
revoke execute on function public.fn_dropbox_backup_due() from public;

comment on function public.fn_dropbox_backup_due() is
  'Once-per-Asia/Dubai-day gate for the Dropbox backup, plus a drain condition so a day''s backlog finishes instead of waiting for tomorrow. Read by resilience_ping every 15 minutes. Reads only; the day is claimed by dropbox_backup logging an ok run to agent_runs.';

-- ---------------------------------------------------------------------------------------------
-- 4. Ownership, BEFORE the deploy. every_deployed_function_has_an_owner.mjs fails in both
--    directions, so a row that lands after the function is serving is a window where the check is
--    red, and a row for a function that never deploys is the "record outliving its subject" state
--    the same check exists to prevent.
-- ---------------------------------------------------------------------------------------------
insert into public.function_owner(function_slug, owner, note) values
 ('compliance_archive','sales_engineer',
  'The founder, 9 Sep 2026: "compliance belong to sales engineer cause those signed t&c eventually belongs to customers and suppliers." Issues the UAE-law Terms-acceptance certificate for a customer or supplier, records signed_terms_path, and maintains the customer register. Called by the live triggers qd_sign_customer and qd_sign_supplier.'),
 ('dropbox_backup','sales_engineer',
  'The founder, 9 Sep 2026: "he is responsible about the organized folders back up in dropbox." Drains public.doc_backups into the organized tree under /QuotesDone Backup built by fn_enqueue_doc_backups. Add-only: its delete path was disabled on restore.')
on conflict (function_slug) do update
  set owner = excluded.owner, note = excluded.note, recorded_at = now(),
      moves_to = null, moves_to_note = null;

-- ---------------------------------------------------------------------------------------------
-- 5. Credential reconciliation. The scopes named six callees that no longer exist; a credential
--    scoped to a deleted function is not a licence to recreate that function, it is a grant with no
--    subject. What each one turned out to be:
--
--      cron.backup       -> ["backup","dr_drill","dropbox_backup","dropbox_sync","github_sync",
--                            "retention_purge"]. Only dropbox_backup is real and coming back; the
--                            other five have no deployed function and are not being restored. The
--                            grant is narrowed to the one callee that exists.
--      fn.dropbox_backup -> ["quote_compare","make_pdf"]. quote_compare needs a held model and its
--                            document is dropped; make_pdf was deleted and pdf_native (v29, live)
--                            does the job. Becomes ["pdf_native"].
--      fn.resilience_ping-> ["send_outbox","alert_founder"]. It now also calls dropbox_backup, so
--                            the callee is added. Without this the tick fails closed at
--                            fn_internal_auth and the backup silently never runs.
--      fn.archive_rfq    -> ["ai_gateway"]. archive_rfq is NOT restored (it exists to summarise a
--                            completed RFQ with a model, and rfq_archives holds 0 rows against 0
--                            inquiries). Deactivated rather than left as an active grant to nothing.
--      fn.dropbox_oauth  -> ["dropbox_sync"]. Neither function exists; the stored refresh token
--                            works, so no OAuth helper is needed. Deactivated.
--
--    db.internal (id 111) already carries compliance_archive, which is the credential the two
--    triggers present as cred_db_internal. It is correct as it stands and is not touched.
-- ---------------------------------------------------------------------------------------------
update public.internal_credential set scope = array['dropbox_backup']            where context = 'cron.backup';
update public.internal_credential set scope = array['pdf_native']                where context = 'fn.dropbox_backup';
update public.internal_credential
   set scope = array['send_outbox','alert_founder','dropbox_backup']             where context = 'fn.resilience_ping';
update public.internal_credential set active = false
 where context in ('fn.archive_rfq','fn.dropbox_oauth') and active;

commit;
