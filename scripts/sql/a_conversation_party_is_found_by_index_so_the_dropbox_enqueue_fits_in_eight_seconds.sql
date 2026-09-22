-- A CONVERSATION PARTY IS FOUND BY INDEX, SO THE DROPBOX ENQUEUE FITS IN EIGHT SECONDS.
-- Assigned: it_engineer. 21 Sep 2026.
--
-- ══ MEASURED, 21 Sep 2026 ~16:00Z, htdblwldjkcgjvmqkbeh, read-only ══════════════════════════════
-- it_watch_finding queue_stalled:doc_backups_failed (open since 19 Sep 07:30Z, seen 10x): ONE row at
--   status 'error' older than 24 h — doc_backups 270782, a Stripe invoice PDF for transaction
--   36267ce7…, attempts 5, "download Object not found". The transaction and the storage object are
--   both gone (the nightly journey's TEST checkout of 18 Sep, torn down). fn_doc_backups_next never
--   claims a row at attempts 5, so it can never drain by upload.
-- The abandonment for exactly this row already exists: a_backup_of_a_source_that_no_longer_exists_…
--   put it inside fn_it_backup_recheck. It never committed. fn_it_backup_tick (resilience_ping step
--   backupVerify, via PostgREST) calls fn_backup_watch -> fn_backup_coverage -> fn_enqueue_doc_backups,
--   and the whole RPC is cancelled at the authenticator's 8 s statement_timeout: resilience_step
--   backupVerify last_ok_at 20 Sep 03:31Z, last_ms 9,042 on 21 Sep 10:46Z. A cancel is not caught by
--   the tick's per-stage "when others", so the recheck's UPDATE rolls back with the rest, every tick.
-- WHY 8 s: pg_stat_statements — fn_enqueue_doc_backups() 7,020 ms mean; fn_conversation_archived
--   (the p_source_table/p_source_id/p_path/p_bytes register RPC, which calls the enqueue) 6,342 ms.
--   EXPLAIN ANALYZE of the enqueue's correspondence SELECT alone: 7,006 ms. It joins all 257
--   conversation_archive rows to v_conversation_message every call (every one already queued; ON
--   CONFLICT discards them), and the view calls fn_conversation_party per message at 20-45 ms because
--   its email lookup `lower(email) = x OR lower(claimed_by) = x` seq-scans 22,270 leads (49.6 ms).
--   The table-export block is 70 ms; nothing else in the enqueue is material.
-- fn_doc_backups_next(p_limit): its own claim query is 0.24 ms (EXPLAIN ANALYZE) and it has averaged
--   7 ms over 5 calls since the 15:09Z stats reset; its earlier 5,422 ms mean was time spent behind the
--   7-second enqueue transactions on the same table, not its own work. No change to it here.
--
-- ══ CHANGES ══════════════════════════════════════════════════════════════════════════════════════
-- 1. fn_conversation_party: the lead lookup by email is two lookups, each on its index (0.8 ms each).
-- 2. fn_enqueue_doc_backups: the correspondence block reads only archive rows with no CONV row yet
--    (1.7 ms with nothing new, EXPLAIN ANALYZE). Body is the live one otherwise; search_path pinned to
--    public, pg_temp (it was public, pg_catalog — pg_catalog is searched first regardless).
-- 3. Row 270782 is abandoned with a dated reason, by the SAME predicate and wording fn_it_backup_recheck
--    uses, so fn_backup_coverage and the recheck read it as a documented abandonment and handoffs
--    28974/38862 close on the next tick that completes. Nothing is marked done; nothing is uploaded.
--
-- ══ NOT CHANGED ══════════════════════════════════════════════════════════════════════════════════
-- fn_whatsapp_owner (21 ms a call, 13 WhatsApp rows: regexp over leads, no index) — not on the enqueue
-- path after change 2. fn_it_backup_tick's handler shape. fn_doc_backups_next. The dropbox_backup edge
-- function (no code change needed). The live fn_enqueue_doc_backups body came from a 21 Sep apply
-- (bank-details removal) whose file is not on this branch; this file must sort after it in MANIFEST.
--
-- Apply: node scripts/apply_sql.mjs scripts/sql/a_conversation_party_is_found_by_index_so_the_dropbox_enqueue_fits_in_eight_seconds.sql --apply

CREATE OR REPLACE FUNCTION public.fn_conversation_party(p_lead bigint, p_customer uuid, p_inquiry uuid, p_email text, p_phone text)
 RETURNS TABLE(party_kind text, party_id text, inquiry_id text, demo boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_email text := lower(nullif(btrim(coalesce(p_email, '')), ''));
        v_tail text := nullif(right(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), 9), '');
        v_c uuid; v_l bigint;
begin
  if v_tail is not null and length(v_tail) < 7 then v_tail := null; end if;
  v_c := p_customer;
  if v_c is null and p_inquiry is not null then select i.customer_id into v_c from public.inquiries i where i.id = p_inquiry; end if;
  if v_c is not null then
    return query select 'customer'::text, v_c::text, p_inquiry::text,
      coalesce((select c.is_demo or coalesce(c.email, '') ~* 'example\.invalid' from public.customers c where c.id = v_c), false);
    return;
  end if;
  v_l := p_lead;
  if v_l is null and v_email is not null then
    select c.id into v_c from public.customers c where lower(c.email) = v_email limit 1;
    if v_c is not null then
      return query select 'customer'::text, v_c::text, null::text,
        coalesce((select c.is_demo or coalesce(c.email, '') ~* 'example\.invalid' from public.customers c where c.id = v_c), false);
      return;
    end if;
    -- 21 SEP 2026 (it_engineer): TWO LOOKUPS, EACH ON ITS INDEX. The single OR over both columns could use
    -- neither index (uq_leads_email_lower is partial on email <> '', which the OR did not state), so every
    -- call seq-scanned all 22,270 leads: 49.6 ms, measured. The non-empty-email clause admits the partial
    -- index (0.8 ms, generic plan); claimed_by has idx_leads_claimedby. A registered email now wins over a
    -- claimed_by match where both exist; before, the scan order chose.
    select l.id into v_l from public.leads l where lower(l.email) = v_email and l.email <> '' limit 1;
    if v_l is null then
      select l.id into v_l from public.leads l where lower(l.claimed_by) = v_email limit 1;
    end if;
  end if;
  if v_l is null and v_tail is not null then
    -- 14 Sep 2026 (#322): only a CONFIRMED WhatsApp number names a party.
    select o.customer_id, o.lead_id into v_c, v_l from public.fn_whatsapp_owner(p_phone) o;
    if v_c is not null then
      return query select 'customer'::text, v_c::text, null::text,
        coalesce((select c.is_demo from public.customers c where c.id = v_c), false);
      return;
    end if;
  end if;
  if v_l is not null then
    return query select 'supplier'::text, v_l::text, null::text,
      coalesce((select coalesce(l.is_demo, false) or coalesce(l.email, '') ~* 'example\.invalid'
                     or coalesce(l.company_name, '') ~* 'ZZ DEMO' from public.leads l where l.id = v_l), false);
    return;
  end if;
  return query select 'company'::text, null::text, null::text, false;
end $function$;

-- AMENDED 22 SEP 2026 (it_engineer, SEATS-05): THE ROUTINE CARRIES ITS OWN TIMEOUT, NOT THE CALLER'S 8 s.
-- MEASURED on production today (pg_stat_statements, 266 calls of the PostgREST RPC): mean 298 ms, max
-- 7,379 ms. The index fix above brought the MEAN inside the authenticator's 8 s budget and left the worst
-- case 600 ms short of it, so a slow pass still lost everything: three cancellations — 21 Sep 09:33:20Z and
-- 17:38:44Z, 22 Sep 09:42:22Z — each rolled the whole enqueue back with "canceling statement due to
-- statement timeout" and logged "no new documents are being queued for Dropbox backup". A function-level
-- SET applies to the routine's own statements, so the pass gets 30 s of headroom while the authenticator's
-- 8 s still bounds every OTHER call the same session makes. The work per pass is already bounded (only
-- archive rows with no CONV row, only documents not yet queued), so a longer ceiling cannot become a longer
-- queue — it only stops a 7-second pass being thrown away 600 ms from the end.
CREATE OR REPLACE FUNCTION public.fn_enqueue_doc_backups()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
 SET statement_timeout TO '30s'
AS $function$
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
  from sd on conflict do nothing;
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
  where cat is not null and length(cat)>0 on conflict do nothing;
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
  on conflict do nothing;
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
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,source,gen_kind,gen_ref,dropbox_path,dedupe_key)
  select 'customer', c.id::text, 'Customer Details','generated','customer_details', c.id::text,
         '/QuotesDone Backup/Customers/'||public.fn_dbx_safe(coalesce(c.full_name,'Customer'))||' ('||left(c.id::text,8)||')/Customer Details.pdf',
         'C:'||c.id||':details'
  from public.customers c on conflict do nothing;
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
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,source,gen_kind,gen_ref,dropbox_path,dedupe_key)
  select 'inquiry', i.id::text, 'Inquiry Summary','generated','inquiry_summary', i.id::text,
         '/QuotesDone Backup/Customers/'||public.fn_dbx_safe(coalesce(c.full_name,'Customer'))||' ('||left(c.id::text,8)||')/Inquiries/'
           || to_char(i.created_at,'YYYY-MM-DD')||' '||left(i.id::text,8)||' - '||public.fn_dbx_safe(coalesce(i.status,'inquiry'))
           || '/Inquiry Summary.pdf', 'I:'||i.id||':summary'
  from public.inquiries i join public.customers c on c.id=i.customer_id
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  -- The gen_kind='comparison' block that stood here is deliberately absent. See the header.

  -- ============ REVENUE INVOICES (9 SEP 2026) ============
  -- The founder: "our accountant need to retrieve that and be connected, then add it to his
  -- records, sync it with back up on dropbox." This is the sync half. The trigger is doc_path
  -- being non-null, NOT who wrote it, so a backfill or a hand-repair mirrors on the same rule as
  -- the webhook. They are filed under Finance rather than under the customer, because the person
  -- who opens this folder is the accountant reconciling a month, not someone reading one customer.
  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'transaction', t.id::text, 'Stripe invoice', 'finance-docs', t.doc_path,
         coalesce(t.doc_name, regexp_replace(t.doc_path,'^.*/','')),
         '/QuotesDone Backup/Finance/Revenue Invoices/'
           || to_char(coalesce(t.revealed_at, now()), 'YYYY') || '/'
           || to_char(coalesce(t.revealed_at, now()), 'YYYY-MM') || '/'
           || public.fn_dbx_safe(coalesce(t.stripe_invoice_number, t.stripe_invoice_id, left(t.id::text,8)))
           || ' - ' || coalesce(t.doc_name, regexp_replace(t.doc_path,'^.*/','')),
         'storage', 'T:'||t.id||':invoice:'||t.doc_path
  from public.transactions t
  where t.doc_path is not null and length(t.doc_path) > 0
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  -- ============ CORRESPONDENCE (14 SEP 2026) ============
  -- The founder: "by back up i mean 2 points. supabase and dropbox." Every conversation message whose
  -- PDF is in backups/conversations/ (public.conversation_archive) is mirrored to Dropbox on his
  -- entity -> type -> date tree. A customer's message on an inquiry goes under that inquiry; a
  -- supplier's goes under the supplier ONLY when the supplier is a registrant (the same predicate the
  -- supplier documents use above); everything else is Company correspondence by month. Demo rows are
  -- never queued. Times are Dubai time.
  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select x.entity, x.entity_id, 'Correspondence', a.pdf_bucket, a.pdf_path, x.fname, x.base || x.fname, 'storage',
         'CONV:' || a.source_table || ':' || a.source_id
  -- 21 SEP 2026 (it_engineer): ONLY ARCHIVE ROWS THAT HAVE NO CORRESPONDENCE ROW YET. This block used to
  -- join every conversation_archive row (257) to v_conversation_message on every call and let ON CONFLICT
  -- discard all of them; the view resolves each message's party through fn_conversation_party, 20-45 ms
  -- a row, so the call cost 7,006 ms (EXPLAIN ANALYZE, 21 Sep) and PostgREST cancels at 8 s. The OFFSET 0
  -- fences keep the anti-join FIRST and the view LATERAL, so a call with nothing new costs 1.7 ms and a
  -- new message costs one party lookup. The dedupe key is unchanged, so what is queued is unchanged.
  from (select ca.* from public.conversation_archive ca
         where not exists (select 1 from public.doc_backups d
                            where d.dedupe_key = 'CONV:' || ca.source_table || ':' || ca.source_id)
         offset 0) a
  cross join lateral (select * from public.v_conversation_message v0
                       where v0.source_table = a.source_table and v0.source_id = a.source_id offset 0) v
  left join public.customers c on v.party_kind = 'customer' and c.id::text = v.party_id
  left join public.inquiries i on c.id is not null and i.id::text = v.inquiry_id
  left join public.leads l on v.party_kind = 'supplier' and l.id::text = v.party_id
       and (l.approved_at is not null or l.registration_submitted_at is not null
         or l.signed_terms_path is not null or l.company_profile_doc_path is not null
         or l.license_doc_path is not null or coalesce(l.claimed,false))
  cross join lateral (select
      case when c.id is not null then 'customer' when l.id is not null then 'supplier' else 'company' end as entity,
      coalesce(c.id::text, l.id::text, v.source_table || ':' || v.source_id) as entity_id,
      case when c.id is not null then
             '/QuotesDone Backup/Customers/' || public.fn_dbx_safe(coalesce(c.full_name,'Customer')) || ' (' || left(c.id::text,8) || ')/'
             || case when i.id is not null then 'Inquiries/' || to_char(i.created_at,'YYYY-MM-DD') || ' ' || left(i.id::text,8)
                       || ' - ' || public.fn_dbx_safe(coalesce(i.status,'inquiry')) || '/' else '' end
             || 'Correspondence/'
           when l.id is not null then
             '/QuotesDone Backup/Suppliers/' || public.fn_dbx_category(l.id) || '/'
             || public.fn_dbx_safe(coalesce(l.company_name,'Supplier')) || ' (' || l.id || ')/Correspondence/'
           else '/QuotesDone Backup/Company/Correspondence/' || to_char(v.occurred_at at time zone 'Asia/Dubai','YYYY-MM') || '/'
      end as base,
      to_char(v.occurred_at at time zone 'Asia/Dubai','YYYY-MM-DD HH24MI') || ' ' || v.direction || ' ' || v.channel || ' - '
        || public.fn_dbx_safe(left(coalesce(nullif(btrim(v.subject),''),'(no subject)'),80)) || ' #' || v.source_id || '.pdf' as fname) x
  where not v.is_demo
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  -- ============ ACCOUNTING (14 SEP 2026, accountant duty 4 of the five further duties) ============
  -- The founder, 14 Sep 2026: "add all for accountant and IT". The accountant's own documents are filed on
  -- the entity -> type -> date tree under Finance: the month close the CEO signed for (PDF and CSV), the
  -- Mashreq statements, every document the accountant issued in the founder's name, and the year-end pack.
  -- A path stored as '<bucket>/<path>' (bank_statement_intake.doc_path, accountant_issued_document.file_path)
  -- is split at its first slash; any other shape is not queued. Demo rows are filtered exactly as
  -- fn_it_backup_expected filters them (a zz_demo account, an @example.invalid recipient, a ZZ DEMO path):
  -- no demo document reaches Dropbox or the backups bucket.
  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'company', 'close:' || to_char(c.month,'YYYY-MM'), v.doc_type, c.pdf_bucket, v.path,
         regexp_replace(v.path,'^.*/',''),
         '/QuotesDone Backup/Finance/Month Close/' || to_char(c.month,'YYYY') || '/' || to_char(c.month,'YYYY-MM')
           || ' - ' || regexp_replace(v.path,'^.*/',''),
         'storage', 'ACCT:close:' || to_char(c.month,'YYYY-MM') || ':' || v.path
  from public.accountant_month_close c
  cross join lateral (values ('Month close (PDF)', c.pdf_path), ('Month close (CSV)', c.csv_path)) v(doc_type, path)
  where c.rendered_at is not null and c.pdf_bucket is not null and length(coalesce(v.path,'')) > 0
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'company', 'bank_statement:' || b.source_ref, 'Bank statement', split_part(b.doc_path,'/',1),
         substr(b.doc_path, strpos(b.doc_path,'/') + 1), regexp_replace(b.doc_path,'^.*/',''),
         '/QuotesDone Backup/Finance/Bank Statements/' || initcap(b.account) || '/'
           || to_char(coalesce(b.statement_month, (b.received_at at time zone 'Asia/Dubai')::date),'YYYY') || '/'
           || to_char(coalesce(b.statement_month, (b.received_at at time zone 'Asia/Dubai')::date),'YYYY-MM')
           || ' - ' || regexp_replace(b.doc_path,'^.*/',''),
         'storage', 'ACCT:bank:' || b.source_ref
  from public.bank_statement_intake b
  where b.doc_path ~ '^[a-z0-9-]+/.+' and b.account <> 'zz_demo'
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'company', 'issued:' || d.id, 'Issued document', split_part(d.file_path,'/',1),
         substr(d.file_path, strpos(d.file_path,'/') + 1), regexp_replace(d.file_path,'^.*/',''),
         '/QuotesDone Backup/Finance/Issued Documents/' || to_char(d.issued_at at time zone 'Asia/Dubai','YYYY') || '/'
           || to_char(d.issued_at at time zone 'Asia/Dubai','YYYY-MM') || '/'
           || to_char(d.issued_at at time zone 'Asia/Dubai','YYYY-MM-DD') || ' ' || d.document_kind || ' #' || d.id
           || ' - ' || regexp_replace(d.file_path,'^.*/',''),
         'storage', 'ACCT:issued:' || d.id
  from public.accountant_issued_document d
  where d.file_path ~ '^[a-z0-9-]+/.+' and d.recipient !~* 'example\.invalid'
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'company', 'year_end:' || p.year, 'Year-end pack', f->>'bucket', f->>'path', f->>'name',
         '/QuotesDone Backup/Finance/Year End/' || p.year || '/' || (f->>'name'),
         'storage', 'ACCT:year_end:' || p.year || ':' || (f->>'name')
  from public.accountant_year_end_pack p cross join lateral jsonb_array_elements(p.files) f
  where p.rendered_at is not null and (f->>'path') !~* 'zz[_ -]?demo'
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  -- ============ TABLE EXPORTS (14 SEP 2026, it_engineer) ============
  -- Every file of a FINISHED day's export (public.table_export_run.status = 'done'), filed as
  -- Company -> Database Exports -> month -> day. Only finished days: a day that is re-run rewrites its
  -- pages, and a page mirrored mid-run would be a copy of an export that never completed. Demo rows
  -- never reach these files (fn_table_export_page). A (bucket, path) already queued by another rule
  -- (a refile) is skipped rather than allowed to fail this whole routine on the unique key.
  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'company', 'table_export:' || to_char(r.stamp,'YYYY-MM-DD'), 'Database export', 'backups', o.name,
         regexp_replace(o.name,'^.*/',''),
         '/QuotesDone Backup/Company/Database Exports/' || to_char(r.stamp,'YYYY-MM') || '/' || o.name,
         'storage', 'EXPORT:' || o.name
  from public.table_export_run r
  join storage.objects o on o.bucket_id = 'backups' and o.name like to_char(r.stamp,'YYYY-MM-DD') || '/%'
  where r.status = 'done'
    and not exists (select 1 from public.doc_backups d where d.bucket = 'backups' and d.path = o.name)
  on conflict do nothing;
  get diagnostics m = row_count; n := n + m;

  -- LEGACY EXPORTS and the STORAGE SWEEP are fn_enqueue_doc_backups_backfill (15 Sep 2026): together they
  -- took this call from milliseconds to 50 s, past PostgREST's 8 s, and every new document stopped.
  return n;
