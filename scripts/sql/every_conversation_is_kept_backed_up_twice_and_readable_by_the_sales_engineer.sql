-- EVERY CONVERSATION IS KEPT, BACKED UP TWICE, AND THE SALES ENGINEER CAN READ ALL OF IT.
--
-- THE FOUNDER, 14 SEPTEMBER 2026, IN HIS WORDS (recorded verbatim in public.founder_instruction
-- below, before any of the work):
--
--   "keep in mind that all conversations need to be saved and the sales agent has access to them
--    at any time. just in case we needed them for any reason"
--   "if the provider has one month history then we print a pdf copy of that email and keep it in
--    our back up"
--   "by back up i mean 2 points. supabase and dropbox. i have already mention the method of
--    dropbox backup organizing"
--
-- Agent: ceo. Owner of what this builds: sales_engineer (the seat that reads the record).
--
-- ── WHAT WAS MEASURED ON PRODUCTION BEFORE THIS FILE (14 Sep 2026) ─────────────────────────────
--
-- Where a conversation lands, and how many rows each store held:
--   inbound_messages      18   inbound email (resend_inbound, inbound_email)
--   notifications         41   everything the company sent: 39 email, 2 WhatsApp
--   wa_messages           13   WhatsApp in + the reply (wa_inbound); wa_turn / wa_conversation 0
--   assistant_logs        42   homepage widget (site_assistant), full message + reply
--   messages               0   portal chat customer <-> supplier (messages_api)
--   rfq_clarification      0   supplier clarify threads
--   contact_messages       0   contact form;  complaint_tickets 0;  quote_review_messages 0
--   agent_chats         1414   the founder's own chats with the seats - internal, not customer or
--                              supplier correspondence, kept as they are and NOT archived here
--
-- Purges: NONE. No public routine deletes from any of these tables, cron.job holds one job and it
-- is inactive (wa_flush), and no edge function calls .delete() on them. Nothing drops a message.
--
-- What WAS lost or was never reachable:
--   1. INBOUND EMAIL WAS TRUNCATED AND, FOR RECEIPTS, REPLACED. resend_inbound cut the text to 8,000
--      characters, and on the expense path it stored a one-line summary instead of the email
--      ("[expense one-off] Vercel 20 USD on ...") - rows 136-151 hold 40-146 characters each. The
--      HTML and Resend's own email id were never stored, so nothing could go back to Resend for
--      the original, and Resend keeps inbound mail about a month. (Fixed in resend_inbound; the
--      emails still inside Resend's window are backfilled by conversation_archive.)
--   2. WHATSAPP INBOUND WAS CUT AT 2,000 CHARACTERS (wa_inbound, five inserts). WhatsApp allows
--      4,096. (Fixed in wa_inbound.)
--   3. THE CUSTOMER PORTAL'S CHAT WITH THE SALES ENGINEER WAS NEVER SAVED. sales_engineer's
--      'assist' wrote a count to agent_runs and nothing else - the question and the answer were
--      gone the moment the widget closed. (Fixed: it now writes assistant_logs, seat
--      'sales_engineer', audience 'customer:<id>'.)
--   4. THE SALES ENGINEER COULD NOT READ ANY OF IT. fn_contact_timeline returns a 140-character
--      summary per event, reads wa_turn (0 rows) instead of wa_messages (the real store), misses
--      the widget, the clarify threads and the complaints, is service-role only, and the
--      sales_engineer function had no action reaching it. (Fixed: fn_conversation_record, the
--      'conversations' action, and a standing grant.)
--   5. NO COPY EXISTED OUTSIDE THE ROWS. (Fixed: every conversation message becomes a PDF in the
--      private 'backups' bucket, and the SAME file is queued for Dropbox on the founder's own tree
--      through the existing doc_backups conveyor - no second uploader.)
--
-- ── WHAT THIS FILE BUILDS ──────────────────────────────────────────────────────────────────────
--   * inbound_messages.provider_email_id + html          the original can be fetched and kept
--   * v_conversation_message                            ONE shape over every store, full text
--   * fn_conversation_party                             who a message belongs to
--   * conversation_archive                              the ledger: which message has which PDF
--   * fn_conversation_archive_pending / _archived        the edge function's two doors
--   * fn_enqueue_doc_backups (+ CORRESPONDENCE section)  Dropbox paths, decided HERE and only here
--   * fn_conversation_record                            what the sales engineer reads
--   * fn_conversation_retention_breaches                what the check and fn_backup_watch read
--   * ceo_standing_grant sales.conversation_record, function_owner, credential scope
--
-- The Dropbox tree is the founder's rule, entity -> type -> date:
--   /QuotesDone Backup/Customers/<full name> (<id8>)/Correspondence/<YYYY-MM-DD HHMM> <in|out> <channel> - <subject> #<ref>.pdf
--   ... and under Inquiries/<YYYY-MM-DD> <inquiry id8> - <status>/Correspondence/ when the message
--       belongs to an inquiry
--   /QuotesDone Backup/Suppliers/<category>/<company> (<lead id>)/Correspondence/...  (registrants only,
--       the same predicate the supplier documents use; mail to a lead who never registered is filed
--       under Company, so it is kept without inventing a supplier folder)
--   /QuotesDone Backup/Company/Correspondence/<YYYY-MM>/...  mail tied to no customer or supplier
-- The '#<ref>' suffix is the one departure from his example: two emails in the same minute with the
-- same subject would otherwise share a path, and dropbox_backup uploads with mode 'overwrite'.
-- Times are Dubai time. Demo rows (is_demo, @example.invalid, ZZ DEMO) are never archived or queued.
--
-- WHAT THIS FILE DOES NOT DO: it does not upload to Dropbox (the daily resilience_ping ->
-- dropbox_backup pass does, and a production Dropbox write from a session is held); it does not
-- add a delete guard on the stores (a cascade from a demo customer would be refused and break the
-- fixture cleanups - the check guards against a purge appearing instead); it does not touch
-- fn_contact_timeline, which stays the short cross-seat summary it is.

-- ── 0. HIS WORDS FIRST ─────────────────────────────────────────────────────────────────────────
insert into public.founder_instruction (said_at, instruction, subject, status, note)
select '2026-09-14 12:00+04', v.i, 'conversation retention and backup', 'open', v.n
from (values
  ('keep in mind that all conversations need to be saved and the sales agent has access to them at any time. just in case we needed them for any reason',
   'Every conversation store keeps full text permanently (no purge), and the sales_engineer seat can read all of it for any customer or supplier: fn_conversation_record via the sales_engineer ''conversations'' action.'),
  ('if the provider has one month history then we print a pdf copy of that email and keep it in our back up',
   'Resend keeps inbound mail about a month. Every inbound and outbound email is rendered to a PDF (headers, body, attachment list, Arabic shaped) into the private backups bucket within one heartbeat; the emails still in Resend are backfilled.'),
  ('by back up i mean 2 points. supabase and dropbox. i have already mention the method of dropbox backup organizing',
   'Two copies: Supabase bucket ''backups'' and Dropbox via the existing doc_backups conveyor, paths decided only by fn_enqueue_doc_backups on the entity -> type -> date tree.'),
  ('i think the IT agent need to check such details yea?',
   'The sales engineer files the backup; the it_engineer verifies it (post-upload hash check, weekly re-check, 48h coverage) and hands missing files back. Built in the_dropbox_backup_is_confirmed_not_assumed.sql.'),
  ('why do we have to mention to customers that we are saving a copy. remove that',
   'No customer- or supplier-facing text says a copy is saved. The correspondence PDFs are internal and carry no archive footer (removed from conversation_archive/document.ts before any reached a customer; none ever did).'),
  ('the part where it says supabase and dropbox. definitely remove that',
   'Supabase and Dropbox are never named on anything a customer or supplier sees; the PDFs rendered with that footer on 14 Sep were re-rendered without it.')
) v(i, n)
where not exists (select 1 from public.founder_instruction f where f.instruction = v.i);

-- ── 1. THE ORIGINAL EMAIL CAN BE KEPT ──────────────────────────────────────────────────────────
alter table public.inbound_messages add column if not exists provider_email_id text;
alter table public.inbound_messages add column if not exists html text;
create unique index if not exists inbound_messages_provider_email_id_key
  on public.inbound_messages (provider_email_id) where provider_email_id is not null;

-- ── 2. WHO A MESSAGE BELONGS TO ────────────────────────────────────────────────────────────────
-- Order matters: an explicit customer, then the inquiry's customer, then the supplier lead, then an
-- address match. A message on an inquiry is filed with the customer's inquiry, even when the
-- supplier wrote it - that is where the person reading the job will look for it.
create or replace function public.fn_conversation_party(
  p_lead bigint, p_customer uuid, p_inquiry uuid, p_email text, p_phone text)
returns table (party_kind text, party_id text, inquiry_id text, demo boolean)
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
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
    select l.id into v_l from public.leads l where lower(l.email) = v_email or lower(l.claimed_by) = v_email limit 1;
  end if;
  if v_l is null and v_tail is not null then
    select c.id into v_c from public.customers c where right(regexp_replace(coalesce(c.phone, ''), '[^0-9]', '', 'g'), 9) = v_tail limit 1;
    if v_c is not null then
      return query select 'customer'::text, v_c::text, null::text,
        coalesce((select c.is_demo from public.customers c where c.id = v_c), false);
      return;
    end if;
    -- ponytail: a sequential scan of leads per phone lookup; fine at tens of WhatsApp rows a day,
    -- an expression index on the 9-digit tail when that stops being true.
    select l.id into v_l from public.leads l
     where v_tail in (right(regexp_replace(coalesce(l.phone_e164, ''), '[^0-9]', '', 'g'), 9),
                      right(regexp_replace(coalesce(l.phone, ''), '[^0-9]', '', 'g'), 9),
                      right(regexp_replace(coalesce(l.whatsapp, ''), '[^0-9]', '', 'g'), 9)) limit 1;
  end if;
  if v_l is not null then
    return query select 'supplier'::text, v_l::text, null::text,
      coalesce((select coalesce(l.is_demo, false) or coalesce(l.email, '') ~* 'example\.invalid'
                     or coalesce(l.company_name, '') ~* 'ZZ DEMO' from public.leads l where l.id = v_l), false);
    return;
  end if;
  return query select 'company'::text, null::text, null::text, false;
end $fn$;
revoke execute on function public.fn_conversation_party(bigint, uuid, uuid, text, text) from public, anon, authenticated;

-- ── 3. ONE SHAPE OVER EVERY STORE, FULL TEXT ───────────────────────────────────────────────────
-- Outbound rows are only those that actually left (status 'sent'): a queued, held or failed
-- notification is kept in its table all the same, but it is not correspondence anyone received.
create or replace view public.v_conversation_message as
select 'inbound_messages'::text as source_table, m.id::text as source_id, 'email'::text as channel, 'in'::text as direction,
       m.created_at as occurred_at, m.from_email as from_addr, m.to_email as to_addr, null::text as cc,
       m.subject, m.body, m.html, jsonb_build_object('count', coalesce(m.attachments_count, 0)) as attachments,
       p.party_kind, p.party_id, p.inquiry_id,
       (coalesce(m.from_email, '') ~* 'example\.invalid' or p.demo) as is_demo
  from public.inbound_messages m
  cross join lateral public.fn_conversation_party(m.lead_id, null, null, m.from_email, null) p
union all
select 'notifications', n.id::text, coalesce(n.channel, 'email'), 'out',
       coalesce(n.sent_at, n.created_at), coalesce(n.sender, 'QuotesDone'), coalesce(n.to_email, n.to_phone),
       array_to_string(n.cc_emails, ', '), n.subject, n.body, n.html, coalesce(n.attachments, '[]'::jsonb),
       p.party_kind, p.party_id, coalesce(p.inquiry_id, n.inquiry_id::text),
       (coalesce(n.to_email, '') ~* 'example\.invalid' or coalesce(n.subject, '') ~* 'ZZ DEMO' or p.demo)
  from public.notifications n
  cross join lateral public.fn_conversation_party(n.lead_id, null, n.inquiry_id, n.to_email, n.to_phone) p
 where n.status = 'sent' and coalesce(n.channel, 'email') in ('email', 'whatsapp')
union all
select 'wa_messages', w.id::text, 'whatsapp', 'in', w.created_at, w.wa_from, w.wa_to, null,
       'WhatsApp' || coalesce(' from ' || nullif(w.profile_name, ''), ''),
       'Received:' || E'\n' || coalesce(w.inbound, '')
         || case when coalesce(w.reply, '') <> '' then E'\n\n' || 'Replied' || case when w.sent then '' else ' (not delivered)' end || ':' || E'\n' || w.reply else '' end,
       null, '[]'::jsonb, p.party_kind, p.party_id, p.inquiry_id, p.demo
  from public.wa_messages w
  cross join lateral public.fn_conversation_party(null, null, null, null, w.wa_from) p
union all
select 'messages', pm.id::text, 'chat', case when pm.sender in ('customer', 'supplier') then 'in' else 'out' end,
       pm.created_at, pm.sender, null, null, 'Portal chat - ' || coalesce(pm.sender, ''),
       pm.body || coalesce(E'\n\n' || 'Attachment: ' || pm.attachment_path, ''), null,
       case when pm.attachment_path is null then '[]'::jsonb else jsonb_build_array(jsonb_build_object('path', pm.attachment_path)) end,
       p.party_kind, p.party_id, coalesce(p.inquiry_id, pm.inquiry_id::text), p.demo
  from public.messages pm
  cross join lateral public.fn_conversation_party(pm.supplier_id, pm.customer_id, pm.inquiry_id, null, null) p
union all
select 'rfq_clarification', r.id::text, 'chat', 'in', r.asked_at, 'supplier ' || coalesce(r.supplier_id::text, ''), null, null,
       'Clarification - ' || coalesce(r.kind, ''),
       'Question:' || E'\n' || coalesce(r.question, '') || case when r.answer is not null then E'\n\n' || 'Answer:' || E'\n' || r.answer else '' end,
       null, '[]'::jsonb, p.party_kind, p.party_id, coalesce(p.inquiry_id, r.inquiry_id::text), p.demo
  from public.rfq_clarification r
  cross join lateral public.fn_conversation_party(r.supplier_id, null, r.inquiry_id, null, null) p
union all
select 'assistant_logs', a.id::text, 'chat', 'in', a.created_at,
       case when a.audience ~ '^customer:' then 'portal customer' else 'website visitor' end, coalesce(a.seat, 'customer_support'), null,
       case when a.seat = 'sales_engineer' then 'Portal - sales engineer' else 'Website assistant' end || coalesce(' - ' || a.path, ''),
       'Asked:' || E'\n' || coalesce(a.message, '') || E'\n\n' || 'Answered:' || E'\n' || coalesce(a.reply, ''),
       null, '[]'::jsonb, p.party_kind, p.party_id, p.inquiry_id, p.demo
  from public.assistant_logs a
  cross join lateral public.fn_conversation_party(null,
       case when a.audience ~ '^customer:[0-9a-f-]{36}$' then substring(a.audience from 10)::uuid end, null, null, null) p
union all
select 'contact_messages', cm.id::text, 'form', 'in', cm.created_at, coalesce(cm.email, cm.phone), null, null,
       'Contact form' || coalesce(' - ' || cm.name, ''), cm.message, null, '[]'::jsonb,
       p.party_kind, p.party_id, p.inquiry_id, (coalesce(cm.email, '') ~* 'example\.invalid' or p.demo)
  from public.contact_messages cm
  cross join lateral public.fn_conversation_party(null, null, null, cm.email, cm.phone) p
union all
select 'complaint_tickets', ct.id::text, 'form', 'in', ct.created_at, ct.email, null, null,
       'Complaint ' || coalesce(ct.ticket_no, ''),
       coalesce(ct.message, '') || case when ct.final_response is not null then E'\n\n' || 'Final response:' || E'\n' || ct.final_response else '' end,
       null, '[]'::jsonb, p.party_kind, p.party_id, p.inquiry_id, (coalesce(ct.email, '') ~* 'example\.invalid' or p.demo)
  from public.complaint_tickets ct
  cross join lateral public.fn_conversation_party(null, null, null, ct.email, null) p
union all
select 'quote_review_messages', q.id::text, 'chat', case when q.role = 'customer' then 'in' else 'out' end, q.created_at,
       q.role, null, null, 'Quote review - ' || coalesce(q.role, ''), q.body, null, coalesce(q.attachments, '[]'::jsonb),
       'company', null, null, false
  from public.quote_review_messages q;
revoke all on public.v_conversation_message from public, anon, authenticated;

-- ── 4. THE LEDGER: WHICH MESSAGE HAS WHICH PDF ─────────────────────────────────────────────────
create table if not exists public.conversation_archive (
  source_table text not null,
  source_id    text not null,
  pdf_bucket   text not null default 'backups',
  pdf_path     text not null,
  bytes        bigint,
  archived_at  timestamptz not null default now(),
  primary key (source_table, source_id)
);
alter table public.conversation_archive enable row level security;
drop policy if exists conversation_archive_service_role_only on public.conversation_archive;
create policy conversation_archive_service_role_only on public.conversation_archive
  as permissive for all to public using (false) with check (false);
revoke all on public.conversation_archive from anon, authenticated;

create or replace function public.fn_conversation_archive_pending(p_limit integer default 25)
returns setof public.v_conversation_message
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  select v.* from public.v_conversation_message v
   where not v.is_demo
     and not exists (select 1 from public.conversation_archive a
                      where a.source_table = v.source_table and a.source_id = v.source_id)
   order by v.occurred_at
   limit greatest(1, least(coalesce(p_limit, 25), 200));
$fn$;
revoke execute on function public.fn_conversation_archive_pending(integer) from public, anon, authenticated;

create or replace function public.fn_conversation_archived(
  p_source_table text, p_source_id text, p_path text, p_bytes bigint)
returns jsonb
language plpgsql security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_queued integer;
begin
  if coalesce(p_path, '') !~ '^conversations/' then
    return jsonb_build_object('ok', false, 'reason', 'the PDF must live under backups/conversations/');
  end if;
  insert into public.conversation_archive (source_table, source_id, pdf_path, bytes)
  values (p_source_table, p_source_id, p_path, p_bytes)
  on conflict (source_table, source_id) do update set pdf_path = excluded.pdf_path, bytes = excluded.bytes, archived_at = now();
  v_queued := public.fn_enqueue_doc_backups();
  return jsonb_build_object('ok', true, 'queued_for_dropbox', v_queued);
end $fn$;
revoke execute on function public.fn_conversation_archived(text, text, text, bigint) from public, anon, authenticated;

-- ── 5. THE DROPBOX PATHS - THE MANIFEST-LAST DEFINITION, EXTENDED, NOT REWRITTEN ───────────────
-- fn_enqueue_doc_backups: copied VERBATIM from its MANIFEST-last definition
-- (the_accountant_retrieves_the_stripe_invoice_and_files_it.sql) with ONE section added before the
-- return - CORRESPONDENCE. Every earlier section is unchanged; this file is now the canonical one.
create or replace function public.fn_enqueue_doc_backups()
returns integer
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $function$
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
  on conflict (dedupe_key) do nothing;
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
  from public.conversation_archive a
  join public.v_conversation_message v on v.source_table = a.source_table and v.source_id = a.source_id
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
  on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  return n;
end $function$;

revoke execute on function public.fn_enqueue_doc_backups() from public, anon, authenticated;

-- ── 6. WHAT THE SALES ENGINEER READS ───────────────────────────────────────────────────────────
-- A contact is an email, a phone number, or 'customer:<uuid>' / 'supplier:<lead id>'. Every message
-- comes back whole - never a 140-character summary - with where its PDF lives in each backup.
create or replace function public.fn_conversation_record(p_contact text, p_limit integer default 200)
returns jsonb
language plpgsql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_raw text := btrim(coalesce(p_contact, '')); v_email text; v_tail text;
        v_kind text; v_id text; v_msgs jsonb;
begin
  v_raw := regexp_replace(v_raw, '^whatsapp:', '', 'i');
  if v_raw ~* '^(customer|supplier):.+' then
    v_kind := lower(split_part(v_raw, ':', 1)); v_id := substring(v_raw from position(':' in v_raw) + 1);
  elsif position('@' in v_raw) > 0 then
    v_email := lower(v_raw);
  elsif length(regexp_replace(v_raw, '[^0-9]', '', 'g')) >= 7 then
    v_tail := right(regexp_replace(v_raw, '[^0-9]', '', 'g'), 9);
  else
    return jsonb_build_object('ok', false, 'reason', 'give an email, a phone number, customer:<id> or supplier:<id>');
  end if;
  if v_kind is null then
    select p.party_kind, p.party_id into v_kind, v_id
      from public.fn_conversation_party(null, null, null, v_email, v_tail) p;
    if v_kind = 'company' then v_kind := null; v_id := null; end if;
  end if;

  select coalesce(jsonb_agg(x order by x->>'at' desc), '[]'::jsonb) into v_msgs from (
    select jsonb_build_object(
             'at', v.occurred_at, 'channel', v.channel, 'direction', v.direction,
             'from', v.from_addr, 'to', v.to_addr, 'cc', v.cc, 'subject', v.subject,
             'body', v.body, 'has_html', v.html is not null, 'attachments', v.attachments,
             'party', v.party_kind, 'party_id', v.party_id, 'inquiry_id', v.inquiry_id,
             'ref', v.source_table || ':' || v.source_id,
             'pdf', case when a.pdf_path is not null then jsonb_build_object('bucket', a.pdf_bucket, 'path', a.pdf_path) end,
             'dropbox', case when b.id is not null then jsonb_build_object('path', b.dropbox_path, 'status', b.status) end) x
      from public.v_conversation_message v
      left join public.conversation_archive a on a.source_table = v.source_table and a.source_id = v.source_id
      left join public.doc_backups b on b.dedupe_key = 'CONV:' || v.source_table || ':' || v.source_id
     where (v_id is not null and v.party_kind = v_kind and v.party_id = v_id)
        or (v_email is not null and (lower(v.from_addr) = v_email or lower(v.to_addr) = v_email or lower(coalesce(v.cc, '')) like '%' || v_email || '%'))
        or (v_tail is not null and (right(regexp_replace(coalesce(v.from_addr, ''), '[^0-9]', '', 'g'), 9) = v_tail
                                 or right(regexp_replace(coalesce(v.to_addr, ''), '[^0-9]', '', 'g'), 9) = v_tail))
     order by v.occurred_at desc
     limit greatest(1, least(coalesce(p_limit, 200), 2000))) z;

  return jsonb_build_object('ok', true, 'contact', coalesce(v_email, v_tail, v_raw),
    'party', v_kind, 'party_id', v_id, 'message_count', jsonb_array_length(v_msgs), 'messages', v_msgs,
    'assembled_by', 'fn_conversation_record (deterministic; full text from every store; no model)');
end $fn$;
revoke execute on function public.fn_conversation_record(text, integer) from public, anon, authenticated;

-- ── 7. WHAT THE CHECK AND fn_backup_watch READ ─────────────────────────────────────────────────
-- A message older than the grace with no PDF, and a PDF with no Dropbox queue row, are both
-- breaches. The heartbeat is 15 minutes, so the default grace of 2 hours is eight missed beats.
create or replace function public.fn_conversation_retention_breaches(p_grace interval default interval '2 hours')
returns jsonb
language sql stable security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with unarchived as (
    select v.source_table, v.source_id, v.channel from public.v_conversation_message v
     where not v.is_demo and v.occurred_at < now() - p_grace
       and not exists (select 1 from public.conversation_archive a where a.source_table = v.source_table and a.source_id = v.source_id)),
  unqueued as (
    select a.source_table, a.source_id from public.conversation_archive a
     where a.archived_at < now() - p_grace
       and not exists (select 1 from public.doc_backups b where b.dedupe_key = 'CONV:' || a.source_table || ':' || a.source_id))
  select jsonb_build_object(
    'grace', p_grace::text,
    'emails_without_pdf', (select count(*) from unarchived where channel = 'email'),
    'conversations_without_pdf', (select count(*) from unarchived),
    'pdfs_without_dropbox_row', (select count(*) from unqueued),
    'total', (select count(*) from unarchived) + (select count(*) from unqueued),
    'sample', (select coalesce(jsonb_agg(u.source_table || ':' || u.source_id), '[]'::jsonb)
                 from (select source_table, source_id from unarchived union all select * from unqueued limit 10) u));
$fn$;
revoke execute on function public.fn_conversation_retention_breaches(interval) from public, anon, authenticated;

-- ── 8. THE SEAT MAY DO IT, THE FUNCTION HAS AN OWNER, THE HEARTBEAT MAY CALL IT ────────────────
insert into public.ceo_standing_grant (grant_key, grantee_role_id, action_class, scope_note, limit_note, max_amount_aed, issued_by, active)
values ('sales.conversation_record', 'sales_engineer', 'conversation_record',
        'Read every saved conversation - email in and out, WhatsApp, portal chat, clarifications, the website assistant, forms - for any customer or supplier, at any time, with the PDF kept in each backup. The founder, 14 Sep 2026: "all conversations need to be saved and the sales agent has access to them at any time".',
        'Read only. It never edits or deletes a message, and a customer caller reads its own record only.',
        null, 'ceo', true)
on conflict (grant_key) do update set scope_note = excluded.scope_note, limit_note = excluded.limit_note, active = true;

insert into public.function_owner (function_slug, owner, note)
values ('conversation_archive', 'sales_engineer',
        'Renders every saved conversation message (email in and out, WhatsApp, chat, forms) to a PDF in the private backups bucket and hands it to the doc_backups Dropbox conveyor; backfills the emails still inside Resend''s month. Driven by resilience_ping every 15 minutes. Founder, 14 Sep 2026.')
on conflict (function_slug) do update set note = excluded.note;

update public.internal_credential set scope = array_append(scope, 'conversation_archive')
 where context = 'fn.resilience_ping' and not (scope @> array['conversation_archive']);

-- ── 9. THE PROBE: READS ONLY, SO IT CAN END IN A NOTICE ────────────────────────────────────────
do $probe$
declare v_rec jsonb; v_long integer; v_view integer; v_tbl integer; v_demo integer; v_b jsonb;
begin
  select count(*) into v_view from public.v_conversation_message where source_table = 'inbound_messages';
  select count(*) into v_tbl from public.inbound_messages;
  if v_view <> v_tbl then raise exception 'the view lost inbound email: % of %', v_view, v_tbl; end if;
  select count(*) into v_view from public.v_conversation_message where source_table = 'wa_messages';
  select count(*) into v_tbl from public.wa_messages;
  if v_view <> v_tbl then raise exception 'the view lost WhatsApp rows: % of %', v_view, v_tbl; end if;
  select count(*) into v_view from public.v_conversation_message where source_table = 'assistant_logs';
  select count(*) into v_tbl from public.assistant_logs;
  if v_view <> v_tbl then raise exception 'the view lost assistant rows: % of %', v_view, v_tbl; end if;

  v_rec := public.fn_conversation_record('management@quotesdone.com', 500);
  select count(*) into v_long from jsonb_array_elements(v_rec->'messages') m where length(m->>'body') > 140;
  if v_long = 0 then raise exception 'fn_conversation_record returned no message longer than a 140-character summary'; end if;

  select count(*) into v_demo from public.fn_conversation_archive_pending(200) where is_demo;
  if v_demo <> 0 then raise exception 'a demo row reached the archive queue'; end if;

  if not exists (select 1 from public.ceo_standing_grant where grant_key = 'sales.conversation_record' and active) then
    raise exception 'the sales engineer has no grant to read conversations'; end if;
  if not exists (select 1 from public.internal_credential where context = 'fn.resilience_ping' and scope @> array['conversation_archive']) then
    raise exception 'the heartbeat cannot call conversation_archive'; end if;

  v_b := public.fn_conversation_retention_breaches(interval '0 seconds');
  raise notice 'CONVERSATIONS: % messages for management@ (% longer than 140 chars, i.e. full text); % stored conversation messages awaiting their first PDF (the heartbeat renders them); breaches at zero grace: %',
    v_rec->>'message_count', v_long, (select count(*) from public.fn_conversation_archive_pending(200)), v_b;
end
$probe$;
