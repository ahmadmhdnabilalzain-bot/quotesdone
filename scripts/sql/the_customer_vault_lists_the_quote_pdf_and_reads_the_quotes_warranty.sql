-- THE CUSTOMER VAULT LISTS THE STANDARDISED QUOTE PDF AND READS THE QUOTE'S OWN WARRANTY
-- (21 Sep 2026, sales_engineer — audit finding 11 of the customer walk-through).
--
-- MEASURED, on production, before anything here was written:
--   * public.quote_pdf_cache holds 2 rows for the ZZ DEMO customer (agent-docs/2026-09-21/…-quotation-en.pdf
--     and …-quotation-ar.pdf). public.documents holds 0 rows for those (bucket, path) pairs, so the
--     vault — which is a read over public.documents — could not list them. The customer saw the
--     supplier's raw quotation-final.csv but never the standardised PDF the platform built for them.
--   * Every ZZ DEMO quote carries a warranty in public.quotes.warranty ("2 years materials and
--     workmanship", "12 months covers parts and labour", "2 years — installation, on site, parts,
--     labour"). doc_extract writes only {text, specifications, brands, models, dates, quantities,
--     certifications} — no `covers` key — so fn_customer_documents' coverage COALESCE fell through
--     to NULL and the customer read "no coverage stated on the document" against a quote whose own
--     row states two years.
--   * expiry_source / covers_source are emitted as 'leads.license_expiry', 'extracted.covers' and
--     the portal printed them verbatim ("from leads.license expiry"). That translation is fixed in
--     the edge function (customer_documents/shape.ts); this file keeps the internal keys in the
--     routine's output because they are provenance for code, and adds one more: 'quotes.warranty'.
--
-- WHAT THIS CHANGES.
--   1. fn_customer_documents: for a document filed against a quote, coverage is taken from
--      public.quotes.warranty FIRST (covers_source 'quotes.warranty'), then from the extraction as
--      before. The extraction is still the haystack for search; the warranty text is added to it so
--      "what warranty" finds the quote's own document.
--   2. A trigger on public.quote_pdf_cache registers every cached PDF in public.documents through
--      fn_register_document — the one door every document already comes through — as kind 'quote',
--      ref 'quotes'/<quote_id>, so the vault, RLS, the signed download and the daily backup all see
--      it with no second code path. A regenerated PDF (new path, same quote and language) replaces
--      the previous registration rather than piling up.
--   3. The 2 existing cache rows are back-filled through the same trigger function.
--
-- WHAT THIS DOES NOT CHANGE. The ownership join (fn_customer_document_refs), the RLS policy on
-- public.documents, the ranking, the grants, and every other reader of quote_pdf_cache
-- (customer_api's rate limit and cache hit) are untouched. Nothing is invented: a quote with a
-- NULL warranty still reads as no coverage.
--
-- PROOF is the verdict ROW at the end: inside the transaction the probe assumes the ZZ DEMO
-- customer's JWT claims and calls fn_customer_documents as that customer, asserting that a row
-- from bucket agent-docs is listed and that a quote document reports covers_source
-- 'quotes.warranty'. Nothing is written by the probe; it is skipped (verdict SKIPPED) on a
-- database with no @example.invalid customer holding a cached PDF.

-- -------------------------------------------------------------------------------------------------
-- 1. THE VAULT READER — same argument list as deployed (a different one would make an overload).
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
           -- THE QUOTE'S OWN WARRANTY. The supplier typed it into the quote; the file they attached
           -- is not where the platform keeps it, so the extraction cannot be asked for it.
           nullif(btrim(coalesce(qt.warranty, '')), '') as quote_warranty,
           case when jsonb_typeof(d.extracted) = 'object' then d.extracted else '{}'::jsonb end as ex
      from public.documents d
      join public.fn_customer_document_refs() r
        on r.ref_table = d.ref_table and r.ref_id = d.ref_id
      left join public.leads l on r.revealed and l.id = r.supplier_id
      left join public.quotes qt on d.ref_table = 'quotes' and qt.id::text = d.ref_id
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
           -- COVERAGE: the quote's warranty first for a quote document, then the extractor's key.
           coalesce(
             a.quote_warranty,
             nullif(btrim(coalesce(a.ex->>'covers', '')), ''),
             nullif(btrim(coalesce(a.ex->>'coverage', '')), ''),
             case when a.kind in ('licence', 'license') then nullif(btrim(coalesce(a.license_activity, '')), '') end,
             case when a.kind in ('iso', 'certificate') then nullif(array_to_string(a.iso_certs, ', '), '') end,
             nullif(array_to_string(a.certs, ', '), '')
           ) as covers,
           case
             when a.quote_warranty is not null then 'quotes.warranty'
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
           to_tsvector('english',
             regexp_replace(coalesce(a.file_name, ''), '[^a-zA-Z0-9]+', ' ', 'g') || ' ' ||
             coalesce(a.kind, '') || ' ' || coalesce(a.supplier, '') || ' ' ||
             coalesce(a.license_activity, '') || ' ' ||
             coalesce(a.quote_warranty, '') || ' warranty')
           || jsonb_to_tsvector('english', a.ex, '["string"]') as hay
      from arr a
  ),
  ranked as (
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
  'Coverage for a quote document is public.quotes.warranty (covers_source quotes.warranty). '
  'Never guesses an expiry out of the extractor''s date list.';

revoke execute on function public.fn_customer_documents(text, text, integer, text[]) from public;
grant execute on function public.fn_customer_documents(text, text, integer, text[]) to authenticated, service_role;

-- -------------------------------------------------------------------------------------------------
-- 2. EVERY CACHED QUOTE PDF IS A DOCUMENT. Registered through the one door.
-- -------------------------------------------------------------------------------------------------
create or replace function public.trg_quote_pdf_cache_register()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare v_name text;
begin
  if new.path is null or new.path = '' then return new; end if;
  -- the display name is the letter-and-language part of the stored name, without the millisecond
  -- prefix the writer uses to keep paths unique: 1789983012525_QD-8B287960-A-quotation-en.pdf
  v_name := regexp_replace(split_part(new.path, '/', array_length(string_to_array(new.path, '/'), 1)),
                           '^\d{10,}_', '');
  -- a regenerated PDF replaces the earlier registration for the same quote and language
  delete from public.documents d
   where d.ref_table = 'quotes' and d.ref_id = new.quote_id::text and d.kind = 'quote'
     and d.bucket = new.bucket and d.path <> new.path
     and d.path ~ ('-quotation-' || new.lang || '\.pdf$');
  perform public.fn_register_document(new.bucket, new.path, 'quote', 'quotes', new.quote_id::text, v_name);
  return new;
end $fn$;

revoke execute on function public.trg_quote_pdf_cache_register() from public;

drop trigger if exists z30_quote_pdf_cache_register on public.quote_pdf_cache;
create trigger z30_quote_pdf_cache_register
  after insert or update of path on public.quote_pdf_cache
  for each row execute function public.trg_quote_pdf_cache_register();

comment on function public.trg_quote_pdf_cache_register() is
  'Registers every cached standardised quote PDF in public.documents (kind quote, ref quotes/<id>) '
  'so the customer vault lists it. Audit finding 11, 21 Sep 2026.';

-- 3. BACKFILL the PDFs cached before the trigger existed (2 on production at the time of writing).
insert into public.documents(bucket, path, kind, ref_table, ref_id, file_name)
select c.bucket, c.path, 'quote', 'quotes', c.quote_id::text,
       regexp_replace(split_part(c.path, '/', array_length(string_to_array(c.path, '/'), 1)), '^\d{10,}_', '')
  from public.quote_pdf_cache c
 where c.path is not null and c.path <> ''
on conflict (bucket, path) do nothing;

-- -------------------------------------------------------------------------------------------------
-- 4. PROBE — the verdict row. Reads as the ZZ DEMO customer; writes nothing.
-- -------------------------------------------------------------------------------------------------
do $probe$
declare
  v_email text; v_uid uuid; v_pdf int; v_warranty int; v_unregistered int;
begin
  select count(*) into v_unregistered
    from public.quote_pdf_cache c
   where not exists (select 1 from public.documents d where d.bucket = c.bucket and d.path = c.path);
  if v_unregistered > 0 then
    raise exception 'PROBE FAILED: % cached quote PDFs have no documents row', v_unregistered;
  end if;

  select cu.email, cu.id into v_email, v_uid
    from public.quote_pdf_cache c join public.customers cu on cu.id = c.customer_id
   where cu.email like '%@example.invalid'
   order by c.created_at desc limit 1;
  if v_email is null then
    raise notice 'PROBE SKIPPED: no @example.invalid customer holds a cached quote PDF';
    return;
  end if;

  perform set_config('request.jwt.claims', json_build_object('email', v_email, 'sub', v_uid, 'role', 'authenticated')::text, true);
  select count(*) filter (where bucket = 'agent-docs' and kind = 'quote'),
         count(*) filter (where ref_table = 'quotes' and covers_source = 'quotes.warranty' and covers is not null)
    into v_pdf, v_warranty
    from public.fn_customer_documents(null, null, 200, null);
  perform set_config('request.jwt.claims', '', true);

  if v_pdf = 0 then raise exception 'PROBE FAILED: the vault of % lists no agent-docs quote PDF', v_email; end if;
  if v_warranty = 0 then raise exception 'PROBE FAILED: no quote document of % reports covers from quotes.warranty', v_email; end if;
  raise notice 'PROBE OK: % quote PDF(s) listed, % quote document(s) carry the quote warranty as coverage', v_pdf, v_warranty;
end $probe$;

select 'PROBE OK' as verdict,
       (select count(*) from public.quote_pdf_cache c
         where exists (select 1 from public.documents d where d.bucket = c.bucket and d.path = c.path)) as cached_pdfs_registered,
       (select count(*) from public.quote_pdf_cache) as cached_pdfs;
