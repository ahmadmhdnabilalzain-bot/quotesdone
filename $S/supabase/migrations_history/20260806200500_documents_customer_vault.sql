-- =================================================================================================
-- SPEC §14 — DOCUMENT INTELLIGENCE VAULT: the customer-side access path.
--
-- MEASURED BEFORE THIS FILE (production, 6 Aug 2026):
--   public.documents           RLS = true, 0 policies, SELECT granted to postgres + service_role only
--   customer-authed readers    0 edge functions read the table
--   => the vault had no access path at all. A surface over it would have rendered nothing.
--
-- WHAT OWNERSHIP MEANS HERE — verified against the data, not assumed. documents has no customer_id;
-- it carries (ref_table, ref_id), and production holds exactly three ref_table values: 'inquiries',
-- 'quotes' and 'leads'. So a document reaches a customer by one of three joins, and the third one
-- is gated by money:
--
--   inquiries -> i.customer_id                       the customer's own upload (drawing, BoQ scan)
--   quotes    -> q.inquiry_id -> i.customer_id       the quotation file sent against their RFQ
--   leads     -> ONLY a supplier this customer has REVEALED (transactions.revealed_at is not null)
--
-- THE THIRD JOIN IS THE ONE THAT COULD LEAK THE BUSINESS MODEL. A supplier's trade licence,
-- insurance schedule or ISO certificate names the company. Handing those to a customer who has not
-- paid the reveal fee is the same defect customer_api documents at length (anonymity pre-reveal is
-- the only thing the reveal fee sells). So supplier documents enter the vault only after a
-- transactions row with revealed_at, and on a quote document the supplier NAME is null until the
-- same row exists — the file is theirs to read, the identity is not.
--
-- WHY A FUNCTION AND NOT A PLAIN POLICY. customers, inquiries, quotes, leads and transactions ALL
-- have RLS enabled with ZERO policies. A policy on documents whose USING clause selected from them
-- directly would evaluate those subqueries as the CALLER, read nothing, and scope every customer to
-- an empty vault — a policy that looks right and denies everything. fn_customer_document_refs() is
-- SECURITY DEFINER and never touches public.documents, so there is no policy recursion either.
--
-- ONE OWNERSHIP DEFINITION. The RLS policy and the vault reader below both call the same function.
-- There is no second copy of this rule in TypeScript: the customer_documents edge function reaches
-- the database with the CUSTOMER'S OWN JWT, so the scoping it gets is the scoping the database
-- enforces, and a bug in the endpoint cannot widen it.
-- =================================================================================================

-- -------------------------------------------------------------------------------------------------
-- 1. WHAT THIS CALLER OWNS, as a set of (ref_table, ref_id).
-- No arguments on purpose: there is no p_customer_id to pass, so no authenticated caller can ask
-- for somebody else's set. The identity comes from the JWT and nowhere else.
--
-- The customer is resolved by EMAIL first because that is how the product actually keys it —
-- kyc and customer_api both do `customers.eq('email', user.email)` and INSERT without an id, so
-- customers.id is a fresh uuid and NOT auth.users.id in production. The demo factory does set
-- them equal, so auth.uid() is kept as a second chance rather than the primary key.
-- -------------------------------------------------------------------------------------------------
create or replace function public.fn_customer_document_refs()
returns table (ref_table text, ref_id text, source text, supplier_id bigint,
               supplier_name text, revealed boolean)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with me as (
    select c.id
      from public.customers c
     where lower(c.email) = lower(nullif(auth.email(), ''))
        or c.id = auth.uid()
     order by (lower(c.email) = lower(nullif(auth.email(), ''))) desc nulls last
     limit 1
  )
  -- the customer's own uploads
  select 'inquiries'::text, i.id::text, 'inquiry'::text, null::bigint, null::text, true
    from public.inquiries i join me on i.customer_id = me.id
  union all
  -- quotation files sent against their RFQs. A draft quote is not shown to the customer by
  -- customer_api, so its attachment is not shown here either.
  select 'quotes'::text, q.id::text, 'quote'::text, q.supplier_id,
         case when t.id is not null then l.company_name end,
         t.id is not null
    from public.quotes q
    join public.inquiries i on i.id = q.inquiry_id
    join me on i.customer_id = me.id
    left join public.leads l on l.id = q.supplier_id
    left join public.transactions t
           on t.quote_id = q.id and t.customer_id = me.id and t.revealed_at is not null
   where coalesce(q.status, '') <> 'draft'
  union all
  -- supplier documents, and ONLY for a supplier this customer has paid to reveal
  select 'leads'::text, l.id::text, 'supplier'::text, l.id, l.company_name, true
    from public.leads l
   where exists (select 1 from public.transactions t join me on t.customer_id = me.id
                  where t.supplier_id = l.id and t.revealed_at is not null);
