-- ROW #5 §11 §14 — A FENCED DEMO MARKET, ON BOTH PROJECTS.
--
-- Founder decision, 2026-08-08, standing: "as i said create demo for whatever is needed."
--
-- §11 (AI Quote Builder) and §14 (Market Intelligence) are the two sections that cannot be built
-- against an empty estate, and not because of a scan blind spot. A "recommended price" with no
-- comparable quotes behind it is an invented number, and a "demand trend" with no series behind it
-- is an arrow pointing at nothing. Both are exactly the kind of figure a supplier would act on. So
-- this file builds the smallest thing that is genuinely a MARKET: six suppliers in one sector,
-- six enquiries in one category, and twenty quotes spread across them with a real spread of prices.
--
-- ── WHAT AN INSERT INTO quotes ACTUALLY SETS OFF, MEASURED ON PRODUCTION, NOT ASSUMED ────────────
-- Nine triggers. Seven are database-only, measured by reading all seven bodies:
--   trg_mask_quote_contact, scrub_quote_contacts, trg_quote_quality, trg_quote_expiry,
--   trg_version_quote, trg_quote_committed_hash, trg_reg_quote_doc (gated on original_file_path,
--   which every row here leaves NULL).
--
-- Exactly one reaches a human — trg_new_quote_sms -> notify_new_quote_sms — and it is gated:
--
--     select i.summary, i.customer_id into inq from public.inquiries i where i.id = NEW.inquiry_id;
--     if inq.customer_id is null then return NEW; end if;
--
-- Every enquiry below has customer_id NULL, so the function returns before it can look up a phone
-- number, and no notification row is written at all. That is the fence: a condition in a trigger
-- this data cannot satisfy, not a comment asking nicely. The same NULL fences the inquiry side —
-- trg_autodispatch_inquiry needs `rfq_ready is true` and every row here leaves it NULL.
--
-- ── THE ONE COST, STATED PLAINLY, AS THE INQUIRY FIXTURE STATED ITS OWN ──────────────────────────
-- trg_event_quote -> fn_emit_event writes one 'quote.received' event into company_event per quote,
-- and trg_event_inquiry writes one 'rfq.created' per enquiry. Six enquiries and twenty-four quotes
-- is 30 synthetic rows, and the fence audit counted 32 on each project afterwards — the extra two
-- belong to the earlier inquiry and quote fixtures. That is the measured number, not the estimate.
-- They land in row #2's separately measured event backbone and they are findable: every one carries
-- the id of a fixture whose brief_source/source is 'qd_demo_fixture', so row #2's next re-run must
-- subtract them or say so. The founder accepted this cost when choosing production over staging.
--
-- ── DEMO NEVER CONTAMINATES A REAL SUPPLIER'S NUMBERS ────────────────────────────────────────────
-- This is the fence the earlier fixtures did not need and this one does. §14 tells a supplier how
-- many companies compete with them; adding six demo companies to the `leads` table would add six to
-- a real HVAC supplier's competitor count and there would be no way for them to know. So
-- fn_supplier_market partitions the population instead of filtering it: a demo fixture's market is
-- computed over demo rows, a real supplier's market over real rows, on one predicate —
--
--     and (l.source = 'qd_demo_fixture') = (me.source = 'qd_demo_fixture')
--
-- — which is symmetric, so neither side can see the other, and which costs a real supplier nothing.
--
-- ── NOTHING IS BACK-DATED ───────────────────────────────────────────────────────────────────────
-- Every created_at is whatever now() is when this runs. The demand trend is therefore computed over
-- a window in which the current bucket is full and the earlier ones are near-empty, and the routine
-- reports the window and both bucket counts so the shape of the series is visible rather than
-- implied. Demand going from ~0 to 6 in a day is what actually happened to this table.
--
-- ── REMOVABLE IN THREE STATEMENTS ───────────────────────────────────────────────────────────────
--     delete from public.quotes     where source       = 'qd_demo_fixture';
--     delete from public.inquiries  where brief_source = 'qd_demo_fixture';
--     delete from public.leads      where source       = 'qd_demo_fixture';

