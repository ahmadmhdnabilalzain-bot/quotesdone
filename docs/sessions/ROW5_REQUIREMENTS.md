# ROW #5 — SUPPLIER PORTAL: THE ENUMERATION

Source: `docs/specs_row5_supplier_portal.txt`, 24 sections, 884 lines.
Enumerated 2026-08-07. **234 requirements.** This number is asserted as `TOTAL` in
`scripts/staging/verify_supplier_blueprint.mjs`; a run that registers a different count prints
`!! N checks ran, the spec has 234` and the percentage is not trustworthy.

The count is not row #4's 147 and was not derived from it. Two sections of this spec have no row #4
equivalent and carry 34 requirements between them: §23 names fifteen technologies and §24 names
nineteen portal modules, each individually verifiable.

Grain rule, identical to row #4: **one enumerated line of a spec mock = one requirement.** Where the
spec draws a screen, every labelled value on that screen is a requirement. Where the spec names a
list (upload formats, nav items, monitored risks, technologies, modules), every member is a
requirement. Each section additionally carries the mechanism requirements the spec implies — the
routine that computes the number, and the render leg that puts it on the supplier's screen.

---

## §1 Supplier Entry Experience — 9

| id | requirement |
|---|---|
| `entry-landing-route` | a supplier landing screen exists and is reachable unauthenticated |
| `entry-headline-network` | "QuotesDone Supplier Network" welcome headline |
| `entry-value-proposition` | "Grow your business with AI-powered procurement" value line |
| `entry-cta-become-verified` | primary CTA "Become a Verified Supplier" → registration |
| `entry-cta-how-it-works` | secondary CTA "Watch How It Works" |
| `entry-bg-animated-network` | animated supply-network background |
| `entry-bg-moving-connections` | moving connections between suppliers and projects |
| `entry-bg-world-map` | world map visualization |
| `entry-not-form-wall` | entry is not "register → fill 20 forms"; form-field count on the entry surface is bounded |

## §2 AI Supplier Onboarding — 11

| id | requirement |
|---|---|
| `onb-ai-conversation` | conversational onboarding surface exists instead of a form |
| `onb-prompt-tell-me` | the agent opens by asking the supplier about their company |
| `onb-freetext-input` | the supplier answers in free text, not fields |
| `onb-extract-company-name` | AI extracts the company name |
| `onb-extract-category` | AI extracts the category |
| `onb-extract-company-type` | AI extracts the company type (Manufacturer/…) |
| `onb-extract-location` | AI extracts the location |
| `onb-extract-capability` | AI extracts the capability |
| `onb-extract-markets` | AI extracts the served markets (multiple) |
| `onb-creates-profile` | extraction writes the supplier profile automatically |
| `onb-extraction-routine` | a server-side routine/endpoint performs the extraction |

## §3 Supplier Digital Twin — 9

| id | requirement |
|---|---|
| `twin-object` | a supplier digital-twin object/routine exists |
| `twin-company-strength` | Company Strength percentage with a bar |
| `twin-capabilities-list` | capability checklist (Manufacturing/Installation/Maintenance) |
| `twin-product-count` | product count |
| `twin-certifications` | certification list (ISO 9001, ISO 14001) |
| `twin-production-capacity` | production capacity (units/year) |
| `twin-best-opportunities` | best-opportunity project types |
| `twin-risk-level` | risk level |
| `twin-supplier-visible` | the twin renders on the supplier's own surface |

## §4 Supplier Command Center UI — 10

| id | requirement |
|---|---|
| `cc-company-header` | the supplier's company name heads the screen |
| `cc-verified-badge` | "Verified Supplier" badge |
| `cc-star-rating` | star rating |
| `cc-intelligence-score` | Supplier Intelligence Score |
| `cc-opportunities-count` | new-RFQ count tile |
| `cc-perf-response` | Response % tile |
| `cc-perf-quality` | Quality % tile |
| `cc-assistant-panel` | AI Assistant panel on the command center |
| `cc-assistant-actionable` | its advice names a concrete gap and a quantified upside |
| `cc-workspace-not-dashboard` | command-center layout, not a table dashboard |

## §5 3D Supplier Environment — 12