end $function$;

-- CREATE OR REPLACE preserves both ACLs (service_role only, measured); restated for the auditor.
revoke execute on function public.fn_conversation_party(bigint, uuid, uuid, text, text) from public, anon, authenticated;
revoke execute on function public.fn_enqueue_doc_backups() from public, anon, authenticated;

-- ══ SETTLE THE STUCK ROW ═════════════════════════════════════════════════════════════════════════
-- The same predicate and wording as fn_it_backup_recheck's orphan step: a transaction backup whose
-- transaction row no longer exists is abandoned with its reason. Measured: exactly one such row (270782).
update public.doc_backups d
   set status = 'abandoned',
       error = left('abandoned: source transaction ' || d.entity_id || ' no longer exists (measured '
                    || to_char(now() at time zone 'Asia/Dubai', 'DD Mon YYYY HH24:MI') || ' Dubai; last error: '
                    || coalesce(d.error, 'none') || ')', 300)
 where d.entity = 'transaction' and d.status <> 'done' and d.status <> 'abandoned'
   and not exists (select 1 from public.transactions t where t.id::text = d.entity_id);

-- ══ PROBE ════════════════════════════════════════════════════════════════════════════════════════
-- DDL above, so the verdict is a ROW, never a raise. It FAILS if the cause returns:
--   * fn_enqueue_doc_backups() takes 2 s or more (was 7,020 ms). Timed inside a subtransaction that is
--     rolled back, exactly as fn_backup_coverage runs it, so the probe files nothing.
--   * the full archive-to-view read (every archived message's party, the read fn_it_backup_expected
--     also makes) takes 2 s or more (was 7,006 ms) — i.e. fn_conversation_party is scanning again.
--   * either routine's fix is missing from its live body.
--   * any doc_backups row sits at status 'error' past the watch's own 1,440-minute threshold.
do $probe$
declare t0 timestamptz;
begin
  t0 := clock_timestamp();
  begin
    perform public.fn_enqueue_doc_backups();
    raise exception using errcode = 'QDRBK', message = 'roll back the probe enqueue';
  exception when sqlstate 'QDRBK' then null;
  end;
  perform set_config('qd.probe_enqueue_ms', (extract(epoch from clock_timestamp() - t0) * 1000)::int::text, false);
  t0 := clock_timestamp();
  perform count(*) from public.conversation_archive a
    join public.v_conversation_message v on v.source_table = a.source_table and v.source_id = a.source_id;
  perform set_config('qd.probe_view_ms', (extract(epoch from clock_timestamp() - t0) * 1000)::int::text, false);
