-- THE ACCOUNTANT RETRIEVES THE STRIPE INVOICE AND FILES IT.
--
-- THE FOUNDER, 9 SEPTEMBER 2026, INSTRUCTION 28, IN HIS WORDS:
--
--   "stripe automatically generates an invoice as far as i know, our accountant need to retrieve
--    that and be connected, then add it to his records, sync it with back up on dropbox. if a
--    refund was requested, then scenario B initiates which we already discussed it earlier."
--
-- Scenario B -- the refund chain (supplier_response_watch, fn_refund_nonresponse_eligibility,
-- fn_supplier_nonresponse_penalty, and the two guards that bind a refund to its one approval and
-- its one Stripe payment) -- is already built and is deliberately untouched here. This file closes
-- the other half of his sentence: RETRIEVE, RECORD, MIRROR.
--
-- ── WHAT CHANGED UPSTREAM, AND WHY THIS FILE CAN EXIST NOW ─────────────────────────────────────
--
-- Earlier today `a_refund_names_the_one_approval_and_the_one_stripe_payment_it_reverses.sql` said,
-- correctly at the time: "stripe_checkout creates the reveal-fee session with mode=payment and NO
-- invoice_creation, so Stripe produces no Invoice object for a reveal fee and there is therefore no
-- invoice_pdf to fetch." The founder said Stripe does issue one. He was right and the estate was
-- wrong -- it is a SETTING, and it was off. supabase/functions/stripe_checkout now sets
-- invoice_creation[enabled]=true with a description, a DET-licence footer and metadata, and that
-- was validated against the live Stripe account (a session came back with invoice_creation.enabled
-- true, and was expired immediately without being payable).
--
-- So from the next paid reveal onward, `checkout.session.completed` carries an `invoice` id, and
-- that invoice carries a real `invoice_pdf`. This file gives that PDF somewhere to live, ties it to
-- the revenue record the books already point at, and puts it on the existing Dropbox conveyor.
--
-- ── WHERE THE INVOICE ATTACHES, AND WHY NOT TO gl_journal ──────────────────────────────────────
--
-- fn_gl_sync_business books reveal-fee revenue as source='reveal_fee', source_ref=transactions.id
-- (accounts 1050/6100 debit, 4000 credit), and supplier registration as source='subscription'.
-- The journal row therefore ALREADY points at the transaction. Hanging the document off
-- gl_journal would mean the document is attached to the bookkeeping rather than to the sale, and a
-- re-post, a reversal or a second journal line would orphan it. public.transactions is the record
-- of the sale, it is what the journal cites, and it is what the refund guards already cite through
-- refunds.transaction_id. One document, one row, everything else points at it.
--
-- The columns are the SAME FIVE public.expense_entries carries for its 48 receipts and that
-- public.refunds gained this morning -- doc_path / doc_name / doc_content_type / doc_kind /
-- doc_note -- because one shape across finance means one habit, one view, one coverage function
-- and one door in the accountant seat. A sixth set of column names would be a sixth thing to learn.
--
-- ── WHY THE HANDLER ASKS RATHER THAN WRITES ────────────────────────────────────────────────────
--
-- fn_transaction_attach_invoice is the same delegation fn_refund_attach_receipt is, for the same
-- reason and with the same guard: a URL that the founder and the CEO will open as EVIDENCE may not
-- be pointed somewhere else by a webhook payload, so both stripe.com URLs are pattern-checked
-- before they are stored, and the stored object path is required to sit under the invoices/ prefix
-- of finance-docs. It is write-once on the invoice identity -- the first invoice a transaction was
-- billed under is the one it stays billed under -- while still allowing the FILE to arrive later
-- than the REFERENCE, which is the ordinary case when Stripe finalises the PDF a moment after the
-- session completes.
--
-- ── THE MIRROR ─────────────────────────────────────────────────────────────────────────────────
--
-- No second backup mechanism is built. public.doc_backups + fn_enqueue_doc_backups + the
-- dropbox_backup edge function already carry every stored document to Dropbox, and
-- fn_dropbox_backup_due is polled every 15 minutes by resilience_ping. fn_enqueue_doc_backups gains
-- ONE block, in the same ON CONFLICT (dedupe_key) DO NOTHING shape as the other six, so an invoice
-- is queued because its doc_path is non-null -- not because a particular writer remembered to queue
-- it. A backfill, a hand-repair or a future path all enqueue by the same rule.
--
-- ── WHAT THIS FILE CANNOT PROVE ────────────────────────────────────────────────────────────────
--
-- There are 0 transactions and 0 Stripe invoices in this account today. Nothing here can be proved
-- on real money. The probe at the bottom therefore proves the SHAPE on a synthetic transaction
-- inside a subtransaction it rolls back itself -- the columns, the path guard, the URL guards, the
-- write-once rule, the view's four states, the coverage arithmetic and the Dropbox enqueue -- and
-- removes every row it made, including the rows the transaction's own triggers made. What remains
-- unproven until the first real payment is stated plainly in the report, not papered over.

