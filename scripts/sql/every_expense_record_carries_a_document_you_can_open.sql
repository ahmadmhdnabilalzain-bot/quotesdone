-- EVERY EXPENSE RECORD CARRIES A DOCUMENT YOU CAN OPEN.
--
-- The founder, 9 September 2026, verbatim: "but the accountant should actually have the pdfs in the
-- records. cause later when we build the OS i wanna be able to click any record and see the actual
-- invoice or receipt or email print pdf if none exist".
--
-- WHAT WAS MEASURED BEFORE THIS FILE (production, 9 Sep 2026, 37 rows in expense_entries):
--   *  4 rows carried the vendor's own invoice PDF   (doc_content_type = application/pdf)
--   *  5 rows carried `receipt.html`, text/html      -- the COVERING EMAIL, not the vendor document
--   * 28 rows carried nothing at all                 (doc_path null; the Gmail-sourced history)
-- and NOTHING in the schema could tell the first class from the second. "application/pdf" is a
-- content type, not a claim about provenance: an email printed to PDF is also application/pdf, and
-- from tomorrow most of these rows are exactly that. A column that cannot distinguish the vendor's
-- invoice from a print of the covering note is a column the OS would have had to guess from a
-- filename -- which is how "Invoice-TLZLFZ-00006.pdf" and "receipt.html" ended up looking like the
-- same kind of evidence for a month.
--
-- SO THE EVIDENCE CLASS IS RECORDED, NOT INFERRED.
--   doc_kind = 'vendor_document'  the vendor's own invoice/receipt file, taken off the source email
--   doc_kind = 'email_print'      a PDF print of the email itself, because no vendor file existed
--                                 (or none could be retrieved -- doc_note then says which)
--   doc_kind = null               there is no document; v_expense_documents reports it as 'missing'
--                                 and it is never silently blank.
--
-- WHAT THIS FILE DELIBERATELY DOES NOT DO. It does not require doc_kind when doc_path is set. A
-- second agent is inserting rows into this table from Outlook while this runs, and a constraint
-- that refused its inserts would stop expenses reaching the book to make a column tidy. The kind is
-- filled by the writer that knows it (resend_inbound, accountant, the backfill); an unclassified
-- row shows as 'unclassified' in the view rather than being rejected at the door.
--
-- NOT ONE FIGURE MOVES HERE. amount, currency, vendor, charged_on, vat_amount and source_msg_id are
-- untouched by every statement below.

begin;

-- ---------------------------------------------------------------------------------------------
-- 1. THE EVIDENCE CLASS, AND THE NOTE THAT SAYS WHY IT IS THAT CLASS.
-- ---------------------------------------------------------------------------------------------
alter table public.expense_entries
  add column if not exists doc_kind text,
  add column if not exists doc_note text;

comment on column public.expense_entries.doc_kind is
  'What KIND of evidence doc_path points at: ''vendor_document'' = the vendor''s own invoice/receipt '
  'file taken off the source email; ''email_print'' = a PDF print of the email itself, because the '
  'email carried no vendor file. null = no document. Never inferred from the filename.';
comment on column public.expense_entries.doc_note is
  'Why the document is the kind it is -- in particular, when an email_print stands in for a vendor '
  'invoice that is known to exist but could not be retrieved, this names it. Read by the OS beside '
  'the document so a print is never mistaken for the invoice.';

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'expense_entries_doc_kind_ck') then
    alter table public.expense_entries
      add constraint expense_entries_doc_kind_ck
      check (doc_kind is null or doc_kind in ('vendor_document', 'email_print'));
  end if;
end $$;

