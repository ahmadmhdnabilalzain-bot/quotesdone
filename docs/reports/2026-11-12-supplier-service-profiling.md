# Supplier service profiling: what exists, how it measures on hard profiles, and the design

Seat: sales_engineer (analyst). 12 Nov 2026, 02:05 to 03:25 UTC. Moved into the repository the same day with the build's first branch (`sales_engineer-the-reader-sees-every-service-and-nothing-is-ticked-for-him`), so that nothing lives only in a scratchpad: the hard-profile set is now `scripts/e2e/services_hard_profiles/`, the recorded readings and scores `docs/reports/supplier-service-profiling-2026-11-12/`. Code read: main 2cc9d1017 (`/tmp/claude-0/main-base`), deployed. Production read: `htdblwldjkcgjvmqkbeh`. Nothing was built in the product, deployed or applied. Founder rulings read verbatim from `public.founder_instruction`: 1647, 1627, 1628, 1008.

## The answer in short

1. **The gap, measured.** On 12 hard company profiles the deployed reader found 85 of 114 stated services (75%): 60 of 61 where the profile is a clean list, 25 of 53 (47%) where it is broad, vague or glossy, which is what the founder described. 4 of 12 companies end at "We are still reading your documents" with no end (the recruitment company, the one-page maintenance company, the glossy 30-page fit-out contractor, the empty profile). Every service delivered through a partner was dropped (22 of 22). The supplier was asked 0 questions in 18 readings. Nothing outside the catalogue was kept. Wrong trades: 0.
2. **A defect in what is deployed.** The reader's catalogue query is cut at 1,000 of 1,104 services, so 104 service keys can never be proposed. Verified by running the query. Half an hour to fix; do it today.
3. **The one real supplier already through this step** confirmed 32 service keys from a 22-word description, most of them whole trades ticked, and the question the system drafted for him was never asked.
4. **The catalogue cannot yet say what the founder's own example needs**: of his three kinds of staff (labourers, professional experts, freelancers) only the first has a key. 43 keys are proposed, no new trade.
5. **The design**: read first (everything the documents evidence, each with its sentence and whether it is stated, shown in projects, or through a partner), map second (catalogue keys or the supplier's own words kept), then ask at most 5 one-tap cards where the documents are vague, broad or name a partner. Nothing is ticked for him; a whole trade can no longer be ticked in one tap; per service one extra fact, own team or partner.
6. **The design's reading was prototyped on the same profiles with the same model**: 89 of 91 stated services found (98%), 11 of 11 partner statements marked, 4 of 4 vague profiles asked a specific question ("What kinds of staff do you supply?"), nothing held, 60 phrases kept in the supplier's own words, median 88 s, USD 0.009 a company. One reading each, on a set the prompt was tuned against: it shows the design is achievable, it is not the certification.
7. **By Sunday**: the catalogue fix today; the over-claim stop, the 43 keys and the new reading certain (18 h); the question cards (14 h) decide whether Monday meets the ruling in full, and are where the second agent goes. The matcher's partner ranking follows in the week without changing what the first friends meet.
8. **One point for the founder**: whether a customer is told that part of a quote is delivered through a partner. Recommended: not in the first version.

Spend USD 0.4451 of a USD 0.60 cap (121 calls, 8 tagged windows). Leftovers 0, all windows closed.

Contents: Part 1 what exists. Part 2 the measurement. Part 3 the design. Part 4 the build slices. Part 5 where everything is.


## Part 1. What exists today

Read from main 2cc9d1017 (`/tmp/claude-0/main-base`) and from production (`htdblwldjkcgjvmqkbeh`) on 12 Nov 2026, 02:05-02:25 UTC. File references are to the repository; row counts are production.

### 1.1 The rulings this work answers to (read verbatim from `public.founder_instruction`)

| id | said | what it fixes |
|---|---|---|
| 1647 | 12 Nov | The agent reads the profile "really well" and is "smart about the services each supplier does". A broad word covers many services (decoration: interior decoration, landscaping, pools through a subcontractor). Where the profile is not straightforward the agent gets specific (recruitment: "what sort of staff"). "If this step is done wrong everything after it goes wrong." |
| 1627 | 11 Nov | Services come from the AI reading the documents as a person would. Not word matching, and not the trade licence. |
| 1628 | 11 Nov | The AI proposes service keywords, the supplier confirms, they are stored as keys, and matching is code over confirmed keys. |
| 1008 | 28 Sep | Every message to a supplier is in English. |

Two older rulings the design touches: 862 (the checklist starts unticked) and 439 (curated "implied" services are pre-included and removable). Section 3 says where 1647 changes how 439 is applied.

### 1.2 The taxonomy

Where it lives: `public.taxonomy_trade` (223 rows, all active, 12 groups in `taxonomy_trade_group`, 70 of them carry an `umbrella_code` parent), `public.taxonomy_trade_service` (1,104 service rows, all active; 3 to 10 per trade, 4.95 on average; key = `<trade>.<code>`; 2,076 aliases on 229 services; `label_en`, `label_ar`, two embedding columns), `public.taxonomy_trade_adjacent` (43 curated trade pairs, one level), `public.service_implication` (113 active rows, 12 of them from a trade code), `public.service_alias_proposal` (the alias review queue: 424 approved, 28 proposed), `public.taxonomy_trade_proposal` (new-trade queue: 5 pending). The full dump as read is in `taxonomy_dump.txt` beside this report.

Shape: two levels only, trade then service. There is no third level, no attribute on a service (segment, staff type, own team or partner), and the same work often sits under two keys that never meet (see 1.5).

Granularity under the broad words a real supplier uses:

| what the supplier says | where it lands today | specific keys under it | what he cannot express today |
|---|---|---|---|
| decoration / interior fit-out | `interior_fitout` (turnkey, office, decoration, retail, interior_design, refurbishment) plus `gypsum` 5, `painting` 5, `wallpaper` 6, `flooring` 5, `joinery` 5, `curtains_blinds` 4, `upholstery` 5, `design_consultancy` 4 | 6 + 39 in neighbours | villa and apartment interiors as a segment; restaurant, cafe and hotel fit-out; clinic fit-out; "we take a single item on its own" versus "only inside a project" |
| landscaping | `landscaping` (softscape, hardscape, irrigation, pools, maintenance, plant_rental, artificial_greenery, artificial_grass) | 8 | landscape design; garden lighting; pergolas and gazebos (only `aluminium.pergolas_shades`); plants, trees and palms supply |
| swimming pools | `swimming_pools` (pool_construction, pool_maintenance, pool_equipment, water_features) and a second key `landscaping.pools` | 4 + 1 duplicate | pool renovation, retiling and leak repair; heating and chillers; jacuzzi, spa, sauna and steam; that pools are done through a partner |
| manpower / recruitment / staff supply | `labour_supply` (skilled, general, hourly, project_manpower, supervisors); `recruitment_executive_search` 5; `hr_outsourcing` 5; `security_guarding` 5; one each in `event_management.event_staff_hostesses`, `occupational_health.onsite_clinic_nurse`, `hse_consultancy.site_safety_officers` | 5 + 18 scattered | drivers and operators; cleaners and housekeeping staff; hospitality staff; office and admin temps; engineers and technicians on secondment; warehouse and factory workers; promoters and merchandisers; freelancers. The founder's own example ("labourers, professional experts, freelancers") has a key for the first only |
| facilities management | `facilities_management` (integrated_fm, mep_amc, soft_services, building_maintenance), `cleaning` 8, `pest_control` 6, `security_guarding` 5 | 4 + 19 | daily and contract cleaning (there is no key for the most common cleaning contract); handyman; concierge and reception; lifeguards; move-out make-ready |
| general maintenance / technical services | no trade. One key `facilities_management.building_maintenance`, and a maintenance key in each of `hvac`, `plumbing`, `electrical`, `painting` | 5 scattered | "general maintenance" as what the company is; carpentry repairs; tile and floor repairs; handyman; annual maintenance contract for a villa; call-out repair as distinct from an annual contract |
| general trading / building materials | no "general trading" trade (by design: goods are named). `building_materials` (cement_concrete, blocks_bricks, aggregates, steel_rebar, sanitary_ware) plus goods trades `plastics_pipes` 5, `electrical_wholesale` 5, `hand_power_tools` 5, `fasteners_fixings` 5, `chemicals` 5, `steel_stock` 5, `safety_equipment` 5 | 5 + 35 | tiles supply; paints; gypsum board; timber, plywood and MDF; general hardware; taps, valves and plumbing fittings; waterproofing and insulation materials |
| MEP | `mep_general` 5, `hvac` 5, `electrical` 6, `plumbing` 5, `fire_fighting` 5, `security_systems` 5, `av_it` 5, `home_automation` 5, `elevators` 5 | 46 | earthing and lightning protection. Otherwise complete: this is the best-covered area |
| cleaning | `cleaning` (deep_cleaning, post_construction, facade_windows, pest_control, facility_management, kitchen_exhaust, ac_duct, air_quality) | 8 | daily and contract cleaning; villa and apartment cleaning; carpet, sofa and curtain cleaning |
| transport | `logistics_moving` 5, `removals_relocation` 4, `courier_express` 4, `staff_transport` 4, `vehicle_leasing` 4, `cold_chain_logistics` 4 | 25 | trucks with driver (pickup, flatbed, trailer); heavy and abnormal loads |
| events | `event_management` 6, `event_equipment_rental` 6, `exhibition_stands` 5, `event_entertainment` 5, `photo_video_production` 6 | 28 | brand activations and roadshows; weddings and private events; event decor and florals |
| printing / signage | `signage` (shop_signs, letters_3d, wayfinding, lightbox, large_format), `commercial_printing` 5 | 10 | vehicle branding and fleet graphics; digital signage and LED displays |
| IT | `it_services` 10, `software_development` 6, `software_licensing` 5, `telecom_services` 4, `device_repair` 5, `office_equipment` 5, `pos_retail` 5 | 40 | nothing that blocks matching |

### 1.3 The reader (#1935, "the model reads the supplier's documents together")

Path: the portal uploads to storage; `supplier_api` action `process_docs` (`supabase/functions/supplier_api/actions/documents.ts:36`) answers and hands the reading to run after the response (`readStoredDocsLater`, `afterResponse`, lines 365-371). `supplier_doc_trades.ts`: code reads each file into text (`readTexts`, line 451; the text is kept beside the file as `<path>.read.txt`, line 205); then `readTogether` (line 235) gives ALL the supplier's documents to the model, profile and catalogues first and the licence last, each under `=== kind: name ===`; the model's answer is checked by code (`supplier_trade_choice.checkChoice`, line 219) and stored on `supplier_capabilities` as `proposed_trades` and `source_docs.{docs, proposed_services, licence_check}` (`proposeFromRead`, lines 512-515). Nothing is written to `trades`, `services` or `confirmed_at`.

- Model, effort, limits: `model_policy` row `supplier_trade_choice`: `openai/gpt-6-luna-pro`, fallback `anthropic/claude-sonnet-5.5`, `max_tokens` 8000, effort `high` (`_shared/effort_policy.ts:60`). Each call may run 115 s (`supplier_trade_choice.ts:338-339`; the gateway keeps 3 s back, `ai_gateway/handle.ts:469-472`). Text cap 400,000 characters (`CHOICE_TEXT_MAX`, line 46), cut into 14,000-character parts read 5 at a time (lines 47, 105); a scanned PDF is cut to its first 30 pages and must be under 12 MB for the vision model (`supplier_docs_later.ts:58, 67`); 40 documents per supplier (`MAX_DOCS`, `supplier_doc_trades.ts:52`); 40 services per trade (`supplier_trade_choice.ts:250`).
- Calls per reading: one reading if it is "clean", otherwise a second and a third and a majority vote (`settleReadings`, lines 156-170), then one "second look" that keeps or drops each TRADE (`verifySystem`, lines 355-363). The second look never sees the services.
- The prompt (`choiceSystem`, lines 67-95): the 223 trades with all 1,104 service keys, then 16 rules. In this run a reading call carried 55,000 to 69,000 prompt tokens and the second look about 26,000 (`ai_cost_log`, `sql/tok.sql`).
- Evidence kept per proposal: for a trade, up to 3 quoted lines and a one-sentence reason; for a service, one quoted line and the model's licence judgement (`covered` / `not_covered` / `unclear`); the document the quote is in. Code refuses a key that is not in the catalogue, a quote that is not in the documents, and anything quoted only from the licence (`readTogether`, lines 250-262).

What the reader does with the five cases the founder cares about, as the prompt is written:

| case | what happens | where |
|---|---|---|
| A broad word ("decoration company") | It is NOT expanded. Rule 7: "MAIN LINES OF BUSINESS ONLY ... When you are not sure a trade is a main line of business, leave it out". Rule 14: items inside a main trade's scope "are that main trade's work, not trades of their own". Services may only be keys of a trade already named (rule 15), so a service in a trade the reader folded away cannot be proposed at all | `supplier_trade_choice.ts:81, 86, 91` |
| A service shown but not listed (project captions, brand lists) | Refused. Rule 7 excludes "a project description"; the code accepts a trade only from a quote the model labels `list_item`, `heading` or `title` (`QUOTE_FORMS`) | lines 81, 104, 242 |
| A subcontracted service | Dropped. Rule 4: work done by a sister, partner or associated company "is that other company's, not this one's". There is no field for "through a partner" anywhere in the answer or the tables | line 78 |
| Something outside the taxonomy | Dropped. Rule 1: "name nothing for it - never the nearest code". The supplier's words are not kept by the reader (they are kept only if he types them himself, 1.4) | line 75 |
| A vague statement | Nothing is asked. The reader has no output for a question. If three readings name nothing, the document is "held": a `doc_trades_held` item is filed for the sales engineer seat and the supplier is told "We are still reading your documents" (`servicesCopy.ts:203`, `profileStateOf` line 241) with no end | `supplier_doc_trades.ts:282, 364`; `supplier_trade_choice.ts:167-168` |

So the reader was tuned, correctly for its day, to stop wrong TRADES (the 13 Oct and 19 Oct measurements in its own comments). Every one of those precision rules now works against what ruling 1647 asks for.

### 1.4 The supplier's side

The Services tab is `src/components/portal/supplier/ServicesTab.tsx` (690 lines), its words `servicesCopy.ts`; the server side is `supabase/functions/_shared/supplier_services.ts` and `supplier_capability.ts` behind `supplier_api` actions `services_state`, `services_rewrite`, `services_save_rewrite` (`supplier_api/actions/capabilities.ts:71-80`; the supplier's id comes from his own token, line 36). An invited supplier reaches it after Documents and Profile; registration stays "Pending, services unconfirmed" until he confirms.

What he is shown, top to bottom: (1) a "Summary of your company profile": up to 3 English lines the trades were quoted from, and the trade names as "keywords" (`ServicesTab.tsx:233-236`); (2) "Services we understood from your documents": each proposed service with "From your document: ..." and a "Not on your trade licence" badge, unticked, with one button "Tick all proposed services" (lines 380-410; `PROPOSED_COPY`); (3) the checklist: every proposed trade (and the trade he chose at sign-up) with ALL of that trade's services, unticked, each trade with a "Select all" (lines 434-480); (4) one free-text box, "Add the services you provide", rewritten by the model into keys, with implied services pre-included and unknown phrases "Kept in your own words" (lines 485-640); (5) "Your role" chips; (6) "Confirm my services".

What is stored on confirm (`capabilityConfirm`): `supplier_capabilities.trades`, `services` (service keys and his own-words phrases in one array), `roles`, `coverage_emirates`, `services_raw_text`, `services_implied`, `services_removed`, `service_phrases`, `confirmed_at`, and a ledger row in `supplier_capability_confirmation` (13 rows). His own phrases go to the alias queue (`fn_service_alias_propose`) and unknown words to `taxonomy_trade_proposal`.

What does not exist anywhere: own team versus through a partner; a question put to the supplier (the routine that maps his typed words already WRITES a question into `taxonomy_trade_proposal.note`, for example "Ask the supplier: What specific type of machines do you trade?", and nothing ever asks him: 5 pending rows, all unanswered). What exists but is not asked on this tab: areas served (`leads.service_emirates`, asked in the registration form; `coverage_emirates` is defaulted from it), project size (`min_project_value`, `max_project_value`: 1 row of 14,746 has a value), brands (1 row), project types (unused).

Production today: 14,746 `supplier_capabilities` rows, 14,733 of them derived from the directory import; 2 confirmed (one ZZ DEMO, one real company); 0 rows read by the current reader (`supplier_doc_trades@4`), so no real supplier has yet been through the reading the friends will meet on Monday.

The one confirmed company that is not a demo (lead 19398, 11 Nov, not named here) is the only production trace of this step, and it shows the failure plainly. His own description was 22 words: steel fabrication, steel workshop, machinery servicing and AMC, repair, millwright work, pipe extension, trading in machines new and used. His profile and licence were read and proposed nothing (reader @3). He confirmed 10 times in 46 minutes (`supplier_capability_confirmation`, versions 1 to 10). His second confirm held 3 service keys; two and a half minutes later the third held 33, because six trades were added and whole trades were ticked (all 5 services each of `industrial_pumps`, `steel_stock`, `cnc_machining` and `steel`; 3 each of `welding_equipment` and `valves_actuators`; `road_works.car_parks`, removed again 37 minutes later). Whether he pressed "Select all" or ticked each box cannot be read from the ledger; the result can. He is now matched for dosing pumps, heat treatment, valve repair and welding-machine sales, none of which his words say. "Machinery servicing" was stored as `packaging_machinery.machine_servicing` although a trade `machinery_repair` exists; "Trading in machines (new and used)" has a trade `industrial_machinery` and got none; 7 phrases are parked in his own words, and the question drafted for him was never asked.

### 1.5 Matching: how a profiling mistake becomes a missed or a wrong match

`public.fn_match_capability(p_trades, p_need, p_products, p_brands, p_project_type, p_value, p_emirate, p_limit, p_services)` (production definition saved as `fn_match.txt`; canonical file `scripts/sql/a_suppliers_own_words_reach_every_customer_who_asks_for_the_same_work.sql`). A supplier is a candidate only when `confirmed_at` is set, he is matchable and available, his role fits the need, and his `trades` overlap the reach: the request's trades, plus the trade of each service the request names, plus (only when a service is named) the curated adjacent trades, one level. Then the gate: with no service named, every candidate in the trade passes; with a service named, he must hold a named service (`fn_services_effective`: his confirmed keys plus curated implied keys minus those he removed), unless the request names no service in any of his trades and he holds the request's own trade.

| profiling mistake | what the matcher then does |
|---|---|
| A trade he does is not on his list (decoration company, landscaping never proposed) | He is not a candidate for any landscaping request, named service or not. A missed match, silent |
| The trade is right but the service was never ticked (vague profile, nothing specific proposed) | A request that names that service in his trade skips him: he "was asked and does not hold it". He still gets every request in the trade that names no service, including ones he cannot do |
| "Select all" on a trade (the real supplier above) | He receives every request naming any service of six trades. Wrong matches, and his quote rate falls, which lowers his rank (`track` weight) for the work he does do |
| A partner service is dropped (pools through a partner) | He never hears of a "garden and pool" request he would have taken whole |
| The same work under two keys | 12 of 13 duplicate pairs checked have no implication between them (`landscaping.pools` and `swimming_pools.pool_construction`; `cleaning.pest_control` and `pest_control.general_pest_control`; `security_systems.guarding` and `security_guarding.manned_guarding`; `gypsum.plastering` and `masonry_blockwork.plastering`; and so on). The reader is told "one item, one trade" (rule 12), so the supplier holds one key; a request that names the other does not reach him |
| An implied service he was never asked about | It IS matched (`fn_services_effective` adds the 113 curated implications, 12 of them from the trade code alone: holding `interior_fitout` matches `gypsum.false_ceiling`, `gypsum.partitions`, `painting.interior`, `flooring.tiling`). This is ruling 439, shown and removable only on the free-text path; on the checklist path he never sees it |

### 1.6 What was already measured, and what it measured

- `docs/reports/2026-11-11-supplier-registration-certification-free-round.md` and `docs/reports/final-audit-2026-11-12/registration_certification_paid.md`: 8 fixture companies, "12 of 12 proposals sensible, 0 absurd". The bar is TRADES: each fixture is a one-line business with a four-item services list, and a proposal passes when it is one of the expected trades. Services are counted as present, not scored. "Services are proposed from his documents" took 19 to 69 s in that walk.
- `scripts/e2e/real_profiles`, `real_profiles_heldout`, `real_profiles_heldout3`: 56 real UAE profiles and catalogues (29 + 15 + 12) with hand-written truth. The truth holds trades (2.4 to 2.7 per document), products and certifications. It holds no services: 0 of 56 documents have a service-level answer key. The recorded results (document-reading qualification of 3 Nov; "recall 100% on 6 of 7 real files" in the 10 Nov launch verification) are trade recall.
- `.claude/memory/supplier-registration-certification.md`: the 11 Nov proof of the current reader (tag 5ec510d7): right trades and 0 absurd on six fixtures and one "General Trading" hard case.

So before this analysis nothing in the estate had measured whether the reader finds the specific SERVICES a company does, distinguishes a partner, or notices vagueness. Part 2 is the first such measurement.

## Part 2. The reader measured on hard profiles

### 2.1 What was run, and how faithful it is

- **The set**: 12 invented ZZ DEMO companies, each a company profile and a trade licence as PDFs with a real text layer, plus a Word copy of the Arabic profile (13 profile files). Written to the brief's twelve cases; `profiles/profiles_def.mjs` is the source, `profiles/ANSWER_KEYS.md` the answer keys. The keys were written BEFORE any reading and were not changed afterwards. Each key lists the services the documents state in so many words ("must"), fair readings, partner services, what has no key today, and the questions a human would ask.
- **The reader**: the production modules, imported from the main checkout and never copied (`run/read_profiles.ts`): `readDocForTrades(..., { textOnly: true })` reads each PDF as registration does, then `readTogether([profile, licence], deps, company)` asks the deployed `ai_gateway` on `model_policy` class `supplier_trade_choice` (GPT-6 Luna Pro, effort high) with the deployed prompts, majority rule and second look, and `withReading` / `servicesAndLicence` lay the answer out as it is stored. This is the path `proposeFromRead` runs after an upload, minus the storage write. It is the cheapest faithful way: a browser walk of 12 registrations would have measured the same reading at about ten times the wall time.
- **Not done**: no browser walk. "What the supplier sees" is derived from the stored proposal and the tab's own rules (`run/screen.mjs`), not photographed.
- **Runs**: 18 complete readings. H01 to H05 twice, H06 to H12 once (the stage's background limit stopped the second pass; the budget went to finishing every profile once rather than repeating). Each stage ran in its own tagged rehearsal window with a database-enforced cap.
- **Timing caveat**: up to three of my own stages ran at once, so times are on the high side. The first 8 readings (H01 to H04) ran with little other load: median 101 s, longest 151 s.

### 2.2 The current reader: scores

Columns: services found / expected counts only the services the documents state in so many words, with the company's own team. "Wrong" is anything outside the key's must, fair and partner lists. "Partner" is, of the service keys the documents say go through a partner, how many were proposed as the company's own / marked as partner / not proposed.

| profile | run | time | outcome | trades found/expected | wrong trades | services found/expected (recall) | fair extras | wrong services | partner: as own / marked / dropped | trades with no service | vague questions / options offered | kept in own words |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| H01 | 1 | 87 s | proposed | 2/2 | - | 5/12 (42%) | 2 | - | 0 / 0 / 4 of 4 | - | 0 / 0 | 0 |
| H01 | 2 | 67 s | proposed | 2/2 | - | 5/12 (42%) | 0 | - | 0 / 0 / 4 of 4 | - | 0 / 0 | 0 |
| H02 | 1 | 151 s | held | 0/1 (missed labour_supply) | - | 0/0 (n/a) | 0 | - | 0 / 0 / 0 of 0 | - | 0 / 0 | 0 |
| H02 | 2 | 142 s | held | 0/1 (missed labour_supply) | - | 0/0 (n/a) | 0 | - | 0 / 0 / 0 of 0 | - | 0 / 0 | 0 |
| H03 | 1 | 46 s | proposed | 1/1 | - | 0/0 (n/a) | 1 | - | 0 / 0 / 0 of 0 | electrical_wholesale, hand_power_tools | 0 / 0 | 0 |
| H03 | 2 | 59 s | proposed | 1/1 | - | 0/0 (n/a) | 1 | - | 0 / 0 / 0 of 0 | electrical_wholesale, hand_power_tools | 0 / 0 | 0 |
| H04 | 1 | 128 s | proposed | 3/3 | - | 9/11 (82%) | 5 | plumbing.drainage, plumbing.heaters_pumps | 0 / 0 / 7 of 7 | - | 0 / 0 | 0 |
| H04 | 2 | 101 s | proposed | 3/3 | - | 6/11 (55%) | 6 | - | 0 / 0 / 7 of 7 | - | 0 / 0 | 0 |
| H05 | 1 | 199 s | proposed | 0/0 | - | 0/0 (n/a) | 1 | - | 0 / 0 / 0 of 0 | - | 0 / 0 | 0 |
| H05 | 2 | 310 s | held | 0/0 | - | 0/0 (n/a) | 0 | - | 0 / 0 / 0 of 0 | - | 0 / 0 | 0 |
| H06 | 1 | 124 s | proposed | 5/5 | - | 19/20 (95%) | 1 | electrical.maintenance, plumbing.maintenance | 0 / 0 / 0 of 0 | - | 0 / 0 | 0 |
| H07 | 1 | 69 s | proposed | 2/2 | - | 8/8 (100%) | 1 | - | 0 / 0 / 0 of 0 | - | 0 / 0 | 0 |
| H08 | 1 | 104 s | proposed | 2/2 | - | 7/7 (100%) | 0 | - | 0 / 0 / 0 of 0 | - | 0 / 0 | 0 |
| H08D | 1 | 72 s | proposed | 2/2 | - | 7/7 (100%) | 0 | - | 0 / 0 / 0 of 0 | - | 0 / 0 | 0 |
| H09 | 1 | 153 s | held | 0/2 (missed interior_fitout, joinery) | - | 0/7 (0%) | 0 | - | 0 / 0 / 0 of 0 | - | 0 / 0 | 0 |
| H10 | 1 | 83 s | proposed | 4/4 | - | 8/8 (100%) | 1 | - | 0 / 0 / 0 of 0 | - | 0 / 0 | 0 |
| H11 | 1 | 47 s | proposed | 3/3 | - | 11/11 (100%) | 0 | - | 0 / 0 / 0 of 0 | - | 0 / 0 | 0 |
| H12 | 1 | 28 s | held | 0/0 | - | 0/0 (n/a) | 0 | - | 0 / 0 / 0 of 0 | - | 0 / 0 | 0 |

TOTAL over 18 readings: services 85/114 (75%), wrong services 4; trades 30/34 (88%), wrong trades 0; partner services proposed as own 0, marked as partner 0, dropped 22; time p50 101 s, max 310 s.

Read by hand, the 4 "wrong" services are not absurd: `plumbing.drainage` and `plumbing.heaters_pumps` (H04) were read off "Plumbing and drainage maintenance, pump servicing", a maintenance line turned into installation services; `electrical.maintenance` and `plumbing.maintenance` (H06) were read off "Annual maintenance contracts for complete MEP", a fair reading my key did not list. No proposal of the "recording studio equipment" kind appeared in 18 readings: the precision work of 11 Nov holds.

What the supplier would see (derived):

| profile | run | banner he reads | "Services we understood" rows (with his sentence shown) | trades on the checklist | checkboxes in all | asked anything | 
|---|---|---|---|---|---|---|
| H01 | 1 | summary + keywords | 7 (7) | interior_fitout, joinery, landscaping | 19 | no |
| H01 | 2 | summary + keywords | 5 (5) | interior_fitout, landscaping | 14 | no |
| H02 | 1 | "We are still reading your documents..." (no end) | 0 (0) | labour_supply (sign-up trade only) | 5 | no |
| H02 | 2 | "We are still reading your documents..." (no end) | 0 (0) | labour_supply (sign-up trade only) | 5 | no |
| H03 | 1 | summary + keywords | 1 (1) | building_materials, electrical_wholesale, hand_power_tools | 15 | no |
| H03 | 2 | summary + keywords | 1 (1) | building_materials, electrical_wholesale, hand_power_tools | 15 | no |
| H04 | 1 | summary + keywords | 16 (16) | cleaning, electrical, facilities_management, hvac, landscaping, mep_general, plumbing, swimming_pools, waste_management, water_treatment_services | 54 | no |
| H04 | 2 | summary + keywords | 12 (12) | cleaning, electrical, facilities_management, hvac, landscaping, mep_general, painting, plumbing, swimming_pools, waste_management, water_treatment_services | 59 | no |
| H05 | 1 | summary + keywords | 1 (1) | facilities_management | 4 | no |
| H05 | 2 | "We are still reading your documents..." (no end) | 0 (0) | facilities_management (sign-up trade only) | 4 | no |
| H06 | 1 | summary + keywords | 22 (22) | electrical, fire_fighting, hvac, mep_general, plumbing | 26 | no |
| H07 | 1 | summary + keywords | 9 (9) | it_services, signage, telecom_services | 19 | no |
| H08 | 1 | summary + keywords | 7 (0) | cleaning, pest_control | 14 | no |
| H08D | 1 | summary + keywords | 7 (0) | cleaning, pest_control | 14 | no |
| H09 | 1 | "We are still reading your documents..." (no end) | 0 (0) | interior_fitout (sign-up trade only) | 6 | no |
| H10 | 1 | summary + keywords | 9 (9) | hand_power_tools, industrial_pumps, machinery_repair, safety_equipment, welding_equipment | 25 | no |
| H11 | 1 | summary + keywords | 11 (11) | event_equipment_rental, event_management, exhibition_stands | 17 | no |
| H12 | 1 | "We are still reading your documents..." (no end) | 0 (0) | building_materials (sign-up trade only) | 5 | no |

### 2.3 What the numbers say

**Where the profile is a clean list, the reader is good.** MEP contractor 19 of 20; the two-division company 8 of 8; the Arabic profile 7 of 7 in both forms, including the PDF whose text layer comes out in visual order; the distributor 8 of 8; the events company with a garments licence 11 of 11, with no garments trade proposed. That is 6 of 13 files at 95 to 100%, with 0 wrong trades in all 18 readings.

**Where the profile is like the founder's examples, it fails, and fails silently.**

| the founder's case | what the reader did | measured |
|---|---|---|
| A decoration company that also does gardens, and pools through a partner (H01) | Proposed the interior and garden headlines. Left out gypsum ceilings, painting, decorative finishes, wallpaper, wall panels, parquet flooring and garden maintenance, all of which are in his own list: they were folded into "decoration" (rule 14). The pools were not proposed and not mentioned | 5 of 12 stated services on both runs (42%); 0 of 4 partner services recorded |
| A recruitment company that "supplies staff and similar services" (H02) | Three readings named nothing; the document was held. He sees "We are still reading your documents" with no end, one trade from sign-up and five boxes. Nobody asks him what sort of staff | held on 2 of 2 runs, 142 s and 151 s; 0 questions |
| General trading, "all kinds of building materials" (H03) | Three trades, one service (sanitary ware). Two trades on his list with no service under them. Nothing asked | 1 service; 15 boxes to tick unaided |
| Facilities management, long list (H04) | The best of the hard cases: 9 and 6 of 11. All 7 partner or sister-company services (fire systems, lifts, pest control, guards) were dropped without a word. Two of the services it could not propose are ones the catalogue query cuts off (2.5) | 82% and 55%; 0 of 7 partner services recorded |
| "General maintenance and technical services", one page (H05) | Run 1: the model named A/C, plumbing, electrical, painting, carpentry and tiling, and the code refused all six because the model labelled the line a sentence about what the company can do, not a list item (`QUOTE_FORMS`); one key survived. Run 2: the readings disagreed and the document was held after 310 s | 1 key, then held |
| A glossy 30-page profile, services in project captions (H09) | Three readings named nothing. A 400-person fit-out contractor with its own joinery factory is told "We are still reading your documents" | held; 0 of 7; 153 s |
| A near-empty profile (H12) | Held. Correct that nothing is proposed; wrong that he is told we are still reading, and is not asked what he does | held |
| A licence that says garments, a profile that says events (H11) | Read the profile, proposed the right 11 services, flagged all 11 "Not on your trade licence", filed an item for the sales engineer seat. The supplier is not asked which business is his today | 11 of 11; 0 questions |
| Brands and distributorships (H10) | The four distributorships with their goods were read. The line of 14 stocked brand names produced nothing, and the brands themselves are stored nowhere | 8 of 8 stated; 0 brands kept |

Totals for the current reader over 18 readings:

- Stated services found: **85 of 114 (75%)**. On the six clean-list files 60 of 61; on the seven hard files 25 of 53 (47%).
- Held ("still reading", no end): **5 of 18 readings, on 4 of 12 companies**.
- Partner services: **0 recorded, 22 of 22 dropped**.
- Questions asked of the supplier: **0**.
- Phrases kept in his own words by the reader: **0**.
- Wrong trades: 0. Services outside the key: 4, none absurd.
- Time for one reading: median 101 s, longest 310 s; **7 of 18 over the certification's own 120 s bar**: five of them profiles that went to a second and third reading (H02 twice, H05 twice, H09), the other two long lists (H04, H06). The certification's own fixtures took 19 to 69 s.
- Cost: USD 0.178 for 18 readings and one cut short, about **USD 0.010 a reading** (50 calls; a reading call carries 55,000 to 69,000 prompt tokens).

The 11 Nov certification's "12 of 12 sensible" is true and is not this. It asked whether the trades are right on companies that state four services in a list. This asks whether the reader finds what a broad, vague or glossy profile means, and on that it finds under half and asks nothing.

### 2.4 The designed reading, measured on the same 13 files

To know that the design of Part 3 can be met by the model the estate already runs, its reading was prototyped as a scratch harness (`run/read_profiles_v3.ts`; not product code) and run once on all 13 files, through the same gateway and model. Step A reads without the service catalogue (it is given the 223 trade names only) and returns every claim with its sentence and basis, the vague statements with a question, and umbrella candidates. Step B maps each phrase onto the services of the trades step A named. Code checks every quote against the profile and every key against the catalogue.

| profile | run | time | outcome | trades found/expected | wrong trades | services found/expected (recall) | fair extras | wrong services | partner: as own / marked / dropped | trades with no service | vague questions / options offered | kept in own words |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| H01 | 1 | 137 s | proposed | 2/2 | masonry_blockwork | 11/12 (92%) | 11 | - | 0 / 3 / 1 of 4 | masonry_blockwork | 0 / 2 | 3 |
| H02 | 1 | 64 s | proposed | 1/1 | - | 0/0 (n/a) | 0 | - | 0 / 0 / 0 of 0 | labour_supply, recruitment_executive_search | 1 / 10 | 2 |
| H03 | 1 | 62 s | proposed | 0/1 (missed building_materials) | - | 0/0 (n/a) | 0 | - | 0 / 0 / 0 of 0 | - | 1 / 8 | 0 |
| H04 | 1 | 107 s | proposed | 3/3 | industrial_pumps | 11/11 (100%) | 6 | pest_control.disinfection | 0 / 5 / 2 of 7 | industrial_pumps, painting | 0 / 4 | 8 |
| H05 | 1 | 68 s | proposed | 0/0 | - | 0/0 (n/a) | 4 | - | 0 / 0 / 0 of 0 | painting, joinery | 1 / 8 | 2 |
| H06 | 1 | 84 s | proposed | 5/5 | - | 19/20 (95%) | 4 | - | 0 / 0 / 0 of 0 | - | 0 / 0 | 5 |
| H07 | 1 | 79 s | proposed | 2/2 | - | 8/8 (100%) | 5 | - | 0 / 0 / 0 of 0 | - | 0 / 2 | 4 |
| H08 | 1 | 97 s | proposed | 2/2 | - | 7/7 (100%) | 2 | - | 0 / 0 / 0 of 0 | - | 0 / 5 | 3 |
| H08D | 1 | 88 s | proposed | 2/2 | - | 7/7 (100%) | 2 | - | 0 / 0 / 0 of 0 | - | 0 / 2 | 2 |
| H09 | 1 | 200 s | proposed | 2/2 | school_furniture | 7/7 (100%) | 15 | upholstery.sofa, wallpaper.supply_install, retail_shelving.display_cabinets_showcases, electrical.lighting, curtains_blinds.curtains, upholstery.curtains, office_furniture.meeting_boardroom_tables, office_furniture.acoustic_pods_booths | 0 / 0 / 0 of 0 | signage, mep_general, marble_stone, school_furniture | 0 / 4 | 23 |
| H10 | 1 | 128 s | proposed | 4/4 | industrial_machinery | 8/8 (100%) | 3 | industrial_machinery.installation_commissioning, cleaning_chemicals.floor_cleaning_machines, material_handling.hoists_lifting_gear | 0 / 0 / 0 of 0 | fasteners_fixings, abrasives_surface_finishing, lubricants_industrial_oils | 0 / 4 | 6 |
| H11 | 1 | 91 s | proposed | 3/3 | - | 10 + 1 asked/11 (100%) | 0 | - | 0 / 0 / 0 of 0 | - | 1 / 10 | 2 |
| H12 | 1 | 29 s | proposed | 0/0 | - | 0/0 (n/a) | 0 | - | 0 / 0 / 0 of 0 | - | 1 / 0 | 0 |

TOTAL over 13 readings: services 89/91 (98%), wrong services 12; trades 26/27 (96%), wrong trades 4; partner services proposed as own 0, marked as partner 8, dropped 3; time p50 88 s, max 200 s.

Read by hand:

- **Stated services: 89 of 91 found (98%)**, against 75% (the denominator differs because each file was read once). The two misses: "interior design" went to `design_consultancy.interior_design` instead of `interior_fitout.interior_design` (the same work under two keys), and "DEWA and Civil Defence approvals" was left in his own words although `mep_general.authority_approvals` exists (a mapping miss).
- **Outside the key: 12 services. Two are wrong and would have been listed for a tick**: "AC duct cleaning and disinfection" also mapped to `pest_control.disinfection`, and "pump commissioning" mapped to `industrial_machinery.installation_commissioning`. The other ten are real items with basis `shown` (eight project-caption items on the glossy profile: banquette upholstery, wallcovering, showcases, boardroom table ...) or `brand` (hoists from Yale and Kito, cleaning machines from Karcher). Under the design those are asked, not listed. 0 quotes failed the code check.
- **Trades outside the key: 4.** Three are the trade attached to a phrase kept in his own words (boundary walls, pump servicing, study carrels); with no key they put nothing on his list. One comes with the wrong pump-commissioning key above. The one trade "missed" (building materials on H03) is the vague profile whose goods arrive through its question, as designed.
- **Partner: 11 statements, 11 marked as partner, 0 proposed as the company's own** (pools, jacuzzi, water features and pool maintenance on H01; fire alarm, fire fighting, lifts, escalators, pest control, guards and concierge on H04). The 3 "dropped" in the table are the duplicate keys of services that were marked under their other key.
- **Vague profiles: 4 of 4 asked.** H02: "What kinds of staff do you supply?" with General labourers, Skilled tradesmen, Drivers, Cleaners, Security guards, Hospitality staff, Office staff, Engineers and technicians. H03: "Which specific products do you stock in these categories?" with eight product lines. H05: the six named works as evidence, and "Which other maintenance works do you carry out?" for the "etc.". H12: "What products or services does the company provide?" Only 3 of H02's 8 options map to a key today: that is the catalogue gap of 1.2, measured.
- **Nothing held.** The glossy profile returned 54 claims, all `shown`; the empty profile returned the question.
- **Kept in his own words: 60 phrases** with no key (garden design, jacuzzi, lifeguards, daily cleaning and housekeeping, move-out make-ready, vehicle branding, neon signs, earthing, lightning protection, tool repair, harness re-certification, clinic fit-out ...). Today these are dropped.
- **Also read**: the licence mismatch on H11 ("covers_profile: no", one sentence); 18 brands on H10 (4 as authorised distributor, 14 as stocked); an area served on 12 of 13 files; roles.
- **Time**: reading median 50 s, longest 87 s; mapping median 46 s, longest 139 s (the glossy profile, 4 mapping calls in two rounds); both steps median 88 s, longest 200 s. **Cost USD 0.116 for 13 files: USD 0.009 a company** (38 calls).

What this does and does not prove. It proves the model can do the reading the design asks for, at today's cost and no slower than today. It does not prove the pass bar of 3.11: the prompt was revised twice against this same set (the first form asked the recruitment company "what other workforce services do you provide" and turned "visas handled by us" into a visa service; both are fixed in the form measured), each file was read once, and the answer keys and the hand judgements are mine. The bar is to be met on two runs by the built reader, and the set should grow by profiles the prompt has never seen. Two earlier forms are kept beside the final one for the record: one call with catalogue and reading together did not answer inside the gateway's 150 s (`read_profiles_v2_onecall_504.ts`, HTTP 504); the two-call form with the whole catalogue in step B took a median 158 s on 8 files, its mapping call missing the 115 s limit twice (`read_profiles_v2.ts`, `scores_design_v2.md`).

### 2.5 A defect in production found on the way

**The reader's catalogue is cut at 1,000 services; 104 service keys can never be proposed.** `supplier_trade_choice.tradeDefs` (`supabase/functions/_shared/supplier_trade_choice.ts:266-279`) reads `taxonomy_trade_service` in one unpaged select ordered by `sort`. The API answers 1,000 rows; the table holds 1,104. Verified by running the same select (`run/count_defs.mjs`: returned 1,000, in table 1,104). The 104 cut rows are the later services of the larger trades, among them `landscaping.maintenance`, `landscaping.artificial_grass`, `cleaning.ac_duct`, `cleaning.kitchen_exhaust`, `gypsum.acoustic_ceiling`, `flooring.carpet`, `joinery.wood_panelling`, `glazing.glass_facades`, `aluminium.pergolas_shades`, `wallpaper.film_wrap`, `industrial_pumps.pump_repair_rewinding`, five of `it_services` and five of `packaging`. The model is never shown them, and if it named one, `checkChoice` would refuse it as "not a service of the trade in the catalogue".

The estate has met this before: `service_vocabulary.activeServiceRows` pages the same table and its comment records the day (29 Sep) an unpaged read "silently lost 47 services". `tradeDefs` gained service keys on 11 Nov (#1935) with an unpaged read. Smallest correct fix: `tradeDefs` reads through `activeServiceRows`; a test asserts the reader's key count equals the table's. It accounts for 7 of the 29 misses in 2.2 (garden maintenance on H01 twice, duct and kitchen-exhaust cleaning on H04 twice, wood panelling on H09). With those 7 taken out of the denominator the current reader's recall is 85 of 107 (79%). It should be fixed today, before any other slice.

Two smaller things seen: the alias queue holds 28 proposed aliases written by ZZ DEMO runs (3.5); and the checks the code applies to the model's answer (`QUOTE_FORMS`, the majority rule) are what turned a correct reading of the one-page maintenance profile into one key, then into "held".

### 2.6 Spend and teardown

| stage | run tag | cap USD | calls | spent USD |
|---|---|---|---|---|
| smoke (H12, current reader) | caafa882 | 0.05 | 3 | 0.0056 |
| current reader, first pass (H01-H05 twice) | d57377c0 | 0.25 | 31 | 0.1212 |
| current reader, second pass (H06-H11) | bf28b5bb | 0.10 | 16 | 0.0514 |
| prototype, one call (HTTP 504, stopped) | ae075d35 | 0.15 | 0 | 0 |
| prototype, two calls, whole catalogue (8 files, then stopped) | dd6d4864 | 0.15 | 19 | 0.1047 |
| prototype v3, first prompt (stopped at once to fix the prompt) | 34160b19 | 0.12 | 0 | 0 |
| prototype v3, second prompt (5 files, then stopped to add chunked mapping) | 9efa6fd0 | 0.12 | 14 | 0.0462 |
| prototype v3, final (13 files) | 78f4e8f5 | 0.12 | 38 | 0.1159 |
| **total** | | | **121** | **0.4451** |

Read from `ai_cost_log` by `e2e_run_tag` after the last stage (`sql/final.sql`). The cap for this work was USD 0.60. Two calls were cut before the gateway answered (the 504, and one stopped mid-call) and have no cost row; if the provider billed them it is not in this total, and at this run's rates it would be one to two cents.

Teardown, proved by the same query: all 8 rehearsal windows closed with models off; ZZ DEMO subject suppliers left: 0; their capability rows: 0; `agent_actions` naming the test documents: 0; storage objects: 0 (the runner reads the PDFs from disk and never uploads them). No message was sent to anyone: the subjects had no auth user and the reader sends nothing. Two stages were stopped before their driver's own clean-up ran (ae075d35 by my mistake in stopping the wrong process, d57377c0 by the 25-minute background limit I had set); each was closed by `run/cleanup.mjs` within minutes. Three more were stopped on purpose by ending only the reader process, so each driver cleaned up after itself. The final query covers all eight.

### 2.7 What was not established

- **Repeatability** of the hard cases H06 to H12 on the current reader (one reading each) and of the prototype (one reading each).
- **The prototype at high effort with its final prompt.** High was measured on the earlier form only (reading 58 to 102 s on 8 files); the final form ran its reading at medium. The effort choice in 3.12 follows the estate's rule and names what must be measured before release.
- **A real supplier's reaction**: whether a general manager answers five cards, and how many chips he taps. No design can settle that before Monday; slice 7's measurements will.
- **Scanned or photographed profiles** on the new reading (the vision path is unchanged and was not exercised here), and profiles longer than 32 pages.
- **The screens** as rendered: derived, not walked.
- **The inquiry side.** Matching needs the customer's request to carry the same keys; whether the intake reader names `labour_supply.drivers_operators` when a customer asks for ten drivers was not measured here. The 43 new keys must be added to its vocabulary in the same slice, and its own evaluation re-run.

## Part 3. The design

One sentence: **the agent reads everything the documents evidence, keeps every claim with its own sentence, asks the supplier a few one-tap questions where the documents are broad, vague or point at a partner, and only what he confirms becomes a key that matching reads.** Everything below is a decision, not a menu.

### 3.0 The eight decisions

1. **Read first, map second: two steps, not one.** Step A reads the documents with no catalogue in front of it and writes down what the company does in the company's own terms. Step B maps each phrase onto catalogue keys, or onto none. Today both happen in one prompt that is about 55,000 tokens of catalogue and 16 precision rules, and the rules have to suppress anything the catalogue cannot name. Splitting them means a service with no key is kept instead of dropped, the mapping can be run again whenever the catalogue grows, and each call is short enough to finish. Measured (Part 2.4): the one-call form of the new reading did not answer inside 150 s; the two-step form found 89 of 91 stated services on the hard set in a median 88 s for USD 0.009 a company, against 85 of 114 in a median 101 s for USD 0.010 a reading today.
2. **Every claim carries its basis.** `stated` (he says he offers it), `shown` (it appears only in his project captions or follows from a brand), `partner` (the documents say it goes through someone else). What the supplier sees depends on the basis: stated services are listed for a tick, shown and partner services are ASKED.
3. **Vagueness is detected twice, once by the model and once by code.** The model flags a statement that names a category without the thing. Code flags, with no judgement at all, any trade that ends the reading with zero evidenced services: a trade with no service is by definition too broad to match on, so its services are asked.
4. **Nothing is ticked for him and nothing is matched until he confirms.** Rulings 862 and 1628 stand. The curated "implied" services (ruling 439) stop being silently added for a supplier profiled this way: they become candidates he is asked about.
5. **A whole trade can no longer be ticked in one tap.** "Select all" on a trade's checklist goes. One-tap acceptance stays only for services that carry his own sentence as evidence.
6. **Per confirmed service, exactly one extra fact: own team or through a partner.** Areas served and role stay at company level, where they already are. Project size, brands and segments are NOT asked at registration (reasons in 3.4).
7. **The supplier's own words are never lost.** A phrase with no key is stored as his words, shown to him as kept, queued for the catalogue, and re-mapped by step B whenever keys are added.
8. **The questions are a record, not a screen.** Each question is a row with a status. The same row is answered at registration, or later from a nudge, or raised months later by a new document or a quote. That one table is what keeps a profile right over time.

### 3.1 (a) The reading

Runs behind the upload, exactly where `readTogether` runs today (`supabase/functions/_shared/supplier_doc_trades.ts:235`), over all the supplier's documents together, profile and catalogues first, licence last.

Step A, the reading (new `profileReadSystem` in `supabase/functions/_shared/supplier_profile_reading.ts`; the prompt measured in Part 2.4 is `READ_SYSTEM` in `run/read_profiles_v3.ts`, to be lifted as it stands). It is given the documents and the 223 trade NAMES, no services, so its prompt is a few thousand tokens against 55,000 to 69,000 today (the final prototype's calls ran from 3,400 to 23,600 prompt tokens, the larger ones being mapping calls). It returns:

- `summary`: two English sentences.
- `evidence[]`: one item per specific service or product line: `words` (a short English name), `quote` (one line copied exactly, original language), `basis` (`stated` | `shown` | `partner` | `brand`), `partner_name`, and the `trade` it belongs to.
- `vague[]`: `quote`, `why`, `ask` (the question), `options[]`.
- `also_ask[]`: the umbrella candidates: `because`, `options[]` (at most 8 in all).
- `licence`: whether its activities cover the profile, and one sentence when they disagree.
- `brands[]`, `areas[]`, `roles[]`.

Step B, the mapping (`profileMapSystem`, same file): the numbered phrases of step A (evidence words with their line, and every option label), at most 15 to a call and the calls in parallel, each against only the services of the trades those phrases were given, their curated adjacent trades and their umbrella parents and children; for each phrase, the keys it IS (usually one, at most two) or none. The catalogue is read through `service_vocabulary.activeServiceRows`, all 1,104 keys (today's reader sees 1,000, Part 2.5).

One reading, not a vote. Today a document is read up to three times and held when the readings disagree; that rule is what left 4 of 12 hard companies at "still reading". Here a wrong claim costs the supplier one tap, a doubtful one is a question, and the quote check is unchanged, so step A runs once per part (retried in halves on a timeout, as today), and the state "held" no longer exists: a reading that finds nothing produces the question "what does your company do".

Code then checks, and only checks (as `checkChoice` does today): every quote is in a document that is not the licence (`quoteFinder`), every key is in the catalogue; a claim that fails is dropped, never repaired. Confidence is not a number the model invents. It is derived by code from facts: **high** = basis `stated`, quote verified, a key mapped; **medium** = `shown` or `brand` with a key; **asked** = everything else. High is listed for a tick. Medium and asked are questions. A profile with no stated services at all (the glossy profile of Part 2: 54 claims, every one from a project caption, 30 keys in 14 trades) is asked by trade, the trades with the most shown work first: "Your projects show fit-out work. Which of these do you take as a job?" Its five cards cover its five main trades; the rest wait as `later`.

What changes from today's rules: "main lines of business only" (rule 7), "a project description names nothing" (rules 7 and 13), "a main trade's own scope" (rule 14) and "a partner's work is not this company's" (rule 4) are removed from the reading. Their purpose, stopping wrong trades, is now served by the basis and by asking. The rules that stay: nothing from names, clients, certificates, policies, values, staff, tools; goods are not works; exact key or none; nothing from the licence alone.

Stored in `supplier_capabilities.source_docs.reading` (the column that already owns "what was read off his documents"): reader version `supplier_doc_trades@5`, read time, summary, the checked items with keys, the vague and umbrella entries, brands, areas, roles, and the per-document status as today.

### 3.2 (b) Umbrella expansion

A broad word becomes specific candidates, asked as one-tap chips. Where candidates come from, in this order, de-duplicated against what is already evidenced:

1. **The trade's own unevidenced services** (taxonomy children): he is in `landscaping` with softscape and irrigation evidenced; hardscape, garden maintenance and artificial grass are asked.
2. **The curated maps**: `service_implication` (113 rows) from what he has evidenced, and the trades adjacent to his (`taxonomy_trade_adjacent`, 43 pairs), their first services. These are the estate's own audited statements of "a company that does X normally does Y", with a reason in English and Arabic.
3. **The reading's `also_ask`**: what the model, knowing this kind of company, thinks he may also do (the founder's decoration example: landscaping, pools). Only options that map to a key are chips; the others are dropped from this list (they are not evidence).
4. **What similar suppliers confirmed** (later, slice 7): keys confirmed by at least 30% of suppliers who share his main trade, once 20 or more suppliers have confirmed in it. Today 2 suppliers are confirmed, so this source is switched off until the data exists.

Limits: at most **12 candidate chips, on at most 2 cards**. A card is one trade or one theme ("Outside the home", "Staff"). Candidates beyond the limit are stored (question status `later`) and offered on his next visit to Services, never discarded.

### 3.3 (c) Vagueness

Detected when either holds: the reading returned a `vague` entry; or a trade is evidenced with no service under it (code). One question card each, most blocking first. The question quotes his own words, asks one thing, and offers up to **8 options plus "None of these" and "Something else"**. Options are catalogue keys wherever a key exists (3.6 adds the missing ones); an option with no key is still shown and, if chosen, kept in his own words.

The recruitment company, as it will read on his phone:

> Your profile says: "We supply staff and similar services to companies across the Emirates."
> **What sort of staff do you supply?** Tap all that apply.
> `General labourers and helpers` `Skilled tradesmen` `Drivers and operators` `Cleaners and housekeeping` `Security guards` `Hospitality staff` `Office and admin staff` `Engineers and technicians` `Freelancers`
> `None of these` `Something else`

A profile that says nothing (Part 2, H12) is the limiting case: one card, "Your profile does not say what your company does. Tell us in a line or two, or choose your trade." It is asked at once; it is never left as "we are still reading".

At most **5 question cards in one sitting**: order is nothing-evidenced, vague, partner, shown, umbrella, licence. The rest wait as `later`.

### 3.4 (d) What is recorded per confirmed service, and why nothing more

| recorded | level | why it earns its place |
|---|---|---|
| the service key | service | it is what matching reads (ruling 1628) |
| **own team or through a partner** | service | The founder named it. A customer who wants a pool builder should get pool builders first; a decorator who subcontracts pools is right for "garden and pool" as one job and weak for a pool alone. Without the fact, the choice is to drop the service (today) or to pretend he builds pools |
| the evidence: the sentence, or the question he answered, or "typed by him" | service | an auditor, and the supplier himself, can see why each key is on his list |
| areas served | company (exists: `leads.service_emirates`, `coverage_emirates`) | already asked once in registration and already read by the matcher. Shown on the confirm screen, changed there if the documents name different emirates. Not asked per service: a UAE contractor's coverage is a company fact in almost every case, and seven more taps per service is where a two-minute form dies |
| role (contractor, supplier, distributor ...) | company (exists: `roles`) | the matcher already gates on it (`p_need`). The reading now proposes it, he confirms it with one tap |

Not asked at registration, on purpose: **project size** (the matcher uses it as a hard gate, most requests carry no value yet, and a wrong minimum hides a supplier from everything; ask it after his first declined request, 3.8); **brands** (the reading extracts them and they are stored as a proposal; confirming distributorships is slice 7, because brand matching is ranking only); **segments** such as villa or hospitality (expressed as service keys where they matter, 3.6, not as a second dimension).

### 3.5 (e) Outside the taxonomy

An evidence item, or a typed answer, that maps to no key is stored in `supplier_capabilities.services` as his words (the array already holds own-words phrases beside keys), shown on the confirm screen under "In your own words", and sent to the two queues that exist: `fn_service_alias_propose` when it is another name for an existing service, `taxonomy_trade_proposal` when it is new. When the sales engineer seat adds a key or approves an alias, step B is run again over the stored readings that hold unmapped phrases, and the supplier gets one question: "We now list `Vehicle branding`. Your profile mentions it. Add it to your services?" Nothing is mapped onto the nearest key meanwhile, and nothing is dropped.

One fix to the queue itself: it holds 28 proposed aliases from ZZ DEMO runs, among them "equipment" for `musical_pro_audio.studio_equipment` and "800 m2 office floor" for office leasing. Demo suppliers must not feed the alias queue (`fn_service_alias_propose` to refuse a ZZ DEMO supplier), and those 28 rows are rejected, not approved.

### 3.6 (f) Taxonomy additions needed now

43 service keys under existing trades, no new trade. Each needs `label_ar`, aliases in English and Arabic, and its two embeddings, written in the same SQL file. Parent is the trade in the key.

| key | label |
|---|---|
| `labour_supply.drivers_operators` | Drivers & equipment operators |
| `labour_supply.cleaners_housekeeping` | Cleaners & housekeeping staff |
| `labour_supply.hospitality_staff` | Hospitality staff (waiters, stewards, kitchen helpers) |
| `labour_supply.office_admin_staff` | Office & admin staff (temporary) |
| `labour_supply.engineers_technicians` | Engineers & technicians (secondment) |
| `labour_supply.warehouse_factory` | Warehouse & factory workers |
| `labour_supply.promoters_merchandisers` | Promoters & merchandisers |
| `labour_supply.freelancers` | Freelance professionals |
| `interior_fitout.residential` | Villa & apartment interiors |
| `interior_fitout.hospitality` | Restaurant, cafe & hotel fit-out |
| `interior_fitout.healthcare` | Clinic & healthcare fit-out |
| `landscaping.design` | Landscape design |
| `landscaping.lighting` | Garden & landscape lighting |
| `landscaping.pergolas_gazebos` | Pergolas & gazebos |
| `landscaping.plants_trees_supply` | Plants, trees & palms supply |
| `swimming_pools.pool_renovation` | Pool renovation, retiling & leak repair |
| `swimming_pools.heating_cooling` | Pool heating & chillers |
| `swimming_pools.jacuzzi_spa_sauna` | Jacuzzi, spa, sauna & steam rooms |
| `facilities_management.handyman` | Handyman & minor repairs |
| `facilities_management.villa_amc` | Annual maintenance contracts for villas & homes |
| `facilities_management.concierge_reception` | Concierge & reception staff |
| `facilities_management.lifeguards` | Lifeguards & pool attendants |
| `facilities_management.make_ready` | Move-in & move-out make-ready |
| `cleaning.contract_cleaning` | Daily & contract cleaning (offices, buildings, schools) |
| `cleaning.residential` | Villa & apartment cleaning |
| `cleaning.carpet_upholstery` | Carpet, sofa & curtain cleaning |
| `joinery.repairs` | Carpentry & door repairs |
| `flooring.repairs` | Tile & floor repairs |
| `building_materials.tiles` | Tiles (ceramic & porcelain) |
| `building_materials.paints` | Paints & painting materials |
| `building_materials.gypsum_boards` | Gypsum boards & plaster |
| `building_materials.timber_plywood` | Timber, plywood & MDF |
| `building_materials.hardware` | General hardware & ironmongery |
| `building_materials.plumbing_fittings` | Taps, valves & plumbing fittings |
| `building_materials.waterproofing_insulation` | Waterproofing & insulation materials |
| `electrical.earthing_lightning` | Earthing & lightning protection |
| `logistics_moving.trucking` | Trucks with driver (pickup, flatbed, trailer) |
| `logistics_moving.heavy_haulage` | Heavy & abnormal load transport |
| `event_management.brand_activations` | Brand activations & roadshows |
| `event_management.weddings_private` | Weddings & private events |
| `event_management.event_decor` | Event decor & florals |
| `signage.vehicle_branding` | Vehicle branding & fleet graphics |
| `signage.digital_signage` | Digital signage & LED displays |


Decided against a "general maintenance" trade and a "general trading" trade. A technical-services company is profiled as the repair and maintenance keys of the trades it works in (`hvac.maintenance_amc`, `plumbing.maintenance`, `electrical.maintenance`, `painting.repainting`, plus the new `joinery.repairs`, `flooring.repairs`, `facilities_management.handyman`, `facilities_management.villa_amc`): that is what a customer asks for, and a second home for the same work would never meet the first at the service gate (1.5). Security guards, nurses, event hostesses already have keys in other trades; the staff question offers those keys.

Also in this file: the same work under two keys. Add a column `service_implication.same boolean not null default false` and one row each way for the true duplicates found (12 pairs listed in `sql/dup.sql`: `landscaping.pools` = `swimming_pools.pool_construction`, `cleaning.pest_control` = `pest_control.general_pest_control`, `security_systems.guarding` = `security_guarding.manned_guarding`, and so on). Confirming one stores both; this is identity, not implication, so it is not a question.

### 3.7 (g) What the matcher does

- **An unconfirmed candidate: nothing.** It is not in `services`, so `fn_match_capability` cannot see it. This is already true; it stays true because proposals and questions live outside `services`.
- **An implied service he was never asked about: nothing, for a supplier profiled by this flow.** At confirm, every curated implied key he did not tick is written to `services_removed` (the column `fn_services_effective` already subtracts). The matcher itself does not change for this; suppliers confirmed before the change keep today's behaviour until they are re-asked (slice 8).
- **Through a partner: he is matched, after everyone who does it with his own team.** New column `supplier_capabilities.services_partner text[]`, a subset of `services`. In `fn_match_capability`: a hit whose every named-service match is in `services_partner` is ordered after all own-team hits, the `why` says "through a partner", and a new output column `partner_hits text[]` carries it to the caller. The callers (`customer_api/lib/matching.ts`, the sales engineer's `match` action) invite a partner-only supplier when fewer than 3 own-team suppliers matched, or when the request names services in two or more trades and he does at least one of them himself (he can take the job whole). Whether the customer is told "delivered with a partner" on the quote is a commercial choice; recommended: not shown in the first version, because the supplier contracts and warrants the work either way. It is the one point here the founder may want to rule on.
- **The same work under two keys** meets through the `same` rows (3.6).

### 3.8 (h) Keeping a profile right over time

Ask, never assume. Each trigger writes question rows into the same table; the supplier sees a card on the Services tab and gets one English message with a link (one reminder after 3 days, then silence).

| trigger | question |
|---|---|
| a new or replaced document is read and evidences a service that is neither confirmed nor declined | "Your new catalogue shows `X` and `Y`. Add them to your services?" |
| he submits a quote for a request whose named service he has not confirmed | "You quoted for `Epoxy flooring`. Shall we send you more requests like this?" |
| he declines 3 requests naming the same service with "not our work", or ignores 5 | "You have passed on 3 requests for `Wallpaper`. Stop sending these?" (this is also where minimum job size is asked, when the reason given is "too small") |
| a key is added or an alias approved that one of his own-words phrases maps to | "We now list `Vehicle branding`. Add it?" |
| 12 months since the last confirm, or a renewed licence with different activities | "Still right?" with his list, one tap to keep |

A declined candidate is remembered (`answered`, not chosen) and never asked again unless a new document evidences it.

### 3.9 (i) The screens, on a phone

All supplier wording is English (ruling 1008). An Arabic quote from his own document is shown beside its English `words`, since they are his words.

**Screen 0, right after upload (Documents step).** "We are reading your company profile. This takes about a minute. Carry on; we will show you what we understood." A line per file: "Company profile.pdf: read, 32 pages". When the reading ends, the Services step shows a dot.

**Screen 1, "What we understood".**
> **Here is what we understood your company does.**
> *ZZ DEMO Rimal is a decoration company for villas and offices in Dubai, Sharjah and Ajman. It also does gardens, and offers pools through a partner.*
> **From your documents (14)**. Tick what you do. These decide which customer requests reach you.
> ☐ **Gypsum ceilings** · *"Gypsum ceilings, cornices and feature walls"*
> ☐ **Decorative paint finishes** · *"Wall painting, stucco and decorative paint finishes"*
> ...
> `Yes, we do all of these` `Next`

One tap on "Yes, we do all of these" ticks the evidenced list (each row shows his sentence, so he is confirming his own words). A row can be unticked. No row here was ever inferred.

**Screen 2, "A few quick questions" (at most 5 cards, one at a time, a progress line "2 of 4").** The wording by kind:

- Vague: "Your profile says: *"...his sentence..."* **What sort of staff do you supply?** Tap all that apply." chips, `None of these`, `Something else`.
- Partner: "Your profile says swimming pools are built *"through our specialist partner"*. **How do you deliver these?**" then per service (`Pool construction`, `Pool maintenance`, `Fountains & water features`): `Through our partner` `With our own team` `We do not offer this`. Small print: "For partner services we send you a request when you can take the whole job."
- Shown: "Your projects show **marble flooring, glass partitions and acoustic ceilings**. **Do you take these as jobs on their own?** Tap the ones you do." chips, `Only inside our own projects`.
- Umbrella: "**Companies like yours often also do these.** Tap any you do." chips, `None of these`.
- Trade with no service: "You work in **Building materials**. **Which of these do you supply?**" the trade's services as chips, `None of these`, `Something else`.
- Licence: "Your trade licence lists **garments and textile trading**. Your profile is about **events**. **Which is your business today?**" `Events only` `Both` `Garments only`. Small print: "You can upload another licence in Documents."
- Nothing evidenced: "Your profile does not say what your company does. **Tell us in a line or two.**" a text box and the microphone, `Choose my trade instead`.

"Something else" opens one text line. What he types is saved as his words at once, with no wait; it is mapped in the background and comes back as a later card if a key fits.

**Screen 3, "Check and confirm".**
> **With your own team (14)** Gypsum ceilings, Interior painting, ...  `Edit`
> **Through a partner (3)** Pool construction, Pool maintenance, Water features  `Edit`
> **In your own words (2)** "Garden lighting", "Jacuzzi". We keep these exactly as written and add them to our list.
> **Where you work** Dubai, Sharjah, Ajman  `Change`
> **Your role** Contractor  `Change`
> `Confirm my services`
> After: "Done. Requests that name these services reach you in Inquiries. You can change them any time in Services."

Below it, collapsed: "Add a service we missed" (the existing free-text box and microphone) and "Browse all services of my trades" (the checklist, with no "Select all").

Taps for the decoration company: 1 (all evidenced) + 3 (partner) + about 4 chips + 1 confirm. For the recruitment company: about 5 chips + 2 + 1. Both are inside two minutes.

### 3.10 (j) What is touched

Data model (one SQL file per subject under `scripts/sql/`, each with its MANIFEST line, applied by the main session):

- `supplier_capabilities`: add `services_partner text[] not null default '{}'`. `source_docs.reading` is new content in an existing jsonb column.
- New table `public.supplier_service_question`: `id`, `supplier_id` (FK `leads`), `kind` (`vague` | `partner` | `shown` | `umbrella` | `trade_services` | `licence` | `nothing` | `new_evidence` | `quoted` | `declined` | `new_key` | `still_right`), `about` jsonb (his sentence, the document, the trade), `prompt_en`, `options` jsonb (`[{key, label_en, own_words}]`), `multi` boolean, `status` (`open` | `later` | `answered` | `skipped` | `expired`), `answer` jsonb, `source` (the reading version or the trigger), `asked_at`, `answered_at`, `reminded_at`. RLS on, with the estate's explicit `service_role`-only policy and a revoke from `anon` and `authenticated` (apply-discipline section 3); the supplier reaches it only through `supplier_api`, which resolves his id from his own token as `capabilities.ts:36` does. Unique on (`supplier_id`, `kind`, a hash of `about`) so a question is never asked twice.
- `service_implication.same boolean not null default false`, and the duplicate-pair rows.
- `taxonomy_trade_service`: the 43 rows of 3.6.
- `fn_match_capability`: `partner_hits` output, the ordering term, the `why` text. `fn_services_effective`: unchanged.
- `fn_service_alias_propose`: refuse ZZ DEMO suppliers; reject the 28 demo rows.
- `model_policy`: no new row for Sunday. Both steps run on the existing class `supplier_trade_choice` (same model, effort high), so the policy map and its SQL mirror do not move.

Functions:

- `supabase/functions/_shared/supplier_profile_reading.ts` (new): the two prompts, `checkReading` (quotes and keys), `proposalOf(reading, taxonomy, implications)` -> the tick list and the question rows (pure; unit-tested offline against the hard-profile answer keys with recorded model answers).
- `supabase/functions/_shared/supplier_trade_choice.ts`: `liveTradeChooser` gains the two-step reader beside the old one behind the reader version; the old `choiceSystem` is deleted when the hard-profile bar passes (no second path left behind).
- `supabase/functions/_shared/supplier_doc_trades.ts`: `readTogether` calls the new reader; `proposeFromRead` stores `source_docs.reading`, writes the question rows, and replaces "held" with the `nothing` question. `READER` becomes `supplier_doc_trades@5`.
- `supabase/functions/_shared/supplier_services.ts`: `servicesState` returns the reading, the tick list and the open questions; `servicesSaveRewrite` accepts `partner` and writes `services_partner` and `services_removed`.
- `supabase/functions/_shared/supplier_capability.ts`: `capabilityConfirm` stores `services_partner` and the answers in the confirmation ledger.
- `supabase/functions/supplier_api/actions/capabilities.ts`: two actions, `services_questions` (read) and `services_answer` (write one answer; no model call).
- `supabase/functions/customer_api/lib/matching.ts` and the sales engineer `match` action: the partner invitation rule.
- Later slices: `supplier_docs_later.ts` (new-document diff), `supplier_api/actions/quotes.ts` (after-quote question), the notification templates for the one nudge.

Website:

- `src/components/portal/supplier/ServicesTab.tsx`: screens 1 and 3; the checklist loses "Select all" and moves under "Browse all services of my trades".
- `src/components/portal/supplier/ServiceQuestions.tsx` (new): the question cards.
- `src/components/portal/supplier/servicesCopy.ts`: the wording of 3.9, English, in one table as today.
- `src/components/portal/supplier/core/Documents.tsx`: screen 0's progress line.

Checks: `scripts/checks/a_supplier_is_asked_never_assumed.test.mjs` (no path writes a key into `services` without a tick or an answer; no "select all" on a trade), and the existing `a_service_inquiry_reaches_only_suppliers_who_ticked_what_it_names.test.mjs` extended with a partner case.

### 3.11 (k) The evaluation that proves it

The hard-profile set of Part 2 becomes a permanent test: `scripts/e2e/services_hard_profiles/` holds `profiles_def.mjs` (the 12 companies and their answer keys), `make_profiles.mjs`, the runner and `score.mjs`, lifted from `profiles/` and `run/` beside this report. Two modes:

- **Offline, every commit, USD 0**: `proposalOf` is run over recorded model answers for the 13 files; the tick list, the questions and their options are asserted against the answer keys. This proves the code half (what is listed, what is asked, what is never ticked).
- **Paid, before any release that touches the reader or the catalogue**: the real reader on the 13 files, twice, in a tagged window.

Pass bar for the paid mode, all of it, on both runs:

| measure | bar |
|---|---|
| specific services evidenced in so many words: found (listed or asked) | at least 90% overall, at least 75% on every profile |
| wrong or absurd proposals (not in the key's must, fair or partner lists) | 0 |
| partner services proposed as his own | 0; marked as partner: every one the documents name |
| vague profiles (H02, H03, H05, H12): a question is asked, and at least 3 of its options are in the answer key's list | 4 of 4 |
| "still reading" or "held" as a final state | 0 |
| a trade with no service and no question | 0 |
| the licence-mismatch profile: the garments trades not proposed, the mismatch asked | yes |
| nothing evidenced from the licence alone | 0 |
| one reading finishes | within 110 s (the gateway wall minus margin) |
| same list on both runs | at least 85% of keys in common per profile |

Add to the set as real suppliers register: every profile where a supplier corrects more than a third of what was proposed is anonymised into a ZZ DEMO twin with an answer key.

### 3.12 (l) Model, effort, time and cost

By the estate's rule (effort by consequence; a step a person waits on fits his wait; background work stays high with a limit that fits):

| step | who waits | model and effort | limit | measured (Part 2.4) |
|---|---|---|---|---|
| A. the reading | Nobody has to: it runs behind the upload while he fills the profile form. If he opens Services first he is shown progress ("about a minute") and then the two-sentence summary as soon as step A lands | `supplier_trade_choice` class (`openai/gpt-6-luna-pro`), **high**: it reads documents and decides what he is asked | 115 s a call; parts of 6,000 characters (today 14,000), five in parallel; a part that times out is read in halves, as today | at medium, final prompt, 13 files: median 50 s, longest 87 s. At high, earlier prompt, 8 files: 58 to 102 s |
| B. the mapping | nobody | same class, **high**: it decides keys | 115 s a call, 15 phrases a call, five calls in parallel | median 46 s, longest 139 s when 4 calls ran in two rounds of three |
| answering a question | the supplier | no model: the options were fixed at reading time; an answer is one database write | under 1 s | not built |
| "Something else" free text | nobody: saved at once as his words; mapped behind by step B | high | 115 s | not built |
| confirm | the supplier | no model | as today (2.3 to 2.7 s in the certification) | certification |

Effort, decided by the estate's rule. Reading documents is "high" by consequence, and this is background work, so it stays high and is given a limit that fits: smaller parts, not lower effort. High with the final prompt was not measured (budget); medium was, and met the recall bar on this set in 22 to 87 s. So the build measures high on the hard set first (bar: every reading inside 110 s). If high does not fit that clock on real profiles, the reading runs at medium BECAUSE OF ITS CLOCK and is recorded so, never as "proven medium".

Time from upload to his list: both steps, median 88 s, longest 200 s here; with all the mapping calls in parallel the longest case should shorten by about the length of one mapping call (not measured). Today's reader on the same files: median 101 s, longest 310 s, and 4 companies never reach a list at all.

Cost per registration: **about USD 0.009** measured (USD 0.116 for 13 companies, 38 calls), against about USD 0.010 a reading today. The earlier two-call form, with a high-effort reading and the whole catalogue in the mapping, cost USD 0.013 a company on 8 files. A later document or an own-words re-map is one more step B call, a fraction of a cent.

## Part 4. The build, in the smallest shippable slices

Sizes are working hours for one engineer agent including its tests, not calendar time. Each slice merges by PR and is proved by execution; SQL is applied and functions deployed by the main session (release-without-ci runbook). Seat: `sales_engineer` owns the reading, the questions and the catalogue; `it_engineer` builds.

| # | slice | files | tests | size |
|---|---|---|---|---|
| 0 | **The reader sees the whole catalogue.** `tradeDefs` reads the services through `activeServiceRows` (paged); today it gets 1,000 of 1,104 and 104 keys can never be proposed (Part 2.5) | `supabase/functions/_shared/supplier_trade_choice.ts` (lines 266-279) | a test that the reader's key count equals `taxonomy_trade_service`'s active count; one paid reading of H01 proposes `landscaping.maintenance` | 0.5 h |
| 1 | **Stop the over-claim.** The checklist loses "Select all" per trade and moves under "Browse all services of my trades"; a document the readings could not agree on stops saying "still reading" for ever and shows the existing free-text box with "Your profile does not say what your company does. Tell us in a line or two." | `src/components/portal/supplier/ServicesTab.tsx`, `servicesCopy.ts` (`profile_pending` split from a new `profile_unclear`), `supabase/functions/_shared/supplier_services.ts` (state for "held") | `scripts/checks/a_supplier_is_asked_never_assumed.test.mjs` (no select-all on a trade); the bilingual-copy check; the registration walk reaches Confirm on a held profile | 3 h |
| 2 | **The catalogue additions.** 43 service rows with Arabic labels, aliases and embeddings; `service_implication.same` and the duplicate-pair rows; the alias queue refuses ZZ DEMO suppliers and the 28 demo rows are rejected | `scripts/sql/<one file>.sql` + MANIFEST line; `supabase/functions/_shared/service_aliases.json` if the seed mirrors it | `every_trade_is_named_grouped_and_serviceable`, `arabic_trade_words_resolve_the_same_in_sql_and_ts`, a new assertion that each duplicate pair meets at the gate (aborted-transaction probe through `fn_match_capability`) | 5 h |
| 3 | **The reading, two steps.** `supplier_profile_reading.ts` (prompts, checks, `proposalOf`); `readTogether` and `proposeFromRead` store `source_docs.reading`; the tick list is the stated, verified, mapped items; unmapped items are kept as own words; reader `@5`; the old one-call chooser deleted once the bar passes | `supabase/functions/_shared/supplier_profile_reading.ts` (new, + `.test.ts`), `supplier_trade_choice.ts`, `supplier_doc_trades.ts`, `supplier_services.ts` (`servicesState` reads the reading) | the hard-profile set offline (recorded answers) on every commit; the paid run twice against the bar of 3.11 (rows for recall, wrong, held, licence); `the_model_reads_the_suppliers_documents_together.test.ts` updated | 10 h |
| 4 | **The questions.** Table `supplier_service_question`; `proposalOf` writes vague, partner, shown, umbrella, trade-services, licence and nothing questions; actions `services_questions` and `services_answer`; `ServiceQuestions.tsx`; screens 1 to 3; `services_partner` stored; un-ticked implied keys written to `services_removed`; the confirmation ledger carries the answers | `scripts/sql/<table>.sql`, `supabase/functions/supplier_api/actions/capabilities.ts`, `_shared/supplier_services.ts`, `_shared/supplier_capability.ts`, `src/components/portal/supplier/ServiceQuestions.tsx` (new), `ServicesTab.tsx`, `servicesCopy.ts` | unit tests of `proposalOf` per question kind and of the limits (5 cards, 8 options, 12 candidates); a 390 px browser walk of H01, H02 and H12 from upload to Confirm inside two minutes; the paid bar's question rows; RLS and revoke checks on the new table | 14 h |
| 5 | **The matcher.** `partner_hits`, the ordering and the `why`; the partner invitation rule in the callers | `scripts/sql/<fn_match_capability file>.sql`, `supabase/functions/customer_api/lib/matching.ts`, the sales engineer `match` action | the existing probe (44 rows) unchanged; new rows: partner-only supplier ranks last, is invited only under the rule; `a_service_inquiry_reaches_only_suppliers_who_ticked_what_it_names` with a partner case | 5 h |
| 6 | **Certify.** The registration certification gains the hard-profile bar as a criterion; two paid runs the same day; the supplier-registration memory note and `docs/release/supplier-registration-certification.md` updated | `scripts/e2e/services_hard_profiles/` (moved in from this analysis), `scripts/e2e/supplier_registration_certification.mjs`, `docs/release/...`, `.claude/memory/...` | itself | 3 h + about USD 0.50 |
| 7 | **Over time.** New-document diff, after-quote question, decline pattern, new-key re-mapping, the one English nudge with one reminder; "what similar suppliers confirmed" as a candidate source once 20 suppliers are confirmed in a trade | `supplier_docs_later.ts`, `supplier_api/actions/quotes.ts`, notification templates, a daily duty for the nudge | unit tests per trigger; a demo journey in a tagged window | 12 h |
| 8 | **Re-ask the suppliers already confirmed** (2 today: one demo, one real). Their questions are generated from their stored documents and words; nothing is removed until they answer | a one-off script under `scripts/` run by the main session | the real supplier's row before and after, by a read | 2 h |
| 9 | **Brands and minimum job size.** Proposed brands confirmed with one tap; minimum size asked on a "too small" decline | `ServiceQuestions.tsx`, `capabilityConfirm` | unit tests | 6 h |

### What can be live and proven by Sunday 15 Nov, said plainly

Three working days remain (Thursday 12 to Saturday 14), with Sunday for the certification.

- **Today, whatever else is decided:** slice 0 (half an hour). It is a defect in what is deployed now.
- **Will be live and proven:** slices 1, 2 and 3 (18 h). They are backend and data except for one small screen change, they do not depend on each other's code, and two agents can take them in parallel (2 beside 3). With these alone, on Monday a friend's profile is read for every specific service with its sentence, a partner service is no longer dropped (it is listed, marked "through a partner" in the evidence, unticked), nothing outside the catalogue is lost, a vague or empty profile gets a direct request to describe the business instead of "still reading", the staff types and the other missing keys exist to be ticked, and no one can tick a whole trade by accident.
- **Should be live and proven, and decides whether Monday meets the ruling in full:** slice 4 (14 h). This is the one that makes the agent ASK: "what sort of staff", "own team or partner". It is the largest slice and the only one with a new screen; it can be built from Friday against the contract fixed by slice 3 (`proposalOf`'s output) and walked on a phone on Saturday. If its browser walk is not clean on Saturday night it does not ship on Sunday, and Monday's friends meet slices 1 to 3: correct and complete proposals to tick, and a text box where the profile is vague. That is a real step down from the ruling (he is not asked the specific question), so slice 4 is where the second agent goes first once 2 is merged.
- **Follows in the week, without lowering what the first friends meet:** slice 5 (the matcher). The founder invites suppliers before customers, and the partner fact is stored from the first confirm (slice 4), or can be backfilled from the stored reading if only slices 1 to 3 have shipped, so ranking by it can land on Tuesday or Wednesday and apply to everything already confirmed. Slice 6 runs on Sunday on whatever has shipped. Slices 7 to 9 follow after the first registrations, and are better designed with those registrations in hand.

What must not happen: shipping slice 3's wider reading WITHOUT slice 1. A reading that proposes more, on a tab that still has "Select all", makes the over-claim worse.

## Part 5. Where everything is

Paths written `run/`, `profiles/` and `sql/` in Parts 1 to 4 are the analysis' own scratch names; this table says where each now is. In the repository since 12 Nov 2026. `<set>` is `scripts/e2e/services_hard_profiles/`, `<evidence>` is `docs/reports/supplier-service-profiling-2026-11-12/`. The PDFs are generated, never committed: `node <set>make_profiles.mjs --out <dir>` renders the same 13 profile files and 12 licences (byte sizes and the text code reads off them checked equal to the analysis' on 12 Nov).

| what | file |
|---|---|
| The 12 companies and their answer keys (source) | `<set>profiles_def.mjs` |
| The answer keys, readable | `<set>ANSWER_KEYS.md`, `<set>answer_keys.json` (generated from the definitions, unchanged since the analysis) |
| How the PDFs are made | `<set>make_profiles.mjs` |
| The runner of the reader (free text read; paid run behind `--paid` and a cap) and its Deno stage | `<set>run.mjs`, `<set>read_profiles.ts` |
| The scorer, and the clean-up of a stopped run | `<set>score.mjs`, `<set>cleanup.mjs` |
| The guard of the set (cap, `--paid`, ZZ DEMO only, no secret, nothing generated in git) | `scripts/checks/the_hard_profile_set_is_capped_and_demo_only.test.mjs` |
| The prototype of the designed reading (final form; evidence, not product code) | `<evidence>read_profiles_v3.ts` |
| Every reading of the deployed reader, and its scores | `<evidence>current_all.json`, `current_all.scores.json`, `scores_current.md`, `screens_current.md` (derived by `screen.mjs`) |
| Every reading of the final prototype, with the model's raw answers, and its scores | `<evidence>design3c.json`, `design3c.scores.json`, `scores_design3c.md`; the earlier form `scores_design_v2.md` |
| The catalogue-cut check | `<evidence>count_defs.mjs` |
| Spend by stage, and the spend and leftovers proof | `<evidence>spend_*.json`, `spend_and_leftovers.sql`, `tokens_per_call.sql` |

The production taxonomy dump, the matcher's deployed text and the reads of the one real supplier's rows stayed in the analysis' scratchpad: the first two are production state anyone can read again, and the third is a real company's record.

## Part 6. The build, measured (12 Nov 2026, the same day)

Two branches. `sales_engineer-the-reader-sees-every-service-and-nothing-is-ticked-for-him` (slices 0 and 1, reviewed twice) and
`sales_engineer-a-profile-is-read-first-and-mapped-second` (slice 3). Built by it_engineer for the sales_engineer seat.

**What slice 3 is.** `supabase/functions/_shared/supplier_profile_reading.ts`, reader `supplier_doc_trades@5`: step A at medium, step B at high,
`checkReading` and `applyMapping` check, and the pure `proposalOf` decides. The one-call chooser is deleted. `source_docs.reading` holds the
reading, the tick list, the partner list, his own words and the question rows (`SupplierServiceQuestionDraft`, the 3.10 table's shape).

**Effort, by the estate's rule.** At high the reading did not fit its clock (run 62033fde): calls took 45-113 s, and 2 of 6 readings died
at the gateway's 115 s wall. The reading runs at medium because of the clock, recorded in
`effort_policy.SURFACES['supplier_doc_trades.profile_reading']`. The mapping stays at high.

**Held out.**
- H05, H07 and H10 were not looked at while tuning.
- H13 to H15 were written with their keys before any tuning: a villa contractor whose MEP is subcontracted, a cleaning-chemicals trader
  whose services come from a sister company, and a transport company offering "complete logistics solutions".
- Tuning used run abd5bd04 on the other ten files.
- Every prompt change was made before the two final runs.
- Three code changes followed the final runs and are not prompt tuning:
  - smaller reading parts, from run A's clock;
  - the halves path recorded for the replay;
  - a trade counts as covered by a vague question only through a key option. This one was prompted by held-out H05.

**The two final runs** (all 16 files; run A 519c9b06, run B 1f18dbf5, which is the recorded run):

| | run A | run B |
|---|---|---|
| stated services found, listed or asked (umbrella cards not counted) | 107/111 (96%) | 107/111 (96%) |
| tuned set (10 files) | 73/75 (97%) | 72/75 (96%) |
| held out, unseen while tuning (H05, H07, H10) | 15/16 (94%) | 16/16 (100%) |
| new profiles (H13-H15) | 19/20 (95%) | 19/20 (95%) |
| lowest profile | 83% (H15) | 82% (H04) |
| wrong listings (outside the key) | 1 (H07, `packaging.labels`) | 1 (H06, `industrial_pumps.booster_sets` for "booster pumps" in a plumbing list) |
| partner services listed as his own | 0 | 0 |
| "held" final state | 0 | 0 |
| vague profiles asked (H02, H03, H05, H12) | 4 of 4 | 4 of 4 |
| licence mismatch asked (H11) | yes | yes |
| model calls over 110 s | 1 of 52 (112.5 s, read; fixed by 4,000-character parts) | 1 of 56 (110.8 s, mapping) |
| per call p50 / p95 | 44 s / 81 s | 46 s / 92 s |
| end to end p50 / max | 105 s / 209 s | 102 s / 310 s (H09, one part read in halves) |
| spend | USD 0.1716 | USD 0.1826 |

**Not met.**
- 0 wrong: 1 in each run.
- Every call inside 110 s: one per run.
- The same list on both runs for at least 85% of keys: met on 7 of 13 profiles that list anything, missed on 6. H01 76%,
  H04 79%, H05 60%, H07 69%, H08 70%, H08D 80%; the differences are fair extras.
- H13's subcontracted MEP is marked partner and asked, but kept in his words: no key covers "Electrical works".

**What the analysis' prototype claimed against what the built reader measures.** The prototype found 89 of 91 stated services on the set it
was tuned on. The built reader finds 107 of 111 on 16 files, 6 of them never tuned on. The old reader found 85 of 114, left 4 of 12
companies held, and asked nothing.

**Spend for the build:** USD 0.5108 of the USD 0.60 cap, 5 tagged windows, all closed, 0 subjects left (`spend_and_leftovers` read by tag).
Evidence: `supplier-service-profiling-2026-11-12/scores_build_*.md`, `build_*.scores.json`, `build_*.bar.json`; the recording is
`scripts/e2e/services_hard_profiles/recorded.json`, replayed by `the_hard_profiles_are_read_offline.test.ts`.

## Part 7. After the independent review of branch 2 (12 Nov 2026), and the one final run

The review's verdict was "merge after fixes"; it confirmed the new reader is better where the old one failed and that deleting the old one
is right. What changed, and run c0afdde7 (16 files, USD 0.1813), which is now the recording replayed every commit.

**What changed:**
1. **A trade is listed only through a stated claim mapped to a key in it.** Trades are no longer taken from captions, brands, his own
   words or a vague statement; those are asked. At Confirm a proposed trade is his only when he ticked a service in it, held it already,
   or chose it at sign-up: the tab sends only those, and the server holds it (`supplier_services.keepTickedProposed`).
   On the recording: 115 trades with 12 wrong before; 67 with 1 wrong after. In the final run: 65 trades, 2 wrong (H06 `industrial_pumps`, H07 `packaging`).
2. **Code maps first.** A phrase that is a catalogue name or an approved alias is mapped by code. The model takes the rest in calls of 8,
   all at once, each part's phrases as soon as that part is read; a failed call is retried in halves. A phrase still unmapped is owed:
   the reading is not proposed and the existing sweep (`rereadDue`) reads it again. The mapping's request no longer depends on timing.
3. **Everything the reading found is visible and tickable, unticked.**
   - Partner rows read "Through a partner".
   - Caption and brand rows read "From your projects" or "From your brand list".
   - A key the model alone mapped, with no word of its name in his sentence, reads "Please check".
   - "Tick all" ticks only his own certain statements.
4. **Progressive.** As soon as step A has read, the summary and his services in his own words are stored (`source_docs.reading_progress`,
   through the same compare-and-set) and shown with "We are now matching these to our standard service names, usually within a minute".
6. **A heading alone proves nothing.** A vague line is quoted only when it was found in his text.
7. **Question hashes are of facts** (kind, trade, document, option keys), never of the model's wording.
8. **The licence is judged per claim**, as reader @4 judged each service. The live request has a test.

**The final run, stated as the supplier sees it with this branch alone** (stated services in the keys: 111):

| | count |
|---|---|
| listed for his tick, certain | 97 (87%) |
| listed "please check" | 3 |
| listed "from your projects" (all of H09's 7, plus 1) | 8 |
| asked only (a card of slice 4) | 1 |
| found in all | 109 (98%) |
| partner services marked partner / listed as his own | 10 / 0 |
| wrong services listed | 2 (H06 `industrial_pumps.booster_sets`, H07 `packaging.labels`) + 1 "please check" (H04) |
| trades listed / wrong | 65 / 2 |
| held, owed | 0, 0 |
| summary and his services on screen (step A) | p50 55 s, max 108 s |
| whole reading | p50 101 s, max 161 s; 13 of 16 within 120 s |

**Time against the old reader** (its mean on the same files, `current_all.json`). Faster on:

| profile | now | old reader |
|---|---|---|
| H02 | 56 s | 147 s |
| H05 | 84 s | 254 s |
| H06 | 110 s | 124 s |
| H08 | 95 s | 104 s |
| H12 | 22 s | 28 s |

Slower on:

| profile | now | old reader |
|---|---|---|
| H01 | 144 s | 77 s |
| H07 | 138 s | 69 s |
| H08D | 80 s | 72 s |
| H10 | 101 s | 83 s |
| H11 | 112 s | 47 s |

On every file his summary and services are on screen sooner than the old reader's whole reading would end, except H01, H07, H10 and
H11.

**Same list as the recorded run 1f18dbf5:** 60-100% per profile (H05 60%, H04 72%, H01 75%; H10 and H14 100%).

**Not met:** 0 wrong (2 listed); every reading within 120 s (3 of 16 over); a short clean profile no slower than the old reader (4 slower).
The certification's eight fixtures were not run: the budget went to the hard set.
