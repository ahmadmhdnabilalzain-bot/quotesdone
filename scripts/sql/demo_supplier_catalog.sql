-- ROW #5 §7 §8 — A DEMO CATALOGUE FOR THE FENCED FIXTURE.
--
-- The founder, 2026-08-07: "not having actual data for customers, suppliers, invoices,,,etc should
-- never be an excuse to avoid following the specs. create demos for all what you require to build."
--
-- supplier_product held 0 rows on production. §7 and §8 describe a screen made entirely of product
-- rows, so there was nothing to render and nothing to test a renderer against. These rows exercise
-- the schema as it was designed — jsonb attributes, certifications, evidence_refs, and variants
-- carrying availability and lead-time policy.
--
-- ── WHAT IS DELIBERATELY ABSENT, AND WHY ────────────────────────────────────────────────────────
-- `ai_match` is NOT set on any product. §8 draws "AI Match 96%", but a match percentage is a claim
-- about a SPECIFIC opportunity and production holds 0 inquiries. Writing 96 here would put a
-- confident number on screen that corresponds to nothing — the precise fabrication this row's
-- scorer exists to catch, and it would make card-ai-match-pct read MET while the mechanism behind
-- it does not exist. It stays null until a real matcher computes it.
--
-- Attached to the DEMO fixture only, and that row is unmatchable on two independent legs, so these
-- products can never surface in a real customer's search or reveal. Removable with the fixture:
--     delete from public.supplier_product where supplier_id in
--       (select id from public.leads where 'demo' = any(tags));
with sup as (
  select id from public.leads where place_id = 'qd-demo-supplier-001'
),
cat as (
  insert into public.supplier_catalog (supplier_id, source_document_path, source_hash, version, status, extracted_at)
  select s.id, 'demo/al-noor-hvac-catalogue-2026.pdf', 'qd-demo-catalog-hash-001', 1, 'approved', now()
  from sup s
  on conflict (supplier_id, source_hash) do update set status = 'approved', extracted_at = now()
  returning id, supplier_id
)
insert into public.supplier_product
  (supplier_id, catalog_id, external_key, name, category_slug, subcategory_slug, brand, model,
   description, attributes, certifications, documents, status, evidence_refs)
select c.supplier_id, c.id, p.ext, p.nm, 'hvac', p.sub, 'Al Noor', p.model, p.descr,
       p.attrs, p.certs, '[]'::jsonb, 'active',
       jsonb_build_array(jsonb_build_object('source', 'demo/al-noor-hvac-catalogue-2026.pdf', 'page', p.page))
from cat c
cross join (values
  ('AHU-X500', 'AHU Model X500', 'air-handling-units', 'X500', 12,
   'Double-skin air handling unit for commercial and healthcare applications.',
   jsonb_build_object('capacity_cfm', '5000', 'efficiency_pct', '92', 'static_pressure_pa', '800',
                      'fan_type', 'EC plug fan', 'filter_class', 'ePM1 60%', 'casing', 'Double skin 50mm',
                      'power_kw', '7.5', 'weight_kg', '820',
                      'compatible_projects', jsonb_build_array('Hospitals', 'Hotels', 'Commercial towers')),
   jsonb_build_array('AHRI 430', 'Eurovent', 'ISO 9001')),
  ('RTU-R200', 'Rooftop Package Unit R200', 'rooftop-units', 'R200', 18,
   'Packaged rooftop unit with integrated free cooling.',
   jsonb_build_object('capacity_tr', '20', 'efficiency_eer', '11.2', 'refrigerant', 'R-32',
                      'free_cooling', 'yes', 'power_kw', '22',
                      'compatible_projects', jsonb_build_array('Retail', 'Warehouses', 'Commercial towers')),
   jsonb_build_array('AHRI 340/360', 'ISO 14001')),
  ('FCU-F80', 'Fan Coil Unit F80', 'fan-coil-units', 'F80', 24,
   'Ceiling-concealed fan coil unit for hotel guest rooms.',
   jsonb_build_object('capacity_cfm', '800', 'rows', '3', 'sound_dba', '38',
                      'motor', 'EC', 'power_w', '95',
                      'compatible_projects', jsonb_build_array('Hotels', 'Residential towers')),
   jsonb_build_array('Eurovent')),
  ('CHL-C1200', 'Air Cooled Chiller C1200', 'chillers', 'C1200', 31,
   'Air-cooled screw chiller with inverter compressors.',
   jsonb_build_object('capacity_tr', '120', 'efficiency_iplv', '4.6', 'refrigerant', 'R-134a',
                      'compressors', '2 x inverter screw', 'power_kw', '132', 'sound_dba', '78',
                      'compatible_projects', jsonb_build_array('Hospitals', 'Commercial towers', 'Data centres')),
   jsonb_build_array('AHRI 550/590', 'ISO 9001', 'ISO 14001'))
) as p(ext, nm, sub, model, page, descr, attrs, certs)
on conflict (supplier_id, external_key) do update set
  name            = excluded.name,
  category_slug   = excluded.category_slug,
  subcategory_slug= excluded.subcategory_slug,
  brand           = excluded.brand,
  model           = excluded.model,
  description     = excluded.description,
  attributes      = excluded.attributes,
  certifications  = excluded.certifications,
  evidence_refs   = excluded.evidence_refs,
  status          = 'active',
  updated_at      = now();

-- Variants carry availability, which is where §8's "Available: 120 units" legitimately lives.
insert into public.supplier_product_variant (product_id, sku, attributes, price_policy, lead_time_policy, active)
select p.id, p.external_key || '-STD',
       jsonb_build_object('available_units', v.avail, 'finish', 'Standard'),
       jsonb_build_object('basis', 'on_request', 'currency', 'AED'),
       jsonb_build_object('lead_time_days', v.lead),
       true
from public.supplier_product p
join public.leads l on l.id = p.supplier_id and l.place_id = 'qd-demo-supplier-001'
join (values ('AHU-X500', '120', 45), ('RTU-R200', '40', 60),
             ('FCU-F80', '600', 21), ('CHL-C1200', '12', 90))
  as v(ext, avail, lead) on v.ext = p.external_key
on conflict (product_id, sku) do update set
  attributes       = excluded.attributes,
  price_policy     = excluded.price_policy,
  lead_time_policy = excluded.lead_time_policy,
  active           = true;