| id | requirement |
|---|---|
| `env-3d-scene` | a 3D/WebGL company environment on the supplier surface |
| `env-node-factory` | Factory node |
| `env-node-production-line` | Production Line node |
| `env-node-inventory` | Inventory node |
| `env-node-orders` | Orders node |
| `env-node-customers` | Customers node |
| `env-clickable-objects` | clicking an object opens its information |
| `env-warehouse-panel` | the warehouse click opens an inventory panel |
| `env-inv-available` | Available quantity |
| `env-inv-reserved` | Reserved quantity |
| `env-inv-production` | In-production quantity |
| `env-inventory-reader` | the panel reads real `inv_items`/`inv_stock_moves` rows |

## §6 Supplier Profile Page — 9

| id | requirement |
|---|---|
| `prof-identity-name` | company identity name |
| `prof-verified-mark` | verified mark |
| `prof-established-year` | established year |
| `prof-employees` | employee count |
| `prof-countries` | countries served |
| `prof-ai-confidence` | AI Confidence percentage |
| `prof-capability-map` | capability map rendered as a visual graph |
| `prof-capability-map-edges` | root category → capability children edges |
| `prof-living-not-static` | the page reads computed/AI fields, not only stored form fields |

## §7 Product Intelligence System — 14

| id | requirement |
|---|---|
| `prod-upload-catalog` | catalogs accepted |
| `prod-upload-pdf` | PDFs accepted |
| `prod-upload-excel` | Excel accepted |
| `prod-upload-bim` | BIM files accepted |
| `prod-upload-cad` | CAD files accepted |
| `prod-upload-images` | images accepted |
| `prod-upload-pricelist` | price lists accepted |
| `prod-ai-extraction` | a routine converts uploads into products |
| `prod-count-products` | product count surfaced |
| `prod-count-categories` | category count surfaced |
| `prod-count-attributes` | specification/attribute count surfaced |
| `prod-searchable` | products are searchable |
| `prod-table-reader` | `supplier_product` has a reader that is not its writer |
| `prod-supplier-visible` | product intelligence renders on the supplier surface |

## §8 AI Product Cards — 9

| id | requirement |
|---|---|
| `card-component` | a product card component exists |
| `card-name` | product name |
| `card-category` | product category |
| `card-spec-attributes` | spec attributes (capacity, efficiency) |
| `card-certifications` | certification mark |
| `card-availability` | available units |
| `card-compatible-projects` | compatible project types |
| `card-ai-match-pct` | AI match percentage |
| `card-match-routine` | the match percentage is computed server-side |

## §9 RFQ Intelligence Center — 9

| id | requirement |
|---|---|
| `rfq-opportunities-screen` | a NEW OPPORTUNITIES screen |
| `rfq-project-title` | project title |
| `rfq-requirement` | the requirement line |
| `rfq-quantity` | quantity |
| `rfq-deadline` | deadline |
| `rfq-ai-match-pct` | AI match percentage |
| `rfq-estimated-value` | estimated opportunity value |
| `rfq-submit-quote-action` | Submit Quote action |
| `rfq-feed-routine` | the opportunity feed is computed server-side for this supplier |

## §10 AI RFQ Ranking — 8

| id | requirement |
|---|---|
| `rank-recommended-list` | a "Recommended For You" list |
| `rank-ordered` | ranked ordering, not chronological |
| `rank-match-pct` | per-RFQ match percentage |
| `rank-why-reasons` | a "Why" explanation list is rendered |
| `rank-reason-capacity` | capacity-fit reason |
| `rank-reason-similar-history` | previous-similar-project reason |
| `rank-reason-location` | proximity reason |
| `rank-routine` | ranking is computed by a routine, not a client-side sort |

## §11 AI Quote Builder — 9

| id | requirement |
|---|---|
| `qb-builder-surface` | a quote-builder surface |
| `qb-nl-intent` | natural-language "I want to quote this project" entry |
| `qb-recommend-price` | recommended price |
| `qb-market-position` | market position verdict |
| `qb-delivery-estimate` | delivery estimate |
| `qb-risk-level` | risk level |
| `qb-warranty-suggestion` | suggested warranty |
| `qb-routine` | a server routine produces the recommendation |
| `qb-writes-quote` | accepting the recommendation creates a real quote |

## §12 AI Negotiation Assistant — 7

| id | requirement |
|---|---|
| `neg-assistant-surface` | a negotiation-assistant surface |
| `neg-detects-price-pressure` | it recognises a discount request in customer correspondence |
| `neg-current-margin` | current margin |
| `neg-possible-reduction` | possible reduction |
| `neg-recommended-response` | a recommended response is drafted |
| `neg-response-actionable` | the draft can be sent or applied |
| `neg-routine` | a server routine produces the analysis |

