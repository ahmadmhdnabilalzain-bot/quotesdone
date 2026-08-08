-- ROW #5 — THE FENCED DEMO SUPPLIER, ON BOTH PROJECTS.
--
-- ── WHY THIS ROW IS ALLOWED TO EXIST, AND WHAT WOULD MAKE IT NOT ────────────────────────────────
-- The founder's instruction of 2026-08-07: "we can generate demo suppliers to test the specs …
-- no staging, production is our target", and "not having actual data … should never be an excuse
-- to avoid following the specs."
--
-- What remains REFUSED, and this file does not do it: setting `verified` or
-- `approval_status='approved'` on any of the 20,464 SCRAPED rows. That would invent a supplier
-- network out of companies who never agreed to receive anything. Creating a NEW row that is
-- labelled a demo, in a company name that cannot be mistaken for a real business, is not that.
--
-- ── THE FENCE IS ENFORCED BY THE PLATFORM, NOT BY THIS COMMENT ──────────────────────────────────
-- Measured before writing: fn_is_matchable(verified, banned, matching_blocked, approval_status,
-- permanently_closed, chat_strikes) is a PURE PREDICATE, and it is the single choke point every
-- matcher calls — fn_match_capability, fn_supplier_matchable, match_suppliers, match_suppliers_kw.
-- It requires verified = true AND matching_blocked = false.
--
-- This row therefore fails it on TWO INDEPENDENT LEGS:
--     verified          = false   → fails the "verified" clause
--     matching_blocked  = true    → fails the "not blocked" clause
-- so a regression that flipped either one alone still cannot put this company in front of a real
-- customer. It can never enter inquiry_matches, never be revealed, never be searched.
--
-- `tags` carries 'demo' so the row is findable and REMOVABLE in one statement:
--     delete from public.leads where 'demo' = any(tags);
--
-- ── AUTHORED, NOT COPIED — WHICH PROMOTION PATH APPLIES ─────────────────────────────────────────
-- promote_rows_to_production.mjs exists because RETYPING a verified value is a bug class. It reads
-- the value back from staging and posts it. It cannot carry this row: leads.id is GENERATED ALWAYS
-- AS IDENTITY, so its whole-row upsert cannot restate the key.
--
-- But there is no verified source value here to transcribe — this row is AUTHORED, and this file is
-- its single source. The honest analogue is --ddl's discipline: the identical text applied to both
-- projects, then the resulting rows asserted digest-equal. Keyed on place_id, so re-running updates
-- rather than duplicating.
insert into public.leads (
  company_name, place_id, source, enrich_source,
  sector, categories, products, services, description, capability_summary,
  city, emirate, service_emirates, website, email, phone,
  founded_year, employee_count, team_size, engineers_count, warehouse_area,
  machinery, brands_carried, certifications, iso_certifications,
  company_type, business_role, scale, lifecycle_stage,
  verified, approval_status, matching_blocked, matching_block_reason, banned,
  permanently_closed, claimed, claimed_by, tags, locale
)
values (
  'ZZ DEMO — Al Noor HVAC Manufacturing (QuotesDone fixture, not a real company)',
  'qd-demo-supplier-001', 'qd_demo_fixture', 'qd_demo_fixture',
  'hvac',
  'Air Handling Units,Chillers,Ducting,Ventilation',
  'AHU Model X500,Rooftop Package Unit R200,Fan Coil Unit F80,Air Cooled Chiller C1200',
  'Manufacturing,Installation,Maintenance,Design',
  'Demo fixture used to exercise the QuotesDone supplier portal. Not a real business. '
    || 'Fenced out of matching, search and reveal on both projects.',
  'Commercial HVAC manufacturing, installation and maintenance. Design and build capability '
    || 'for hotels, hospitals and commercial towers.',
  'Dubai', 'Dubai', array['Dubai','Abu Dhabi','Sharjah']::text[],
  'https://example.invalid/qd-demo-supplier', 'demo-supplier@example.invalid', '+971500000000',
  1998, 450, 450, 38, '12,000 sqm',
  '["CNC panel line","Coil winding line","Powder coating booth","Test chamber"]'::jsonb,
  '["Danfoss","Ziehl-Abegg","Belimo"]'::jsonb,   -- brands_carried is jsonb, not csv text
  'ISO 9001,ISO 14001',
  '["ISO 9001:2015","ISO 14001:2015"]'::jsonb,
  'manufacturer', 'supplier', 'large', 'not_contacted',
  -- THE FENCE, both legs. Neither may be relaxed.
  false,            -- verified            → fn_is_matchable fails here
  'pending',        -- approval_status     → never 'approved'
  true,             -- matching_blocked    → fn_is_matchable fails here too
  'QuotesDone demo fixture — must never be matched, searched or revealed to a real customer',
  false,            -- banned
  false,            -- permanently_closed
  true,             -- claimed: the fixture is claimed so it can actually sign in and be SEEN.
  -- claimed_by is the login identity. example.invalid is a reserved TLD that can never receive
  -- mail, so this address cannot reach a real inbox even if something tried to send to it.
  'demo-supplier@example.invalid',
  array['demo','row5-fixture']::text[],
  'en'
)
on conflict (place_id) do update set
  company_name        = excluded.company_name,
  sector              = excluded.sector,
  categories          = excluded.categories,
  products            = excluded.products,
  services            = excluded.services,
  description         = excluded.description,
  capability_summary  = excluded.capability_summary,
  service_emirates    = excluded.service_emirates,
  founded_year        = excluded.founded_year,
  employee_count      = excluded.employee_count,
  team_size           = excluded.team_size,
  engineers_count     = excluded.engineers_count,
  warehouse_area      = excluded.warehouse_area,
  machinery           = excluded.machinery,
  brands_carried      = excluded.brands_carried,
  certifications      = excluded.certifications,
  iso_certifications  = excluded.iso_certifications,
  -- The fence is re-asserted on every re-run, so a manual flip does not survive the next apply.
  verified            = false,
  approval_status     = 'pending',
  matching_blocked    = true,
  matching_block_reason = excluded.matching_block_reason,
  banned              = false,
  claimed             = true,
  claimed_by          = excluded.claimed_by,
  tags                = excluded.tags;