-- ── 1. FIVE MORE FENCED SUPPLIERS, so the existing fixture has peers ────────────────────────────
-- Fenced on the same three independent legs as supplier-001: verified false, matching_blocked true
-- with a reason, approval_status pending. fn_is_matchable fails on any one of them.
insert into public.leads (
    place_id, company_name, source, enrich_source, sector, emirate, city, categories,
    company_type, business_role, verified, matching_blocked, matching_block_reason,
    approval_status, permanently_closed, banned, chat_strikes, claimed,
    service_emirates, employee_count, team_size, founded_year, description, capability_summary,
    email, phone, locale, lifecycle_stage, verification_status, registration_status, rating
  )
  select v.place_id, v.company_name, 'qd_demo_fixture', 'qd_demo_fixture', 'hvac', v.emirate, v.emirate,
         v.categories, v.company_type, 'supplier', false, true,
         'QuotesDone demo fixture — must never be matched, searched or revealed to a real customer',
         'pending', false, false, 0, true,
         v.service_emirates, v.employees, v.employees, v.founded, v.descr, v.cap,
         v.place_id || '@example.invalid', '+97150000000' || v.n, 'en', 'registered', 'unverified',
         'not_due', v.rating
  from (values
    ('qd-demo-supplier-002', 'ZZ DEMO — Gulf Climate Systems (QuotesDone fixture, not a real company)',
     'Dubai', 'Air Handling Units,Chillers,Ducting', 'manufacturer',
     array['Dubai','Sharjah'], 210, 2004,
     'Demo fixture used to exercise the QuotesDone supplier portal. Not a real business.',
     'Commercial HVAC manufacturing and installation for towers and hotels.', 4.5, '2'),
    ('qd-demo-supplier-003', 'ZZ DEMO — Emirates Air Engineering (QuotesDone fixture, not a real company)',
     'Abu Dhabi', 'Ducting,Ventilation,Fan Coil Units', 'contractor',
     array['Abu Dhabi','Dubai'], 95, 2011,
     'Demo fixture used to exercise the QuotesDone supplier portal. Not a real business.',
     'Ductwork fabrication and ventilation installation for commercial fit-outs.', 4.2, '3'),
    ('qd-demo-supplier-004', 'ZZ DEMO — Northern Cooling Contracting (QuotesDone fixture, not a real company)',
     'Sharjah', 'Chillers,Air Handling Units,Maintenance', 'contractor',
     array['Sharjah','Ajman','Dubai'], 60, 2015,
     'Demo fixture used to exercise the QuotesDone supplier portal. Not a real business.',
     'Chiller installation and planned maintenance for mid-size commercial buildings.', 3.9, '4'),
    ('qd-demo-supplier-005', 'ZZ DEMO — Al Barsha HVAC Trading (QuotesDone fixture, not a real company)',
     'Dubai', 'Fan Coil Units,Ventilation,Ducting', 'trader',
     array['Dubai'], 24, 2019,
     'Demo fixture used to exercise the QuotesDone supplier portal. Not a real business.',
     'Supply of fan coil units and ventilation equipment to contractors.', 4.0, '5'),
    ('qd-demo-supplier-006', 'ZZ DEMO — Capital Mechanical Works (QuotesDone fixture, not a real company)',
     'Abu Dhabi', 'Air Handling Units,Chillers,Ducting,Ventilation', 'manufacturer',
     array['Abu Dhabi','Al Ain','Dubai'], 380, 1996,
     'Demo fixture used to exercise the QuotesDone supplier portal. Not a real business.',
     'Large-scale MEP and HVAC manufacturing with in-house test facilities.', 4.7, '6')
  ) as v(place_id, company_name, emirate, categories, company_type, service_emirates,
         employees, founded, descr, cap, rating, n)
  where not exists (select 1 from public.leads l where l.place_id = v.place_id);

