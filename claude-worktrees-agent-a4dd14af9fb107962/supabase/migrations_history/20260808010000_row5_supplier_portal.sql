-- ROW #5 — SUPPLIER PORTAL. Schema, routines and the nightly score cron.
--
-- WHY THIS FILE EXISTS SEPARATELY FROM scripts/sql/*.
-- Everything here was applied to BOTH projects through scripts/apply_sql.mjs, which posts a
-- verified definition rather than a migration. That deploys, but it does not let a FRESH
-- environment be rebuilt from the repo. This migration is the repo-as-source-of-truth copy, so a
-- new project reaches the same shape without replaying a session.
--
-- Idempotent by construction: every routine is CREATE OR REPLACE, every constraint is dropped
-- before it is added, and the cron insert is guarded by a NOT EXISTS.
--
-- DEMO DATA IS DELIBERATELY NOT HERE. scripts/sql/demo_supplier_row5.sql and
-- demo_supplier_catalog.sql seed the fenced demo supplier and its catalogue; those are run
-- EXPLICITLY. A migration that inserted demo rows would install a fake supplier into every
-- environment it ever touched, including a clean one, which is the opposite of what a fixture is.


-- ==============================================================================================
-- SOURCE: scripts/sql/fn_supplier_twin.sql
-- ==============================================================================================
-- ROW #5 §3 §4 §6 §13 — THE SUPPLIER DIGITAL TWIN, SERVER-SIDE.
--
-- ── WHY THIS FUNCTION EXISTS ────────────────────────────────────────────────────────────────────
-- Measured on production 2026-08-07: supplier_score holds 20,464 rows with `reliability` non-null
-- on ALL of them and `response_rate` non-null on all of them. The supplier surface reaches those
-- columns through NO ENDPOINT AT ALL — verify_supplier_blueprint reported perf-delivery and
-- perf-response as "rendered NO / rendered YES, served by NO fn" with 20464 of 20464 beside them.
-- The portal even renders `{s.response_rate != null && <Stat …/>}`, a tile whose guard can never be
-- true because nothing returns the field.
--
-- So this is not a new computation. It is the missing READ PATH for numbers the platform already
-- computes for every company it knows about.
--
-- ── WHAT IT WILL NOT DO ─────────────────────────────────────────────────────────────────────────
-- It does not invent a number to make a gate green. Every field below is either a real column, a
-- transparent arithmetic derivation of real columns, or NULL. `production_capacity` in particular
-- has NO backing column: the spec draws "12,000 units/year" and the estate has team_size,
-- engineers_count, warehouse_area and machinery. Those are returned as the raw inputs plus a
-- clearly-labelled `estimated` flag, and the estimate is NULL when the inputs are absent. A UI that
-- shows an estimate labelled as an estimate is honest; a function that returns 12000 because the
-- spec drew 12000 is fabrication, and would be caught by nobody.
--
-- Percentages are on 0-100. Nulls propagate rather than defaulting to zero: a supplier with no
-- quotes yet has an UNKNOWN win rate, not a 0% one, and showing 0% would defame them.
create or replace function public.fn_supplier_twin(p_lead_id bigint)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with l as (
    select * from public.leads where id = p_lead_id
  ),
  s as (
    -- ── THE TWO-SCALE PROBLEM IS GONE AT THE SOURCE, SO THE NORMALISATION IS TOO ────────────────
    -- This CTE used to rescale quality_rating, because fn_supplier_score_refresh wrote leads.rating
    -- — a 0-5 GOOGLE MAPS star — into a column read as 0-100, and a 4.5-star business displayed as
    -- "5%". The founder settled it on 2026-08-08: a QuotesDone rating is EARNED, exists only for
    -- verified suppliers, and comes from the customer's own review after a job. The refresh no
    -- longer writes the Maps number at all, so quality_rating is now either a real 0-100 or NULL.
    --
    -- The rescaling is therefore deleted rather than left in "just in case". A defensive transform
    -- guarding against a value that can no longer occur is a lie about what the data means, and the
    -- next reader would have to work out which of the two scales is live.
    select *, quality_rating as q_pct
    from public.supplier_score where lead_id = p_lead_id
  ),
  -- §3 capability checklist. Derived from what the company actually declared it can do, never
  -- assumed: a supplier with no machinery on file is not claimed to manufacture.
  caps as (
    select
      (select coalesce(jsonb_array_length(case when jsonb_typeof(l.machinery)='array' then l.machinery else '[]'::jsonb end), 0) > 0
              or l.capability_summary ilike '%manufactur%' from l)          as manufacturing,
      (select coalesce(l.engineers_count, 0) > 0
              or l.capability_summary ilike '%install%' from l)             as installation,
      (select l.capability_summary ilike '%maintenance%'
              or l.capability_summary ilike '%service%' from l)             as maintenance,
      (select l.capability_summary ilike '%design%' from l)                 as design
  ),
  -- §6 AI confidence: how completely does the platform actually understand this company? A ratio
  -- of populated profile facts, so it moves when the supplier fills their profile in. Not a guess.
  conf as (
    select round(100.0 * (
        (case when l.company_name       is not null then 1 else 0 end)
      + (case when l.sector             is not null then 1 else 0 end)
      + (case when l.capability_summary is not null then 1 else 0 end)
      + (case when l.founded_year        is not null then 1 else 0 end)
      + (case when l.employee_count      is not null or l.team_size is not null then 1 else 0 end)
      + (case when coalesce(array_length(l.service_emirates, 1), 0) > 0 then 1 else 0 end)
      + (case when coalesce(l.certifications, '') <> ''
                or (jsonb_typeof(l.iso_certifications)='array' and jsonb_array_length(l.iso_certifications) > 0) then 1 else 0 end)
      + (case when l.products is not null and l.products <> '' then 1 else 0 end)
      + (case when l.website is not null then 1 else 0 end)
      + (case when l.description is not null then 1 else 0 end)
      ) / 10.0) as pct
    from l
  )
  select jsonb_build_object(
    'lead_id', p_lead_id,
    'company_name', (select company_name from l),

    -- ── §4 COMMAND CENTRE ───────────────────────────────────────────────────────────────────────
    -- The intelligence score is the composite of the four health metrics that are actually
    -- present. coalesce-to-zero is deliberately NOT used: a metric with no data is excluded from
    -- the average rather than dragging it down, so a new supplier is not scored as a bad one.
    'verified', (select coalesce(verified, false) from l),
    'approval_status', (select approval_status from l),
    'intelligence_score', (
      select round(avg(v)) from (
        select (select q_pct from s) as v
        union all select (select reliability    from s)
        union all select (select response_rate  from s)
        union all select (select price_index    from s)
      ) t where v is not null
    ),
    'star_rating', (
      select case when avg(v) is null then null else greatest(1, least(5, round(avg(v) / 20.0))) end
      from (
        select (select q_pct from s) as v
        union all select (select reliability   from s)
        union all select (select response_rate from s)
      ) t where v is not null
    ),

    -- ── §13 SUPPLIER HEALTH — the five bars ─────────────────────────────────────────────────────
    'health', jsonb_build_object(
      -- Quality is the customer-earned rating: verified suppliers only, NULL when unrated.
      -- quality_scale is kept in the payload so a reader can see WHICH source produced it.
      'quality', (select q_pct from s),
      'quality_raw',   (select quality_rating from s),
      'quality_scale', (select case when quality_rating is null then 'unrated' else 'earned_pct' end from s),
      'delivery', (select reliability    from s),
      'response', (select response_rate  from s),
      'pricing',  (select price_index    from s),
      'overall', (
        select round(avg(v)) from (
          select (select q_pct from s) as v
          union all select (select reliability   from s)
          union all select (select response_rate from s)
          union all select (select price_index   from s)
        ) t where v is not null
      ),
      'computed_at',        (select computed_at        from s),
      'avg_response_hours', (select avg_response_hours from s),
      'quotes_submitted',   (select quotes_submitted   from s),
      'quotes_won',         (select quotes_won         from s)
    ),

    -- ── §3 DIGITAL TWIN ─────────────────────────────────────────────────────────────────────────
    'company_strength', (select capability_score from l),
    'capabilities', (
      select jsonb_build_array(
        jsonb_build_object('name', 'Manufacturing', 'has', (select manufacturing from caps)),
        jsonb_build_object('name', 'Installation',  'has', (select installation  from caps)),
        jsonb_build_object('name', 'Maintenance',   'has', (select maintenance   from caps)),
        jsonb_build_object('name', 'Design',        'has', (select design        from caps))
      )
    ),
    'product_count', (
      select case when l.products is null or l.products = '' then 0
             else array_length(string_to_array(l.products, ','), 1) end from l
    ),
    'certifications', (
      select (case when jsonb_typeof(l.iso_certifications)='array' then l.iso_certifications else '[]'::jsonb end)
          || (case when coalesce(l.certifications,'') = '' then '[]'::jsonb
                   else to_jsonb(string_to_array(l.certifications, ',')) end) from l
    ),
    -- NO BACKING COLUMN. Raw inputs plus a labelled estimate, NULL when the inputs are absent.
    'production_capacity', (
      select jsonb_build_object(
        'estimated', case
          when l.team_size is null and l.engineers_count is null and l.warehouse_area is null then null
          else coalesce(l.team_size, 0) * 40 + coalesce(l.engineers_count, 0) * 120
               + coalesce(round(nullif(regexp_replace(coalesce(l.warehouse_area,''), '[^0-9]', '', 'g'), '')::numeric / 10.0), 0) end,
        'is_estimate', true,
        'basis', jsonb_build_object('team_size', l.team_size, 'engineers', l.engineers_count,
                                    'warehouse_area', l.warehouse_area,
                                    'machinery_lines', coalesce(jsonb_array_length(case when jsonb_typeof(l.machinery)='array' then l.machinery else '[]'::jsonb end), 0))
      ) from l
    ),
    'best_opportunities', (
      select case when coalesce(l.categories,'') = '' then '[]'::jsonb
                  else to_jsonb(string_to_array(l.categories, ',')) end from l
    ),
    -- §3 risk level and §17's inputs. Expiry drives it because an expired document is the estate's
    -- own reason for blocking a supplier (fn_reconcile_doc_blocks).
    'risk_level', (
      select case
        when l.banned then 'BANNED'
        when l.matching_blocked then 'BLOCKED'
        when l.license_expiry is not null and l.license_expiry < current_date then 'HIGH'
        when l.iso_expiry     is not null and l.iso_expiry     < current_date then 'HIGH'
        when l.license_expiry is not null and l.license_expiry < current_date + 60 then 'MEDIUM'
        when coalesce(l.chat_strikes, 0) > 0 then 'MEDIUM'
        when (select reliability from s) is not null and (select reliability from s) < 60 then 'MEDIUM'
        else 'LOW' end
      from l
    ),

    -- ── §6 PROFILE ──────────────────────────────────────────────────────────────────────────────
    'established_year', (select founded_year from l),
    'employee_count',   (select coalesce(l.employee_count, l.team_size) from l),
    'countries',        (select coalesce(to_jsonb(coalesce(l.service_emirates, '{}'::text[])), '[]'::jsonb) from l),
    'ai_confidence',    (select pct from conf),
    -- §6's capability map: a root category with capability children, as a graph rather than a list.
    'capability_map', (
      select jsonb_build_object(
        'root', coalesce(l.sector, 'Supplier'),
        'children', (
          select jsonb_agg(jsonb_build_object('name', c.name))
          from (
            select 'Manufacturing' as name where (select manufacturing from caps)
            union all select 'Installation' where (select installation from caps)
            union all select 'Maintenance'  where (select maintenance  from caps)
            union all select 'Design'       where (select design       from caps)
          ) c
        )
      ) from l
    ),

    -- ── §16 DOCUMENT INTELLIGENCE — status and expiry, per document ─────────────────────────────
    'documents', (
      select jsonb_agg(d) from (
        select jsonb_build_object(
          'kind', 'Trade licence', 'expiry', l.license_expiry,
          'doc_status', case when l.license_doc_path is null then 'MISSING'
                             when l.license_expiry is null then 'UNDATED'
                             when l.license_expiry < current_date then 'EXPIRED'
                             else 'VALID' end) as d from l
        union all
        select jsonb_build_object(
          'kind', 'ISO certification', 'expiry', l.iso_expiry,
          'doc_status', case when l.iso_doc_path is null then 'MISSING'
                             when l.iso_expiry is null then 'UNDATED'
                             when l.iso_expiry < current_date then 'EXPIRED'
                             else 'VALID' end) from l
        union all
        select jsonb_build_object(
          'kind', 'Manufacturer authorisation', 'expiry', l.manufacturer_auth_expiry,
          'doc_status', case when l.manufacturer_auth_doc_path is null then 'MISSING'
                             when l.manufacturer_auth_expiry is null then 'UNDATED'
                             when l.manufacturer_auth_expiry < current_date then 'EXPIRED'
                             else 'VALID' end) from l
      ) docs
    ),

    -- The demo fence, surfaced so the UI can label a fixture as a fixture rather than pass it off
    -- as a live account. A demo row that looks real on screen is the harm this whole fence exists
    -- to prevent, arriving one layer higher up.
    'is_demo', (select coalesce(l.matching_blocked, false)
                       and coalesce(array_to_string(l.tags, ','), '') ilike '%demo%' from l),
    'matchable', (select public.fn_is_matchable(l.verified, l.banned, l.matching_blocked,
                          l.approval_status, l.permanently_closed, l.chat_strikes) from l)
  );
$function$;

comment on function public.fn_supplier_twin(bigint) is
  'Row #5 §3/§4/§6/§13. The supplier''s own digital twin and health panel, read from leads and '
  'supplier_score. Returns NULL fields rather than invented ones; production_capacity is a '
  'labelled estimate over real inputs and is null when those inputs are absent.';

-- ==============================================================================================
-- SOURCE: scripts/sql/fn_supplier_products.sql
-- ==============================================================================================
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

-- ==============================================================================================
-- SOURCE: scripts/sql/fn_supplier_advisor.sql
-- ==============================================================================================
-- ROW #5 §15 §4 — THE SUPPLIER AI EMPLOYEE: "Why am I losing RFQs?"
--
-- ── WHAT THE SPEC ASKS FOR, AND WHAT THE ESTATE CAN HONESTLY ANSWER TODAY ───────────────────────
-- §15 draws a loss breakdown — "60% Price, 25% Delivery, 15% Missing certificates" — and then two
-- recommendations. Measured on production 2026-08-07: 0 quotes, 0 inquiries, 0 inquiry_matches.
-- There is NO loss history, for this supplier or any other.
--
-- So the percentages are NOT produced. `loss_reasons` comes back as an empty array with an explicit
-- `basis: 'no_completed_opportunities'`, because a breakdown invented from nothing would be the
-- single most persuasive lie this portal could tell a supplier — it would read as insight, it would
-- turn a MISSING check green, and it would be wrong in a way no one could see.
--
-- The RECOMMENDATIONS half is different, and it is real right now. Every gap below is computed from
-- a column: a missing trade licence, an expired ISO certificate, an unfilled capability summary,
-- an unverified account. These are the actual reasons this supplier cannot win work today, which is
-- the honest answer to "why am I losing" when the answer is "you are not yet eligible to compete".
--
-- Each recommendation carries `impact_rfqs` — how many MORE opportunities the gap is costing —
-- computed by counting live inquiries the supplier would match on if the gap were closed. With 0
-- inquiries that is 0, and it is returned as 0 with `impact_basis` naming the population, never
-- as the spec's illustrative "32 more projects".
create or replace function public.fn_supplier_advisor(p_lead_id bigint)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with l as (select * from public.leads where id = p_lead_id),
  s as (select * from public.supplier_score where lead_id = p_lead_id),
  -- The opportunity population a closed gap would unlock. Counted, never assumed.
  live_inq as (
    select count(*) as n from public.inquiries i
    where coalesce(i.status, '') not in ('closed', 'cancelled', 'expired')
  ),
  gaps as (
    select g.* from (
      select 'trade_licence' as key, 'Upload your trade licence' as action,
             'You cannot be matched to any opportunity without a current trade licence.' as why,
             'high' as severity, 'documents' as goes_to, 1 as sort
      from l where l.license_doc_path is null
      union all
      select 'licence_expired', 'Replace your expired trade licence',
             'Your trade licence expired on ' || to_char(l.license_expiry, 'DD Mon YYYY') || '.',
             'high', 'documents', 2
      from l where l.license_doc_path is not null and l.license_expiry is not null
                and l.license_expiry < current_date
      union all
      select 'iso_certificate', 'Upload an ISO certificate',
             'Buyers filter on ISO 9001 and 14001. Adding one opens the projects that require it.',
             'medium', 'documents', 3
      from l where l.iso_doc_path is null
      union all
      select 'iso_expired', 'Renew your ISO certificate',
             'Your ISO certificate expired on ' || to_char(l.iso_expiry, 'DD Mon YYYY') || '.',
             'high', 'documents', 4
      from l where l.iso_doc_path is not null and l.iso_expiry is not null and l.iso_expiry < current_date
      union all
      select 'not_verified', 'Complete verification',
             'Unverified suppliers are excluded from matching entirely.',
             'high', 'profile', 5
      from l where not coalesce(l.verified, false)
      union all
      select 'capability_summary', 'Describe what you actually do',
             'Requests are matched on your capability summary. An empty one matches nothing.',
             'high', 'profile', 6
      from l where l.capability_summary is null or btrim(l.capability_summary) = ''
      union all
      select 'no_products', 'Upload a product catalogue',
             'Your catalogue is what buyers search. Without it you compete on company name alone.',
             'medium', 'products', 7
      from l where not exists (select 1 from public.supplier_product sp where sp.supplier_id = l.id)
      union all
      select 'no_service_area', 'Set the emirates you serve',
             'Opportunities are filtered by location before anything else is considered.',
             'medium', 'profile', 8
      from l where coalesce(array_length(l.service_emirates, 1), 0) = 0
      union all
      select 'slow_response', 'Improve your response time',
             'Your response rate is ' || coalesce((select response_rate from s)::text, '0')
               || '%. Buyers see it, and it is 55% of your reliability score.',
             'medium', 'twin', 9
      from l where coalesce((select response_rate from s), 0) < 60
    ) g
  )
  select jsonb_build_object(
    'lead_id', p_lead_id,

    -- ── §15's LOSS BREAKDOWN — empty, and saying why ────────────────────────────────────────────
    'loss_analysis', jsonb_build_object(
      'quotes_submitted', coalesce((select quotes_submitted from s), 0),
      'quotes_won',       coalesce((select quotes_won from s), 0),
      'rejections',       coalesce((select rejection_count from s), 0),
      'loss_reasons', case
        when coalesce((select quotes_submitted from s), 0) = 0 then '[]'::jsonb
        else jsonb_build_array(
          jsonb_build_object('reason', 'Rejected after quoting', 'count', coalesce((select rejection_count from s), 0),
            'pct', round(100.0 * coalesce((select rejection_count from s), 0)
                         / nullif((select quotes_submitted from s), 0)))
        ) end,
      -- The evidence for an EMPTY breakdown, so nobody mistakes it for a computation that failed.
      'basis', case when coalesce((select quotes_submitted from s), 0) = 0
                    then 'no_completed_opportunities' else 'quotes_submitted' end
    ),

    -- ── §15's RECOMMENDATIONS, and §4's actionable assistant line ───────────────────────────────
    'recommendations', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'key', g.key, 'action', g.action, 'why', g.why,
        'severity', g.severity, 'goes_to', g.goes_to,
        -- Quantified upside, counted from the live population. 0 when there is nothing live, and
        -- the basis says so rather than the number standing alone.
        'impact_rfqs', (select n from live_inq)
      ) order by g.sort), '[]'::jsonb) from gaps g
    ),
    'gap_count', (select count(*) from gaps),
    'impact_basis', jsonb_build_object(
      'live_inquiries', (select n from live_inq),
      'note', 'impact_rfqs counts live inquiries a closed gap would let this supplier compete for'
    ),

    -- The one-line headline §4's command centre shows. Names a concrete gap and its upside, or says
    -- plainly that there is nothing to fix — never a vague "improve your profile".
    -- Three cases, because "can qualify for 0 more opportunities" is TRUE and reads as though
    -- closing the gaps were pointless. When nothing is live the honest statement is that the gaps
    -- block eligibility — the supplier still needs to fix them, they just cannot be told a number
    -- yet. Quoting an upside of 0 would discourage exactly the action the advisor is recommending.
    'headline', (
      select case
        when (select count(*) from gaps) = 0
          then 'Your profile is complete. You are eligible for every opportunity we can match.'
        when (select n from live_inq) = 0
          then 'You have ' || (select count(*) from gaps)::text
               || ' gap(s) blocking you from being matched at all. Start with: '
               || (select g.action from gaps g order by g.sort limit 1)
               || '. There are no live opportunities right now, so there is time to fix them.'
        else 'Your profile can qualify for ' || (select n from live_inq)::text
             || ' more opportunities if you close ' || (select count(*) from gaps)::text
             || ' gap(s), starting with: ' || (select g.action from gaps g order by g.sort limit 1) || '.'
      end
    )
  );
$function$;

comment on function public.fn_supplier_advisor(bigint) is
  'Row #5 §15/§4. Why a supplier is losing work, and what to do about it. Loss percentages are '
  'returned ONLY when quotes exist; with none, loss_reasons is empty and basis says why. Every '
  'recommendation is computed from a real column, and impact_rfqs counts live inquiries.';

-- ==============================================================================================
-- SOURCE: scripts/sql/fn_supplier_network_map.sql
-- ==============================================================================================
-- ROW #5 §19 — THE SUPPLIER NETWORK MAP: real geography, and four layers scored honestly.
--
-- ── WHAT IS REAL AND WHAT IS EMPTY, MEASURED BEFORE WRITING ─────────────────────────────────────
-- suppliers  : 20,464 leads carry an emirate. REAL, and dense enough to be worth looking at.
-- demand     : 0 inquiries on production.
-- projects   : 0.
-- shipments  : there is no shipments relation at all.
--
-- So one of §19's four layers has data and three do not. Each layer returns its own `count` and its
-- own `basis`, and the empty ones come back as empty arrays rather than as plausible dots. A globe
-- speckled with invented demand would be the most seductive lie in this whole spec: it looks like
-- market intelligence, it photographs well, and nobody can tell by looking that it is nothing.
--
-- ── COORDINATES ARE REFERENCE GEOGRAPHY, NOT BUSINESS DATA ──────────────────────────────────────
-- leads has no lat/lng column, so emirate centroids are stated here as constants. That is the same
-- kind of fact as a map projection — the position of Dubai is not a claim about QuotesDone. What
-- WOULD be fabrication is the count at that position, and every count below is a real count(*).
create or replace function public.fn_supplier_network_map()
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with centroid(emirate, lat, lng) as (
    values ('Dubai', 25.2048, 55.2708),
           ('Abu Dhabi', 24.4539, 54.3773),
           ('Sharjah', 25.3463, 55.4209),
           ('Ajman', 25.4052, 55.5136),
           ('Ras Al Khaimah', 25.7895, 55.9432),
           ('Umm Al Quwain', 25.5647, 55.5552),
           ('Fujairah', 25.1288, 56.3265)
  ),
  -- Emirate names arrive in several spellings across 20,464 scraped rows, so they are normalised
  -- to the centroid table's keys. A row that matches nothing is counted as unplaced rather than
  -- dropped: silently discarding rows would make the map look tidier than the data is.
  norm as (
    select case
             when l.emirate ilike '%dubai%'      then 'Dubai'
             when l.emirate ilike '%abu%dhabi%'  then 'Abu Dhabi'
             when l.emirate ilike '%sharjah%'    then 'Sharjah'
             when l.emirate ilike '%ajman%'      then 'Ajman'
             when l.emirate ilike '%ras%khaim%'  then 'Ras Al Khaimah'
             when l.emirate ilike '%umm%quwain%' then 'Umm Al Quwain'
             when l.emirate ilike '%fujairah%'   then 'Fujairah'
             else null end as emirate,
           l.id, l.verified, l.matching_blocked
    from public.leads l
  )
  select jsonb_build_object(
    'generated_for', 'row5-section-19',

    -- ── LAYER 1: SUPPLIERS. Real, and the only populated one. ──────────────────────────────────
    'suppliers', jsonb_build_object(
      'basis', 'leads.emirate',
      'count', (select count(*) from norm where emirate is not null),
      'unplaced', (select count(*) from norm where emirate is null),
      'markers', (
        select coalesce(jsonb_agg(jsonb_build_object(
          'name', c.emirate, 'lat', c.lat, 'lng', c.lng,
          'count', (select count(*) from norm n where n.emirate = c.emirate),
          -- Kept separate because they are different claims: how many companies we KNOW OF versus
          -- how many can actually receive an RFQ. On production the second is 0 and the map must
          -- not let the first stand in for it.
          'matchable', (select count(*) from norm n where n.emirate = c.emirate
                          and coalesce(n.verified, false) and not coalesce(n.matching_blocked, false))
        ) order by c.emirate), '[]'::jsonb)
        from centroid c
      )
    ),

    -- ── LAYERS 2-4: EMPTY, each saying so in its own words ─────────────────────────────────────
    'demand', jsonb_build_object(
      'basis', 'inquiries',
      'count', (select count(*) from public.inquiries),
      'markers', '[]'::jsonb,
      'note', 'no inquiries exist yet, so no demand is plotted'
    ),
    'projects', jsonb_build_object(
      'basis', 'inquiries with a project',
      'count', (select count(*) from public.inquiries),
      'markers', '[]'::jsonb,
      'note', 'no projects exist yet'
    ),
    'shipments', jsonb_build_object(
      'basis', 'none',
      'count', 0,
      'markers', '[]'::jsonb,
      'note', 'there is no shipments relation in this schema; nothing is tracked to plot'
    ),

    'totals', jsonb_build_object(
      'leads', (select count(*) from public.leads),
      'placed', (select count(*) from norm where emirate is not null),
      'matchable', (select count(*) from norm
                    where coalesce(verified, false) and not coalesce(matching_blocked, false))
    )
  );
$function$;

comment on function public.fn_supplier_network_map() is
  'Row #5 §19. Supplier density by emirate from real leads, plus demand/projects/shipments layers '
  'that return EMPTY with a stated basis rather than plausible dots. Centroids are reference '
  'geography; every count is a real count(*).';

-- ==============================================================================================
-- SOURCE: scripts/sql/fn_supplier_market.sql
-- ==============================================================================================
-- ROW #5 §14 — MARKET INTELLIGENCE. The demand half, now that there is demand to read.
--
-- ── WHAT CHANGED AND WHY ────────────────────────────────────────────────────────────────────────
-- The previous version hard-coded `available: false` on demand_trend, most_requested and
-- avg_market_price, and that was the right answer to the estate it was written against: 0 inquiries
-- and 0 quotes, so every one of those figures would have been invented. A hard-coded false is the
-- wrong answer to a market that exists, and it is wrong in the more dangerous direction — it would
-- keep saying "not available yet" after the platform could answer, and no one would notice.
--
-- So availability is now COMPUTED. Each of the three figures returns a real value when its
-- population is non-empty and returns `available: false` with the empty population named when it is
-- not. The flag is derived from a count, which means this routine tells the truth on both sides of
-- the day the market starts, and neither side needs anybody to remember to come back and edit it.
--
-- ── DEMO ROWS AND REAL ROWS CANNOT SEE EACH OTHER ───────────────────────────────────────────────
-- This is a fence, not a filter, and it is the one the fixtures could not enforce for themselves.
-- §14 tells a supplier how many companies compete with them and what the market pays. Six demo
-- companies and twenty-four demo quotes would have moved both numbers for every real HVAC supplier
-- on the platform, and a real supplier would have had no way to know their competitor count was
-- inflated. One symmetric predicate, applied to every population below:
--
--     (coalesce(l.source, '') = 'qd_demo_fixture') = is_demo
--
-- A demo fixture's market is computed over demo rows; a real supplier's market over real rows.
-- Symmetric, so neither side leaks into the other, and it costs a real supplier nothing.
--
-- ── THE PERCENTAGE THIS CANNOT HONESTLY GIVE, AND THE ONE IT CAN ────────────────────────────────
-- Nothing here is back-dated, so every demo enquiry was created within minutes of each other and
-- the prior period is empty. A period-over-period percentage from a base of zero is undefined, and
-- "demand ↑ 600%" would be a fabrication dressed as arithmetic. So `pct` is NULL whenever the prior
-- period is empty, `from_zero` says why, and the weekly `series` is returned so the shape of the
-- run-up is visible rather than asserted.
--
-- `share_pct` IS honest and is computed: what proportion of all enquiries in the window are in this
-- supplier's category. It is labelled as a share, never as a trend, because they are different
-- claims and only one of them is available today.
create or replace function public.fn_supplier_market(p_lead_id bigint)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with me as (select * from public.leads where id = p_lead_id),
  flag as (select coalesce((select source from me), '') = 'qd_demo_fixture' as is_demo),

  -- Competitors: same sector, overlapping service area, not this supplier, same side of the fence.
  peers as (
    select l.*
    from public.leads l, me, flag
    where l.id <> me.id
      and l.sector is not null
      and me.sector is not null
      and l.sector = me.sector
      and coalesce(l.permanently_closed, false) = false
      and (coalesce(l.source, '') = 'qd_demo_fixture') = flag.is_demo
  ),
  peers_here as (
    select p.* from peers p, me
    where me.service_emirates is null
       or coalesce(array_length(me.service_emirates, 1), 0) = 0
       or p.emirate is null
       or exists (select 1 from unnest(me.service_emirates) e where p.emirate ilike '%' || e || '%')
  ),

  -- ── THE DEMAND POPULATIONS ────────────────────────────────────────────────────────────────────
  -- Every enquiry on this side of the fence, and the subset in this supplier's own category.
  -- The window is 28 days split into two 14-day halves; `cur` is the half that just ended.
  demand_all as (
    select i.* from public.inquiries i, flag
    where (coalesce(i.brief_source, '') = 'qd_demo_fixture') = flag.is_demo
      and i.created_at >= now() - interval '28 days'
  ),
  demand_mine as (
    select d.* from demand_all d, me where me.sector is not null and d.category = me.sector
  ),
  -- Quotes are priced against enquiries, so the price population is the quotes ON those enquiries.
  priced as (
    select q.quote_amount amt
    from public.quotes q join demand_mine d on d.id = q.inquiry_id, flag
    where (coalesce(q.source, '') = 'qd_demo_fixture') = flag.is_demo
      and q.quote_amount is not null and q.quote_amount > 0
  ),

  -- ── THE THREE FIGURES, EACH BUILT ONCE ────────────────────────────────────────────────────────
  -- Built in a CTE and referenced by key below, rather than inline, so each figure's empty branch
  -- sits with the computation it belongs to instead of beside the key it answers for.
  figures as (
    select
      -- Trend. Direction is a comparison of two counted halves; pct is only produced when there is
      -- a prior period to divide by.
      (with c as (
         select count(*) filter (where created_at >= now() - interval '14 days') as recent,
                count(*) filter (where created_at <  now() - interval '14 days') as earlier
         from demand_mine)
       select case when c.recent = 0 and c.earlier = 0
         then jsonb_build_object(
                'available', false, 'value', null, 'direction', null,
                'basis', 'enquiries in your category over the last 28 days',
                'population', 0,
                'note', 'no enquiries in your category yet, so there is no series to trend')
         else jsonb_build_object(
                'available', true,
                'category', (select sector from me),
                'value', c.recent,
                'prior', c.earlier,
                'direction', case when c.recent > c.earlier then 'up'
                                  when c.recent < c.earlier then 'down' else 'flat' end,
                'pct', case when c.earlier > 0
                            then round(((c.recent - c.earlier)::numeric / c.earlier) * 100, 1)
                            else null end,
                'from_zero', c.earlier = 0,
                'share_pct', case when (select count(*) from demand_all) > 0
                             then round((c.recent::numeric
                                  / nullif((select count(*) from demand_all), 0)) * 100, 1)
                             else null end,
                'series', (
                  select coalesce(jsonb_agg(jsonb_build_object('week', w.wk, 'count', w.c) order by w.wk), '[]'::jsonb)
                  from (select date_trunc('week', created_at)::date wk, count(*) c
                        from demand_mine group by 1) w),
                'basis', 'enquiries in your category, two 14-day halves',
                'population', (select count(*) from demand_mine),
                'note', case when c.earlier = 0
                        then 'first activity in this window, so there is no prior period to take a percentage against'
                        else null end)
         end from c) as trend_obj,

      -- The single most-asked-for category across the whole population, with its count.
      (with r as (select category cat, count(*) c from demand_all
                  where category is not null group by 1 order by count(*) desc limit 1)
       select case when not exists (select 1 from r)
         then jsonb_build_object(
                'available', false, 'value', null,
                'basis', 'enquiries over the last 28 days',
                'population', (select count(*) from demand_all),
                'note', 'that is a fact about requests, and none have been made')
         else jsonb_build_object(
                'available', true,
                'value', (select cat from r),
                'count', (select c from r),
                'basis', 'enquiries over the last 28 days, grouped by category',
                'population', (select count(*) from demand_all))
         end) as topcat_obj,

      -- What the market is actually charging. The median matters more than the mean to a supplier
      -- deciding where to sit, and the quartiles are what "you are high/low" is measured against,
      -- so all of them are returned rather than one number with no spread around it.
      (with s as (
         select count(*) n, round(avg(amt)) mean,
                round(percentile_cont(0.5)  within group (order by amt)) mid,
                round(percentile_cont(0.25) within group (order by amt)) lo,
                round(percentile_cont(0.75) within group (order by amt)) hi,
                min(amt) lowest, max(amt) highest
         from priced)
       select case when s.n = 0
         then jsonb_build_object(
                'available', false, 'value', null, 'currency', 'AED',
                'basis', 'quotes on enquiries in your category',
                'population', 0,
                'note', 'nothing in your category has been priced, so there is no market price')
         else jsonb_build_object(
                'available', true, 'currency', 'AED',
                'value', s.mean, 'median', s.mid, 'p25', s.lo, 'p75', s.hi,
                'low', s.lowest, 'high', s.highest,
                'basis', 'quotes on enquiries in your category over the last 28 days',
                'population', s.n)
         end from s) as money_obj
  )

  select jsonb_build_object(
    'lead_id', p_lead_id,
    'sector', (select sector from me),
    'population', case when (select is_demo from flag) then 'demo' else 'live' end,

    -- ── The competitive picture, real since the first scrape ─────────────────────────────────────
    'competitors', jsonb_build_object(
      'available', true,
      'basis', 'leads in the same sector',
      'total', (select count(*) from peers),
      'in_my_area', (select count(*) from peers_here),
      -- The number a scraped list hides: how many competitors can receive an RFQ at all.
      'matchable', (
        select count(*) from peers p
        where public.fn_is_matchable(p.verified, p.banned, p.matching_blocked,
                                     p.approval_status, p.permanently_closed, p.chat_strikes)
      ),
      -- Group FIRST, build the json after. `group by 1` over a jsonb_build_object containing
      -- count(*) raises 42803: the grouping key would be an expression containing an aggregate.
      'by_emirate', (
        select coalesce(jsonb_agg(jsonb_build_object('emirate', s.em, 'count', s.c) order by s.c desc), '[]'::jsonb)
        from (
          select p.emirate as em, count(*) as c
          from peers p where p.emirate is not null
          group by p.emirate order by count(*) desc limit 8
        ) s
      )
    ),

    'market_composition', jsonb_build_object(
      'available', true,
      'basis', 'leads in the same sector, grouped by category',
      'segments', (
        select coalesce(jsonb_agg(jsonb_build_object('name', s.nm, 'count', s.c) order by s.c desc), '[]'::jsonb)
        from (
          select coalesce(nullif(btrim(split_part(p.categories, ',', 1)), ''), 'Uncategorised') as nm,
                 count(*) as c
          from peers p group by 1 order by count(*) desc limit 8
        ) s
      )
    ),

    -- ── The demand half. Computed when there is a population, refused when there is not ──────────
    'demand_trend',     (select trend_obj  from figures),
    'most_requested',   (select topcat_obj from figures),
    'avg_market_price', (select money_obj  from figures)
  );
$function$;

comment on function public.fn_supplier_market(bigint) is
  'Row #5 §14. Competitor and supply-composition figures from real leads; demand trend, '
  'most-requested and average price are COMPUTED when their population is non-empty and return '
  'available:false naming the empty population when it is not. Demo and live rows are partitioned '
  'symmetrically so a fixture can never move a real supplier''s numbers.';

-- ==============================================================================================
-- SOURCE: scripts/sql/fn_supplier_workspaces.sql
-- ==============================================================================================
-- ROW #5 §18 — THE SUPPLIER COLLABORATION WORKSPACE.
--
-- ── "EVERY CUSTOMER RELATIONSHIP GETS A WORKSPACE" ──────────────────────────────────────────────
-- A relationship in this schema is an (inquiry, supplier) pair: that is what chat_threads and
-- messages are keyed on, and what a reveal creates. So a workspace is one row per pair, holding the
-- project it belongs to, its files, its message count and its timeline — the four things §18 draws.
--
-- The pieces all existed separately. inquiries carries the project, messages carries the
-- conversation, and documents carries the files keyed by (ref_table, ref_id) — there is no
-- inquiry_docs table, which an earlier draft of this file assumed and Postgres corrected. NOTHING
-- joined them into a per-relationship container the supplier could open. This is that join.
--
-- ── WHY THIS RETURNS AN EMPTY LIST ON PRODUCTION TODAY, AND WHY THAT IS NOT A BUG ───────────────
-- 0 inquiries and 0 inquiry_matches exist, so there are no relationships to render. The function
-- returns an empty array with `population` naming the two counts, so an empty workspace list is
-- never mistaken for a query that failed.
--
-- It is NOT filled with a demo relationship, and that is a deliberate limit rather than an
-- oversight. Inserting one inquiry on production fires TWELVE triggers, including
-- fn_emit_event('inquiry','rfq.created') — which would inject a synthetic event into the row #2
-- event backbone that is separately measured at 107/110 — and trg_autodispatch_inquiry. Matching
-- would find 0 suppliers because none is verified, so no real company would be contacted, but
-- polluting another row's measured estate is the founder's call to make, not a side effect to slip
-- in. The mechanism is built and provable; the data path is flagged, not faked.
create or replace function public.fn_supplier_workspaces(p_lead_id bigint)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with rel as (
    -- One row per customer relationship this supplier actually has: an inquiry they were matched
    -- to, or one they have exchanged messages about.
    select distinct i.id as inquiry_id
    from public.inquiries i
    where exists (select 1 from public.inquiry_matches m
                  where m.inquiry_id = i.id and m.supplier_id = p_lead_id)
       or exists (select 1 from public.messages g
                  where g.inquiry_id = i.id and g.supplier_id = p_lead_id)
  )
  select jsonb_build_object(
    'lead_id', p_lead_id,
    'count', (select count(*) from rel),
    -- The populations behind an empty list, so nobody has to guess whether the query worked.
    'population', jsonb_build_object(
      'inquiries', (select count(*) from public.inquiries),
      'matches_for_me', (select count(*) from public.inquiry_matches where supplier_id = p_lead_id)
    ),
    'note', case when (select count(*) from rel) = 0
                 then 'no customer relationships yet — nothing has been matched or messaged'
                 else null end,
    'workspaces', (
      select coalesce(jsonb_agg(w order by w->>'last_activity' desc nulls last), '[]'::jsonb)
      from (
        select jsonb_build_object(
          'inquiry_id', i.id,
          -- §18's project identity.
          'project', jsonb_build_object(
            -- inquiries has no `title` column. The human-readable name is the summary, then the
            -- category, then the RFQ number — falling through in that order means a workspace
            -- always has a name rather than rendering as blank.
            'title', coalesce(nullif(btrim(coalesce(i.summary, '')), ''), i.category,
                              'RFQ ' || coalesce(i.rfq_no::text, i.id::text)),
            'category', i.category,
            'emirate', i.emirate,
            'status', i.status,
            'created_at', i.created_at
          ),
          -- §18's files, CATEGORISED. The spec names drawings, specifications and contracts, so the
          -- bucket is derived from the document's own kind rather than left as one undifferentiated
          -- pile — a workspace whose files are a flat list is the thing §18 replaces.
          'files', (
            select coalesce(jsonb_agg(jsonb_build_object(
              'name', d.file_name, 'kind', d.kind, 'created_at', d.created_at,
              'category', case
                when d.kind ~* 'drawing|dwg|plan|layout'        then 'drawings'
                when d.kind ~* 'spec|datasheet|boq|schedule'    then 'specifications'
                when d.kind ~* 'contract|agreement|po|purchase' then 'contracts'
                else 'other' end
            ) order by d.created_at desc), '[]'::jsonb)
            from public.documents d
            where d.ref_table = 'inquiries' and d.ref_id = i.id::text
          ),
          'file_categories', (
            select jsonb_build_object(
              'drawings', count(*) filter (where d.kind ~* 'drawing|dwg|plan|layout'),
              'specifications', count(*) filter (where d.kind ~* 'spec|datasheet|boq|schedule'),
              'contracts', count(*) filter (where d.kind ~* 'contract|agreement|po|purchase'),
              'other', count(*) filter (where d.kind !~* 'drawing|dwg|plan|layout|spec|datasheet|boq|schedule|contract|agreement|po|purchase')
            )
            from public.documents d
            where d.ref_table = 'inquiries' and d.ref_id = i.id::text
          ),
          -- §18's message count, and the unread split a supplier actually acts on.
          'message_count', (
            select count(*) from public.messages g
            where g.inquiry_id = i.id and g.supplier_id = p_lead_id and not coalesce(g.blocked, false)
          ),
          'unread', (
            select count(*) from public.messages g
            where g.inquiry_id = i.id and g.supplier_id = p_lead_id
              and g.sender = 'customer' and not coalesce(g.read_by_supplier, false)
              and not coalesce(g.blocked, false)
          ),
          'last_activity', (
            select max(g.created_at) from public.messages g
            where g.inquiry_id = i.id and g.supplier_id = p_lead_id
          ),
          -- §18's timeline percentage. Derived from the stages the relationship has actually
          -- passed, so it moves for a real reason and is null before anything has happened rather
          -- than sitting at a meaningless 0%.
          'timeline', (
            select jsonb_build_object(
              'pct', case when total = 0 then null else round(100.0 * hit / total) end,
              'stages', jsonb_build_object(
                'matched', matched, 'messaged', messaged, 'quoted', quoted, 'awarded', awarded)
            )
            from (
              select 4 as total,
                (exists (select 1 from public.inquiry_matches m where m.inquiry_id = i.id and m.supplier_id = p_lead_id))::int
                  as matched,
                (exists (select 1 from public.messages g where g.inquiry_id = i.id and g.supplier_id = p_lead_id))::int
                  as messaged,
                (exists (select 1 from public.quotes q where q.inquiry_id = i.id and q.supplier_id = p_lead_id))::int
                  as quoted,
                (exists (select 1 from public.quotes q where q.inquiry_id = i.id and q.supplier_id = p_lead_id
                         and q.status = 'won'))::int as awarded
            ) s, lateral (select (s.matched + s.messaged + s.quoted + s.awarded) as hit) h
          )
        ) as w
        from rel r join public.inquiries i on i.id = r.inquiry_id
      ) t
    )
  );
$function$;

comment on function public.fn_supplier_workspaces(bigint) is
  'Row #5 §18. One workspace per customer relationship — project, categorised files, message count '
  'and a stage-derived timeline. Returns an empty list with its population named when the supplier '
  'has no relationships; timeline pct is null rather than 0 before anything has happened.';

-- ==============================================================================================
-- SOURCE: scripts/sql/supplier_rating_model.sql
-- ==============================================================================================
-- ROW #5 — THE SUPPLIER RATING MODEL, as the founder specified it on 2026-08-08.
--
-- ── THE DECISION THIS IMPLEMENTS ────────────────────────────────────────────────────────────────
-- "These leads will not have rating. We will have rating for the verified suppliers. So once we
--  start emailing and inviting these leads, once they join in and they are verified, then the score
--  and score rating for the suppliers is active. It's just for the verified ones."
--
-- Three inputs, in the founder's own order of power:
--   1. A reveal the supplier does not respond to  — the only thing that DROPS a rating today.
--   2. Jobs won through the platform              — more work, higher rating.
--   3. The customer's own 1-5 rating with a written reason, solicited after the job — HIGHEST power.
--
-- ── WHAT WAS WRONG BEFORE ───────────────────────────────────────────────────────────────────────
-- fn_supplier_score_refresh wrote `leads.rating` into supplier_score.quality_rating.
-- leads.rating is the GOOGLE MAPS star rating of a scraped business — Google's opinion of a company
-- QuotesDone has never worked with, on 4,477 rows, none of them verified, none of them a customer of
-- ours. Presenting that as "your QuotesDone quality rating" is a claim the platform has not earned
-- and cannot stand behind. It was also on the wrong scale: 0-5 rendered into a 0-100 bar, so a
-- 4.5-star business displayed as "5%".
--
-- The scale bug is now moot, because the Maps number is not the source at all.
--
-- ── AND THE `reviews` TABLE WAS ALREADY THERE, UNREAD ───────────────────────────────────────────
-- public.reviews already carries supplier_id, customer_id, inquiry_id, rating, comment and six
-- sub-scores. Measured before this change: 0 rows, and ZERO routines referencing it. Built and
-- abandoned, exactly like supplier_product was. This is its first reader.

-- ── 1. A RATING WITHOUT A REASON IS NOT ACCEPTED ────────────────────────────────────────────────
-- "he need to specify a reason. he need to write anything. Like, even if it's, like, five words
--  would be enough." A bare star with no words is worth little to the next customer reading it, and
--  the whole point of collecting these is that a future customer can weigh them. Ten characters is
--  about five short words — low enough not to make it hard, high enough to exclude an empty box.
alter table public.reviews
  drop constraint if exists reviews_reason_required;
alter table public.reviews
  add constraint reviews_reason_required
  check (comment is not null and length(btrim(comment)) >= 10) not valid;

alter table public.reviews
  drop constraint if exists reviews_rating_range;
alter table public.reviews
  add constraint reviews_rating_range check (rating between 1 and 5) not valid;

-- One rating per customer per job. Without this a single unhappy customer could file ten reviews and
-- sink a supplier, which would make the whole signal untrustworthy for everyone reading it.
create unique index if not exists reviews_one_per_job
  on public.reviews (supplier_id, inquiry_id, customer_id);

-- ── 2. QUALITY RATING IS EARNED ON THE PLATFORM, BY VERIFIED SUPPLIERS ONLY ─────────────────────
create or replace function public.fn_supplier_quality(p_lead_id bigint)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  select jsonb_build_object(
    'lead_id', p_lead_id,
    -- NULL, not 0, when there is nothing to say. An unrated supplier is unrated; a supplier rated
    -- zero is one every customer disliked, and those must never look the same on a screen.
    'stars', (select round(avg(r.rating)::numeric, 2) from public.reviews r where r.supplier_id = p_lead_id),
    'pct', (select round(avg(r.rating)::numeric * 20, 1) from public.reviews r where r.supplier_id = p_lead_id),
    'count', (select count(*) from public.reviews r where r.supplier_id = p_lead_id),
    'eligible', (select coalesce(verified, false) from public.leads where id = p_lead_id),
    'reason', case
      when not (select coalesce(verified, false) from public.leads where id = p_lead_id)
        then 'not_verified'
      when (select count(*) from public.reviews r where r.supplier_id = p_lead_id) = 0
        then 'no_reviews_yet'
      else null end,
    -- The written reasons, which are the point. A star with no words persuades nobody.
    'recent', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'stars', r.rating, 'comment', r.comment, 'at', r.created_at
      ) order by r.created_at desc), '[]'::jsonb)
      from (select * from public.reviews where supplier_id = p_lead_id
            order by created_at desc limit 5) r
    ),
    -- The sub-scores the table already carries, averaged where present.
    'facets', (
      select jsonb_build_object(
        'communication', round(avg(r.r_communication)::numeric, 2),
        'quality', round(avg(r.r_quality)::numeric, 2),
        'punctuality', round(avg(r.r_punctuality)::numeric, 2),
        'documentation', round(avg(r.r_documentation)::numeric, 2),
        'after_sales', round(avg(r.r_after_sales)::numeric, 2),
        'compliance', round(avg(r.r_compliance)::numeric, 2))
      from public.reviews r where r.supplier_id = p_lead_id
    )
  );
$function$;

comment on function public.fn_supplier_quality(bigint) is
  'Row #5. A supplier''s EARNED quality rating: customer reviews only, verified suppliers only, '
  'NULL when unrated. Never the scraped Google Maps star rating.';

-- ==============================================================================================
-- SOURCE: scripts/sql/fn_supplier_score_refresh.sql
-- ==============================================================================================
CREATE OR REPLACE FUNCTION public.fn_supplier_score_refresh()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare n integer;
begin
  insert into supplier_score (lead_id, response_rate, avg_response_hours, quotes_submitted, quotes_won,
                              rejection_count, price_index, quality_rating, reliability, last_active, computed_at)
  select l.id,
         coalesce(l.rv_response_rate, 0),
         null,
         coalesce(q.submitted, 0),
         coalesce(q.won, 0),
         coalesce(q.rejected, 0),
         q.price_index,
         -- QUALITY RATING IS EARNED ON THE PLATFORM, NOT SCRAPED FROM GOOGLE.
         -- Founder decision, 2026-08-08: rating exists only for VERIFIED suppliers, and comes from
         -- the customer's own 1-5 review after a job. leads.rating is the Google Maps star rating of
         -- a business we have never worked with; presenting it as a QuotesDone quality rating is a
         -- claim the platform has not earned. NULL when unverified or unreviewed -- an unrated
         -- supplier is unrated, and must never look like one every customer disliked.
         case when not coalesce(l.verified, false) then null
              else (select round(avg(rv.rating)::numeric * 20, 1)
                      from reviews rv where rv.supplier_id = l.id) end,
         -- Reliability: response behaviour dominates, win rate confirms it, rejections and refunds subtract.
         round(least(100, greatest(0,
             coalesce(l.rv_response_rate,0) * 0.55
           + (case when coalesce(q.submitted,0) > 0 then 100.0*coalesce(q.won,0)/q.submitted else 0 end) * 0.25
           + (case when l.verified then 20 else 0 end)
           - coalesce(q.rejected,0) * 2
           - coalesce(l.rv_nonresponse_refunds,0) * 5
         )), 1),
         greatest(l.portal_updated_at, l.approved_at, l.scraped_at),
         now()
  from leads l
  left join (
    select q.supplier_id,
           count(*) as submitted,
           count(*) filter (where q.status = 'won')      as won,
           count(*) filter (where q.status = 'rejected') as rejected,
           round(avg(q.quote_amount) filter (where q.quote_amount > 0), 2) as price_index
    from quotes q group by q.supplier_id
  ) q on q.supplier_id = l.id
  where l.id is not null
  on conflict (lead_id) do update set
    response_rate = excluded.response_rate, quotes_submitted = excluded.quotes_submitted,
    quotes_won = excluded.quotes_won, rejection_count = excluded.rejection_count,
    price_index = excluded.price_index, quality_rating = excluded.quality_rating,
    reliability = excluded.reliability, last_active = excluded.last_active, computed_at = now();
  get diagnostics n = row_count;
  return n;
end; $function$
;

-- ==============================================================================================
-- SOURCE: scripts/sql/cron_supplier_score_refresh.sql
-- ==============================================================================================
-- ROW #5 §13 `perf-living` — MAKE THE SUPPLIER SCORE ACTUALLY LIVING.
--
-- ── THE MEASUREMENT THAT PROMPTED THIS ──────────────────────────────────────────────────────────
-- verify_supplier_blueprint, 2026-08-07:
--   perf-living  MISSING  0 active cron(s) recompute a score, 4 routine(s) touch supplier_score,
--                         20465 of 20465 row(s) computed in the last 30d
--
-- The spec's §13 opens with the words "A LIVING score". The estate already had the whole
-- computation — public.fn_supplier_score_refresh() recomputes response_rate, quotes submitted/won,
-- rejections, price_index, quality and reliability for EVERY lead from `leads` and `quotes` — and
-- nothing ever called it on a schedule. A score written once is a snapshot, not a living thing, and
-- the check was right to say so.
--
-- ── WHY THIS IS SAFE TO RUN OVER 20,465 ROWS ────────────────────────────────────────────────────
-- Verified before scheduling, rather than assumed:
--   · supplier_score.quality_rating is non-null on 4,478 rows and leads.rating on 4,477 — the same
--     population, so the existing data was already produced by THIS routine. Re-running refreshes
--     values rather than rewriting semantics.
--   · avg(reliability) is currently 0.0 across the estate: rv_response_rate is set on 2 rows and
--     `verified` on none, so the formula legitimately yields ~0 for a company with no traffic. The
--     refresh will keep yielding ~0 until there is traffic. Nothing is inflated by running it.
--   · It is an upsert keyed on lead_id, so it neither duplicates nor deletes.
--
-- 03:40 UTC: after the nightly enrichment crons and well clear of doc_expiry_daily at 05:20, so a
-- supplier's score reflects the documents and profile state the same night's jobs left behind.
select cron.schedule(
  'supplier_score_refresh_daily',
  '40 3 * * *',
  $$select public.fn_supplier_score_refresh();$$
)
where not exists (select 1 from cron.job where jobname = 'supplier_score_refresh_daily');

-- Run it once now. A cron that has never fired leaves `computed_at` stale until tomorrow, and a
-- check asking "is this score living" would read the same MISSING for a day while being wrong.
select public.fn_supplier_score_refresh();

-- SOURCE: scripts/sql/fn_supplier_quote_recommend.sql
-- ==============================================================================================
-- ROW #5 §11 — THE AI QUOTE BUILDER. The supplier writes nothing; the routine proposes the terms.
--
-- ── WHAT THIS IS NOT, BECAUSE THE ESTATE ALREADY HAS BOTH OF THEM ───────────────────────────────
-- fn_quote_coach GRADES a quote the supplier already wrote. fn_supplier_negotiation READS one back
-- and drafts a reply about it. Both live near the words "recommend" and "price" and neither one
-- proposes a quote. §11's premise is the opposite of both: nothing exists yet, and the routine
-- produces the price, the delivery, the warranty and the risk from the market around the enquiry.
--
-- ── EVERY FIGURE COMES FROM THE COMPETING BIDS ON THIS ENQUIRY, NOT FROM A CATEGORY AVERAGE ──────
-- The first design took the median of every quote in the category. That is wrong in a way that
-- looks right: the category holds a 268,000 restaurant extract and a 1,333,400 tower FCU package,
-- so its median is a number no individual project has any reason to be near. What a supplier
-- actually needs to know is what the OTHER suppliers bid on THIS enquiry, and that is a population
-- of four here — small, but exactly the right four.
--
-- When that population is empty the routine returns available:false and names it. It does not fall
-- back to a category average and call it a recommendation, because a supplier cannot tell the
-- difference on screen between a figure derived from this project and one derived from a different
-- project of a different size.
--
-- ── WHY THE MEDIAN, AND WHY THE SPREAD IS RETURNED WITH IT ──────────────────────────────────────
-- The recommendation is the midpoint of the competing bids. Undercutting is a decision with
-- consequences for the supplier's margin and it is theirs to take, not the routine's to take for
-- them — so the full range and both quartiles come back with the number and the surface shows them.
-- A single figure with no spread around it would hide how much disagreement there is about scope.
--
-- ── DEMO AND LIVE ARE PARTITIONED, AS THEY ARE IN fn_supplier_market ─────────────────────────────
-- Same symmetric predicate. A demo fixture prices against demo bids; a real supplier prices against
-- real ones. A fixture can never move the price a real supplier is advised to charge.
create or replace function public.fn_supplier_quote_recommend(p_lead_id bigint, p_inquiry_id uuid)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with me as (select * from public.leads where id = p_lead_id),
  flag as (select coalesce((select source from me), '') = 'qd_demo_fixture' as is_demo),
  inq as (select * from public.inquiries where id = p_inquiry_id),

  -- The competing bids: what every OTHER supplier has priced this same enquiry at.
  bids as (
    select q.quote_amount amt, q.lead_time, q.warranty, q.payment_terms
    from public.quotes q, flag
    where q.inquiry_id = p_inquiry_id
      and q.supplier_id is distinct from p_lead_id
      and q.quote_amount is not null and q.quote_amount > 0
      and (coalesce(q.source, '') = 'qd_demo_fixture') = flag.is_demo
  ),
  stat as (
    select count(*) n,
           round(percentile_cont(0.5)  within group (order by amt)) mid,
           round(percentile_cont(0.25) within group (order by amt)) lo,
           round(percentile_cont(0.75) within group (order by amt)) hi,
           min(amt) lowest, max(amt) highest
    from bids
  ),

  -- The supplier's own habit, measured rather than assumed: across every enquiry they have priced,
  -- where did they sit against the midpoint of that enquiry's other bids? An index of 1.04 means
  -- this company prices 4% above the middle of the market, and it is computed from their own rows.
  habit as (
    select round(avg(ratio)::numeric, 3) idx, count(*) n
    from (
      select q.quote_amount / nullif((
               select percentile_cont(0.5) within group (order by o.quote_amount)
               from public.quotes o
               where o.inquiry_id = q.inquiry_id and o.supplier_id is distinct from q.supplier_id
                 and o.quote_amount > 0), 0) as ratio
      from public.quotes q, flag
      where q.supplier_id = p_lead_id and q.quote_amount > 0
        and (coalesce(q.source, '') = 'qd_demo_fixture') = flag.is_demo
    ) r where r.ratio is not null
  ),

  -- ── DELIVERY, WARRANTY AND TERMS ARE TEXT, SO THEY ARE PICKED, NOT AVERAGED ───────────────────
  -- The average of "8-10 weeks" and "12-14 weeks" is not a promise anybody made, so the routine
  -- returns an answer a real supplier actually gave.
  --
  -- WHICH answer took two attempts, and the first one was wrong in a way worth recording. Taking
  -- `order by count(*) desc, <text>` looks like "the most common", but when all four bids are
  -- distinct every count is 1 and the tie breaks ALPHABETICALLY — which recommended "12-14 weeks",
  -- the slowest delivery on the board, and "12 months on equipment", the weakest warranty. A
  -- tie-break is not a market consensus, and dressing one up as the modal answer is the same defect
  -- class as an invented percentage: arithmetic that ran correctly over the wrong population.
  --
  -- So: when a value genuinely repeats, that mode is the answer and `agreed_by` says how many said
  -- it. When nothing repeats there IS no consensus, and the answer is the MIDDLE of the observed
  -- range ranked by its leading number — a real bid, neither the fastest nor the slowest — with
  -- `consensus` false so the surface can say the suppliers disagreed.
  ranked as (
    select 'lead' kind, lead_time v, count(*) c,
           min(coalesce(substring(lead_time from '\d+')::int, 999)) ord
    from bids where lead_time is not null group by 1, 2
    union all
    select 'warranty', warranty, count(*),
           min(coalesce(substring(warranty from '\d+')::int, 999))
    from bids where warranty is not null group by 1, 2
    union all
    select 'terms', payment_terms, count(*),
           min(coalesce(substring(payment_terms from '\d+')::int, 999))
    from bids where payment_terms is not null group by 1, 2
  ),
  picked as (
    select kind, v, c, has_mode from (
      select r.kind, r.v, r.c,
             max(r.c) over (partition by r.kind) >= 2 as has_mode,
             row_number() over (partition by r.kind order by r.c desc, r.ord) rn_mode,
             row_number() over (partition by r.kind order by r.ord) rn_ord,
             count(*) over (partition by r.kind) tot
      from ranked r
    ) z
    where (z.has_mode and z.rn_mode = 1)
       or (not z.has_mode and z.rn_ord = (z.tot + 1) / 2)
  ),
  lead_pick  as (select v, c, has_mode from picked where kind = 'lead'),
  warr_pick  as (select v, c, has_mode from picked where kind = 'warranty'),
  terms_pick as (select v, c, has_mode from picked where kind = 'terms'),

  -- ── RISK, AS NAMED SIGNALS RATHER THAN A MOOD ─────────────────────────────────────────────────
  -- Each signal is a condition on a real column, each carries the sentence a supplier would need to
  -- act on it, and the level is the count. A risk score with no reasons attached is a number the
  -- supplier can neither check nor fix.
  risk as (
    select coalesce(jsonb_agg(jsonb_build_object('signal', s.k, 'detail', s.d)) filter (where s.hit), '[]'::jsonb) items,
           count(*) filter (where s.hit) n
    from (
      select 'not_matchable' k,
             not public.fn_is_matchable(m.verified, m.banned, m.matching_blocked,
                                        m.approval_status, m.permanently_closed, m.chat_strikes) hit,
             'Your account cannot currently receive work, so a quote sent now may not reach the customer.' d
      from me m
      union all
      select 'licence_missing',
             (select license_expiry is null from me),
             'No licence expiry is on file, and approval depends on it.'
      union all
      select 'licence_expired',
             (select coalesce(license_expiry < current_date, false) from me),
             'Your trade licence has expired.'
      union all
      select 'brief_incomplete',
             coalesce(((select completeness->>'score' from inq))::int < 60, true),
             'The customer brief is incomplete, so the scope you price may move after you send this.'
      union all
      select 'thin_market',
             (select n from stat) < 3,
             'Fewer than three other suppliers have priced this, so the midpoint is a weak signal.'
      union all
      select 'wide_spread',
             (select case when mid > 0 then (highest - lowest) / mid > 0.4 else false end from stat),
             'The other bids disagree by more than 40%, which usually means the scope is being read differently.'
    ) s
  )

  select case when (select n from stat) = 0
    then jsonb_build_object(
      'available', false,
      'lead_id', p_lead_id, 'inquiry_id', p_inquiry_id,
      'basis', 'quotes from other suppliers on this enquiry',
      'population', 0,
      'note', 'no other supplier has priced this enquiry yet, so there is no market midpoint to '
              'recommend against. A figure taken from a different project of a different size '
              'would look identical on screen and mean nothing.')
    else jsonb_build_object(
      'available', true,
      'lead_id', p_lead_id, 'inquiry_id', p_inquiry_id,
      'summary', (select summary from inq),
      'population', (select n from stat),
      'basis', 'the midpoint of every other supplier''s bid on this enquiry',

      -- The recommended price, with the spread it came from.
      'recommended_price', jsonb_build_object(
        'value', (select mid from stat), 'currency', 'AED',
        'p25', (select lo from stat), 'p75', (select hi from stat),
        'low', (select lowest from stat), 'high', (select highest from stat),
        'basis', 'median of ' || (select n from stat)::text || ' competing bid(s) on this enquiry'),

      -- Where that recommendation sits, and where this supplier usually sits.
      'market_position', jsonb_build_object(
        'verdict', 'at the market midpoint',
        'your_index', (select idx from habit),
        'your_quotes_measured', (select n from habit),
        'detail', case when (select idx from habit) is null
                  then 'You have not priced enough enquiries yet for us to know where you usually sit.'
                  when (select idx from habit) > 1.02
                  then 'You normally price about ' || round(((select idx from habit) - 1) * 100)::text
                       || '% above the middle of the market, so this suggestion is lower than your habit.'
                  when (select idx from habit) < 0.98
                  then 'You normally price about ' || round((1 - (select idx from habit)) * 100)::text
                       || '% below the middle of the market, so this suggestion is higher than your habit.'
                  else 'You normally price close to the middle of the market, in line with this suggestion.' end),

      -- Delivery, suggested from what the competition actually promised.
      'delivery_estimate', jsonb_build_object(
        'value', (select v from lead_pick),
        'agreed_by', (select c from lead_pick),
        'consensus', (select has_mode from lead_pick),
        'observed', (select coalesce(jsonb_agg(distinct lead_time), '[]'::jsonb) from bids where lead_time is not null),
        'basis', case when (select has_mode from lead_pick)
                 then 'the lead time most of the competing bids gave'
                 else 'no two bids gave the same lead time, so this is the middle of the range' end),

      -- Warranty, picked the same way and with the same honesty about disagreement.
      'warranty', jsonb_build_object(
        'value', (select v from warr_pick),
        'agreed_by', (select c from warr_pick),
        'consensus', (select has_mode from warr_pick),
        'observed', (select coalesce(jsonb_agg(distinct warranty), '[]'::jsonb) from bids where warranty is not null),
        'basis', case when (select has_mode from warr_pick)
                 then 'the warranty most of the competing bids offered'
                 else 'no two bids offered the same warranty, so this is the middle of the range' end),

      'payment_terms', jsonb_build_object(
        'value', (select v from terms_pick),
        'agreed_by', (select c from terms_pick),
        'consensus', (select has_mode from terms_pick),
        'basis', case when (select has_mode from terms_pick)
                 then 'the payment terms most of the competing bids asked for'
                 else 'no two bids asked for the same terms, so this is the middle of the range' end),

      -- ── RISK: A LEVEL, ITS REASONS, AND WHAT TO DO ABOUT IT ───────────────────────────────────
      -- The first version returned a level and its signals and stopped there, which leaves the
      -- supplier holding the word "high" and no next move. Every other figure on this screen is a
      -- proposal, and the risk should be one too: the routine names the single action that would
      -- most reduce it, drawn from the same signals rather than from a phrasebook.
      'risk_level', jsonb_build_object(
        'value', case when (select n from risk) >= 3 then 'high'
                      when (select n from risk) >= 1 then 'medium' else 'low' end,
        'count', (select n from risk),
        'signals', (select items from risk),
        'recommended_action', case
          when (select n from risk) = 0
            then 'Nothing is working against this quote. We suggest sending it as proposed.'
          when exists (select 1 from jsonb_array_elements((select items from risk)) e
                       where e->>'signal' in ('not_matchable', 'licence_expired', 'licence_missing'))
            then 'We suggest fixing your account before you send this: a quote from an account that '
                 || 'cannot be matched may never reach the customer, whatever price is on it.'
          when exists (select 1 from jsonb_array_elements((select items from risk)) e
                       where e->>'signal' = 'wide_spread')
            then 'We suggest asking the customer to confirm the scope before you commit to a price. '
                 || 'The other bids disagree enough that they are probably not all pricing the same job.'
          when exists (select 1 from jsonb_array_elements((select items from risk)) e
                       where e->>'signal' = 'brief_incomplete')
            then 'We suggest putting your assumptions in writing with this quote, so a change of '
                 || 'scope later is a variation rather than an argument.'
          else 'We suggest treating the suggested price as indicative until more suppliers have priced this.'
          end,
        'basis', 'six checked signals on your account, the brief and the shape of the competing bids'))
  end;
$function$;

comment on function public.fn_supplier_quote_recommend(bigint, uuid) is
  'Row #5 §11. Proposes a price, a delivery estimate, a warranty, payment terms, a market position '
  'and a risk level for one supplier on one enquiry, computed from the competing bids on that same '
  'enquiry. Returns available:false naming the empty population when nobody else has priced it. '
  'Demo and live rows are partitioned symmetrically.';

-- SOURCE: scripts/sql/fn_supplier_document_impact.sql
-- ==============================================================================================
-- ROW #5 §16 §4 — WHAT EACH DOCUMENT IS ACTUALLY DOING FOR THE SUPPLIER.
--
-- §16's claim is that documents are ALIVE rather than stored files. The portal already shows which
-- ones are on file and when they expire. What it could not answer is the only question a supplier
-- actually cares about: what is this piece of paper WORTH to me, and what is the missing one
-- costing me. Both halves are counts over real enquiries, so both are answerable now.
--
--   unlocked      enquiries this supplier has already priced while the document was on file and
--                 unexpired. Their own trading history, not a projection.
--   would_unlock  OPEN enquiries in their category that they cannot currently be matched to
--                 because this document is missing or expired. Zero when the document is fine,
--                 which is the correct answer — a document that is already working unlocks
--                 nothing further by being uploaded again.
--
-- ── THE NUMBER IS NEVER A GUESS, AND WHERE IT WOULD BE, IT IS NULL ──────────────────────────────
-- `unlocked` counts quotes, and there is no per-document history table, so the routine cannot know
-- whether a licence uploaded last week was on file when a quote was sent last month. It therefore
-- only attributes quotes when the document is on file AND unexpired TODAY, and names that basis in
-- the payload. Attributing a supplier's whole quote history to a document uploaded this morning
-- would be the flattering answer and the false one.
--
-- ── DEMO AND LIVE ARE PARTITIONED, AS EVERYWHERE ELSE IN THIS ROW ───────────────────────────────
create or replace function public.fn_supplier_document_impact(p_lead_id bigint)
returns jsonb
language sql
stable
security definer
set search_path to 'public', 'pg_temp'
as $function$
  with me as (select * from public.leads where id = p_lead_id),
  flag as (select coalesce((select source from me), '') = 'qd_demo_fixture' as is_demo),

  -- Open enquiries this supplier's trade could serve. This is the population a missing document
  -- is measured against, so it is scoped to their sector and to briefs that are still open.
  reachable as (
    select count(*) n from public.inquiries i, me, flag
    where i.status = 'open'
      and me.sector is not null and i.category = me.sector
      and (coalesce(i.brief_source, '') = 'qd_demo_fixture') = flag.is_demo
  ),
  -- Their own priced history.
  priced as (
    select count(distinct q.inquiry_id) n from public.quotes q, flag
    where q.supplier_id = p_lead_id
      and (coalesce(q.source, '') = 'qd_demo_fixture') = flag.is_demo
  ),

  docs as (
    select d.* from (
      select 'trade_licence' as key, 'Trade licence' as label,
             (select license_doc_path from me) as path,
             (select license_expiry from me) as expiry,
             true as gates_matching
      union all
      select 'iso', 'ISO certification',
             (select iso_doc_path from me), (select iso_expiry from me), false
      union all
      select 'insurance', 'Insurance',
             (select insurance_doc_path from me), (select insurance_expiry from me), false
      union all
      select 'manufacturer_auth', 'Manufacturer authorisation',
             (select manufacturer_auth_doc_path from me), (select manufacturer_auth_expiry from me), false
      union all
      select 'company_profile', 'Company profile',
             (select company_profile_doc_path from me), null::date, false
    ) d
  ),
  scored as (
    select d.key, d.label, d.gates_matching,
           d.path is not null as on_file,
           d.expiry,
           coalesce(d.expiry < current_date, false) as expired,
           (d.path is not null and not coalesce(d.expiry < current_date, false)) as effective
    from docs d
  )

  select jsonb_build_object(
    'lead_id', p_lead_id,
    'open_in_my_trade', (select n from reachable),
    'basis', 'open enquiries in your trade, and the enquiries you have already priced',
    'documents', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'key', s.key,
        'label', s.label,
        'on_file', s.on_file,
        'expiry', s.expiry,
        'expired', s.expired,
        -- What it has already earned. Only attributable while the document is genuinely in force.
        'unlocked', case when s.effective then (select n from priced) else 0 end,
        -- What its absence is costing. Only the licence blocks matching outright, so only the
        -- licence can claim the whole open population; the others are supporting evidence and
        -- claim nothing they cannot demonstrate.
        'would_unlock', case
          when s.effective then 0
          when s.gates_matching then (select n from reachable)
          else 0 end,
        'note', case
          when s.effective then 'On file and in force.'
          when s.expired and s.gates_matching then 'Expired. Renewing it reopens every open enquiry in your trade.'
          when s.expired then 'Expired. Customers see this as a gap when comparing you.'
          when s.gates_matching then 'Missing. It is the document that decides whether you can be matched at all.'
          else 'Missing. It is optional, but it is what a customer looks for when comparing two similar quotes.'
          end
      ) order by s.gates_matching desc, s.key), '[]'::jsonb)
      from scored s)
  );
$function$;

comment on function public.fn_supplier_document_impact(bigint) is
  'Row #5 §16 §4. Per document: whether it is on file and in force, how many enquiries it has '
  'already unlocked, and how many open enquiries in the supplier''s trade its absence is currently '
  'costing them. Counts are attributed only while a document is genuinely in force.';
