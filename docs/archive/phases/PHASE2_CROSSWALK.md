# Phase 2 · Step 1 — the 86-route crosswalk, for review

**2 August 2026 · generated from production · `public.v_kb_route_crosswalk`**
**The router is OFF. Nothing was activated. This document exists to be argued with before anything is switched on.**

---

## What the numbers say before you read the table

| | |
|---|---:|
| Operational routes | **86** |
| Routes with no mapped subcategory | **0** |
| Routes with no Arabic alias | **0** |
| Mapped subcategories | 426 |
| Mandatory questions reachable through a route | 6,548 |
| Optional questions reachable through a route | 10,073 |
| **Mandatory questions with no field key** | **0** |
| Optional questions with no field key (per-route, double-counted where a subcategory serves several routes) | 3,469 |
| Distinct optional questions with no field key | **2,537** |

Two of those matter more than the rest.

**Every mandatory question has a field key.** That is the number that decides whether `dispatch_eligible` can ever be trusted, and it is clean. The 2,537 gaps are all optional — they degrade the quality of a brief, they cannot make a request dispatchable when it is not.

**The field-key gaps are not spread evenly.** Eight routes hold 2,366 of the 3,469 per-route gaps: MEP (667), Utility Contractors (399), Smart Home (369), Electrical (362), ELV & Security (272), Gas Systems (264), Fire Fighting (251), Plumbing (183). These are the same routes that carry the most named regulators. That is not a coincidence — the deepest technical categories have both the most optional detail and the most authorities — but it does mean the two risks stack in the same places, which is an argument for keeping them out of the first cohort rather than for rushing to fix them.

## How to read "authorities"

The column counts **distinct named regulators** across the records reachable from that route — Dubai Civil Defence, DEWA, Dubai Municipality, MOHAP, TDRA, ESMA and so on. It is the honest regulatory signal.

I had a first version of this column that counted any record with a jurisdiction *or* an authority, and it reported 1,499 of 1,499 records "regulated" for Construction Materials. That is true and useless: it would have marked all 86 routes for review and told you nothing. Naming actual regulators separates 41 routes that reference none at all from the ones that reference fifteen.

## Recommendation column

- **Shadow now** — no named regulator, no optional field-key gaps. 41 routes.
- **Hold: confirm escalation for N authorities** — the knowledge is complete, but the route touches regulated work and the escalation path should be confirmed before it routes anything, even in shadow.
- **Hold: regulated + N field-key gaps** — both. 13 routes. These are last, not first.

---

## The 86 routes

Columns: **#** · name · production slug · knowledge packages · mapped subcategories · mandatory Qs · optional Qs · optional Qs with no field key · distinct sources · named regulators · aliases EN/AR · recommendation