-- ── 2. SIX FENCED ENQUIRIES IN ONE CATEGORY ─────────────────────────────────────────────────────
-- customer_id NULL: belongs to nobody, so the SMS trigger returns before it can find a phone and
-- every customer-facing query filters it out. rfq_ready NULL: trg_autodispatch_inquiry cannot fire
-- and trg_gate_incomplete_match silently drops any inquiry_matches row, which is why there are none.
--
-- raw_input is the CUSTOMER'S OWN BRIEF and has to read like one — it is what the opportunity
-- surface shows as the requirement and what fn_supplier_product_match scores products against.
-- Fixture metadata goes in the marker and the trailing parenthesis, never in place of the brief.
insert into public.inquiries (
    customer_id, category, emirate, role_needed, summary, raw_input,
    status, brief_source, rfq_ready, scope_type
  )
  select null, 'hvac', v.emirate, 'supplier', v.summary, v.raw_input,
         'open', 'qd_demo_fixture', null, v.scope
  from (values
    ('ZZ DEMO — chiller replacement, 9-storey office (QuotesDone fixture, not a real project)',
     'ZZ DEMO — We need to replace two air-cooled chillers serving a nine-storey office in Business Bay, '
     || 'around 400 TR total, including removal of the old units, crane lift and commissioning. '
     || '(QuotesDone demo fixture, not a real enquiry. rfq_ready is NULL so trg_autodispatch_inquiry cannot fire.)',
     'Dubai', 'supply_and_install'),
    ('ZZ DEMO — AHU supply for a hotel refurbishment (QuotesDone fixture, not a real project)',
     'ZZ DEMO — Supply of eleven air handling units for a hotel refurbishment in Deira, capacities '
     || 'between 4,000 and 18,000 CFM, with EC fans and MERV 13 filtration. Supply only, our contractor installs. '
     || '(QuotesDone demo fixture, not a real enquiry. rfq_ready is NULL so trg_autodispatch_inquiry cannot fire.)',
     'Dubai', 'supply_only'),
    ('ZZ DEMO — ductwork for a warehouse fit-out (QuotesDone fixture, not a real project)',
     'ZZ DEMO — Galvanised ductwork and diffusers for a 6,000 sqm warehouse and office fit-out in '
     || 'Mussafah, including insulation and balancing. '
     || '(QuotesDone demo fixture, not a real enquiry. rfq_ready is NULL so trg_autodispatch_inquiry cannot fire.)',
     'Abu Dhabi', 'supply_and_install'),
    ('ZZ DEMO — fan coil units for a residential tower (QuotesDone fixture, not a real project)',
     'ZZ DEMO — Two hundred and forty concealed fan coil units for a residential tower in Al Nahda, '
     || 'with thermostats and three-speed control. Delivery in phases over four months. '
     || '(QuotesDone demo fixture, not a real enquiry. rfq_ready is NULL so trg_autodispatch_inquiry cannot fire.)',
     'Sharjah', 'supply_only'),
    ('ZZ DEMO — kitchen extract and MVHR to a restaurant (QuotesDone fixture, not a real project)',
     'ZZ DEMO — Kitchen extract canopy, ductwork to roof, and heat recovery ventilation for a '
     || 'restaurant in JLT. Needs to meet DM kitchen ventilation requirements. '
     || '(QuotesDone demo fixture, not a real enquiry. rfq_ready is NULL so trg_autodispatch_inquiry cannot fire.)',
     'Dubai', 'supply_and_install'),
    ('ZZ DEMO — annual HVAC maintenance, three buildings (QuotesDone fixture, not a real project)',
     'ZZ DEMO — Annual planned maintenance contract for HVAC across three commercial buildings in '
     || 'Khalifa City — chillers, AHUs, FCUs and controls, quarterly visits plus call-out cover. '
     || '(QuotesDone demo fixture, not a real enquiry. rfq_ready is NULL so trg_autodispatch_inquiry cannot fire.)',
     'Abu Dhabi', 'service')
  ) as v(summary, raw_input, emirate, scope)
  where not exists (select 1 from public.inquiries i where i.summary = v.summary);