-- ---------------------------------------------------------------------------------------------
-- 2. THE REPORTABLE STATE OF EVERY RECORD. A record with no document must be REPORTABLE as such --
--    the founder's own condition -- so 'missing' is a value the view emits, never an absence.
--    doc_bucket is stated rather than left to the caller: receipt-files is where receipt documents
--    live, and an OS guessing a bucket name is the same defect as an OS guessing a path.
-- ---------------------------------------------------------------------------------------------
create or replace view public.v_expense_documents as
select
  e.id,
  e.vendor,
  e.charged_on,
  e.amount,
  e.currency,
  e.category,
  e.source_msg_id,
  case
    when e.source_msg_id like 'resend:%'  then 'resend'
    when e.source_msg_id like 'gmail:%'   then 'gmail'
    when e.source_msg_id like 'outlook:%' then 'outlook'
    when e.source_msg_id is null          then 'none'
    else split_part(e.source_msg_id, ':', 1)
  end                                                as source_channel,
  'receipt-files'::text                              as doc_bucket,
  e.doc_path,
  e.doc_name,
  e.doc_content_type,
  e.doc_kind,
  e.doc_note,
  case
    when e.doc_path is null  then 'missing'
    when e.doc_kind is null  then 'unclassified'
    else e.doc_kind
  end                                                as document_state,
  (e.doc_path is not null)                           as is_openable
from public.expense_entries e;

comment on view public.v_expense_documents is
  'One row per expense record with the state of its evidence. document_state is ''vendor_document'', '
  '''email_print'', ''unclassified'' (a document whose writer did not say what kind it is) or '
  '''missing'' (no document at all). The founder''s rule of 9 Sep 2026: a record with no document '
  'must be reportable as such, never silently blank.';

-- ---------------------------------------------------------------------------------------------
-- 3. THE ROW -> DOCUMENT LOOKUP. The OS asks for an entry id and is told the bucket, the path, the
--    kind and the name -- or told, in words, that there is none. It never has to compose a path.
--    SECURITY INVOKER on purpose: the caller's own rights decide, so this cannot become a way to
--    read finance paths from a seat that may not read finance.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_expense_document(p_entry_id bigint)
returns jsonb
language sql
stable
as $fn$
  select coalesce(
    (select jsonb_build_object(
       'ok',            v.doc_path is not null,
       'entry_id',      v.id,
       'vendor',        v.vendor,
       'charged_on',    v.charged_on,
       'amount',        v.amount,
       'currency',      v.currency,
       'bucket',        v.doc_bucket,
       'path',          v.doc_path,
       'name',          v.doc_name,
       'content_type',  v.doc_content_type,
       'kind',          v.doc_kind,
       'note',          v.doc_note,
       'state',         v.document_state,
       'reason',        case
                          when v.doc_path is not null then null
                          else 'This expense has no stored document. Its source message carried no '
                               || 'vendor file that could be retrieved and no email print has been '
                               || 'rendered for it yet.'
                        end)
     from public.v_expense_documents v where v.id = p_entry_id),
    jsonb_build_object('ok', false, 'entry_id', p_entry_id, 'state', 'no_such_entry',
                       'reason', 'There is no expense_entries row with that id.'));
$fn$;

comment on function public.fn_expense_document(bigint) is
  'The OS''s way from an expense row to its document: bucket + path + kind + name, or ok:false with '
  'the reason in words. The bucket is private, so the signed URL is minted by the accountant edge '
  'function''s `document` action, which calls this to find out what to sign.';

-- ---------------------------------------------------------------------------------------------
-- 4. THE STANDING COUNT. So "how many records cannot be opened" is one call, and a regression shows
--    up as a number rather than as a blank cell somebody notices months later.
-- ---------------------------------------------------------------------------------------------
create or replace function public.fn_expense_document_coverage()
returns jsonb
language sql
stable
as $fn$
  select jsonb_build_object(
    'entries',          count(*),
    'vendor_document',  count(*) filter (where document_state = 'vendor_document'),
    'email_print',      count(*) filter (where document_state = 'email_print'),
    'unclassified',     count(*) filter (where document_state = 'unclassified'),
    'missing',          count(*) filter (where document_state = 'missing'),
    'openable',         count(*) filter (where is_openable),
    'missing_ids',      coalesce(jsonb_agg(id order by id) filter (where document_state = 'missing'), '[]'::jsonb),
    'by_channel',       (select coalesce(jsonb_object_agg(source_channel, n), '{}'::jsonb)
                         from (select source_channel, count(*) n
                               from public.v_expense_documents group by 1) s))
  from public.v_expense_documents;
$fn$;

comment on function public.fn_expense_document_coverage() is
  'How many expense records carry the vendor''s own document, how many carry a print of the covering '
  'email, and which ids carry nothing. The founder''s condition of 9 Sep 2026 made measurable.';

commit;