| # | Category | Production slug | Pkg | Sub | Mand | Opt | NoKey | Src | Auth | EN/AR | Recommendation |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| 1 | Construction Materials Suppliers | `construction-materials-suppliers` | 1 | 6 | 71 | 102 | 0 | 25 | 13 | 81/80 | Hold: confirm escalation for 13 authorities |
| 2 | Steel & Reinforcement Suppliers | `steel-and-reinforcement-suppliers` | 1 | 1 | 12 | 16 | 0 | 10 | 3 | 12/12 | Hold: confirm escalation for 3 authorities |
| 3 | Cement & Concrete Suppliers | `cement-and-concrete-suppliers` | 1 | 2 | 25 | 34 | 0 | 16 | 6 | 26/23 | Hold: confirm escalation for 6 authorities |
| 4 | Formwork & Scaffolding Suppliers | `formwork-and-scaffolding-suppliers` | 1 | 1 | 12 | 17 | 0 | 7 | 3 | 14/14 | Hold: confirm escalation for 3 authorities |
| 5 | Waterproofing Suppliers | `waterproofing-suppliers` | 1 | 1 | 14 | 15 | 0 | 9 | 4 | 17/17 | Hold: confirm escalation for 4 authorities |
| 6 | Insulation Suppliers | `insulation-suppliers` | 1 | 1 | 10 | 19 | 0 | 9 | 3 | 17/16 | Hold: confirm escalation for 3 authorities |
| 7 | Roofing Suppliers | `roofing-suppliers` | 1 | 1 | 13 | 16 | 0 | 8 | 4 | 16/16 | Hold: confirm escalation for 4 authorities |
| 8 | MEP Suppliers / Electromechanical Suppliers | `mep-suppliers-electromechanical-suppliers` | 1 | 11 | 137 | 1009 | 667 | 64 | 16 | 189/175 | Hold: regulated + 667 field-key gaps |
| 9 | HVAC Suppliers | `hvac-suppliers` | 1 | 2 | 24 | 185 | 122 | 20 | 6 | 35/36 | Hold: regulated + 122 field-key gaps |
| 10 | Electrical Suppliers | `electrical-suppliers` | 1 | 6 | 78 | 544 | 362 | 38 | 11 | 101/97 | Hold: regulated + 362 field-key gaps |
| 11 | Plumbing & Sanitaryware Suppliers | `plumbing-and-sanitaryware-suppliers` | 1 | 3 | 35 | 280 | 183 | 22 | 8 | 57/54 | Hold: regulated + 183 field-key gaps |
| 12 | Fire Fighting Equipment Suppliers | `fire-fighting-equipment-suppliers` | 1 | 5 | 80 | 346 | 251 | 17 | 3 | 55/55 | Hold: regulated + 251 field-key gaps |
| 13 | Fire Alarm & Life Safety Suppliers | `fire-alarm-and-life-safety-suppliers` | 1 | 3 | 47 | 211 | 152 | 12 | 4 | 34/33 | Hold: regulated + 152 field-key gaps |
| 14 | ELV & Security Systems Suppliers | `elv-and-security-systems-suppliers` | 2 | 5 | 95 | 366 | 272 | 41 | 13 | 65/59 | Hold: regulated + 272 field-key gaps |
| 15 | Smart Home & Home Automation Suppliers | `smart-home-and-home-automation-suppliers` | 1 | 7 | 142 | 483 | 369 | 28 | 15 | 69/61 | Hold: regulated + 369 field-key gaps |
| 16 | Fit-Out Contractors / Interior Fit-Out Suppliers | `fit-out-contractors-interior-fit-out-suppliers` | 2 | 16 | 252 | 241 | 0 | 13 | 7 | 64/62 | Hold: confirm escalation for 7 authorities |
| 17 | Gypsum & False Ceiling Suppliers | `gypsum-and-false-ceiling-suppliers` | 1 | 2 | 30 | 28 | 0 | 6 | 0 | 10/13 | Shadow now |
| 18 | Flooring Suppliers | `flooring-suppliers` | 1 | 1 | 15 | 14 | 0 | 6 | 0 | 3/8 | Shadow now |
| 19 | Aluminium & Glass Suppliers | `aluminium-and-glass-suppliers` | 1 | 2 | 30 | 28 | 0 | 6 | 0 | 12/14 | Shadow now |
| 20 | Joinery & Carpentry Suppliers | `joinery-and-carpentry-suppliers` | 1 | 3 | 45 | 42 | 0 | 6 | 0 | 19/20 | Shadow now |
| 21 | Paints & Finishing Materials Suppliers | `paints-and-finishing-materials-suppliers` | 1 | 2 | 30 | 28 | 0 | 6 | 0 | 12/15 | Shadow now |
| 22 | Interior Decoration | `interior-decoration` | 1 | 7 | 105 | 98 | 0 | 7 | 0 | 15/19 | Shadow now |
| 23 | Furniture Suppliers / FF&E Suppliers | `furniture-suppliers-ff-and-e-suppliers` | 1 | 7 | 105 | 98 | 0 | 6 | 0 | 23/27 | Shadow now |
| 24 | Kitchen & Bathroom Suppliers | `kitchen-and-bathroom-suppliers` | 2 | 2 | 27 | 103 | 59 | 16 | 4 | 25/25 | Hold: regulated + 59 field-key gaps |
| 25 | Swimming Pool Suppliers & Contractors | `swimming-pool-suppliers-and-contractors` | 1 | 6 | 102 | 101 | 0 | 13 | 6 | 8/11 | Hold: confirm escalation for 6 authorities |
| 26 | Cold Room & Refrigeration Suppliers | `cold-room-and-refrigeration-suppliers` | 1 | 6 | 102 | 78 | 0 | 11 | 0 | 11/14 | Shadow now |
| 27 | Catering Companies | `catering-companies` | 1 | 4 | 68 | 48 | 0 | 8 | 0 | 19/22 | Shadow now |
| 28 | Hospitality Supplies Companies | `hospitality-supplies-companies` | 2 | 5 | 83 | 62 | 0 | 10 | 0 | 13/15 | Shadow now |
| 29 | Bakery Equipment Suppliers | `bakery-equipment-suppliers` | 1 | 2 | 34 | 24 | 0 | 6 | 0 | 4/6 | Shadow now |
| 30 | Food Processing Equipment Suppliers | `food-processing-equipment-suppliers` | 2 | 4 | 63 | 53 | 0 | 13 | 7 | 7/8 | Hold: confirm escalation for 7 authorities |
| 31 | Event Management Companies | `event-management-companies` | 2 | 6 | 96 | 78 | 0 | 7 | 0 | 14/16 | Shadow now |
| 32 | Exhibition Stand Contractors | `exhibition-stand-contractors` | 1 | 5 | 80 | 65 | 0 | 7 | 0 | 6/9 | Shadow now |
| 33 | AV & Media Equipment Suppliers | `av-and-media-equipment-suppliers` | 1 | 9 | 144 | 117 | 0 | 7 | 0 | 38/39 | Shadow now |
| 34 | Marketing & Advertising Agencies | `marketing-and-advertising-agencies` | 1 | 10 | 160 | 130 | 0 | 6 | 0 | 43/47 | Shadow now |
| 35 | IT Companies / IT Services Providers | `it-companies-it-services-providers` | 1 | 10 | 190 | 110 | 0 | 7 | 0 | 48/49 | Shadow now |
| 36 | Data Centre Suppliers & Service Providers | `data-centre-suppliers-and-service-providers` | 1 | 6 | 114 | 66 | 0 | 9 | 0 | 10/12 | Shadow now |
| 37 | Telecommunication Companies | `telecommunication-companies` | 2 | 7 | 133 | 133 | 51 | 18 | 3 | 21/19 | Hold: regulated + 51 field-key gaps |
| 38 | Accounting & Audit Firms | `accounting-and-audit-firms` | 1 | 2 | 36 | 24 | 0 | 10 | 0 | 12/14 | Shadow now |
| 39 | Tax Consultants | `tax-consultants` | 1 | 1 | 18 | 12 | 0 | 10 | 0 | 7/9 | Shadow now |
| 40 | Corporate Service Providers / PRO Services | `corporate-service-providers-pro-services` | 2 | 4 | 72 | 48 | 0 | 11 | 0 | 16/19 | Shadow now |
| 41 | Law Firms | `law-firms` | 1 | 9 | 162 | 108 | 0 | 11 | 0 | 33/35 | Shadow now |
| 42 | Management Consulting Firms | `management-consulting-firms` | 1 | 7 | 126 | 84 | 0 | 10 | 0 | 20/22 | Shadow now |
| 43 | HR & Recruitment Agencies | `hr-and-recruitment-agencies` | 1 | 6 | 108 | 72 | 0 | 11 | 0 | 24/27 | Shadow now |
| 44 | Staffing Companies | `staffing-companies` | 2 | 3 | 53 | 36 | 0 | 17 | 0 | 13/16 | Shadow now |
| 45 | Facilities Management Companies | `facilities-management-companies` | 1 | 8 | 120 | 112 | 0 | 8 | 0 | 27/29 | Shadow now |
| 46 | Cleaning Companies | `cleaning-companies` | 2 | 4 | 62 | 55 | 0 | 13 | 0 | 10/13 | Shadow now |
| 47 | Security Companies | `security-companies` | 1 | 3 | 54 | 221 | 162 | 15 | 4 | 40/35 | Hold: regulated + 162 field-key gaps |
| 48 | Business Centres & Coworking Spaces | `business-centres-and-coworking-spaces` | 1 | 4 | 72 | 48 | 0 | 12 | 0 | 5/8 | Shadow now |
| 49 | Logistics & Freight Forwarding Companies | `logistics-and-freight-forwarding-companies` | 1 | 6 | 102 | 78 | 0 | 10 | 0 | 22/26 | Shadow now |
| 50 | Warehousing & 3PL Companies | `warehousing-and-3pl-companies` | 1 | 2 | 34 | 26 | 0 | 10 | 0 | 11/12 | Shadow now |
| 51 | Oil & Gas Equipment Suppliers | `oil-and-gas-equipment-suppliers` | 1 | 4 | 68 | 52 | 0 | 8 | 0 | 19/21 | Shadow now |
| 52 | Industrial Equipment Suppliers | `industrial-equipment-suppliers` | 2 | 7 | 109 | 99 | 0 | 13 | 7 | 36/26 | Hold: confirm escalation for 7 authorities |
| 53 | Industrial Automation Suppliers | `industrial-automation-suppliers` | 1 | 6 | 102 | 78 | 0 | 9 | 0 | 8/11 | Shadow now |
| 54 | Bearings & Power Transmission Suppliers | `bearings-and-power-transmission-suppliers` | 1 | 6 | 102 | 78 | 0 | 8 | 0 | 8/11 | Shadow now |
| 55 | Fasteners & Fixings Suppliers | `fasteners-and-fixings-suppliers` | 1 | 6 | 102 | 78 | 0 | 8 | 0 | 8/11 | Shadow now |
| 56 | Tools & Abrasives Suppliers | `tools-and-abrasives-suppliers` | 2 | 7 | 114 | 95 | 0 | 13 | 7 | 14/12 | Hold: confirm escalation for 7 authorities |
| 57 | Air Compressor & Pneumatic Suppliers | `air-compressor-and-pneumatic-suppliers` | 2 | 5 | 85 | 65 | 0 | 8 | 0 | 9/11 | Shadow now |
| 58 | Chemical Suppliers | `chemical-suppliers` | 2 | 6 | 119 | 91 | 0 | 14 | 0 | 12/14 | Shadow now |
| 59 | Laboratory Equipment Suppliers | `laboratory-equipment-suppliers` | 1 | 6 | 119 | 91 | 0 | 14 | 0 | 12/14 | Shadow now |
| 60 | Cleanroom Suppliers & Contractors | `cleanroom-suppliers-and-contractors` | 1 | 5 | 85 | 65 | 0 | 9 | 0 | 7/9 | Shadow now |
| 61 | Medical Equipment Suppliers | `medical-equipment-suppliers` | 1 | 3 | 51 | 39 | 0 | 9 | 0 | 15/17 | Shadow now |
| 62 | Pharmaceutical Suppliers | `pharmaceutical-suppliers` | 1 | 1 | 17 | 13 | 0 | 9 | 0 | 6/8 | Shadow now |
| 63 | Education Equipment Suppliers | `education-equipment-suppliers` | 1 | 4 | 68 | 48 | 0 | 8 | 0 | 18/20 | Shadow now |
| 64 | Aviation & Ground Support Suppliers | `aviation-and-ground-support-suppliers` | 1 | 2 | 24 | 34 | 0 | 8 | 6 | 8/6 | Hold: confirm escalation for 6 authorities |
| 65 | Marine Equipment & Marine Safety Suppliers | `marine-equipment-and-marine-safety-suppliers` | 2 | 6 | 72 | 102 | 0 | 9 | 7 | 19/11 | Hold: confirm escalation for 7 authorities |
| 66 | Offshore & Marine Construction Companies | `offshore-and-marine-construction-companies` | 1 | 6 | 72 | 102 | 0 | 8 | 6 | 10/11 | Hold: confirm escalation for 6 authorities |
| 67 | Renewable Energy Companies (Solar, EV, Battery) | `renewable-energy-companies` | 1 | 4 | 68 | 52 | 0 | 11 | 0 | 6/9 | Shadow now |
| 68 | Real Estate Agencies | `real-estate-agencies` | 1 | 4 | 48 | 68 | 0 | 7 | 7 | 8/8 | Hold: confirm escalation for 7 authorities |
| 69 | Property Management Companies | `property-management-companies` | 1 | 4 | 48 | 68 | 0 | 7 | 7 | 6/8 | Hold: confirm escalation for 7 authorities |
| 70 | Textile & Uniform Suppliers | `textile-and-uniform-suppliers` | 1 | 7 | 84 | 119 | 0 | 7 | 6 | 19/12 | Hold: confirm escalation for 6 authorities |
| 71 | Beauty & Spa Equipment Suppliers | `beauty-and-spa-equipment-suppliers` | 1 | 5 | 75 | 99 | 0 | 13 | 6 | 10/9 | Hold: confirm escalation for 6 authorities |
| 72 | Gym & Sports Equipment Suppliers | `gym-and-sports-equipment-suppliers` | 1 | 5 | 60 | 85 | 0 | 7 | 7 | 9/9 | Hold: confirm escalation for 7 authorities |
| 73 | Jewelry Suppliers / Gold & Diamond Traders | `jewelry-suppliers-gold-and-diamond-traders` | 1 | 6 | 72 | 102 | 0 | 8 | 7 | 8/11 | Hold: confirm escalation for 7 authorities |
| 74 | Luxury & Concierge Service Providers | `luxury-and-concierge-service-providers` | 1 | 5 | 60 | 85 | 0 | 8 | 8 | 8/9 | Hold: confirm escalation for 8 authorities |
| 75 | Travel Agencies | `travel-agencies` | 1 | 5 | 60 | 85 | 0 | 8 | 7 | 7/9 | Hold: confirm escalation for 7 authorities |
| 76 | Domestic Services Companies (Maids, Care) | `domestic-services-companies` | 1 | 4 | 48 | 68 | 0 | 7 | 5 | 7/9 | Hold: confirm escalation for 5 authorities |
| 77 | Pet Care & Veterinary Services | `pet-care-and-veterinary-services` | 1 | 4 | 48 | 68 | 0 | 7 | 6 | 8/8 | Hold: confirm escalation for 6 authorities |
| 78 | Translation & Interpretation Companies | `translation-and-interpretation-companies` | 1 | 3 | 36 | 51 | 0 | 6 | 6 | 10/8 | Hold: confirm escalation for 6 authorities |
| 79 | Tender & Bid Management Consultants | `tender-and-bid-management-consultants` | 1 | 4 | 48 | 68 | 0 | 7 | 7 | 5/8 | Hold: confirm escalation for 7 authorities |
| 80 | Testing, Inspection & Certification Companies | `testing-inspection-and-certification-companies` | 1 | 10 | 120 | 170 | 0 | 8 | 7 | 33/15 | Hold: confirm escalation for 7 authorities |
| 81 | Modular & Prefab Building Suppliers | `modular-and-prefab-building-suppliers` | 2 | 5 | 84 | 62 | 0 | 17 | 9 | 39/38 | Hold: confirm escalation for 9 authorities |
| 82 | Gas Systems Suppliers (LPG, Medical Gas, Industrial Gas) | `gas-systems-suppliers` | 1 | 5 | 87 | 361 | 264 | 27 | 12 | 53/49 | Hold: regulated + 264 field-key gaps |
| 83 | Utility Contractors (DEWA / SEWA / FEWA approved) | `utility-contractors` | 1 | 7 | 104 | 585 | 399 | 35 | 15 | 68/71 | Hold: regulated + 399 field-key gaps |
| 84 | Wastewater & Drainage Contractors | `wastewater-and-drainage-contractors` | 1 | 4 | 57 | 194 | 156 | 17 | 4 | 40/44 | Hold: regulated + 156 field-key gaps |
| 85 | Signage & Printing Suppliers | `signage-and-printing-suppliers` | 3 | 7 | 91 | 112 | 0 | 15 | 7 | 30/21 | Hold: confirm escalation for 7 authorities |
| 86 | Lifts & Escalator Suppliers | `lifts-and-escalator-suppliers` | 1 | 12 | 119 | 129 | 0 | 17 | 6 | 69/56 | Hold: confirm escalation for 6 authorities |