-- ── 3. THE QUOTES — A REAL SPREAD, WHICH IS THE ONLY REASON THIS FILE EXISTS ─────────────────────
-- A market with one price in it has no distribution, and a "recommended price" taken from a
-- distribution of one is just that one number wearing a hat. Each enquiry is quoted by four of the
-- six suppliers at a per-supplier factor of its base value, so the median, the spread and a
-- supplier's position within it are all computed from something.
--
-- The factors are a standing characteristic of each demo company rather than noise: 006 is the big
-- manufacturer and prices above the market, 005 is the small trader and prices below it. That makes
-- "you are 12% above the market median" a statement with a cause behind it.
insert into public.quotes (
    inquiry_id, supplier_id, quote_amount, source, status, notes, lead_time, warranty, payment_terms
  )
  select i.id, l.id,
         round(b.base * f.factor, -2),
         'qd_demo_fixture', 'submitted',
         'ZZ DEMO — ' || b.label || '. QuotesDone fixture, not a real quote.',
         f.lead_time, f.warranty, f.terms
  from (values
    ('ZZ DEMO — chiller replacement, 9-storey office (QuotesDone fixture, not a real project)',  980000::numeric, 'chiller replacement including lift and commissioning'),
    ('ZZ DEMO — AHU supply for a hotel refurbishment (QuotesDone fixture, not a real project)',  742000::numeric, 'eleven air handling units, supply only'),
    ('ZZ DEMO — ductwork for a warehouse fit-out (QuotesDone fixture, not a real project)',      615000::numeric, 'galvanised ductwork, insulation and balancing'),
    ('ZZ DEMO — fan coil units for a residential tower (QuotesDone fixture, not a real project)',1180000::numeric,'240 concealed fan coil units with controls'),
    ('ZZ DEMO — kitchen extract and MVHR to a restaurant (QuotesDone fixture, not a real project)',268000::numeric,'kitchen extract, ductwork and heat recovery'),
    ('ZZ DEMO — annual HVAC maintenance, three buildings (QuotesDone fixture, not a real project)',432000::numeric,'annual planned maintenance, quarterly visits')
  ) as b(summary, base, label)
  join public.inquiries i on i.summary = b.summary and i.brief_source = 'qd_demo_fixture'
  cross join (values
    ('qd-demo-supplier-001', 1.04, '10-12 weeks', '24 months on equipment, 12 on workmanship', '30% advance, 60% on delivery, 10% on handover'),
    ('qd-demo-supplier-002', 0.97, '8-10 weeks',  '18 months on equipment, 12 on workmanship', '40% advance, balance on delivery'),
    ('qd-demo-supplier-003', 0.93, '6-8 weeks',   '12 months on workmanship',                  '50% advance, balance on completion'),
    ('qd-demo-supplier-004', 1.01, '9-11 weeks',  '12 months on equipment and workmanship',    '30% advance, 70% on completion'),
    ('qd-demo-supplier-005', 0.88, '5-7 weeks',   '12 months on equipment',                    '100% on delivery'),
    ('qd-demo-supplier-006', 1.13, '12-14 weeks', '36 months on equipment, 24 on workmanship', '20% advance, 70% on delivery, 10% retention')
  ) as f(place_id, factor, lead_time, warranty, terms)
  join public.leads l on l.place_id = f.place_id
  -- Four of the six quote each enquiry, chosen by a stable rotation rather than at random so the
  -- file is reproducible and a re-run cannot quietly produce a different market.
  where ((b.base::bigint / 1000) + right(f.place_id, 1)::int) % 6 <> 0
    and ((b.base::bigint / 1000) + right(f.place_id, 1)::int) % 6 <> 3
    and not exists (
      select 1 from public.quotes q where q.inquiry_id = i.id and q.supplier_id = l.id
    );