-- ── INPUTS, NOT OUTPUTS. THIS IS THE capability_score LESSON GENERALISED ───────────────────────
-- An earlier draft authored capability_score = 92 and the leads trigger recomputed it to 43. The
-- same trap applies to supplier_score: an earlier draft authored quality_rating/reliability/
-- response_rate directly, and fn_supplier_score_refresh -- the platform's own recompute, now on a
-- nightly cron -- would overwrite all three the first time it ran.
--
-- A fixture must author the INPUTS a real supplier would have and let the platform derive the rest.
-- rv_response_rate and rating are inputs (a real supplier accrues them); quality_rating and
-- reliability are outputs. Deriving them means the demo's health panel shows what the platform
-- actually computes, which is the only thing worth demonstrating.
--
-- Consequence, and it is the honest one: reliability lands near 54, not 88, because the formula is
-- rv_response_rate*0.55 + win_rate*0.25 + (verified ? 20 : 0) - penalties, and this fixture is
-- deliberately UNVERIFIED so it can never be matched. The fence costs it 20 points. That is a
-- truthful number, and a demo showing varied bars -- one high, one mid, one null -- exercises the
-- panel far better than four nineties would.
update public.leads set
  rv_response_rate = 99,       -- input: responds to almost every reveal
  rv_reveals       = 24,
  rv_responded     = 24,
  rating           = 4.8       -- input: the Maps star rating, 0-5. See fn_supplier_twin's q_pct note.
where place_id = 'qd-demo-supplier-001';

-- Recompute now so the fixture's derived score exists immediately rather than at 03:40 tomorrow.
select public.fn_supplier_score_refresh();
