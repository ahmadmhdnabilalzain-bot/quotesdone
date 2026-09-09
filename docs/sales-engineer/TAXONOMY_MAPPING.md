# Sales Engineer pack — candidate taxonomy mapping

**What this is.** The Sales Engineer knowledge pack ships a registry of 128 sector families
(`contracts/sector_registry.json`). This document lines each of those 128 families up against the
two live taxonomies that already carry bindings in the estate, and records how confident the match
is. It is research output only.

**Nothing has been mapped in the database.** `sales_sector.maps_to_trades` is deliberately left
empty. The estate has four live taxonomies with live bindings — `catalog_supplier_categories` has
13,906 leads bound to it and `taxonomy_trade` has 15,305 capability rows bound to it — and a wrong
mapping does not fail loudly, it silently misroutes leads and capabilities. This report is the
**input to a later mapping decision, not the decision.** No SQL was written, no rows were changed.

**How the candidates were chosen.** Matching is on meaning (family `title` + `scope` against the
live `label` / `name`), not string equality. Every code and slug below was read out of the live
tables — `taxonomy_trade` (40 active rows: `code`, `label`) and `catalog_supplier_categories`
(86 rows: `slug`, `name`) — and is quoted exactly. Nothing is invented. A family with no genuine
live counterpart is marked `none` with an empty candidate list.

**Confidence labels.**

- `high` — at least one live entry is the same thing, not a parent of it. Safe to map with review.
- `medium` — the only live entry is a broader parent (or the match exists in one taxonomy but not
  the other). Mapping loses precision but does not misroute.
- `low` — only a tangential container exists. Mapping here would be a guess.
- `none` — no live counterpart in either taxonomy.

## Headline counts (of 128)

| Confidence | Families |
|---|---|
| high | 59 |
| medium | 53 |
| low | 13 |
| none | 3 |

Read that as: **59 of 128 families (46%) have a live entry that means the same thing.** Another 53
resolve only to a broader parent. 16 families (low + none) have no defensible live target at all.

## The 128 families

