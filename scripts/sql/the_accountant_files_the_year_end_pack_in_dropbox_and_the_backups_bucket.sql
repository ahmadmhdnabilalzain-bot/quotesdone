-- THE ACCOUNTANT FILES THE YEAR-END PACK IN DROPBOX AND IN THE BACKUPS BUCKET, AND THE IT ENGINEER CHECKS IT.
--
-- Assigned: accountant (the pack and its filing); the it_engineer verifies the upload through the backup loop
-- it already runs. Founder, 14 Sep 2026: "add all for accountant and IT" — duty 4 of the five further
-- accountant duties: the ledger, the bank reconciliations, the invoices, the refunds and the disputes filed in
-- Dropbox on the existing tree (entity -> type -> date) and in the private Supabase `backups` bucket.
--
-- WHAT WAS MEASURED (14 Sep 2026, main at #645 + 297d29c):
--   * Four of the accountant's file columns were registered in fn_backup_source_registry as 'OPEN GAP: ...
--     not yet in the Dropbox tree': accountant_month_close.pdf_path and .csv_path (the close the CEO signs
--     for), accountant_issued_document.file_path (what was issued in the founder's name) and
--     bank_statement_intake.doc_path (the Mashreq statements, saved as 'receipt-files/bank/...').
--   * Nothing produced a year: no ledger export, no reconciliation listing, no refunds or disputes register.
--     The Stripe invoices themselves are already filed (fn_enqueue_doc_backups: REVENUE INVOICES).
--
-- WHAT THIS BUILDS:
--   accountant_year_end_pack          one row per financial year: the files the runtime wrote to backups/
--                                     accountant/year-end/<year>/ and when
--   fn_accountant_year_end_pack_document(year)  seven CSVs from the books: ledger (every journal line),
--       bank reconciliation (Stripe payouts against the Mashreq lines), bank statements, invoices, refunds,
--       disputes and the month closes. ZZ DEMO rows are left out. The runtime (action 'duties') uploads them.
--   fn_accountant_year_end_pack_attach / _due / _tick   the runtime records the files; from gl_settings
--       year_end_pack_day in January the pack for the year before is due, and two days late it is an
--       accountant finding round the IT loop until it is filed.
--   fn_enqueue_doc_backups gains ACCOUNTING (section 5), which files the four gap columns and the year-end
--       pack under /QuotesDone Backup/Finance/. The it_engineer's expected list, fn_it_backup_expected, is NOT
--       defined here: every_stored_document_source_is_registered_for_backup.sql owns it, expects the same
--       files, and is applied after this file. The registry rows flip to backed up in that file too.
--
-- WHAT IT DOES NOT DO. No corporate tax schedule and no VAT return (founder, 14 Sep 2026; no VAT until the
-- AED 375,000 threshold). It does not close the other OPEN GAPs (refunds.doc_path, supplier_dues letters):
-- the refunds and disputes are in the pack as registers, not as their documents.
--
--   node scripts/apply_sql.mjs scripts/sql/the_accountant_files_the_year_end_pack_in_dropbox_and_the_backups_bucket.sql --apply --ddl

create table if not exists public.accountant_year_end_pack (
  year        int         primary key check (year >= 2000),
  files       jsonb       not null default '[]'::jsonb check (jsonb_typeof(files) = 'array'),
  rendered_at timestamptz,
  created_at  timestamptz not null default now()
);
comment on table public.accountant_year_end_pack is
  'One row per financial year: the year-end CSVs (ledger, bank reconciliation, statements, invoices, refunds, disputes, month closes) the accountant wrote to the backups bucket, each {name, bucket, path}. fn_enqueue_doc_backups files them in Dropbox under Finance/Year End/<year>.';
alter table public.accountant_year_end_pack enable row level security;
drop policy if exists accountant_year_end_pack_service_role_only on public.accountant_year_end_pack;
create policy accountant_year_end_pack_service_role_only on public.accountant_year_end_pack
  as permissive for all to public using (false) with check (false);
revoke all on public.accountant_year_end_pack from anon, authenticated;

insert into public.gl_settings (key, num_value, txt_value) values
  ('year_end_pack_day', 15, 'Day of January (Dubai) from which the accountant files the year-end pack for the year before.'),
  ('year_end_pack_first_year', 2026, 'The first financial year QuotesDone traded; no pack is due for an earlier year.')
on conflict (key) do nothing;

-- ── 1. ONE CSV ROW, EVERY CELL QUOTED ────────────────────────────────────────────────────────────
-- A null is an empty quoted cell, so a missing value never shifts the columns after it.
create or replace function public.fn_accountant_csv_row(variadic p_cells text[])
returns text language sql immutable set search_path to 'public', 'pg_temp' as $fn$
  select string_agg('"' || replace(coalesce(c, ''), '"', '""') || '"', ',' order by i)
    from unnest(p_cells) with ordinality u(c, i)
$fn$;
revoke execute on function public.fn_accountant_csv_row(text[]) from public, anon, authenticated;

-- ── 2. THE PACK, FROM THE BOOKS ──────────────────────────────────────────────────────────────────
create or replace function public.fn_accountant_year_end_pack_document(p_year int)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_d0 date := make_date(p_year, 1, 1); v_d1 date := make_date(p_year, 12, 31);
  v_t0 timestamptz := make_date(p_year, 1, 1)::timestamp at time zone 'Asia/Dubai';
  v_t1 timestamptz := make_date(p_year + 1, 1, 1)::timestamp at time zone 'Asia/Dubai';
  v_ledger text; v_rec text; v_stmt text; v_inv text; v_ref text; v_dis text; v_close text;
begin
  select coalesce(string_agg(public.fn_accountant_csv_row(j.entry_no, j.entry_date::text, j.status, j.source, j.source_ref, j.memo,
                    l.line_no::text, l.account_code, a.name, l.debit::text, l.credit::text, l.memo),
                    E'\n' order by j.entry_date, j.id, l.line_no), '')
    into v_ledger
    from public.gl_journal j join public.gl_journal_lines l on l.journal_id = j.id left join public.gl_accounts a on a.code = l.account_code
   where j.entry_date between v_d0 and v_d1
     and coalesce(j.source, '') <> 'zz_demo' and coalesce(j.memo, '') !~* 'zz[ _-]?demo';

  select coalesce(string_agg(public.fn_accountant_csv_row(p.id, p.arrival_date::text, (p.amount_fils / 100.0)::text, p.currency, p.status,
                    p.bank_line_id::text, b.value_date::text, b.amount_aed::text, b.description, p.matched_at::text),
                    E'\n' order by p.arrival_date, p.id), '')
    into v_rec
    from public.stripe_payout p left join public.bank_statement_line b on b.id = p.bank_line_id
   where p.livemode and p.arrival_date between v_d0 and v_d1;

  select coalesce(string_agg(public.fn_accountant_csv_row(s.source_ref, s.account, s.statement_month::text, s.state, s.lines::text,
                    s.closing_balance_aed::text, s.balance_on::text, s.doc_path, s.received_at::text),
                    E'\n' order by s.received_at), '')
    into v_stmt
    from public.bank_statement_intake s
   where s.account <> 'zz_demo' and coalesce(s.statement_month, (s.received_at at time zone 'Asia/Dubai')::date) between v_d0 and v_d1;

  select coalesce(string_agg(public.fn_accountant_csv_row(t.id::text, t.revealed_at::text, t.stripe_invoice_number, t.stripe_invoice_id,
                    t.total_charged::text, t.reveal_fee::text, t.fee_status, t.doc_path),
                    E'\n' order by t.revealed_at, t.id), '')
    into v_inv
    from public.transactions t left join public.customers c on c.id = t.customer_id
   where t.revealed_at >= v_t0 and t.revealed_at < v_t1 and t.fee_status in ('paid', 'refunded') and not coalesce(c.is_demo, false);

  select coalesce(string_agg(public.fn_accountant_csv_row(r.id::text, r.requested_at::text, r.status, (r.amount_fils / 100.0)::text,
                    r.currency, r.reason_code, r.decided_by, r.settled_at::text, r.stripe_refund_id, r.doc_path),
                    E'\n' order by r.created_at, r.id), '')
    into v_ref
    from public.refunds r left join public.customers c on c.id = r.customer_id
   where r.created_at >= v_t0 and r.created_at < v_t1 and not coalesce(c.is_demo, false);

  select coalesce(string_agg(public.fn_accountant_csv_row(d.id, d.first_seen_at::text, d.reason, d.status, (d.amount_fils / 100.0)::text,
                    d.currency, d.evidence_due_by::text, d.evidence_submitted_at::text, d.submit_trigger, d.outcome, d.closed_at::text),
                    E'\n' order by d.first_seen_at, d.id), '')
    into v_dis
    from public.stripe_dispute d
   where d.livemode and d.first_seen_at >= v_t0 and d.first_seen_at < v_t1;

  select coalesce(string_agg(public.fn_accountant_csv_row(to_char(c.month, 'YYYY-MM'), c.closed_at::text, c.ceo_report_id::text,
                    c.pdf_bucket, c.pdf_path, c.csv_path, c.figures#>>'{profit_and_loss,net_result_aed}'),
                    E'\n' order by c.month), '')
    into v_close
    from public.accountant_month_close c
   where c.month between v_d0 and v_d1;

  return jsonb_build_object('year', p_year, 'folder', 'accountant/year-end/' || p_year,
    'files', jsonb_build_array(
      jsonb_build_object('name', p_year || ' Ledger.csv', 'csv',
        'entry_no,entry_date,status,source,source_ref,memo,line_no,account_code,account_name,debit_aed,credit_aed,line_memo' || E'\n' || v_ledger),
      jsonb_build_object('name', p_year || ' Bank reconciliation.csv', 'csv',
        'payout,arrival_date,amount,currency,status,bank_line_id,bank_value_date,bank_amount_aed,bank_description,matched_at' || E'\n' || v_rec),
      jsonb_build_object('name', p_year || ' Bank statements.csv', 'csv',
        'source_ref,account,statement_month,state,lines,closing_balance_aed,balance_on,doc_path,received_at' || E'\n' || v_stmt),
      jsonb_build_object('name', p_year || ' Invoices.csv', 'csv',
        'transaction,revealed_at,stripe_invoice_number,stripe_invoice_id,total_charged_aed,reveal_fee_aed,fee_status,doc_path' || E'\n' || v_inv),
      jsonb_build_object('name', p_year || ' Refunds.csv', 'csv',
        'refund,requested_at,status,amount,currency,reason_code,decided_by,settled_at,stripe_refund_id,doc_path' || E'\n' || v_ref),
      jsonb_build_object('name', p_year || ' Disputes.csv', 'csv',
        'dispute,first_seen_at,reason,status,amount,currency,evidence_due_by,evidence_submitted_at,submit_trigger,outcome,closed_at' || E'\n' || v_dis),
      jsonb_build_object('name', p_year || ' Month closes.csv', 'csv',
        'month,closed_at,ceo_report_id,pdf_bucket,pdf_path,csv_path,net_result_aed' || E'\n' || v_close)));
end $fn$;
revoke execute on function public.fn_accountant_year_end_pack_document(int) from public, anon, authenticated;

-- ── 3. DUE, FILED, AND LATE ──────────────────────────────────────────────────────────────────────
create or replace function public.fn_accountant_year_end_pack_due()
returns int language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select z.y from (select extract(year from (now() at time zone 'Asia/Dubai'))::int - 1 as y) z
   where z.y >= coalesce((select num_value::int from public.gl_settings where key = 'year_end_pack_first_year'), 2026)
     and extract(doy from (now() at time zone 'Asia/Dubai')) >= coalesce((select num_value::int from public.gl_settings where key = 'year_end_pack_day'), 15)
     and not exists (select 1 from public.accountant_year_end_pack p where p.year = z.y and p.rendered_at is not null)
$fn$;
revoke execute on function public.fn_accountant_year_end_pack_due() from public, anon, authenticated;

-- p_files: [{name, bucket, path}], what the runtime uploaded. Filing is queued at once.
create or replace function public.fn_accountant_year_end_pack_attach(p_year int, p_files jsonb)
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
begin
  if jsonb_typeof(p_files) is distinct from 'array' or jsonb_array_length(p_files) = 0
     or exists (select 1 from jsonb_array_elements(p_files) f
                 where coalesce(f->>'name', '') = '' or coalesce(f->>'bucket', '') = '' or coalesce(f->>'path', '') = '') then
    raise exception 'a year-end pack is recorded only with every file''s name, bucket and path';
  end if;
  insert into public.accountant_year_end_pack (year, files, rendered_at) values (p_year, p_files, now())
  on conflict (year) do update set files = excluded.files, rendered_at = now();
  return jsonb_build_object('ok', true, 'year', p_year, 'files', jsonb_array_length(p_files), 'enqueued', public.fn_enqueue_doc_backups());
end $fn$;
revoke execute on function public.fn_accountant_year_end_pack_attach(int, jsonb) from public, anon, authenticated;

-- Two days after the pack fell due and still not filed: an accountant finding until the runtime files it.
-- Once filed, whether each file reached Dropbox is the it_engineer's to verify (section 6).
create or replace function public.fn_accountant_year_end_tick()
returns jsonb language plpgsql security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_y int := public.fn_accountant_year_end_pack_due();
  v_day int := coalesce((select num_value::int from public.gl_settings where key = 'year_end_pack_day'), 15);
  v_items jsonb := '[]'::jsonb;
begin
  if v_y is not null and extract(doy from (now() at time zone 'Asia/Dubai')) >= v_day + 2 then
    v_items := jsonb_build_array(jsonb_build_object('item', 'unfiled:' || v_y, 'owner_seat', 'accountant', 'subject', 'accountant_year_end_pack',
      'title', 'The ' || v_y || ' year-end pack (ledger, bank reconciliations, invoices, refunds, disputes) is not filed: the accountant runtime has not written it to the backups bucket',
      'blast', 'agent_facing', 'affected', 1, 'evidence', jsonb_build_object('year', v_y)));
  end if;
  return jsonb_build_object('due_year', v_y, 'findings', public.fn_accountant_duty_settle('year_end', v_items));
end $fn$;
revoke execute on function public.fn_accountant_year_end_tick() from public, anon, authenticated;

-- ── 5. FILED IN DROPBOX: fn_enqueue_doc_backups, the MANIFEST-last definition
-- (every_conversation_is_kept_backed_up_twice_and_readable_by_the_sales_engineer.sql) copied VERBATIM with
-- ONE section added before the return - ACCOUNTING. Every earlier section is unchanged.
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
  on conflict (dedupe_key) do nothing;
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
  on conflict (dedupe_key) do nothing;
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
  on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  insert into public.doc_backups(entity,entity_id,doc_type,bucket,path,file_name,dropbox_path,source,dedupe_key)
  select 'company', 'year_end:' || p.year, 'Year-end pack', f->>'bucket', f->>'path', f->>'name',
         '/QuotesDone Backup/Finance/Year End/' || p.year || '/' || (f->>'name'),
         'storage', 'ACCT:year_end:' || p.year || ':' || (f->>'name')
  from public.accountant_year_end_pack p cross join lateral jsonb_array_elements(p.files) f
  where p.rendered_at is not null and (f->>'path') !~* 'zz[_ -]?demo'
  on conflict (dedupe_key) do nothing;
  get diagnostics m = row_count; n := n + m;

  return n;
end $function$;

revoke execute on function public.fn_enqueue_doc_backups() from public, anon, authenticated;