-- ── 1. THE INVOICE LIVES WITH THE SALE ─────────────────────────────────────────────────────────
alter table public.transactions
  add column if not exists stripe_invoice_id        text,
  add column if not exists stripe_invoice_number    text,
  add column if not exists stripe_invoice_status    text,
  add column if not exists stripe_invoice_total_fils bigint,
  add column if not exists stripe_invoice_currency  text,
  add column if not exists stripe_invoice_pdf_url   text,
  add column if not exists stripe_invoice_hosted_url text,
  add column if not exists doc_path                 text,
  add column if not exists doc_name                 text,
  add column if not exists doc_content_type         text,
  add column if not exists doc_kind                 text,
  add column if not exists doc_note                 text;

comment on column public.transactions.stripe_invoice_id is
  'The Stripe Invoice object (in_...) this reveal fee was billed under. Written once, by '
  'fn_transaction_attach_invoice, from a signature-verified checkout.session.completed. NULL on any '
  'transaction paid before invoice_creation was enabled on 9 Sep 2026 -- an honest gap, counted by '
  'fn_revenue_document_coverage rather than left blank.';
comment on column public.transactions.stripe_invoice_pdf_url is
  'Stripe''s own invoice_pdf link. A REFERENCE, not the document: it is Stripe-hosted and can expire '
  'or move. The durable copy is doc_path in finance-docs, which is what reaches Dropbox.';
comment on column public.transactions.stripe_invoice_total_fils is
  'The invoice total as Stripe states it, in the smallest unit of stripe_invoice_currency. Stored '
  'beside reveal_fee rather than instead of it, so a disagreement between what we charged and what '
  'Stripe billed is visible instead of averaged away.';
comment on column public.transactions.doc_path is
  'Object path in the private finance-docs bucket for the stored Stripe invoice PDF, under the '
  'invoices/ prefix. NULL means no file is held; v_revenue_documents reports it rather than leaving '
  'a blank cell somebody notices months later.';
comment on column public.transactions.doc_kind is
  'What the stored document IS: stripe_invoice. NULL alongside a doc_path is ''unclassified'' -- a '
  'file whose writer did not say what it was.';