| sector_id | title | taxonomy_trade candidate(s) | catalog_supplier_categories candidate(s) | confidence | note |
|---|---|---|---|---|---|
| earthworks | Earthworks and excavation | `civil_works` | — | medium | Only the broad civil container; no excavation-specific live entry. |
| piling-foundations | Piling and specialist foundations | `civil_works` | — | medium | Specialist geotechnical work collapses into general civil. |
| ready-mix | Ready-mix concrete supply | `building_materials` | `cement-and-concrete-suppliers` | high | Category is an exact subject match. |
| structural-steel | Structural steel fabrication and erection | `steel` | `steel-and-reinforcement-suppliers` | high | Both taxonomies name it. |
| masonry | Masonry, blockwork and plaster | `building_materials`, `civil_works` | `construction-materials-suppliers` | medium | Materials exist live; the installed-works trade does not. |
| precast | Precast concrete components | `building_materials` | `cement-and-concrete-suppliers`, `modular-and-prefab-building-suppliers` | medium | Split across two partial categories; neither is precast per se. |
| demolition | Demolition and strip-out | `civil_works` | — | low | No demolition entry anywhere live. |
| concrete-cutting | Concrete cutting, coring and repair | `civil_works` | — | low | Niche trade with no live counterpart. |
| scaffolding | Scaffolding access systems | `scaffolding` | `formwork-and-scaffolding-suppliers` | high | Exact in both. |
| formwork | Formwork and falsework | `scaffolding` | `formwork-and-scaffolding-suppliers` | high | Category exact; the trade conflates formwork with access scaffold — the pack scope explicitly says they are not interchangeable. |
| excavation-shoring | Excavation support and shoring | `civil_works` | — | low | Shoring is not scaffolding; nothing live is closer than "civil". |
| crane-lifting | Cranes and lifting services | `heavy_equipment` | `industrial-equipment-suppliers` | medium | Equipment parents only; operated-lift services are not modelled. |
| mewp | Mobile elevating work platforms | `heavy_equipment`, `scaffolding` | — | medium | Access-equipment hire sits between two trade parents. |
| construction-hoists | Construction hoists and material lifts | `heavy_equipment` | `lifts-and-escalator-suppliers` | low | The live lifts category is permanent building lifts, not temporary site hoists. |
| site-cabins | Site cabins and modular temporary facilities | — | `modular-and-prefab-building-suppliers` | medium | Good category, no trade. |
| temporary-traffic | Temporary traffic and site logistics | `signage` | `signage-and-printing-suppliers` | low | Only the barrier/signage sliver overlaps; traffic management itself is absent. |
| turnkey-fitout | Integrated fit-out and refurbishment | `interior_fitout` | `fit-out-contractors-interior-fit-out-suppliers` | high | Exact in both. |
| interior-design | Interior design consultancy | `engineering_consultancy` | `interior-decoration` | medium | Live entries cover decoration and engineering design; design consultancy deliverables are not separated. |
| joinery | Custom joinery and cabinetry | `joinery` | `joinery-and-carpentry-suppliers` | high | Exact in both. |
| partitions | Partitions and drylining | `gypsum` | `gypsum-and-false-ceiling-suppliers` | high | Exact in both. |
| ceilings | Ceilings and suspended systems | `gypsum` | `gypsum-and-false-ceiling-suppliers` | high | Same live pair as partitions — the two pack families share one live target. |
| flooring | Floor finishes and raised floors | `flooring` | `flooring-suppliers` | high | Exact in both. |
| painting | Painting and protective decorative coatings | `painting` | `paints-and-finishing-materials-suppliers` | high | Exact in both. |
| furniture | Office and contract furniture | `upholstery` | `furniture-suppliers-ff-and-e-suppliers` | high | Category exact; the trade covers only soft furnishing. |
| waterproofing | Waterproofing and leak remediation | `waterproofing` | `waterproofing-suppliers` | high | Exact in both. |
| roofing | Roofing and roof refurbishment | `waterproofing` | `roofing-suppliers` | high | Category exact; trade is the waterproofing parent. |
| facade-cladding | Facade and cladding systems | `aluminium` | `aluminium-and-glass-suppliers` | high | Trade label is "Aluminium & cladding". |
| aluminium-windows | Aluminium windows and glazed openings | `aluminium`, `doors` | `aluminium-and-glass-suppliers` | high | Two trades split the same subject. |
| glass-mirrors | Architectural glass and mirrors | `glazing` | `aluminium-and-glass-suppliers` | high | Exact trade; category bundles glass with aluminium. |
| doors-hardware | Doors, shutters and architectural hardware | `doors` | `aluminium-and-glass-suppliers` | high | Trade exact; no live door-hardware category. |
| thermal-insulation | Thermal and acoustic insulation | `waterproofing` | `insulation-suppliers` | high | Category exact; the trade label already pairs waterproofing with insulation. |
| sealants-joints | Sealants, movement joints and repairs | `waterproofing`, `chemicals` | `chemical-suppliers` | medium | Only chemical/waterproofing parents; joint systems are not modelled. |
| integrated-mep | Integrated MEP contracting | `mep_general` | `mep-suppliers-electromechanical-suppliers` | high | Exact in both. |
| split-ac | Split and packaged air conditioning | `hvac` | `hvac-suppliers` | high | One live HVAC pair serves five pack families. |
| vrf | VRF and multi-split air conditioning | `hvac` | `hvac-suppliers` | high | Same live pair as split-ac. |
| chilled-water | Chilled-water plants and distribution | `hvac` | `hvac-suppliers` | high | Same live pair; plant vs. terminal distinction is lost. |
| ductwork | Ductwork and air distribution | `hvac` | `hvac-suppliers` | high | Same live pair. |
| ventilation | Ventilation, extract and indoor air systems | `hvac` | `hvac-suppliers` | high | Same live pair. |
| bms | Building management and controls | `home_automation`, `av_it` | `smart-home-and-home-automation-suppliers`, `industrial-automation-suppliers` | medium | Live entries are residential smart-home and industrial automation; commercial BMS falls between them. |
| energy-audit | Energy audits and building optimization | `engineering_consultancy` | — | medium | Consultancy parent only. |
| lv-distribution | Low-voltage electrical installations | `electrical` | `electrical-suppliers` | high | One live electrical pair serves four pack families. |
| switchgear-panels | Switchgear and control panels | `electrical` | `electrical-suppliers` | high | Same live pair. |
| cables-containment | Cables, cable containment and accessories | `electrical` | `electrical-suppliers` | high | Same live pair. |
| lighting | Lighting systems and controls | `electrical` | `electrical-suppliers` | high | Same live pair; no lighting-specific live entry. |
| generators | Generator sets and temporary power | `power_generators` | `electrical-suppliers`, `industrial-equipment-suppliers` | high | Trade exact; no generator category. |
| ups-batteries | UPS and battery backup | `power_generators`, `electrical` | `renewable-energy-companies-solar-ev-battery` | medium | The only battery category is the renewables one — a poor fit for standby UPS. |
| solar-pv | Solar PV systems | `solar` | `renewable-energy-companies-solar-ev-battery` | high | Exact in both. |
| ev-charging | EV charging infrastructure | `solar`, `electrical` | `renewable-energy-companies-solar-ev-battery` | high | Category names EV explicitly; the trade is the renewables parent. |
| plumbing | Water supply and plumbing | `plumbing` | `plumbing-and-sanitaryware-suppliers` | high | Exact in both. |
| pumps | Pumps and packaged pumping systems | `plumbing` | `industrial-equipment-suppliers` | medium | Pumps split between a plumbing and an industrial parent. |
| water-tanks | Water tanks and storage systems | `plumbing` | `plumbing-and-sanitaryware-suppliers` | medium | Parent only; tanks are not separated live. |
| water-treatment | Water treatment and filtration | `plumbing`, `chemicals` | `chemical-suppliers` | medium | No treatment category; chemicals is the nearest container. |
| drainage | Drainage, sewerage and stormwater | `plumbing` | `wastewater-and-drainage-contractors` | high | Category exact and regulated. |
| fire-alarm | Fire detection and alarm systems | `fire_fighting` | `fire-alarm-and-life-safety-suppliers` | high | Exact in both. |
| fire-suppression | Firefighting and suppression systems | `fire_fighting` | `fire-fighting-equipment-suppliers` | high | Exact in both. |
| passive-fire | Passive fire protection and firestopping | `fire_fighting` | `fire-fighting-equipment-suppliers` | medium | Live entries are active fire equipment; firestopping is a different discipline. |
| cctv | CCTV and video surveillance | `security_systems` | `elv-and-security-systems-suppliers` | high | One live ELV/security pair serves three pack families. |
| access-control | Access control and identity-based entry | `security_systems` | `elv-and-security-systems-suppliers` | high | Same live pair. |
| intrusion-alarm | Intrusion alarms and security monitoring | `security_systems` | `elv-and-security-systems-suppliers` | high | Note `security-companies` is manned guarding, a different subject — do not map it here. |
| structured-cabling | Structured copper and fiber cabling | `av_it`, `it_services` | `it-companies-it-services-providers`, `telecommunication-companies` | medium | Passive cabling infrastructure has no live entry of its own. |
| networking | Enterprise networking and Wi-Fi | `it_services` | `it-companies-it-services-providers` | high | Direct match in both. |
| av-systems | Audio-visual and conferencing systems | `av_it` | `av-and-media-equipment-suppliers` | high | Exact in both. |
| data-centers | Server rooms and data-center infrastructure | `it_services` | `data-centre-suppliers-and-service-providers` | high | Category exact. |
| cybersecurity | Authorized cybersecurity services | `it_services` | `it-companies-it-services-providers` | medium | IT parent only; no security-services entry live. |
| precision-machining | CNC machining and precision parts | `steel` | `industrial-equipment-suppliers` | low | Contract manufacturing is not modelled; both candidates are distant parents. |
| sheet-metal | Sheet-metal fabrication | `steel` | `industrial-equipment-suppliers` | medium | The steel trade covers metal fabrication broadly. |
| industrial-welding | Industrial welding and repair | `steel` | `industrial-equipment-suppliers` | medium | Fabrication parent; qualified welding services not separated. |
| industrial-automation | Industrial automation and controls | — | `industrial-automation-suppliers` | medium | Category exact, but no trade counterpart at all. |
| motors-drives | Electric motors and variable-speed drives | — | `bearings-and-power-transmission-suppliers`, `industrial-automation-suppliers` | medium | Split across two partial categories; no trade. |
| compressed-air | Compressed-air systems | — | `air-compressor-and-pneumatic-suppliers` | medium | Category exact, no trade. |
| hydraulics-pneumatics | Hydraulics and pneumatic systems | — | `air-compressor-and-pneumatic-suppliers` | medium | Category covers pneumatics only; hydraulics is absent. |
| process-valves-instruments | Process valves and instrumentation | `oilfield` | `industrial-automation-suppliers`, `oil-and-gas-equipment-suppliers` | medium | Process instrumentation appears only inside oil-and-gas and automation parents. |
| fasteners | Fasteners and fixing systems | — | `fasteners-and-fixings-suppliers` | medium | Category exact, no trade. |
| bearings-seals | Bearings, seals and power-transmission parts | — | `bearings-and-power-transmission-suppliers` | medium | Category exact, no trade. |
| hand-power-tools | Hand tools and power tools | — | `tools-and-abrasives-suppliers` | medium | Category exact, no trade. |
| ppe-workwear | PPE and protective workwear | `safety_equipment` | `textile-and-uniform-suppliers` | high | Trade exact; the category is garments generally, not certified PPE. |
| industrial-lubricants | Industrial lubricants and maintenance fluids | `chemicals`, `oilfield` | `chemical-suppliers` | medium | Chemicals parents only. |
| industrial-gases | Lawful industrial gas supply | `chemicals` | `gas-systems-suppliers-lpg-medical-gas-industrial-gas` | high | Category names industrial gas explicitly and is regulated. |
| packaging | Packaging materials and protective packaging | `packaging` | — | high | Trade exact ("Packaging & Printing Supplies"); there is no packaging category live at all. |
| industrial-filtration | Industrial filtration and filter elements | — | `industrial-equipment-suppliers` | low | Only a generic equipment container. |
| facilities-management | Integrated facilities management | `cleaning` | `facilities-management-companies` | high | Category exact; the trade label is "Cleaning & facility services". |
| commercial-cleaning | Commercial and specialist cleaning | `cleaning` | `cleaning-companies` | high | Exact in both. |
| facade-cleaning | Facade and high-level cleaning | `cleaning` | `cleaning-companies` | medium | Parent only; the work-at-height competence that defines this family is invisible live. |
| pest-control | Licensed pest-management services | `cleaning` | `facilities-management-companies` | low | A licensed discipline with no live entry; both candidates are containers. |
| waste-recycling | Waste collection and recycling | `cleaning` | — | low | No waste or recycling entry live. |
| lift-maintenance | Lift and escalator maintenance | `elevators` | `lifts-and-escalator-suppliers` | high | Exact in both; supply vs. maintenance is not separated live. |
| laundry-equipment-service | Commercial laundry equipment and service | — | `hospitality-supplies-companies` | low | Distant container only. |
| property-maintenance | Property repair and minor works | `cleaning` | `facilities-management-companies`, `property-management-companies` | medium | The "diagnose before assigning a trade" family maps only to FM parents. |
| freight-forwarding | International freight forwarding | `logistics_moving` | `logistics-and-freight-forwarding-companies` | high | Exact in both. |
| customs-clearance | Customs brokerage and clearance | `logistics_moving` | `logistics-and-freight-forwarding-companies` | medium | Brokerage is a distinct regulated activity folded into the freight parent. |
| warehousing | Warehousing and fulfillment | `logistics_moving` | `warehousing-and-3pl-companies` | high | Category exact. |
| courier-delivery | Courier and last-mile delivery | `logistics_moving` | `logistics-and-freight-forwarding-companies` | medium | Last-mile is not separated from freight live. |
| office-moving | Office and commercial relocation | `logistics_moving` | `logistics-and-freight-forwarding-companies` | high | Trade label is "Logistics, Movers & Storage". |
| heavy-haul | Heavy and oversize transport | `logistics_moving`, `heavy_equipment` | `logistics-and-freight-forwarding-companies` | medium | Engineered transport falls between a logistics and an equipment parent. |
| fleet-vehicle-rental | Commercial fleet and vehicle rental | — | — | none | Vehicle rental exists in neither taxonomy. |
| controlled-temperature-logistics | Non-F&B controlled-temperature logistics | `logistics_moving` | `warehousing-and-3pl-companies`, `cold-room-and-refrigeration-suppliers` | medium | The cold-room category is equipment supply, not validated cold-chain transport. |
| engineering-consultancy | Engineering design consultancy | `engineering_consultancy` | — | high | Trade exact ("Engineering Consultancy & Architecture"); no consultancy category. |
| project-management | Project management and client representation | `engineering_consultancy` | `management-consulting-firms` | medium | Construction PM is not distinguished from general management consulting. |
| quantity-surveying | Quantity surveying and cost consultancy | `engineering_consultancy` | `tender-and-bid-management-consultants` | medium | Nearest category is bid management, which is adjacent, not the same. |
| surveying | Land, building and utility surveys | `engineering_consultancy` | `testing-inspection-and-certification-companies` | medium | Land/utility survey has no live entry; TIC is the nearest. |
| testing-inspection | Material testing and independent inspection | — | `testing-inspection-and-certification-companies` | medium | Category exact, no trade. |
| environmental-consultancy | Environmental assessments and monitoring | `engineering_consultancy` | `testing-inspection-and-certification-companies` | low | Both candidates are distant; environmental work is not modelled. |
| accounting-tax | Accounting, audit and tax services | — | `accounting-and-audit-firms`, `tax-consultants` | medium | Two exact categories, no trade counterpart. |
| legal-translation | Legal services and certified translation | — | `law-firms`, `translation-and-interpretation-companies` | medium | The pack deliberately keeps these separate; live has both, but no trade. |
| custom-software | Custom software development | `it_services` | `it-companies-it-services-providers` | high | Direct match in both. |
| websites-ecommerce | Websites and non-F&B e-commerce | `it_services` | `it-companies-it-services-providers`, `marketing-and-advertising-agencies` | medium | Web work straddles IT and marketing live. |
| erp-crm | ERP and CRM implementation | `it_services` | `it-companies-it-services-providers` | medium | IT parent only; implementation practice not separated. |
| managed-it | Managed IT support | `it_services` | `it-companies-it-services-providers` | high | Direct match in both. |
| cloud-data-services | Cloud, data and analytics services | `it_services` | `data-centre-suppliers-and-service-providers`, `it-companies-it-services-providers` | medium | Data-centre is infrastructure, not cloud/analytics services. |
| digital-marketing | Digital marketing and campaign services | — | `marketing-and-advertising-agencies` | medium | Category exact, no trade. |
| creative-photography | Design, photography and video production | — | `marketing-and-advertising-agencies` | medium | Production services folded into agencies; no trade. |
| printing-signage | Printing, signage and display fabrication | `signage` | `signage-and-printing-suppliers` | high | Exact in both. |
| recruitment-staffing | Recruitment and lawful staffing services | `labour_supply` | `hr-and-recruitment-agencies`, `staffing-companies` | high | Live already separates recruitment from staffing, matching the pack scope. |
| training | Professional and technical training | — | `education-equipment-suppliers` | low | The live category is equipment supply, not training delivery. |
| uniforms | Uniforms and textile production | `safety_equipment` | `textile-and-uniform-suppliers` | high | Category exact; the trade only covers the PPE end. |
| events-exhibitions | Non-F&B event and exhibition services | — | `event-management-companies`, `exhibition-stand-contractors` | medium | Two exact categories, no trade. |
| landscaping | Landscape construction and maintenance | `landscaping` | — | high | Trade exact ("Landscaping & pools"); no landscaping category exists. |
| irrigation | Irrigation systems | `landscaping` | — | medium | Landscaping parent only. |
| swimming-pools | Swimming pools and water features | `landscaping` | `swimming-pool-suppliers-and-contractors` | high | Category exact; the trade bundles pools with landscaping. |
| sports-playgrounds | Sports surfaces and playground equipment | — | `gym-and-sports-equipment-suppliers` | low | Live category is gym equipment; sports surfaces and playgrounds are absent. |
| medical-equipment | Medical equipment procurement and servicing | — | `medical-equipment-suppliers` | medium | Category exact and regulated, but no trade. |
| laboratory-equipment | Laboratory equipment and laboratory fit-out | — | `laboratory-equipment-suppliers`, `cleanroom-suppliers-and-contractors` | medium | Two exact categories cover equipment and fit-out; no trade. |
| jewelry-manufacturing | Jewelry design and contract manufacturing | — | `jewelry-suppliers-gold-and-diamond-traders` | medium | Live category is trading, not contract manufacturing; no trade. |
| marine-services | Marine equipment and vessel services | `marine` | `marine-equipment-and-marine-safety-suppliers`, `offshore-and-marine-construction-companies` | high | Exact in both taxonomies. |
| aviation-ground-equipment | Aviation ground equipment and authorized services | — | `aviation-and-ground-support-suppliers` | medium | Category exact and regulated; no trade. |
| vehicle-parts-repair | Vehicle parts and automotive services | — | — | none | Automotive exists in neither taxonomy. |
| real-estate-services | Commercial real-estate and property services | — | `real-estate-agencies`, `property-management-companies` | medium | Two exact categories; no trade. |
| insurance-brokerage | Business insurance and authorized brokerage | — | — | none | Insurance exists in neither taxonomy. |

