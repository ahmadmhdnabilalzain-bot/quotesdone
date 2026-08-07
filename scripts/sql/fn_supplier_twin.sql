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
    select * from public.supplier_score where lead_id = p_lead_id
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
        select (select quality_rating  from s) as v
        union all select (select reliability    from s)
        union all select (select response_rate  from s)
        union all select (select price_index    from s)
      ) t where v is not null
    ),
    'star_rating', (
      select case when avg(v) is null then null else greatest(1, least(5, round(avg(v) / 20.0))) end
      from (
        select (select quality_rating from s) as v
        union all select (select reliability   from s)
        union all select (select response_rate from s)
      ) t where v is not null
    ),

    -- ── §13 SUPPLIER HEALTH — the five bars ─────────────────────────────────────────────────────
    'health', jsonb_build_object(
      'quality',  (select quality_rating from s),
      'delivery', (select reliability    from s),
      'response', (select response_rate  from s),
      'pricing',  (select price_index    from s),
      'overall', (
        select round(avg(v)) from (
          select (select quality_rating from s) as v
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
