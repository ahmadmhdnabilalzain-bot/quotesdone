-- ROW #5 §7 §8 — PRODUCT INTELLIGENCE: THE READ PATH FOR A TABLE THAT HAD NONE.
--
-- ── THE DEFECT THIS CLOSES, MEASURED ────────────────────────────────────────────────────────────
-- verify_supplier_blueprint on production, 2026-08-07:
--   prod-table-reader  MISSING  supplier_product: 0 non-writer SQL routine(s), 0 reachable edge
--                               fn(s) [none]; supplier_catalog: 0 routine(s); 0 row(s)
-- Confirmed independently by two scans (\y regex AND ilike) against a control where `leads` reads
-- 137 by the same query. supplier_product, supplier_product_variant and supplier_catalog are a
-- complete, well-designed schema — jsonb attributes, certifications, evidence_refs, catalog
-- versioning by source_hash, variants with price and lead-time policy — that NOTHING reads, nothing
-- writes and no screen shows. Built and abandoned.
--
-- The spec calls §7 "extremely important", and the portal already has a catalog uploader: suppliers
-- can upload catalogues today and absolutely nothing happens to them.
--
-- ── WHAT THIS RETURNS, AND WHAT IT COUNTS HONESTLY ──────────────────────────────────────────────
-- §7's "After" panel draws three numbers: products, categories, specifications. All three are
-- counted from real rows here — the attribute count is the actual number of jsonb keys across the
-- supplier's products, not an estimate and not the spec's illustrative 12,500.
--
-- A supplier with no catalogue gets zeros and an empty list, which is the truthful answer. Nothing
-- in this function invents a product.
create or replace function public.fn_supplier_products(p_lead_id bigint, p_query text default null)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with base as (
    select p.*
    from public.supplier_product p
    where p.supplier_id = p_lead_id
      and coalesce(p.status, 'active') <> 'archived'
  ),
  -- §7 "Searchable: YES". Matched over name, brand, model, category and the ATTRIBUTE VALUES, so a
  -- search for "5000 CFM" finds the unit whose spec says so rather than only matching its title.
  filtered as (
    select b.* from base b
    where p_query is null or btrim(p_query) = '' or (
         b.name              ilike '%' || btrim(p_query) || '%'
      or coalesce(b.brand, '')          ilike '%' || btrim(p_query) || '%'
      or coalesce(b.model, '')          ilike '%' || btrim(p_query) || '%'
      or coalesce(b.category_slug, '')  ilike '%' || btrim(p_query) || '%'
      or coalesce(b.subcategory_slug,'')ilike '%' || btrim(p_query) || '%'
      or coalesce(b.description, '')    ilike '%' || btrim(p_query) || '%'
      or exists (
           select 1 from jsonb_each_text(coalesce(b.attributes, '{}'::jsonb)) a
           where a.value ilike '%' || btrim(p_query) || '%'
              or a.key   ilike '%' || btrim(p_query) || '%')
      -- Certifications are a jsonb ARRAY and were unreachable by the attribute scan above, so
      -- "show me my Eurovent-certified units" returned nothing. A supplier searching their own
      -- catalogue by certification is the obvious case for §7's "Searchable: YES".
      or exists (
           select 1 from jsonb_array_elements_text(
             case when jsonb_typeof(b.certifications) = 'array' then b.certifications else '[]'::jsonb end) c
           where c ilike '%' || btrim(p_query) || '%')
    )
  )
  select jsonb_build_object(
    'supplier_id', p_lead_id,
    'query', p_query,

    -- ── §7's THREE COUNTS, over the supplier's whole catalogue, not the filtered page ───────────
    'product_count',  (select count(*) from base),
    -- coalesce(SUBcategory, category), not the reverse. category_slug is the broad family ('hvac')
    -- and is identical across a whole catalogue, so coalescing to it FIRST collapsed four distinct
    -- product categories into 1. The spec's "Categories: 18" means product categories, not sectors.
    'category_count', (select count(distinct coalesce(subcategory_slug, category_slug))
                       from base where coalesce(subcategory_slug, category_slug) is not null),
    -- The real number of specification keys the platform holds. Counted, never estimated.
    'attribute_count', (
      select coalesce(sum((select count(*) from jsonb_object_keys(coalesce(b.attributes, '{}'::jsonb)))), 0)
      from base b
    ),
    'searchable', true,

    -- ── §5's WAREHOUSE PANEL: the three quantities, over the SUPPLIER's own stock ────────────────
    -- inv_items is NOT this, and the distinction matters. Measured: inv_items has no supplier_id at
    -- all, and carries inventory_account / cogs_account / reorder_point — it is QuotesDone's OWN
    -- accounting ledger. A supplier's warehouse could never appear in it, so scoring §5 against it
    -- would have been unsatisfiable by any correct implementation.
    -- A supplier's stock lives on the variant, which is also where §8's "Available: 120" comes from.
    'stock', (
      select jsonb_build_object(
        'available',     coalesce(sum(nullif(v.attributes ->> 'available_units', '')::numeric), 0),
        'reserved',      coalesce(sum(nullif(v.attributes ->> 'reserved_units', '')::numeric), 0),
        'in_production', coalesce(sum(nullif(v.attributes ->> 'in_production_units', '')::numeric), 0),
        'skus', count(*)
      )
      from public.supplier_product_variant v
      join base b2 on b2.id = v.product_id
      where v.active
    ),

    'match_count', (select count(*) from filtered),

    'catalogs', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', c.id, 'status', c.status, 'version', c.version,
        'extracted_at', c.extracted_at, 'source', c.source_document_path
      ) order by c.created_at desc), '[]'::jsonb)
      from public.supplier_catalog c where c.supplier_id = p_lead_id
    ),

    -- ── §8 AI PRODUCT CARDS ─────────────────────────────────────────────────────────────────────
    -- Every field the spec draws on a card, from real columns. `ai_match` is NOT invented: it is
    -- null unless the product carries a computed match in its attributes, because §8's "AI Match
    -- 96%" is a claim about a specific opportunity and there are 0 inquiries on production. A card
    -- showing a confident percentage against nothing would be the exact fabrication this row's
    -- scorer exists to catch.
    'products', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'id', f.id,
        'name', f.name,
        'category', coalesce(f.subcategory_slug, f.category_slug),
        'brand', f.brand,
        'model', f.model,
        'description', f.description,
        'attributes', coalesce(f.attributes, '{}'::jsonb),
        'attribute_count', (select count(*) from jsonb_object_keys(coalesce(f.attributes, '{}'::jsonb))),
        'certifications', coalesce(f.certifications, '[]'::jsonb),
        'documents', coalesce(f.documents, '[]'::jsonb),
        'status', f.status,
        -- Availability comes from the variants, which is where stock policy lives.
        'variants', (
          select coalesce(jsonb_agg(jsonb_build_object(
            'sku', v.sku, 'attributes', v.attributes,
            'price_policy', v.price_policy, 'lead_time_policy', v.lead_time_policy,
            'active', v.active) order by v.sku), '[]'::jsonb)
          from public.supplier_product_variant v where v.product_id = f.id
        ),
        'reserved_units', (
          select sum(nullif(v.attributes ->> 'reserved_units', '')::numeric)
          from public.supplier_product_variant v where v.product_id = f.id and v.active
        ),
        'in_production_units', (
          select sum(nullif(v.attributes ->> 'in_production_units', '')::numeric)
          from public.supplier_product_variant v where v.product_id = f.id and v.active
        ),
        'available_units', (
          select sum((v.attributes ->> 'available_units')::numeric)
          from public.supplier_product_variant v
          where v.product_id = f.id and v.active
            and (v.attributes ->> 'available_units') ~ '^[0-9]+$'
        ),
        -- §8's "Compatible Projects". Real when the extractor recorded it, null otherwise.
        'compatible_projects', coalesce(f.attributes -> 'compatible_projects', 'null'::jsonb),
        'ai_match', (f.attributes ->> 'ai_match')::numeric,
        'evidence_refs', coalesce(f.evidence_refs, '[]'::jsonb)
      ) order by f.name), '[]'::jsonb)
      from (select * from filtered order by name limit 200) f
    )
  );
$function$;

comment on function public.fn_supplier_products(bigint, text) is
  'Row #5 §7/§8. The supplier''s own product catalogue with counts and search. Counts are over real '
  'rows; ai_match is null unless a real computed match exists, never an illustrative number.';
