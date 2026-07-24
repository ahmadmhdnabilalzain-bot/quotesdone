# Trade-specific quote & intake specs (research-grounded, 2026-07-24)

Built from authoritative UAE sources (SIRA, Dubai Civil Defence, ESMA, Al Sa'fat,
Dubai Municipality, DEWA). Two layers now enforce domain completeness:

1. **Intake (category_specs.fields)** — deepened for security(CCTV), hvac, glass,
   aluminium, electrical, plumbing, safety(fire): the RFQ chat asks the exact
   questions a supplier needs (e.g. CCTV: camera count by zone, indoor/outdoor,
   31/90-day SIRA retention; HVAC: system type, capacity basis, AMC).

2. **Quote gate (category_quote_specs + fn_quote_category_score)** — a quote is
   blocked from reaching the customer unless it states the mandatory domain specs
   for its trade (CCTV: resolution + NVR channels + storage; HVAC: capacity + unit
   type + refrigerant; glazing: glass make-up + thickness + dimensions; joinery:
   carcass + finish + dimensions; electrical: cable + DB board + load; plumbing:
   pipe material + diameter + fixtures). Naming aliases resolve across the three
   category systems (cctv-security->security, ac-maintenance->hvac, etc.).

The live source of truth is the database; org-as-code/ mirrors it nightly.
Full field & aspect definitions are in org-as-code/category_specs and the
category_quote_specs export.