$fn$;

comment on function public.fn_customer_document_refs() is
  'SPEC 14. The (ref_table, ref_id) pairs in public.documents that belong to the CALLING customer, '
  'resolved from the JWT. Takes no arguments so it cannot be aimed at another customer. Supplier '
  'documents appear only after a paid reveal.';

-- -------------------------------------------------------------------------------------------------
-- 2. THE POLICY AND THE GRANT. Both legs are required: RLS with no policy denies everything, and a
-- policy with no grant is unreachable.
-- -------------------------------------------------------------------------------------------------
alter table public.documents enable row level security;

drop policy if exists documents_customer_select on public.documents;
create policy documents_customer_select on public.documents
  for select to authenticated
  using (exists (select 1 from public.fn_customer_document_refs() r
                  where r.ref_table = documents.ref_table
                    and r.ref_id    = documents.ref_id));

grant select on public.documents to authenticated;

-- -------------------------------------------------------------------------------------------------
-- 3. THE VAULT READER — retrieval over the EXTRACTION, not over the filename.
--
-- doc_extract (green 7/7) writes documents.extracted as
--   { text, specifications[], brands[], models[], dates[], quantities[], certifications[] }
-- and license_extract's cert mode produces { issuer, expiry_date, covers, ... }. Both shapes are
-- read below. The search haystack is the extracted TEXT, specifications, certifications and brands
-- plus the supplier's licensed activity — a filename LIKE would not find "warranty" inside a file
-- called 1784642800192_catalogue-ventilation-2026.pdf, and that file is what production holds.
--
-- WHAT THIS FUNCTION WILL NOT DO. doc_extract emits a `dates` ARRAY — every date it could read off
-- the page. Choosing one of them and calling it an expiry would be an invented fact of exactly the
-- kind this project has already been burned by, so it is not done: expiry_date is null unless a
-- field that MEANS expiry carries it, and expiry_source names which field that was. Same for
-- covers. A surface can therefore say "no expiry recorded" truthfully instead of guessing.
--
-- p_related_refs is how natural language widens recall: the endpoint asks fn_memory_search for the
-- RFQs and quotes that match the phrase, and passes the ones this customer owns back in, so
-- "warranty documents for HVAC" also returns the documents attached to their HVAC request even
-- when the document's own text never says HVAC. Ownership is still the join, so an unowned ref
-- passed in here returns nothing.
--
-- ponytail: no index on the extraction text; the tsvector is built per call. 16 documents in
-- production and a per-customer scope of a handful; add a GIN index on the expression if a single
-- customer ever holds thousands.
-- -------------------------------------------------------------------------------------------------
create or replace function public.fn_customer_documents(
  p_q text default null,
  p_kind text default null,
  p_lim integer default 50,
  p_related_refs text[] default null)
