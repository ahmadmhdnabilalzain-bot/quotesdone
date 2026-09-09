-- THE TERMS LABEL SAYS THE VERSION THE DOCUMENT ACTUALLY IS.
--
-- A signed certificate prints app_secrets.<party>_terms_label. The acceptance row stores
-- app_secrets.<party>_terms_version. On 9 Sep 2026 those two disagreed, on both sides:
--
--   customer_terms_label    'Customer Terms & Conditions — Version 3'   customer_terms_version  v5
--   supplier_terms_label    'Supplier Agreement — Version 5'            supplier_terms_version  v8
--
-- So a supplier could sign a document captioned Version 5 while the database recorded that they
-- accepted v8, and a customer one captioned Version 3 against a stored v5.
--
-- WHY THIS IS A TYPO AND NOT A LEGAL DECISION, established before touching anything. The founder
-- asked what the difference between version 5 and version 8 is. Measured: there is none, because
-- they are not two documents.
--
--   public.legal_documents, the published register:
--     supplier-agreement  'Supplier Agreement & Platform Terms'  version v8  effective 2026-09-06
--     customer-terms      'Customer Terms & Conditions'          version v5  effective 2026-09-06
--
--   and the copy the signing path actually uses is the same bytes as the published one:
--     md5(legal_documents.body_html) where slug='supplier-agreement'  = c7573d417bc9fc9f828a04da360687ca
--     md5(app_secrets.supplier_terms_html)                            = c7573d417bc9fc9f828a04da360687ca
--
-- v8 IS the current supplier agreement. v5 IS the current customer terms. Nothing about the
-- agreements is in question; the caption beside them was simply never updated when they were
-- revised on 6 September, so it kept naming an earlier revision of the same document.
--
-- The label is therefore corrected to describe its own document, which is the opposite of
-- rewriting a legal term: it stops the certificate misdescribing what was signed.
--
-- WHY IT MATTERS MORE THAN A CAPTION. supabase/functions/collections_legal/index.ts consumes
-- signed_terms_path as `evidence_terms_path` when it assembles a demand letter and case file --
-- the certificate is the EXHIBIT in a collections claim. A version stated on the exhibit that
-- disagrees with the version in the record is the first thing a counterparty attacks, on the one
-- path where the company is trying to enforce. (collections_legal is not currently deployed.)
--
-- The title text is taken from legal_documents.title rather than retyped, so the label cannot drift
-- from the register again by a hand edit, and the version is read from the same row.
--
--   node scripts/apply_sql.mjs scripts/sql/the_terms_label_says_the_version_the_document_actually_is.sql --apply

begin;

-- Build each label from the register itself: '<title> — Version <n>', where both halves come from
-- the row that IS the document. An em dash, matching the existing convention.
update public.app_secrets s
   set value = d.title || ' — Version ' || ltrim(d.version, 'vV')
  from public.legal_documents d
 where s.key = 'customer_terms_label'
   and d.slug = 'customer-terms';

update public.app_secrets s
   set value = 'Supplier Agreement — Version ' || ltrim(d.version, 'vV')
  from public.legal_documents d
 where s.key = 'supplier_terms_label'
   and d.slug = 'supplier-agreement';

-- The closing assertion: the number printed on a certificate must equal the number stored against
-- the acceptance. A file that was supposed to reconcile them and did not must say so.
do $check$
declare
  c_label text; c_ver text; s_label text; s_ver text;
  c_doc text; s_doc text;
begin
  select value into c_label from public.app_secrets where key = 'customer_terms_label';
  select value into c_ver   from public.app_secrets where key = 'customer_terms_version';
  select value into s_label from public.app_secrets where key = 'supplier_terms_label';
  select value into s_ver   from public.app_secrets where key = 'supplier_terms_version';
  select version into c_doc from public.legal_documents where slug = 'customer-terms';
  select version into s_doc from public.legal_documents where slug = 'supplier-agreement';

  -- The label must END with the version the acceptance row stores, digits compared as digits.
  if c_label not like ('%Version ' || ltrim(c_ver, 'vV')) then
    raise exception 'CUSTOMER LABEL STILL DISAGREES: label %L, stored version %L', c_label, c_ver;
  end if;
  if s_label not like ('%Version ' || ltrim(s_ver, 'vV')) then
    raise exception 'SUPPLIER LABEL STILL DISAGREES: label %L, stored version %L', s_label, s_ver;
  end if;

  -- And the stored version must still equal the published register, or we have reconciled the
  -- caption to a number that is itself stale.
  if c_ver is distinct from c_doc then
    raise exception 'CUSTOMER VERSION DISAGREES WITH THE PUBLISHED REGISTER: stored %L, legal_documents %L', c_ver, c_doc;
  end if;
  if s_ver is distinct from s_doc then
    raise exception 'SUPPLIER VERSION DISAGREES WITH THE PUBLISHED REGISTER: stored %L, legal_documents %L', s_ver, s_doc;
  end if;

  raise notice 'labels reconciled — customer: % (%), supplier: % (%)', c_label, c_ver, s_label, s_ver;
end
$check$;

commit;
