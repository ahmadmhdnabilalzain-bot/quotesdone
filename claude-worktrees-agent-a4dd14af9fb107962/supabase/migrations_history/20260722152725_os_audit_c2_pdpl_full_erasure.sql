-- Recovered from production's migration ledger by scripts/recover_missing_migrations.mjs.
-- Applied version: 20260722152725   name: os_audit_c2_pdpl_full_erasure
-- This file was never committed; its SQL is the text schema_migrations recorded when it ran.

-- C2: PDPL right-to-erasure — extend redaction to free-text surfaces + queue Dropbox/storage files for external deletion.
create table if not exists public.pdpl_erase_files (
  id bigserial primary key,
  request_id uuid not null references public.pdpl_requests(id) on delete cascade,
  subject_email text not null,
  bucket text,
  storage_path text,
  dropbox_path text,
  origin text,
  status text not null default 'pending',
  error text,
  created_at timestamptz not null default now(),
  erased_at timestamptz
);
alter table public.pdpl_erase_files enable row level security;
create index if not exists idx_pdpl_erase_files_req on public.pdpl_erase_files(request_id, status);
revoke all on public.pdpl_erase_files from public, anon, authenticated;

create or replace function public.fn_pdpl_redact(p_request_id uuid)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_email text; v_status text;
  v_cust_ids uuid[]; v_phones text[]; v_inq_ids uuid[]; v_quote_ids uuid[];
  c_cust int:=0; c_lead int:=0; c_notif int:=0; c_out int:=0; c_ev int:=0; c_pv int:=0; c_ai int:=0;
  c_msg int:=0; c_inb int:=0; c_wa int:=0; c_inq int:=0; c_rfq int:=0; c_doc int:=0; c_files int:=0;