returns table (
  id bigint, kind text, file_name text, bucket text, path text, mime text, status text,
  created_at timestamptz, source text, ref_table text, ref_id text,
  supplier text, supplier_revealed boolean,
  expiry_date date, expiry_source text, covers text, covers_source text,
  summary text, specifications text[], certifications text[], brands text[],
  extracted_at timestamptz, match_reason text, score real)
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $fn$
  with q as (
    -- A QUESTION IS NOT A SEARCH STRING. plainto_tsquery ANDs every content word, so the spec's own
    -- example — "Find warranty documents for HVAC" — becomes find & warranti & document & hvac and
    -- matches nothing a human would call a warranty document. Measured on staging: 0 hits against a
    -- fixture whose filename is literally hvac-warranty-agreement.pdf. The lexemes are therefore
    -- OR-ed, and ts_rank does the discriminating — a document carrying two of the four terms
    -- outranks one carrying a single term, which is what "ask in natural language" has to mean.
    select nullif(btrim(coalesce(p_q, '')), '') as qtext,
           (select nullif(string_agg('''' || replace(l.lexeme, '''', '''''') || '''', ' | '), '')::tsquery
              from unnest(to_tsvector('english', coalesce(p_q, ''))) l) as tsq,
           coalesce(p_related_refs, '{}'::text[]) as rel
  ),
  base as (
    select d.id, d.kind, d.file_name, d.bucket, d.path, d.mime, d.status, d.created_at,
           d.processed_at, r.source, d.ref_table, d.ref_id,
           case when r.revealed then r.supplier_name end as supplier,
           coalesce(r.revealed, false) as supplier_revealed,
           l.license_expiry, l.insurance_expiry, l.iso_expiry, l.manufacturer_auth_expiry,
           l.license_activity, l.iso_certifications,
           case when jsonb_typeof(d.extracted) = 'object' then d.extracted else '{}'::jsonb end as ex
      from public.documents d
      join public.fn_customer_document_refs() r
        on r.ref_table = d.ref_table and r.ref_id = d.ref_id
      left join public.leads l on r.revealed and l.id = r.supplier_id
  ),
  arr as (
    select b.*,
           (select coalesce(array_agg(x), '{}'::text[]) from jsonb_array_elements_text(
              case when jsonb_typeof(b.ex->'specifications') = 'array' then b.ex->'specifications'
                   else '[]'::jsonb end) x) as specs,
           (select coalesce(array_agg(x), '{}'::text[]) from jsonb_array_elements_text(
              case when jsonb_typeof(b.ex->'certifications') = 'array' then b.ex->'certifications'
                   else '[]'::jsonb end) x) as certs,
           (select coalesce(array_agg(x), '{}'::text[]) from jsonb_array_elements_text(
              case when jsonb_typeof(b.ex->'brands') = 'array' then b.ex->'brands'
                   else '[]'::jsonb end) x) as brnds,
           (select coalesce(array_agg(x), '{}'::text[]) from jsonb_array_elements_text(
              case when jsonb_typeof(b.iso_certifications) = 'array' then b.iso_certifications
                   else '[]'::jsonb end) x) as iso_certs
      from base b
  ),
  shaped as (
    select a.id, a.kind, a.file_name, a.bucket, a.path, a.mime, a.status, a.created_at,
           a.source, a.ref_table, a.ref_id, a.supplier, a.supplier_revealed,
           -- EXPIRY: only from a field that means expiry.
           coalesce(
             case when a.ex->>'expiry_date' ~ '^\d{4}-\d{2}-\d{2}$' then (a.ex->>'expiry_date')::date end,
             case when a.ex->>'valid_until' ~ '^\d{4}-\d{2}-\d{2}$' then (a.ex->>'valid_until')::date end,
             case when a.kind in ('licence', 'license') then a.license_expiry end,
             case when a.kind = 'insurance' then a.insurance_expiry end,
             case when a.kind in ('iso', 'certificate') then a.iso_expiry end,
             case when a.kind = 'manufacturer' then a.manufacturer_auth_expiry end
           ) as expiry_date,
           case
             when a.ex->>'expiry_date' ~ '^\d{4}-\d{2}-\d{2}$' then 'extracted.expiry_date'
             when a.ex->>'valid_until' ~ '^\d{4}-\d{2}-\d{2}$' then 'extracted.valid_until'
             when a.kind in ('licence', 'license') and a.license_expiry is not null then 'leads.license_expiry'
             when a.kind = 'insurance' and a.insurance_expiry is not null then 'leads.insurance_expiry'
             when a.kind in ('iso', 'certificate') and a.iso_expiry is not null then 'leads.iso_expiry'
             when a.kind = 'manufacturer' and a.manufacturer_auth_expiry is not null then 'leads.manufacturer_auth_expiry'
           end as expiry_source,
           -- COVERAGE: what the document covers, from the extractor's own key first.
           coalesce(
             nullif(btrim(coalesce(a.ex->>'covers', '')), ''),
             nullif(btrim(coalesce(a.ex->>'coverage', '')), ''),
             case when a.kind in ('licence', 'license') then nullif(btrim(coalesce(a.license_activity, '')), '') end,
             case when a.kind in ('iso', 'certificate') then nullif(array_to_string(a.iso_certs, ', '), '') end,
             nullif(array_to_string(a.certs, ', '), '')
           ) as covers,
           case
             when nullif(btrim(coalesce(a.ex->>'covers', '')), '') is not null then 'extracted.covers'
             when nullif(btrim(coalesce(a.ex->>'coverage', '')), '') is not null then 'extracted.coverage'
             when a.kind in ('licence', 'license')
              and nullif(btrim(coalesce(a.license_activity, '')), '') is not null then 'leads.license_activity'
             when a.kind in ('iso', 'certificate')
              and nullif(array_to_string(a.iso_certs, ', '), '') is not null then 'leads.iso_certifications'
             when nullif(array_to_string(a.certs, ', '), '') is not null then 'extracted.certifications'
           end as covers_source,
           left(nullif(btrim(coalesce(a.ex->>'text', '')), ''), 600) as summary,
           a.specs, a.certs, a.brnds, a.processed_at,
           -- THE HAYSTACK IS THE WHOLE EXTRACTION. jsonb_to_tsvector with a ["string"] filter walks
           -- every string value in the jsonb, so doc_extract's text/specifications/certifications/
           -- brands AND license_extract's issuer/covers/reference are all searchable without this
           -- function having to know which extractor wrote the row. A hand-picked key list is how
           -- `covers: "Full system"` ended up unsearchable in the first version.
           -- The filename is de-punctuated first: the parser lexes hvac-warranty-agreement.pdf as a
           -- single `file` token, so "warranty" did not match the file actually called that.
           to_tsvector('english',
             regexp_replace(coalesce(a.file_name, ''), '[^a-zA-Z0-9]+', ' ', 'g') || ' ' ||
             coalesce(a.kind, '') || ' ' || coalesce(a.supplier, '') || ' ' ||
             coalesce(a.license_activity, ''))
           || jsonb_to_tsvector('english', a.ex, '["string"]') as hay
      from arr a
  ),
  ranked as (
    -- match_reason and the rank are computed here, and the final select orders by THIS alias.
    -- RETURNS TABLE makes `score` and `created_at` OUT parameters, and an unqualified ORDER BY
    -- against a name that is also a parameter is how a SQL function starts erroring at call time.
    select s.*,
           case when q.qtext is null then 'all'
                when s.hay @@ q.tsq then 'text'
                else 'related_request' end as mreason,
           case when q.qtext is null then 0::real else ts_rank(s.hay, q.tsq) end as rank_score
      from shaped s, q
     where (p_kind is null or s.kind = lower(btrim(p_kind)))
       and (q.qtext is null
            or s.hay @@ q.tsq
            or (s.ref_table || ':' || s.ref_id) = any (q.rel))
  )
  select z.id, z.kind, z.file_name, z.bucket, z.path, z.mime, z.status, z.created_at,
         z.source, z.ref_table, z.ref_id, z.supplier, z.supplier_revealed,
         z.expiry_date, z.expiry_source, z.covers, z.covers_source,
         z.summary, z.specs, z.certs, z.brnds, z.processed_at, z.mreason, z.rank_score
    from ranked z
   order by z.rank_score desc, z.created_at desc nulls last
   limit greatest(1, coalesce(p_lim, 50));
$fn$;

comment on function public.fn_customer_documents(text, text, integer, text[]) is
  'SPEC 14. The calling customer''s document vault, searched over doc_extract''s extraction output '
  'rather than the filename, with supplier / expiry / coverage and the SOURCE of each of those. '
  'Never guesses an expiry out of the extractor''s date list.';

-- PUBLIC holds EXECUTE on every new function by default, which handed anon a callable entry point.
-- Both return nothing without a JWT (auth.email() and auth.uid() are null, so no customer resolves
-- and the `me` CTE is empty) — but a grant list should state the boundary rather than rely on the
-- body being careful.
revoke execute on function public.fn_customer_document_refs() from public;
revoke execute on function public.fn_customer_documents(text, text, integer, text[]) from public;
grant execute on function public.fn_customer_document_refs() to authenticated, service_role;
grant execute on function public.fn_customer_documents(text, text, integer, text[]) to authenticated, service_role;

-- -------------------------------------------------------------------------------------------------
-- 4. ONE SPELLING PER KIND, at the single door every document comes through.
--
-- The spec names six kinds. documents.kind carries no constraint and no canon, so the vault's
-- vocabulary was whatever each caller happened to type — and the customer-facing kind filter added
-- above has to mean something. The mapping below is an ALIAS TABLE, not a rewrite: every kind the
-- three existing registrars pass (drawing, licence, profile, egr, catalog, quote) comes out
-- byte-identical, so no existing reader — doc_extract's INDEX_KINDS, v_supplier_doc_score — changes
-- behaviour. What it adds is a defined destination for the three spec kinds nothing writes yet.
--
-- SAME ARGUMENT LIST AS THE DEPLOYED FUNCTION. A CREATE OR REPLACE with a different one makes an
-- OVERLOAD and the three triggers keep calling the old body.
-- -------------------------------------------------------------------------------------------------
create or replace function public.fn_register_document(
  p_bucket text, p_path text, p_kind text, p_ref_table text, p_ref_id text,
  p_file_name text default null::text)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare v_kind text;
begin
  if p_path is null or p_path = '' then return; end if;
  v_kind := lower(btrim(coalesce(p_kind, '')));
  v_kind := case v_kind
    when 'quotation'      then 'quote'
    when 'quotations'     then 'quote'
    when 'quotes'         then 'quote'
    when 'agreement'      then 'contract'
    when 'agreements'     then 'contract'
    when 'contracts'      then 'contract'
    when 'bill'           then 'invoice'
    when 'bills'          then 'invoice'
    when 'invoices'       then 'invoice'
    when 'license'        then 'licence'
    when 'licenses'       then 'licence'
    when 'licences'       then 'licence'
    when 'cert'           then 'certificate'
    when 'certs'          then 'certificate'
    when 'certificates'   then 'certificate'
    when 'dwg'            then 'drawing'
    when 'drawings'       then 'drawing'
    when 'plan'           then 'drawing'
    when 'plans'          then 'drawing'
    when 'boq'            then 'drawing'
    when 'po'             then 'purchase_order'
    when 'pos'            then 'purchase_order'
    when 'purchase order' then 'purchase_order'
    when 'purchase-order' then 'purchase_order'
    else v_kind
  end;
  if v_kind is null or v_kind = '' then v_kind := 'other'; end if;
  insert into public.documents(bucket, path, kind, ref_table, ref_id, file_name)
  values (p_bucket, p_path, v_kind, p_ref_table, p_ref_id,
          coalesce(p_file_name, split_part(p_path, '/', array_length(string_to_array(p_path, '/'), 1))))
  on conflict (bucket, path) do nothing;
end $function$;