## Families with no candidate at all

Three of the 128 have no live counterpart in either taxonomy:

| sector_id | title |
|---|---|
| `fleet-vehicle-rental` | Commercial fleet and vehicle rental |
| `vehicle-parts-repair` | Vehicle parts and automotive services |
| `insurance-brokerage` | Business insurance and authorized brokerage |

**What the gap means.** All three are whole commercial verticals — automotive (both rental and
parts/repair) and insurance — that the live taxonomies simply do not model. This is not a naming
mismatch that a better synonym would fix; there is no row to map to. A buyer arriving with a fleet
or an insurance requirement has no lead category to land in and no supplier capability row to be
matched against, so the Sales Engineer questions for these three families would be asked into a
routing dead end.

The 13 `low` families are a softer version of the same gap: demolition, concrete cutting,
excavation shoring, construction hoists, temporary traffic management, precision machining,
industrial filtration, pest control, waste and recycling, laundry equipment service, environmental
consultancy, training delivery, and sports surfaces/playgrounds all exist live only as a distant
parent. Mapping any of them would be a guess dressed as a decision, and — given
`catalog_supplier_categories` carries 13,906 bound leads and `taxonomy_trade` 15,305 bound
capability rows — a guess is exactly what must not be written.

Two structural asymmetries are also worth carrying into the mapping decision:

- **Trade-only subjects.** `packaging`, `landscaping` and `engineering_consultancy` have an exact
  trade code but no category at all.
- **Category-only subjects.** A large block — industrial automation, compressors/pneumatics,
  fasteners, bearings, tools, testing/inspection, accounting, legal, translation, marketing, events,
  medical, laboratory, jewelry, aviation, real estate — has an exact category slug but no trade
  code. These are precisely the families capped at `medium` above, and they are capped for a
  taxonomy-shape reason, not a matching-quality one: `taxonomy_trade` is a construction/MEP
  vocabulary, while `catalog_supplier_categories` spans the wider business economy.