begin
  select email, status into v_email, v_status from public.pdpl_requests where id=p_request_id;
  if not found then raise exception 'pdpl request % not found', p_request_id; end if;
  if coalesce(v_status,'') <> 'approved' then
    raise exception 'pdpl request % must be status=approved before redaction (current: %)', p_request_id, coalesce(v_status,'null');
  end if;
  if v_email is null then raise exception 'pdpl request % has no email', p_request_id; end if;

  -- resolve subject linkage BEFORE mutating identity fields
  select coalesce(array_agg(id),'{}'), coalesce(array_agg(phone) filter (where phone is not null),'{}')
    into v_cust_ids, v_phones from public.customers where email=v_email;
  select coalesce(array_agg(id),'{}') into v_inq_ids from public.inquiries where customer_id = any(v_cust_ids);
  select coalesce(array_agg(id),'{}') into v_quote_ids from public.quotes where inquiry_id = any(v_inq_ids);

  -- queue Dropbox/storage copies for external erasure BEFORE nulling any file paths
  insert into public.pdpl_erase_files(request_id,subject_email,bucket,storage_path,dropbox_path,origin)
  select p_request_id, v_email, db.bucket, db.path, db.dropbox_path, 'doc_backups:'||coalesce(db.entity,'?')
    from public.doc_backups db
   where (db.entity='customer' and db.entity_id = any(v_cust_ids::text[]))
      or (db.entity='inquiry'  and db.entity_id = any(v_inq_ids::text[]))
      or (db.entity='quote'    and db.entity_id = any(v_quote_ids::text[]));
  insert into public.pdpl_erase_files(request_id,subject_email,bucket,storage_path,dropbox_path,origin)
  select p_request_id, v_email, d.bucket, d.path,
         (select db.dropbox_path from public.doc_backups db where db.bucket=d.bucket and db.path=d.path limit 1),
         'documents:'||coalesce(d.ref_table,'?')
    from public.documents d
   where (d.ref_table='inquiries' and d.ref_id = any(v_inq_ids::text[]))
      or (d.ref_table='quotes'    and d.ref_id = any(v_quote_ids::text[]))
      or (d.ref_table='customers' and d.ref_id = any(v_cust_ids::text[]));
  insert into public.pdpl_erase_files(request_id,subject_email,bucket,storage_path,dropbox_path,origin)
  select p_request_id, v_email, r.bucket, r.archive_path,
         (select db.dropbox_path from public.doc_backups db where db.bucket=r.bucket and db.path=r.archive_path limit 1),
         'rfq_archive'
    from public.rfq_archives r
   where r.customer_id = any(v_cust_ids::text[]);

  -- structured identity tables (existing behaviour, unchanged)
  update public.customers set full_name='[erased-PDPL]', phone=null, date_of_birth=null,
         email='erased_'||id||'@removed.invalid' where email=v_email;
  get diagnostics c_cust = row_count;
  update public.leads set phone=null, whatsapp=null, email=null, matching_blocked=true where email=v_email;
  get diagnostics c_lead = row_count;
  update public.notifications set to_email='[erased]', to_phone=null where to_email=v_email;
  get diagnostics c_notif = row_count;
  update public.outreach set email='[erased]' where email=v_email;
  get diagnostics c_out = row_count;
  update public.email_verifications set email='[erased]' where email=v_email;
  get diagnostics c_ev = row_count;
  update public.phone_verifications set email='[erased]' where email=v_email;
  get diagnostics c_pv = row_count;
  update public.ai_usage set email='[erased]' where email=v_email;
  get diagnostics c_ai = row_count;

  -- free-text conversation / archive surfaces (C2 closure)
  update public.messages set body='[erased-PDPL]', redacted_body='[erased-PDPL]'
    where customer_id = any(v_cust_ids);
  get diagnostics c_msg = row_count;
  update public.inbound_messages set from_email='[erased]', to_email='[erased]', subject='[erased]',
         body='[erased-PDPL]', ai_draft_reply=null, ai_summary=null, ai_notes=null, raw='{}'::jsonb
    where from_email=v_email or to_email=v_email;
  get diagnostics c_inb = row_count;
  if array_length(v_phones,1) is not null then
    update public.wa_messages set wa_from='[erased]', wa_to='[erased]', profile_name='[erased]',
           inbound='[erased-PDPL]', reply='[erased-PDPL]', meta='{}'::jsonb
      where wa_from = any(v_phones) or wa_to = any(v_phones);
    get diagnostics c_wa = row_count;
  end if;
  update public.inquiries set raw_input='[erased-PDPL]', summary='[erased-PDPL]', spec='{}'::jsonb,
         drawing_file_name=null, drawing_file_path=null
    where id = any(v_inq_ids);
  get diagnostics c_inq = row_count;
  update public.rfq_archives set ai_summary='{}'::jsonb where customer_id = any(v_cust_ids::text[]);
  get diagnostics c_rfq = row_count;
  update public.documents set extracted='{}'::jsonb, status='erased'
    where (ref_table='inquiries' and ref_id = any(v_inq_ids::text[]))
       or (ref_table='quotes'    and ref_id = any(v_quote_ids::text[]))
       or (ref_table='customers' and ref_id = any(v_cust_ids::text[]));
  get diagnostics c_doc = row_count;

  update public.pdpl_requests set status='completed', handled_at=now(),
         handled_by=coalesce(handled_by,'fn_pdpl_redact') where id=p_request_id;
  select count(*) into c_files from public.pdpl_erase_files where request_id=p_request_id;

  insert into public.security_events(kind,severity,source,subject,detail)
  values('pdpl_redaction','high','pdpl', v_email,
    jsonb_build_object('request_id',p_request_id,'customers',c_cust,'leads',c_lead,'notifications',c_notif,
      'outreach',c_out,'email_verifications',c_ev,'phone_verifications',c_pv,'ai_usage',c_ai,
      'messages',c_msg,'inbound_messages',c_inb,'wa_messages',c_wa,'inquiries',c_inq,'rfq_archives',c_rfq,
      'documents',c_doc,'files_queued_for_erasure',c_files));

  return jsonb_build_object('subject',v_email,
    'redacted', jsonb_build_object('customers',c_cust,'supplier_leads',c_lead,'notifications',c_notif,
      'outreach',c_out,'email_verifications',c_ev,'phone_verifications',c_pv,'ai_usage',c_ai,
      'messages',c_msg,'inbound_messages',c_inb,'wa_messages',c_wa,'inquiries',c_inq,
      'rfq_archives',c_rfq,'documents',c_doc),
    'files_queued_for_erasure', c_files,
    'files_note','Dropbox/storage copies queued in pdpl_erase_files; run dropbox_backup {op:pdpl_erase, request_id} to delete them.',
    'kept','email_suppressions retained as do-not-contact');
end $function$;

revoke all on function public.fn_pdpl_redact(uuid) from public, anon, authenticated;
grant execute on function public.fn_pdpl_redact(uuid) to service_role;