end $probe$;

with chk as (
  select current_setting('qd.probe_enqueue_ms')::int as enqueue_ms,
         current_setting('qd.probe_view_ms')::int    as view_ms,
         (select prosrc not like '%lower(l.email) = v_email or lower(l.claimed_by)%'
             and prosrc like '%lower(l.email) = v_email and l.email <> ''''%'
            from pg_proc where oid = 'public.fn_conversation_party(bigint,uuid,uuid,text,text)'::regprocedure) as party_split,
         (select prosrc like '%where d.dedupe_key = ''CONV:'' || ca.source_table || '':'' || ca.source_id%'
            from pg_proc where oid = 'public.fn_enqueue_doc_backups()'::regprocedure) as enqueue_new_only,
         (select count(*) from public.doc_backups
           where status = 'error' and created_at < now() - interval '1440 minutes') as undrained_errors,
         (select status from public.doc_backups where id = 270782) as row_270782
)
select case when enqueue_ms < 2000 and view_ms < 2000 and party_split and enqueue_new_only and undrained_errors = 0
       then 'PROBE OK: fn_enqueue_doc_backups ' || enqueue_ms || ' ms (was 7,020), archive-to-view read ' || view_ms
            || ' ms (was 7,006), 0 doc_backups rows at error past 24 h; row 270782 is ' || coalesce(row_270782, 'gone') || '.'
       else 'PROBE FAILED: enqueue_ms=' || enqueue_ms || ' view_ms=' || view_ms || ' party_split=' || coalesce(party_split::text, 'null')
            || ' enqueue_new_only=' || coalesce(enqueue_new_only::text, 'null') || ' undrained_errors=' || undrained_errors
            || ' row_270782=' || coalesce(row_270782, 'gone')
       end as verdict
from chk;