## §13 Supplier Performance Intelligence — 9

| id | requirement |
|---|---|
| `perf-health-panel` | a SUPPLIER HEALTH panel |
| `perf-quality` | Quality metric |
| `perf-delivery` | Delivery metric |
| `perf-response` | Response metric |
| `perf-pricing` | Pricing metric |
| `perf-overall` | Overall score out of 100 |
| `perf-bars-rendered` | metrics render as bars, not bare numbers |
| `perf-living` | the score is recomputed by a routine/cron, not a static column |
| `perf-supplier-visible` | the panel renders on the supplier surface |

## §14 Market Intelligence — 7

| id | requirement |
|---|---|
| `mkt-panel` | a Market Intelligence panel |
| `mkt-demand-trend` | demand trend: category, direction, percentage |
| `mkt-most-requested` | most-requested project type |
| `mkt-avg-market-price` | average market price |
| `mkt-competitor-count` | competitor count |
| `mkt-routine` | the figures are computed from real demand data |
| `mkt-chart` | the trend renders as a chart |

## §15 Supplier AI Employee — 7

| id | requirement |
|---|---|
| `emp-assistant-present` | an AI assistant is available on the supplier surface |
| `emp-nl-question` | it accepts free-form questions |
| `emp-loss-analysis` | it produces a lost-opportunity breakdown |
| `emp-loss-reasons-pct` | the reasons carry percentages |
| `emp-recommendations` | it recommends concrete actions |
| `emp-recommendation-actionable` | the recommendation links to the fix |
| `emp-agent-routine` | an agent routine backs it with supplier context |

## §16 Supplier Document Intelligence — 8

| id | requirement |
|---|---|
| `doc-intelligence-panel` | a document-intelligence panel |
| `doc-identity` | documents are recognised by type, not filename |
| `doc-status-valid` | validity status |
| `doc-expiry-date` | expiry date |
| `doc-used-for-count` | how many RFQs the document unlocked |
| `doc-impact` | impact rating |
| `doc-extraction-routine` | server-side document understanding |
| `doc-supplier-visible` | the panel renders on the supplier surface |

## §17 Supplier Risk Protection — 8

| id | requirement |
|---|---|
| `risk-monitor-routine` | a monitoring routine runs on a schedule |
| `risk-monitor-cert-expiry` | it monitors certificate expiry |
| `risk-monitor-complaints` | it monitors customer complaints |
| `risk-monitor-response-delays` | it monitors response delays |
| `risk-monitor-performance-drops` | it monitors performance drops |
| `risk-warning-surface` | warnings render to the supplier |
| `risk-warning-cause` | the warning names its cause |
| `risk-recommended-action` | the warning carries a recommended action |

## §18 Supplier Collaboration Workspace — 8

| id | requirement |
|---|---|
| `collab-workspace-per-relationship` | every customer relationship gets a workspace |
| `collab-project-identity` | the workspace names its project |
| `collab-files` | files live in the workspace |
| `collab-file-categories` | drawings / specifications / contracts categorisation |
| `collab-message-count` | message count |
| `collab-messaging` | messages are readable and sendable in the workspace |
| `collab-timeline-pct` | timeline completion percentage |
| `collab-supplier-visible` | the workspace renders on the supplier surface |

## §19 Supplier Network Map — 7

| id | requirement |
|---|---|
| `map-globe` | a 3D globe component |
| `map-geo-markers` | markers positioned by real geography |
| `map-layer-suppliers` | suppliers layer |
| `map-layer-demand` | demand layer |
| `map-layer-projects` | projects layer |
| `map-layer-shipments` | shipments layer |
| `map-data-reader` | markers read real rows, not fixtures |

## §20 Supplier Gamification — 8

| id | requirement |
|---|---|
| `game-ranking-surface` | a QuotesDone Supplier Ranking surface |
| `game-tiers` | Platinum / Gold / Silver tiers |
| `game-tier-assignment-routine` | tier is computed from score by a routine |
| `game-leaderboard` | a ranked list of suppliers |
| `game-benefit-more-rfqs` | tier actually affects RFQ distribution |
| `game-benefit-preferred-status` | preferred-supplier status is conferred |
| `game-benefit-visibility` | tier affects visibility |
| `game-supplier-visible` | the ranking renders on the supplier surface |