---

## Things in the table worth your eye before you approve it

**Route 8, MEP, is an outlier and probably a mapping problem, not a knowledge problem.** 1,009 optional questions against 137 mandatory, and 11 subcategories — more optional questions than any other route by a factor of two. MEP overlaps HVAC, Electrical, Plumbing and Fire; it looks like it inherits their subcategories rather than owning its own. Worth confirming that is intended before it routes anything, because a route that inherits four other routes' questions will ask a customer far too many.

**Pharmaceutical (62) and Medical Equipment (61) show zero named authorities.** That is almost certainly a corpus gap rather than the truth — MOHAP and the Department of Health should appear. They are marked "Shadow now" by the rule, and I would **not** put them in an activation cohort on that basis. The rule is mechanical; this is where it is wrong.

**Law Firms (41), Tax Consultants (39), Accounting (38)** also show zero authorities. Same caution: professional-licensing regimes exist and are not represented in the records. Shadowing them is safe — they only observe — but they should not be early activation candidates.

**Flooring (18) has 3 English aliases.** The thinnest alias set of all 86. It will under-match in shadow, and that will look like a router failure when it is an alias gap. Worth noting now so it is not misdiagnosed later.

---

## Recommended activation cohort — and why

Your preference list was office furniture, uniforms, commercial printing, corporate gifts, cleaning. Measured against the table:

| Candidate | Route | Verdict |
|---|---|---|
| **Cleaning services** | 46 | **Yes.** 0 regulators, 0 field-key gaps, 62 mandatory / 55 optional, 13 sources, aliases 10 EN / 13 AR. Small, self-contained, low consequence if a route is wrong. |
| **Office furniture** | 23 Furniture / FF&E | **Yes.** 0 regulators, 0 field-key gaps, 105/98, aliases 23 EN / 27 AR — among the better bilingual coverage. |
| Uniforms | 70 Textile & Uniform | Not first. 6 named regulators, and only 12 Arabic aliases against 19 English — the weakest EN/AR balance among your candidates. |
| Commercial printing | 85 Signage & Printing | Not first. 7 regulators (signage permits are municipal), 3 packages feeding one route. |
| Corporate gifts | — | No route exists. It would land in 23 or 85 depending on the item; worth deciding deliberately rather than discovering in shadow. |

**Proposed cohort: routes 46 and 23.** Two routes, 167 mandatory questions between them, no regulator in either, no field-key gaps, decent bilingual aliases, and the failure mode if a route is wrong is a customer being asked about desks when they meant carpets — recoverable in one message, with no safety, permit or money consequence.

Rollback will be a single flag row per route, flipped without a deploy, with the previous path still live underneath throughout shadow — demonstrated before activation, not asserted.

---

## What happens next, in order

1. **You review this table.** Specifically: MEP's 1,009 optional questions, the zero-authority anomalies on 61/62/38/39/41, and whether 46 + 23 is the cohort you want.
2. Only then: the scenario harness, then all 3,324 scenarios against the agreed thresholds.
3. Field-key work is limited to the ten priority classes you listed and only where it changes a brief, a normalised quote, a comparison, a price driver or a document requirement.
4. Feature flags, shadow mode, measurement, then a cohort.

**The router remains off. No `target_state` record was activated, no company-operations workflow was touched, and neither corpus was re-imported.**
