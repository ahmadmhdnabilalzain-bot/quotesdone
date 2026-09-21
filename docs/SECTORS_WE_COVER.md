# Which sectors QuotesDone covers

Seat: sales_engineer. Measured read-only on production `htdblwldjkcgjvmqkbeh` on **21 Sep 2026
between 09:18 and 09:50 UTC** through `scripts/qsql.mjs` (the management API read path; nothing
written) and from the repository at commit `bc049bd`. This document answers the founder's question
of 18 Sep 2026 — *which sectors do we cover?* — because the answer defines the scope of the
knowledge doctrine (`docs/KNOWLEDGE_DOCTRINE.md`). The founder's own belief, instruction 54:
*"we actually do almost every category available in UAE except F&B for now"*.

## 1. The answer in four lines

1. **The platform sells exactly 40 trades** — `public.taxonomy_trade`, 40 rows, all active, every
   one with an English label, an Arabic label, aliases (8–37 each) and **five prepared services**
   (`taxonomy_trade_service`: 201 active rows over 40 trades; `interior_fitout` has six because the
   founder's own decoration example needed one). These 40 are the only trades an inquiry can be
   routed to, a supplier can confirm, or an invitation can target.
2. **All 40 are construction, MEP, fit-out, industrial supply and site services.** There is no F&B
   trade — and also no professional-services trade (legal, accounting, HR, insurance, real estate,
   medical, pharma, education, travel, pets, jewellery). Those exist only in the 86-row supplier
   catalogue and in the knowledge bulk; nothing sells them (§4).
3. **Every one of the 40 has a live supplier population**: 18,767 of 22,265 real leads carry at
   least one `invite_trades` code; the smallest trade holds 26 leads (`logistics_moving`), the
   largest 3,762 (`building_materials`). `supplier_capabilities.trades` names the same 40 codes and
   no other; `leads.invite_trades` names no code outside the 40.
4. **Demand is not yet measurable**: `inquiries` holds 3 rows (2 gypsum, 1 painting), none demo,
   and `inquiry_trade_candidate` is empty. Coverage is therefore a statement about *supply and
   vocabulary*, not about *demand*.

## 2. The table — one row per trade the platform sells

Columns: *taxonomy* = `taxonomy_trade`; *services* = active `taxonomy_trade_service` rows;
*implication map* = `service_implication` rows whose `from_code` starts with this trade / whose
`implies_trade` is this trade (113 active rows in total); *directory pages* = the
`category_specs` slugs (the 54 pages of `src/content/categories.json` plus `general` and
`carpentry`) that `fn_taxonomy_trades_for()` resolves to this trade; *leads* = real leads
(`is_demo` false) with this code in `invite_trades`; *supplier_capabilities* = rows with this code
in `trades` (15,307 rows, 1 confirmed); *inquiries* = rows with this code in `inquiries.trades`;
*mep_trade* = the legacy 5-row bilingual MEP table.

| # | trade code | EN | AR | taxonomy | services | implication map (from / to) | directory pages (category_specs slugs that resolve here) | leads (invite_trades) | supplier_capabilities.trades | inquiries.trades | mep_trade |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `hvac` | HVAC & air conditioning | التكييف والتهوية | active, 18 aliases | 5 | 1 / 6 | `hvac` | 654 | 492 | 0 | HVAC (core) |
| 2 | `electrical` | Electrical | الأعمال الكهربائية | active, 23 aliases, authority: electrical_utility | 5 | 2 / 7 | `electrical` | 1346 | 1194 | 0 | Electrical (core) |
| 3 | `building_materials` | Building & Construction Materials | مواد البناء والتشييد | active, 15 aliases | 5 | 0 / 0 | **none** | 3762 | 1905 | 0 | — |
| 4 | `engineering_consultancy` | Engineering Consultancy & Architecture | الاستشارات الهندسية والعمارة | active, 19 aliases | 5 | 0 / 0 | `engineering-and-architectural-consultancies` | 1058 | 661 | 0 | — |
| 5 | `power_generators` | Generators & Power Equipment | المولدات ومعدات الطاقة | active, 12 aliases | 5 | 2 / 2 | `generators` | 98 | 83 | 0 | — |
| 6 | `heavy_equipment` | Heavy Equipment & Plant | المعدات الثقيلة والآليات | active, 22 aliases | 5 | 1 / 1 | **none** | 470 | 384 | 0 | — |
| 7 | `plumbing` | Plumbing & sanitary | السباكة والأدوات الصحية | active, 15 aliases | 5 | 2 / 8 | `plumbing` | 578 | 487 | 0 | Plumbing & Sanitaryware (core) |
| 8 | `labour_supply` | Manpower & Labour Supply | توريد العمالة | active, 12 aliases | 5 | 0 / 0 | **none** | 207 | 187 | 0 | — |
| 9 | `safety_equipment` | Safety Equipment & PPE | معدات السلامة والوقاية الشخصية | active, 13 aliases | 5 | 0 / 0 | **none** | 272 | 152 | 0 | — |
| 10 | `solar` | Solar & Renewable Energy | الطاقة الشمسية والمتجددة | active, 12 aliases | 5 | 2 / 2 | `solar` | 78 | 56 | 0 | — |
| 11 | `chemicals` | Industrial & Construction Chemicals | الكيماويات الصناعية والإنشائية | active, 8 aliases | 5 | 0 / 0 | **none** | 326 | 296 | 0 | — |
| 12 | `plastics_pipes` | Plastics, Pipes & Fittings | البلاستيك والأنابيب والتجهيزات | active, 12 aliases | 5 | 0 / 0 | **none** | 371 | 340 | 0 | — |
| 13 | `oilfield` | Oilfield & Industrial Supplies | مستلزمات حقول النفط والصناعة | active, 9 aliases | 5 | 0 / 0 | **none** | 187 | 164 | 0 | — |
| 14 | `home_automation` | Home & Building Automation | أتمتة المنازل والمباني | active, 14 aliases | 5 | 2 / 2 | `smart-home` | 184 | 52 | 0 | — |
| 15 | `logistics_moving` | Logistics, Movers & Storage | النقل والتخزين والخدمات اللوجستية | active, 14 aliases | 5 | 1 / 1 | `movers` | 26 | 21 | 0 | — |
| 16 | `packaging` | Packaging & Printing Supplies | مستلزمات التغليف والطباعة | active, 9 aliases | 5 | 0 / 0 | **none** | 129 | 76 | 0 | — |
| 17 | `marine` | Marine & Offshore Supplies | المستلزمات والأعمال البحرية | active, 9 aliases | 5 | 0 / 0 | **none** | 169 | 102 | 0 | — |
| 18 | `fire_fighting` | Fire fighting & life safety | مكافحة الحريق وأنظمة السلامة | active, 24 aliases, authority: civil_defence | 5 | 2 / 2 | `safety` | 424 | 412 | 0 | — |
| 19 | `it_services` | IT & Network Services | خدمات تقنية المعلومات والشبكات | active, 12 aliases | 5 | 3 / 2 | `it-networking` | 169 | 22 | 0 | — |
| 20 | `joinery` | Joinery & carpentry | النجارة والأعمال الخشبية | active, 37 aliases | 5 | 3 / 7 | `carpentry`, `carpentry-joinery`, `kitchens` | 655 | 573 | 0 | — |
| 21 | `glazing` | Glass & glazing | الزجاج والواجهات الزجاجية | active, 11 aliases | 5 | 1 / 3 | `glass` | 733 | 499 | 0 | — |
| 22 | `aluminium` | Aluminium & cladding | الألمنيوم والتكسية | active, 16 aliases | 5 | 3 / 2 | `aluminium` | 822 | 546 | 1 | — |
| 23 | `steel` | Steel & metal fabrication | الحديد وتشكيل المعادن | active, 19 aliases | 5 | 3 / 3 | `steel`, `structural-steel-fabrication` | 602 | 453 | 0 | — |
| 24 | `flooring` | Flooring | الأرضيات | active, 26 aliases | 5 | 1 / 12 | `carpets`, `epoxy-flooring`, `flooring`, `marble-granite`, `tiling` | 1393 | 1275 | 0 | — |
| 25 | `painting` | Painting & finishes | الدهانات والتشطيبات | active, 10 aliases | 5 | 2 / 10 | `painting` | 1139 | 1057 | 1 | — |
| 26 | `gypsum` | Gypsum, partitions & ceilings | الجبس والقواطع والأسقف | active, 15 aliases | 5 | 3 / 17 | `gypsum` | 338 | 320 | 2 | — |
| 27 | `signage` | Signage & printing | اللافتات والطباعة | active, 15 aliases | 5 | 2 / 2 | `signage` | 583 | 582 | 0 | — |
| 28 | `landscaping` | Landscaping & pools | تنسيق الحدائق والمسابح | active, 21 aliases | 5 | 2 / 2 | `landscaping`, `swimming-pools` | 732 | 686 | 0 | — |
| 29 | `security_systems` | Security systems | الأنظمة الأمنية | active, 18 aliases, authority: sira | 5 | 1 / 1 | `security` | 652 | 637 | 0 | — |
| 30 | `elevators` | Elevators & escalators | المصاعد والسلالم المتحركة | active, 12 aliases | 5 | 1 / 1 | `elevators` | 154 | 84 | 0 | — |
| 31 | `doors` | Doors & windows | الأبواب والنوافذ | active, 12 aliases | 5 | 1 / 1 | `garage-doors` | 516 | 447 | 0 | — |
| 32 | `waterproofing` | Waterproofing & insulation | العزل المائي والحراري | active, 10 aliases | 5 | 1 / 2 | `insulation`, `waterproofing` | 118 | 89 | 0 | — |
| 33 | `upholstery` | Upholstery & soft furnishing | التنجيد والمفروشات | active, 15 aliases | 5 | 2 / 3 | `blinds-curtains`, `upholstery` | 695 | 682 | 0 | — |
| 34 | `wallpaper` | Wallpaper & wall finishes | ورق الجدران والتشطيبات الجدارية | active, 9 aliases | 5 | 1 / 4 | `wallpaper` | 308 | 308 | 0 | — |
| 35 | `scaffolding` | Scaffolding & access | السقالات ومعدات الوصول | active, 9 aliases | 5 | 1 / 1 | `scaffolding` | 314 | 264 | 0 | — |
| 36 | `cleaning` | Cleaning & facility services | التنظيف وخدمات المرافق | active, 16 aliases | 5 | 2 / 2 | `cleaning`, `facade-cleaning`, `water-tank-cleaning` | 735 | 434 | 0 | — |
| 37 | `av_it` | AV, IT & low current | الصوت والصورة والتيار الخفيف | active, 14 aliases | 5 | 1 / 2 | `av-systems`, `it-networking` | 179 | 168 | 0 | — |
| 38 | `interior_fitout` | Interior fit-out | التشطيبات والتجهيزات الداخلية | active, 18 aliases | 6 | 37 / 0 | `commercial-retail-fitout`, `fitout`, `interior-design` | 1676 | 1369 | 0 | — |
| 39 | `civil_works` | Civil & construction works | الأعمال المدنية والإنشائية | active, 25 aliases | 5 | 11 / 5 | `demolition`, `general-building-contracting`, `masonry` | 3689 | 3101 | 0 | — |
| 40 | `mep_general` | MEP (combined) | الأعمال الكهروميكانيكية المتكاملة (MEP) | active, 10 aliases | 5 | 16 / 0 | `combined-mep`, `mep` | 648 | 500 | 0 | — |

A lead may carry several codes, so the leads column sums to 27,189 over 18,767 leads; the
supplier_capabilities column sums to 21,160 over 15,307 rows.

## 3. Named in one place but not the others

**Taxonomy trades with NO directory page** (sold and matched, but no `category_specs` intake
form, no page in `src/content/categories.json`, and therefore no `fn_quote_spec_group` group, no
`price_benchmark` row and no `category_quote_specs` mandatory-spec list): `building_materials`
(3,762 leads — the largest trade), `heavy_equipment`, `labour_supply`, `safety_equipment`,
`chemicals`, `plastics_pipes`, `oilfield`, `packaging`, `marine`. Nine trades. A customer can be
routed to them and a supplier can confirm them, but the comparison engine has no per-trade spec
vocabulary for them.

**Directory pages that resolve to NO taxonomy trade** (`fn_taxonomy_trades_for` returns only the
slug itself): `acrylic` (52 leads under sector `acrylic`), `custom-furniture`, `roofing`,
`pest` (50 leads under `pest_control`), `tents-and-shade-structures`, `job-shop-manufacturing`,
and the two catch-alls `general` / `general-services-other`. A customer who picks one of these
pages produces an inquiry whose `category` no supplier trade matches; `intake_trade_taxonomy` (31
rows) does not map them. `roofing` is the surprising one: it has a page, 5 price bands and a spec
group, and no trade.

**mep_trade only**: `fire` (Fire & Life Safety) and `elv` (ELV & Security) — the legacy 5-row
table names them; the taxonomy names `fire_fighting` and `security_systems`/`av_it` instead.
`mep_trade` is read by `src/content/categories.json` for two Arabic labels and by nothing that
routes.

**Leads sectors with no trade** (the scraper's `sector`, real leads): `general` 3,442,
`contractor` 3,039, `equipment` 940, `consultant` 556, `interior_design` 380, `concrete` 71,
`visa-pro-services` 64, `pest_control` 50, `events` 40, `facilities_management` 35 — the file
`scripts/sql/four_thousand_suppliers_lost_to_a_hyphen.sql` records the decision that `general` and
`contractor` stay unmatched until the supplier states its own scope, and that events, garments,
catering and visa services are out of scope.

**`sales_sector`**: 128 rows, every one with `maps_to_trades = {}`. It is a list of 128
sub-sectors the sales seat could recognise, and it is joined to nothing. It is not evidence of
coverage.

**The 86-row supplier catalogue** (`catalog_supplier_categories`) and the 67 knowledge
families (`catalog_domains`) name F&B (catering 27, bakery 29, food processing 30) and every
professional service. `lead_trade_map` (63 rows) bridges 40-trade codes and legacy slugs to
catalogue slugs — 16 catalogue categories are reachable from a trade; the other 70 are reachable
from nothing that sells.

## 4. So: is it "everything except F&B"?

Measured: **F&B is indeed not sold** — no taxonomy trade, no directory page, no `invite_trades`
code, and the 40 `events` / catering-type leads sit in the `~none` invitation bucket. But
"everything" is 40 trades of the built environment and its supply chain. Not sold, though not
F&B either: legal, accounting/tax/PRO, HR/staffing, insurance, real estate, healthcare, pharma,
laboratory, education, travel, pets, beauty, jewellery, translation, telecoms, data centres, cold
rooms, hospitality supplies. Whether they *should* be sold is the founder's commercial call; this
document only records that today nothing sells them, and that the knowledge doctrine therefore
scopes to the 40 trades in §2.

## 5. Boundary of what was measured

- Read only the tables named above; not `catalog_subcategories`, `seo_categories`,
  `marketing_category_demand`, `org_category_identity` or the website's blog/SEO pages.
- `leads` counts exclude the one `is_demo` row and count codes, not companies.
- `inquiries.trades` was 3 rows at read time; the aluminium count moved from 0 to 1 and
  `supplier_capabilities` aluminium from 543 to 546 between two reads 20 minutes apart — the
  tables are live.
- Directory pages were resolved through `fn_taxonomy_trades_for(array[slug])`, the same routine
  routing uses; a page that resolves only to itself is reported as "no trade" even if a human could
  guess one, because the founder's rule is exact match or none (14 Sep 2026).
- `sales_sector.maps_to_trades` empty on 128/128 was measured; why it is empty was not.