## §21 Supplier Mobile App — 9

| id | requirement |
|---|---|
| `mob-bottom-nav` | a bottom navigation bar |
| `mob-nav-command` | Command destination |
| `mob-nav-rfqs` | RFQs destination |
| `mob-nav-products` | Products destination |
| `mob-nav-messages` | Messages destination |
| `mob-nav-ai` | AI destination |
| `mob-nav-company` | Company destination |
| `mob-responsive` | the supplier surface is usable at phone width |
| `mob-same-intelligence` | mobile carries the same modules, not a cut-down set |

## §22 Maximum UI Design Language — 13

| id | requirement |
|---|---|
| `ui-dark-theme` | dark professional theme |
| `ui-glass-panels` | glass panels |
| `ui-holographic-layers` | holographic data layers |
| `ui-3d-maps` | 3D maps |
| `ui-animated-charts` | animated charts |
| `ui-realtime-updates` | real-time updates |
| `ui-not-sidebar-tables-forms` | not a sidebar / tables / forms interface |
| `ui-ai-workspace` | an AI Workspace interface model |
| `ui-floating-windows` | floating windows |
| `ui-drag-and-drop` | drag and drop |
| `ui-command-palette` | command palette |
| `ui-context-menus` | context menus |
| `ui-interactive-graphs` | interactive graphs |

## §23 Technology Behind This UI — 15

Each named technology must be present **on the supplier surface**, not merely in `package.json`.

| id | requirement |
|---|---|
| `tech-nextjs` | Next.js |
| `tech-react` | React |
| `tech-threejs` | Three.js |
| `tech-r3f` | React Three Fiber |
| `tech-framer-motion` | Framer Motion |
| `tech-webgl` | WebGL |
| `tech-d3` | D3.js |
| `tech-3d-model-assets` | Blender models — 3D model assets exist |
| `tech-gltf` | GLTF loading |
| `tech-webgpu` | WebGPU |
| `tech-openrouter` | OpenRouter |
| `tech-vector-db` | Vector database |
| `tech-agent-framework` | Agent framework |
| `tech-document-ai` | Document AI |
| `tech-knowledge-graph` | Knowledge graph |

## §24 Final Supplier Portal Structure — 19

Each module must be **reachable from the supplier portal's navigation**. Scored as a per-item
coverage count over ONE navigation component (defect class #3), not nineteen independent greps.

`struct-ai-command-center`, `struct-digital-twin`, `struct-company-profile`,
`struct-product-intelligence`, `struct-catalog-ai`, `struct-rfq-marketplace`,
`struct-quote-builder`, `struct-negotiation-ai`, `struct-customer-projects`, `struct-documents`,
`struct-certifications`, `struct-inventory`, `struct-analytics`, `struct-market-intelligence`,
`struct-supplier-score`, `struct-ai-assistant`, `struct-messages`, `struct-finance`,
`struct-settings`

---

## TOTAL

| § | n | § | n | § | n | § | n |
|---|---|---|---|---|---|---|---|
| 1 | 9 | 7 | 14 | 13 | 9 | 19 | 7 |
| 2 | 11 | 8 | 9 | 14 | 7 | 20 | 8 |
| 3 | 9 | 9 | 9 | 15 | 7 | 21 | 9 |
| 4 | 10 | 10 | 8 | 16 | 8 | 22 | 13 |
| 5 | 12 | 11 | 9 | 17 | 8 | 23 | 15 |
| 6 | 9 | 12 | 7 | 18 | 8 | 24 | 19 |

**234**

## KNOWN OVERLAP RISKS — to be resolved in the refutation pass

Four pairs describe adjacent things and must not share evidence. Each check must target a distinct
component or routine, or the score double-counts one implementation:

1. `env-3d-scene` (§5 factory scene) / `map-globe` (§19 globe) / `ui-3d-maps` (§22 design language)
   / `tech-threejs` (§23 dependency) — four different claims about 3D. One `<Canvas>` must not
   satisfy all four.
2. `twin-product-count` (§3 twin summary) / `prod-count-products` (§7 module) — different surfaces.
3. `cc-perf-response` + `cc-perf-quality` (§4 command-center tiles) / `perf-*` (§13 health panel).
4. `cc-assistant-panel` (§4) / `emp-assistant-present` (§15) / `struct-ai-assistant` (§24 nav).