-- ── 2. THE HANDLER ASKS; THE DATABASE DECIDES ──────────────────────────────────────────────────
-- Same delegation as fn_refund_attach_receipt, same reasons. The invoice object is passed whole,
-- as Stripe returns it, so the handler does not get to decide which fields count.
create or replace function public.fn_transaction_attach_invoice(
  p_transaction_id  uuid,
  p_invoice         jsonb,
  p_doc_path        text default null,
  p_doc_name        text default null,
  p_doc_content_type text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_inv_id   text := nullif(btrim(coalesce(p_invoice->>'id','')), '');
  v_pdf      text := nullif(btrim(coalesce(p_invoice->>'invoice_pdf','')), '');
  v_hosted   text := nullif(btrim(coalesce(p_invoice->>'hosted_invoice_url','')), '');
  v_path     text := nullif(btrim(coalesce(p_doc_path,'')), '');
  v_existing public.transactions%rowtype;
  v_rows     integer;
begin
  if p_transaction_id is null then
    return jsonb_build_object('ok', false, 'reason', 'no transaction id');
  end if;
  if v_inv_id is null then
    return jsonb_build_object('ok', false, 'reason', 'the invoice object carries no id');
  end if;
  -- A Stripe Invoice id is in_...; anything else is not the object this column names, and a column
  -- the accountant reconciles against Stripe must not hold something Stripe cannot resolve.
  if v_inv_id !~ '^in_[A-Za-z0-9_]+$' then
    return jsonb_build_object('ok', false, 'reason', 'not a stripe invoice id',
                              'given', left(v_inv_id, 60));
  end if;

  -- Both links are opened as evidence by the founder and the CEO. A spoofed payload may not aim
  -- them anywhere but Stripe. Same pattern fn_refund_attach_receipt uses, and it refuses lookalikes
  -- such as stripe.com.evil.example because the host must END at stripe.com before the first slash.
  if v_pdf is not null and v_pdf !~ '^https://[a-z0-9.-]*\.?stripe\.com/' then
    return jsonb_build_object('ok', false, 'reason', 'invoice_pdf is not a stripe.com url',
                              'given', left(v_pdf, 120));
  end if;
  if v_hosted is not null and v_hosted !~ '^https://[a-z0-9.-]*\.?stripe\.com/' then
    return jsonb_build_object('ok', false, 'reason', 'hosted_invoice_url is not a stripe.com url',
                              'given', left(v_hosted, 120));
  end if;

  -- The stored object is named by its PREFIX, not by a free path. A caller that could name any path
  -- in finance-docs could make this row point at another record's document.
  if v_path is not null and v_path !~ '^invoices/' then
    return jsonb_build_object('ok', false, 'reason', 'a stored invoice must live under invoices/ in finance-docs',
                              'given', left(v_path, 120));
  end if;

  select * into v_existing from public.transactions where id = p_transaction_id;
  if not found then
    return jsonb_build_object('ok', false,
             'reason', format('no transaction %s', p_transaction_id));
  end if;

  -- WRITE-ONCE ON IDENTITY. The first invoice a sale was billed under is the one it stays billed
  -- under; a second, different invoice id is a fact about a different sale and is refused rather
  -- than allowed to overwrite the reference the books were reconciled against.
  if coalesce(v_existing.stripe_invoice_id, '') <> '' and v_existing.stripe_invoice_id <> v_inv_id then
    return jsonb_build_object('ok', false, 'reason', 'this transaction is already billed under another invoice',
                              'existing', v_existing.stripe_invoice_id, 'given', v_inv_id);
  end if;

  -- The FILE may arrive after the REFERENCE -- Stripe finalises the PDF moments after the session
  -- completes -- so the document columns fill in on a later call without disturbing what is set.
  update public.transactions t set
    stripe_invoice_id         = v_inv_id,
    stripe_invoice_number     = coalesce(nullif(btrim(coalesce(p_invoice->>'number','')),''), t.stripe_invoice_number),
    stripe_invoice_status     = coalesce(nullif(btrim(coalesce(p_invoice->>'status','')),''), t.stripe_invoice_status),
    stripe_invoice_total_fils = coalesce((p_invoice->>'total')::bigint, t.stripe_invoice_total_fils),
    stripe_invoice_currency   = coalesce(upper(nullif(btrim(coalesce(p_invoice->>'currency','')),'')), t.stripe_invoice_currency),
    stripe_invoice_pdf_url    = coalesce(v_pdf, t.stripe_invoice_pdf_url),
    stripe_invoice_hosted_url = coalesce(v_hosted, t.stripe_invoice_hosted_url),
    doc_path                  = coalesce(t.doc_path, v_path),
    doc_name                  = coalesce(t.doc_name, nullif(btrim(coalesce(p_doc_name,'')),'')),
    doc_content_type          = coalesce(t.doc_content_type, nullif(btrim(coalesce(p_doc_content_type,'')),'')),
    doc_kind                  = case when t.doc_path is null and v_path is not null then 'stripe_invoice'
                                     else t.doc_kind end
  where t.id = p_transaction_id;
  get diagnostics v_rows = row_count;

  return jsonb_build_object(
    'ok', v_rows > 0,
    'transaction_id', p_transaction_id,
    'invoice_id', v_inv_id,
    'stored', v_path is not null or coalesce(v_existing.doc_path,'') <> '',
    'state', (select document_state from public.v_revenue_documents where id = p_transaction_id));
end
$fn$;

revoke execute on function public.fn_transaction_attach_invoice(uuid, jsonb, text, text, text)
  from public, anon, authenticated;

comment on function public.fn_transaction_attach_invoice(uuid, jsonb, text, text, text) is
  'The one door from a Stripe Invoice to the sale it billed. Refuses an id that is not in_..., a '
  'pdf or hosted URL that is not stripe.com, and a stored path outside invoices/ in finance-docs; '
  'write-once on the invoice identity, while letting the stored FILE arrive after the REFERENCE. '
  'stripe_webhook calls this rather than writing to transactions itself, for the same reason it '
  'calls fn_refund_attach_receipt rather than writing to refunds: one set of rules, in one place.';

-- ── 3. THE STATE OF THE EVIDENCE, PER SALE ─────────────────────────────────────────────────────
create or replace view public.v_revenue_documents as
select
  t.id,
  t.quote_id,
  t.customer_id,
  t.supplier_id,
  t.revealed_at,
  t.fee_status,
  t.reveal_fee,
  t.payment_ref,
  t.refund_status,
  t.stripe_invoice_id,
  t.stripe_invoice_number,
  t.stripe_invoice_status,
  t.stripe_invoice_total_fils,
  t.stripe_invoice_currency,
  t.stripe_invoice_pdf_url,
  t.stripe_invoice_hosted_url,
  'finance-docs'::text as doc_bucket,
  t.doc_path,
  t.doc_name,
  t.doc_content_type,
  t.doc_kind,
  t.doc_note,
  case
    when t.doc_path is not null and t.doc_kind is null then 'unclassified'
    when t.doc_path is not null                        then t.doc_kind
    when t.stripe_invoice_id is not null               then 'reference_only'
    else 'missing'
  end as document_state,
  t.doc_path is not null as is_openable,
  -- Does the invoice Stripe issued agree with the fee we recorded? Reported as a fact per row, so
  -- a disagreement is a value in a column rather than something a reconciliation has to discover.
  case
    when t.stripe_invoice_total_fils is null then 'unknown'
    when t.stripe_invoice_total_fils = round(coalesce(t.reveal_fee,0) * 100)::bigint then 'agrees'
    else 'disagrees'
  end as invoice_agrees_with_fee,
  -- A sale that took money is a sale that owes an invoice. Anything else is not counted as a gap.
  (t.fee_status = 'paid' and coalesce(t.reveal_fee, 0) > 0) as fee_was_taken
from public.transactions t;

comment on view public.v_revenue_documents is
  'One row per sale with the state of its Stripe invoice. document_state is the doc_kind, '
  '''unclassified'', ''reference_only'' (Stripe''s invoice is known but no file is stored) or '
  '''missing''. invoice_agrees_with_fee compares Stripe''s own total against reveal_fee rather than '
  'assuming they match. The mirror of v_expense_documents and v_refund_documents, on purpose.';

revoke all on public.v_revenue_documents from anon, authenticated;

-- ── 4. THE ROW -> DOCUMENT LOOKUP ──────────────────────────────────────────────────────────────
-- SECURITY INVOKER on purpose, exactly as fn_expense_document and fn_refund_document are: the
-- caller's own rights decide, so this cannot become a way to read finance paths from a seat that
-- may not read finance. The caller names a SALE, never a path.
create or replace function public.fn_revenue_document(p_transaction_id uuid)
returns jsonb language sql stable set search_path to 'public', 'pg_temp' as $fn$
  select coalesce(
    (select jsonb_build_object(
       'ok',              v.doc_path is not null,
       'transaction_id',  v.id,
       'quote_id',        v.quote_id,
       'revealed_at',     v.revealed_at,
       'reveal_fee',      v.reveal_fee,
       'payment_ref',     v.payment_ref,
       'invoice_id',      v.stripe_invoice_id,
       'invoice_number',  v.stripe_invoice_number,
       'invoice_status',  v.stripe_invoice_status,
       'invoice_total_fils', v.stripe_invoice_total_fils,
       'invoice_currency',   v.stripe_invoice_currency,
       'invoice_pdf_url',    v.stripe_invoice_pdf_url,
       'invoice_hosted_url', v.stripe_invoice_hosted_url,
       'invoice_agrees_with_fee', v.invoice_agrees_with_fee,
       'bucket',          v.doc_bucket,
       'path',            v.doc_path,
       'name',            v.doc_name,
       'content_type',    v.doc_content_type,
       'kind',            v.doc_kind,
       'note',            v.doc_note,
       'state',           v.document_state,
       'reason',          case
                            when v.doc_path is not null then null
                            when v.stripe_invoice_id is not null
                              then 'Stripe issued invoice ' || coalesce(v.stripe_invoice_number, v.stripe_invoice_id)
                                || ' for this sale, but its PDF has not been fetched into finance-docs yet.'
                            else 'This sale has no Stripe invoice on record. Reveal fees paid before '
                              || 'invoice_creation was enabled on 9 Sep 2026 produced no Invoice '
                              || 'object at all, so there is nothing to fetch for those.'
                          end)
     from public.v_revenue_documents v where v.id = p_transaction_id),
    jsonb_build_object('ok', false, 'transaction_id', p_transaction_id, 'state', 'no_such_transaction',
                       'reason', 'There is no public.transactions row with that id.'));
$fn$;

comment on function public.fn_revenue_document(uuid) is
  'The way from a sale to its Stripe invoice: bucket + path + kind + name, or ok:false with the '
  'reason in words. finance-docs is private, so the signed URL is minted by the accountant edge '
  'function, which calls this to find out what to sign -- the caller never names a path.';

-- ── 5. THE STANDING COUNT ──────────────────────────────────────────────────────────────────────
-- The founder's condition made measurable: "every reveal fee has its invoice" is a number, and a
-- regression shows up as that number falling rather than as a blank cell nobody looks at.
create or replace function public.fn_revenue_document_coverage()
returns jsonb language sql stable set search_path to 'public', 'pg_temp' as $fn$
  select jsonb_build_object(
    'sales',              count(*),
    'fees_taken',         count(*) filter (where fee_was_taken),
    'invoiced',           count(*) filter (where fee_was_taken and stripe_invoice_id is not null),
    'openable',           count(*) filter (where fee_was_taken and is_openable),
    'reference_only',     count(*) filter (where fee_was_taken and document_state = 'reference_only'),
    'unclassified',       count(*) filter (where fee_was_taken and document_state = 'unclassified'),
    'missing',            count(*) filter (where fee_was_taken and document_state = 'missing'),
    'missing_ids',        coalesce(jsonb_agg(id order by revealed_at)
                            filter (where fee_was_taken and document_state = 'missing'), '[]'::jsonb),
    'reference_only_ids', coalesce(jsonb_agg(id order by revealed_at)
                            filter (where fee_was_taken and document_state = 'reference_only'), '[]'::jsonb),
    'total_disagrees_ids', coalesce(jsonb_agg(id order by revealed_at)
                            filter (where fee_was_taken and invoice_agrees_with_fee = 'disagrees'), '[]'::jsonb),
    'by_state',           (select coalesce(jsonb_object_agg(document_state, n), '{}'::jsonb)
                           from (select document_state, count(*) n
                                 from public.v_revenue_documents
                                 where fee_was_taken group by 1) s))
  from public.v_revenue_documents;
$fn$;

comment on function public.fn_revenue_document_coverage() is
  'How many sales that TOOK money carry a Stripe invoice, how many of those invoices can actually '
  'be opened out of finance-docs, and which ids carry nothing -- plus which invoices disagree with '
  'the fee we recorded. The mirror of fn_expense_document_coverage. Sales that took no fee are '
  'excluded from every gap count: a free reveal owes no invoice, and counting it as missing would '
  'make the instrument read red while the system works.';

-- ── 6. THE MIRROR: ONE MORE BLOCK ON THE EXISTING CONVEYOR ─────────────────────────────────────
-- Everything above the INVOICES block is byte-for-byte the definition that was live before this
-- file, read back out of the database rather than retyped from memory. The only change is the
-- block marked 9 SEP 2026, and it is the same shape as the six around it: source='storage',
-- ON CONFLICT (dedupe_key) DO NOTHING, so the sweep is idempotent and a re-run enqueues nothing
-- twice. dropbox_backup calls this on every run and resilience_ping polls fn_dropbox_backup_due
-- every 15 minutes, so no scheduling is added either.
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

  return n;
end $function$;

revoke execute on function public.fn_enqueue_doc_backups() from public, anon, authenticated;

-- ── 7. THE PROBE. SELF-CLEANING, AND IT SAYS SO ────────────────────────────────────────────────
-- There are 0 transactions and 0 invoices, so nothing here can be proved on real money. What CAN
-- be proved is the shape, and it is proved on a synthetic sale inside a subtransaction that this
-- block rolls back itself -- including the rows the transaction's own AFTER INSERT trigger writes
-- (fn_emit_event, which is a plain insert and does no I/O, so the rollback is complete). The
-- assertions are accumulated into a variable declared OUTSIDE the subtransaction, so the findings
-- survive the rollback even though not one row does.
do $probe$
declare
  v_tx      uuid := gen_random_uuid();
  v_res     jsonb;
  v_cov     jsonb;
  v_state   text;
  v_dbx     integer;
  v_dbxpath text;
  v_rolled  boolean := false;
  v_report  text := '';
  v_before  bigint;
begin
  -- Columns exist. This survives the rollback because it is DDL applied above, not probe data.
  if (select count(*) from information_schema.columns
       where table_schema='public' and table_name='transactions'
         and column_name in ('stripe_invoice_id','stripe_invoice_number','stripe_invoice_status',
                             'stripe_invoice_total_fils','stripe_invoice_currency',
                             'stripe_invoice_pdf_url','stripe_invoice_hosted_url',
                             'doc_path','doc_name','doc_content_type','doc_kind','doc_note')) <> 12 then
    raise exception 'the twelve invoice/document columns are not all on public.transactions';
  end if;

  -- Refusals that need no row at all.
  v_res := public.fn_transaction_attach_invoice(null, '{"id":"in_x"}'::jsonb);
  if (v_res->>'ok')::boolean then raise exception 'accepted a null transaction id'; end if;
  v_res := public.fn_transaction_attach_invoice(gen_random_uuid(), '{}'::jsonb);
  if (v_res->>'ok')::boolean then raise exception 'accepted an invoice object with no id'; end if;
  v_res := public.fn_transaction_attach_invoice(gen_random_uuid(), '{"id":"ch_notaninvoice"}'::jsonb);
  if v_res->>'reason' <> 'not a stripe invoice id' then
    raise exception 'a non-invoice id was refused for the wrong reason: %', v_res->>'reason';
  end if;
  v_res := public.fn_transaction_attach_invoice(gen_random_uuid(),
             '{"id":"in_1","invoice_pdf":"https://evil.example.com/x.pdf"}'::jsonb);
  if v_res->>'reason' <> 'invoice_pdf is not a stripe.com url' then
    raise exception 'a non-Stripe invoice_pdf was refused for the wrong reason: %', v_res->>'reason';
  end if;
  v_res := public.fn_transaction_attach_invoice(gen_random_uuid(),
             '{"id":"in_1","invoice_pdf":"https://stripe.com.evil.example/x.pdf"}'::jsonb);
  if (v_res->>'ok')::boolean or v_res->>'reason' <> 'invoice_pdf is not a stripe.com url' then
    raise exception 'a stripe.com lookalike passed the invoice_pdf check';
  end if;
  v_res := public.fn_transaction_attach_invoice(gen_random_uuid(),
             '{"id":"in_1","hosted_invoice_url":"https://evil.example.com/i"}'::jsonb);
  if v_res->>'reason' <> 'hosted_invoice_url is not a stripe.com url' then
    raise exception 'a non-Stripe hosted_invoice_url was accepted';
  end if;
  v_res := public.fn_transaction_attach_invoice(gen_random_uuid(), '{"id":"in_1"}'::jsonb,
             'receipts/somebody-elses.pdf');
  if v_res->>'reason' !~ 'invoices/' then
    raise exception 'a path outside invoices/ was accepted: %', coalesce(v_res->>'reason','(none)');
  end if;
  -- An unknown transaction is named in the refusal, not silently ignored.
  v_res := public.fn_transaction_attach_invoice(v_tx, '{"id":"in_1"}'::jsonb);
  if (v_res->>'ok')::boolean then raise exception 'accepted an unknown transaction id'; end if;
  if v_res->>'reason' !~ v_tx::text then raise exception 'the refusal did not name the transaction'; end if;
  v_report := v_report || 'refused: null id, no invoice id, non-invoice id, non-Stripe pdf, '
           || 'stripe.com lookalike, non-Stripe hosted url, path outside invoices/, unknown transaction. ';

  -- Coverage on the estate as it stands, BEFORE the synthetic row.
  v_cov := public.fn_revenue_document_coverage();
  v_before := (v_cov->>'fees_taken')::bigint;
  v_report := v_report || format('coverage before the probe: %s sales, %s fees taken, %s invoiced. ',
                                 v_cov->>'sales', v_cov->>'fees_taken', v_cov->>'invoiced');

  -- ── THE SYNTHETIC SALE, AND ITS UNDOING ──────────────────────────────────────────────────────
  begin
    insert into public.transactions(id, reveal_fee, app_fee, customer_price, quote_amount,
                                    fee_status, paid_by, payment_ref, revealed_at)
    values (v_tx, 100.00, 100.00, 100.00, 1000.00, 'paid', 'customer', 'pi_ZZ_DEMO_probe', now());

    -- A paid sale with no invoice at all reads 'missing', and is COUNTED as missing.
    select document_state into v_state from public.v_revenue_documents where id = v_tx;
    if v_state <> 'missing' then raise exception 'a paid sale with no invoice read % rather than missing', v_state; end if;
    v_cov := public.fn_revenue_document_coverage();
    if (v_cov->>'fees_taken')::bigint <> v_before + 1 then raise exception 'the coverage function did not count the paid sale'; end if;
    if not (v_cov->'missing_ids' @> to_jsonb(v_tx::text)) then raise exception 'the missing sale was not named in missing_ids'; end if;

    -- The REFERENCE arrives first, with no file. That is 'reference_only', not 'missing'.
    v_res := public.fn_transaction_attach_invoice(v_tx,
      jsonb_build_object('id','in_ZZDEMOprobe','number','ZZDEMO-0001','status','paid',
                         'total', 10000, 'currency','aed',
                         'invoice_pdf','https://pay.stripe.com/invoice/zz/pdf',
                         'hosted_invoice_url','https://invoice.stripe.com/i/zz'));
    if not (v_res->>'ok')::boolean then raise exception 'the reference was refused: %', v_res->>'reason'; end if;
    select document_state into v_state from public.v_revenue_documents where id = v_tx;
    if v_state <> 'reference_only' then raise exception 'an invoice with no file read % rather than reference_only', v_state; end if;
    if (select invoice_agrees_with_fee from public.v_revenue_documents where id = v_tx) <> 'agrees' then
      raise exception '10000 fils against a reveal_fee of 100.00 did not read as agreeing';
    end if;

    -- A SECOND, DIFFERENT invoice is refused. The first one is the one the books cite.
    v_res := public.fn_transaction_attach_invoice(v_tx, '{"id":"in_ZZDEMOother"}'::jsonb);
    if (v_res->>'ok')::boolean then raise exception 'a second invoice overwrote the first'; end if;

    -- The FILE arrives later, on the same invoice id. Now it is openable and classified.
    v_res := public.fn_transaction_attach_invoice(v_tx,
      jsonb_build_object('id','in_ZZDEMOprobe'),
      'invoices/stripe/2026-09-09/in_ZZDEMOprobe_ZZDEMO-0001.pdf',
      'ZZDEMO-0001.pdf', 'application/pdf');
    if not (v_res->>'ok')::boolean then raise exception 'the file was refused: %', v_res->>'reason'; end if;
    select document_state into v_state from public.v_revenue_documents where id = v_tx;
    if v_state <> 'stripe_invoice' then raise exception 'a stored invoice read % rather than stripe_invoice', v_state; end if;
    if not (select is_openable from public.v_revenue_documents where id = v_tx) then
      raise exception 'a stored invoice did not read as openable';
    end if;
    -- The reference the first call set was not lost by the second.
    if (select stripe_invoice_number from public.transactions where id = v_tx) <> 'ZZDEMO-0001' then
      raise exception 'the second call lost the invoice number the first call set';
    end if;

    -- fn_revenue_document opens the same door the accountant seat will.
    v_res := public.fn_revenue_document(v_tx);
    if not (v_res->>'ok')::boolean then raise exception 'fn_revenue_document did not report the stored invoice'; end if;
    if v_res->>'bucket' <> 'finance-docs' then raise exception 'the lookup named the wrong bucket'; end if;

    -- THE MIRROR. The existing sweep queues it for Dropbox, once, on the existing path.
    perform public.fn_enqueue_doc_backups();
    select count(*), max(dropbox_path) into v_dbx, v_dbxpath
      from public.doc_backups where dedupe_key = 'T:'||v_tx||':invoice:invoices/stripe/2026-09-09/in_ZZDEMOprobe_ZZDEMO-0001.pdf';
    if v_dbx <> 1 then raise exception 'the invoice was not queued for Dropbox exactly once (got %)', v_dbx; end if;
    if v_dbxpath !~ '^/QuotesDone Backup/Finance/Revenue Invoices/' then
      raise exception 'the Dropbox path is not under Finance/Revenue Invoices: %', v_dbxpath;
    end if;
    -- And a second sweep queues nothing twice.
    perform public.fn_enqueue_doc_backups();
    select count(*) into v_dbx from public.doc_backups
     where dedupe_key = 'T:'||v_tx||':invoice:invoices/stripe/2026-09-09/in_ZZDEMOprobe_ZZDEMO-0001.pdf';
    if v_dbx <> 1 then raise exception 'a second sweep duplicated the Dropbox queue row'; end if;

    v_report := v_report || 'shape proved on a synthetic sale: missing -> reference_only -> '
             || 'stripe_invoice, second invoice refused, reference kept across calls, coverage '
             || 'counted it, Dropbox queued it once at ' || v_dbxpath || ' and twice-swept without '
             || 'duplicating. ';

    -- Undo everything, including the event row the AFTER INSERT trigger wrote.
    raise exception using errcode = 'ZZ999', message = 'probe rollback';
  exception when sqlstate 'ZZ999' then
    v_rolled := true;
  end;

  if not v_rolled then raise exception 'the probe did not roll itself back'; end if;
  if exists (select 1 from public.transactions where id = v_tx) then
    raise exception 'THE PROBE LEFT ITS SYNTHETIC SALE BEHIND';
  end if;
  if exists (select 1 from public.doc_backups where entity_id = v_tx::text) then
    raise exception 'THE PROBE LEFT A DROPBOX QUEUE ROW BEHIND';
  end if;

  -- Coverage is back exactly where it started.
  v_cov := public.fn_revenue_document_coverage();
  if (v_cov->>'fees_taken')::bigint <> v_before then
    raise exception 'coverage did not return to its pre-probe value';
  end if;

  raise notice 'THE INVOICE IS CONNECTED TO THE BOOKS. %', v_report;
  raise notice 'CLEAN: the synthetic sale, its event row and its Dropbox queue row are all gone; coverage is back to % fees taken.', v_before;
  raise notice 'UNPROVEN UNTIL THE FIRST REAL PAYMENT: that Stripe puts an invoice id on checkout.session.completed, that the invoice_pdf downloads, and that dropbox_backup uploads a finance-docs object. Those need money to move.';
end
$probe$;
