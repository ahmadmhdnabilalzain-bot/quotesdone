# SPEC #4 — `customer portal.txt` (895 lines)
# SPEC #5 — `supplier portal.txt` (884 lines)

Audited 2026-08-11 13:50–14:25 UTC. No scorer run; verdicts are direct measurements of
`src/components/me/`, `src/components/portal/`, and production data.

| | PRESENT | PARTIAL | ABSENT | CONTRADICTED | total |
|---|---|---|---|---|---|
| Spec #4 | 24 | 27 | 11 | 0 | **62** |
| Spec #5 | 31 | 24 | 9 | 1 | **65** |

## The single fact that governs both files

```
leads         20,470      really claimed 0      approved  0
customers          0      inquiries      0      quotes    0
```

**Both portals are built. Neither has ever served its user.** 20,470 leads is a scraped directory,
not a supplier network.

**Corrected 11 Aug after first merge:** this section originally read "6 suppliers have claimed a
profile". All six are `ZZ DEMO — … (QuotesDone fixture, not a real company)` rows on
`@example.invalid` addresses, seeded 7–8 Aug and still `approval_status = 'pending'`. **Real claimed
suppliers is zero.**

Every verdict below that says PARTIAL for a screen with real code behind it says so for this reason
and no other, and that is stated once here rather than repeated 60 times.

This is not a defect in the portals. **It is a testing gap, not an unfixable one** — the flow can be
proved with a marked fixture set and torn down afterwards, which is scheduled in
`docs/sessions/NEXT_SESSION_BRIEF_2026_08_12_REHEARSAL.md`. What code cannot manufacture is *real*
demand; proving the machinery works does not need it.

---

# SPEC #4 — the customer portal

`src/components/me/CustomerPortal.tsx` — 1,031 lines. Its own comments cite "§22 module list" and
"§21", so this file was written against the spec deliberately. `MODULES` holds nine entries:

```
projects · spatial · documents · messages · approvals · orders · predict · profile · account
```

## §1–§4 Entry, digital twin, assistant, command centre (L41–L249)

| spec | claim | verdict | evidence |
|---|---|---|---|
| §1 L43–49 | "Do not start with Login Dashboard. Start with AI Procurement Workspace" | PRESENT | the portal opens on a workspace with module windows, not a login-then-dashboard |
| §1 L55–86 | greeting, active projects, RFQ count, potential savings, 3 AI recommendations | PARTIAL | the dashboard renders these slots; `projects` **0 rows**, so savings and project counts render empty |
| §2 L87–145 | Customer Digital Twin: industry, active projects, annual procurement, preferred suppliers, buying patterns, approval process, AI understanding % | PRESENT | `twin/CompanyTwin.tsx` renders exactly this profile shape. **PARTIAL on data** — `customers` 0 |
| §3 L146–199 | AI Procurement Assistant — "not a chatbot, a procurement specialist"; free text → requirement, project, quantity, documents, recommended suppliers with match % | PARTIAL | `fn_inquiry_interpret` and `run_rfq_clarify` do the extraction server-side; `twin/SupplierDiscovery.tsx` renders matches. Never run on a real request |
| §4 L200–249 | Command Center with projects / procurement / financial intelligence / supplier network panels | PRESENT | all four panels exist; supplier network reads `leads` and shows a real 20,470 |
| §4 L204 | "Not dashboards. A workspace." | PRESENT | modules open as `Dialog` floating windows, not routed pages |

## §5–§8 Projects, 3D, RFQ creation, RFQ command centre (L250–L420)

| spec | claim | verdict | evidence |
|---|---|---|---|
| §5 L252 | "Every major customer need becomes a project." | PRESENT | `projects/ProjectsModule.tsx`, `ProjectWorkspace`, `ProjectList`, `ProjectForm`; `projects` table **0 rows** |
| §6 L290–333 | 3D project visualisation; click a component → RFQs, suppliers, documents, costs, timeline | PARTIAL | `spatial/SpatialModule.tsx` + `spatial/ProjectRoom.tsx` exist and `@react-three/fiber@9.7.0` and `@react-three/drei@10.7.8` are installed. A **floor-by-floor building model with per-component status** is not built — the spatial module is a room/graph view, not a storeyed model |
| §7 L334–376 | "No manual forms" — free text → RFQ with product, quantity, spec, location, delivery, certificates | PARTIAL | `fn_inquiry_interpret` + `fn_rfq_required_check` + `fn_split_inquiry` implement it; `inquiries` 0 |
| §8 L378–419 | RFQ Command Center with a 5-dot status rail (Created→Sent→Quotes→AI Analysis→Award), responses count, best match % | PRESENT | `PIPELINE` in `OsxShell.tsx` is `sent→matched→quoted→revealed→completed`; the customer portal renders its own RFQ list with status. **The rails differ in vocabulary between the console and the spec** — a naming drift, not a defect |

## §9–§13 Discovery, comparison, visualisation, approvals, supplier CRM (L421–L623)

| spec | claim | verdict | evidence |
|---|---|---|---|
| §9 L423–464 | "Customer does not search. They ask." → filtered results with match % and reasons | PRESENT | `twin/SupplierDiscovery.tsx`; `match_suppliers`, `match_suppliers_kw`, `fn_supplier_product_match` |
| §10 L466–508 | AI comparison room with star ratings per dimension and a reasoned recommendation | PARTIAL | `quote_compare` edge function + `fn_quote_score_json` + `fn_supplier_quote_recommend` exist. `quote_comparisons` **0**, `comparison_run_v2` **0**. Note the skill's own warning: `quote_compare` returned `{ok:false}` at HTTP 200 for weeks |
| §11 L510–560 | spending intelligence, annual procurement, forecast, 4 supplier performance graphs, cost optimisation with per-category savings | PARTIAL | `intelligence/SpendingIntelligence.tsx` is the one component `CustomerPortal` imports directly by path. No spend to chart |
| §12 L562–589 | multi-stage purchase approval (Engineer→PM→Finance→CEO) | PRESENT | `approvals/ApprovalChain.tsx` + `fn_approval_policy_match` + `fn_approval_decide` + `procurement_approval_policy`/`_request` (both **0 rows**) |
| §13 L591–622 | per-supplier relationship intelligence: RFQ count, orders, avg delivery, quality, relationship score | PRESENT | `suppliers/SupplierRelationship.tsx`; `fn_customer_supplier_score` |

## §14–§21 Vault, negotiation, comms, memory, mobile, spatial, prediction, style (L624–L830)

| spec | claim | verdict | evidence |
|---|---|---|---|
| §14 L624–657 | Document Intelligence Vault storing 6 document types, answering "find warranty documents for HVAC" | PARTIAL | `documents/DocumentVault.tsx`; `fn_register_document`, `fn_doc_expiry_scan`, `fn_expiring_docs`. Semantic document Q&A is not wired to the vault |
| §15 L659–684 | AI Negotiation Assistant: market average, recommended % reduction, suggested message | PRESENT | `predict/NegotiationAssistant.tsx` + `fn_negotiation_guidance` + `fn_price_confidence` |
| §16 L686–700 | one unified centre: supplier chat, WhatsApp, email, documents, calls — all attached to project/RFQ/supplier | PARTIAL | `comms/CommunicationCenter.tsx` serves four `messages_api` actions and — per its own code comment — **states explicitly which channels the inbox does and does not carry.** Calls are not carried; `customer_calls` **0 rows**. Honest, and incomplete |
| §17 L701–713 | customer AI memory — preferences (local suppliers, 60-day terms, ISO) auto-applied to future RFQs | PARTIAL | `twin/CustomerMemory.tsx` + `trg_learn_customer_preference` + `fn_customer_preference_learn`. `customer_preference` **0 rows**; the trigger is one of the 30 no-table trigger functions and has never fired |
| §18 L715–736 | mobile app with 7-item bottom navigation | ABSENT | no mobile app in the repo. The web portal is responsive; that is not what §18 asks for |
| §19 L738–769 | Project Room; animated Supply Chain Map (Factory→Warehouse→Site with live status) | PARTIAL | `spatial/ProjectRoom.tsx` and `spatial/SupplyChainMap.tsx` both exist. No shipments to animate — `shipment_leg` **0 rows** |
| §20 L771–792 | predictive intelligence: "you will likely need electrical cables within 45 days" | PARTIAL | `predict/PredictiveIntelligence.tsx` + `fn_customer_forecast`. Prediction over zero purchase history would be invention |
| §21 L794–829 | dark mode, glass, smooth animations, AI-generated layouts, 3D models, interactive graphs, floating windows; "Not sidebar/pages/tables/forms" | PARTIAL | floating windows PRESENT (`Dialog` module windows); glass PRESENT (`bg-card/85 backdrop-blur`); **AI-generated layouts PRESENT and unusually well done** — `customer_layout` drives per-customer module order, and the code deliberately treats the server order as *a floor, not a whitelist*, appending unranked modules so a new module cannot become invisible. `customer_layout` is **0 rows**, so every customer currently gets the default order |

## §22 Final structure (L831–L870) — 18 named modules

| module | verdict | artefact |
|---|---|---|
| AI Procurement Assistant | PARTIAL | server-side (`fn_inquiry_interpret`) |
| Command Center | PRESENT | dashboard |
| Company Digital Twin | PRESENT | `twin/CompanyTwin.tsx` |
| Projects | PRESENT | `projects/` (4 files) |
| 3D Project View | PARTIAL | `spatial/` (3 files) |
| RFQ Management | PRESENT | portal RFQ list |
| Supplier Discovery | PRESENT | `twin/SupplierDiscovery.tsx` |
| Quote Comparison | PARTIAL | `quote_compare` |
| Negotiation AI | PRESENT | `predict/NegotiationAssistant.tsx` |
| Orders | PRESENT | `approvals/OrdersList.tsx` |
| Approvals | PRESENT | `approvals/ApprovalChain.tsx` |
| Documents | PRESENT | `documents/DocumentVault.tsx` |
| Communication | PRESENT | `comms/CommunicationCenter.tsx` |
| Analytics | PARTIAL | folded into Spending Intelligence |
| Spending Intelligence | PRESENT | `intelligence/SpendingIntelligence.tsx` |
| Supplier Relationships | PRESENT | `suppliers/SupplierRelationship.tsx` |
| Forecasting | PRESENT | `predict/PredictiveIntelligence.tsx` |
| Settings | PRESENT | `profile` / `account` modules |

**17 of the 18 named modules have a named component.** The one gap is that "Analytics" and "Spending
Intelligence" are served by the same component. This is the highest structural conformance of any
spec file after #2.

---

# SPEC #5 — the supplier portal

`src/components/portal/SupplierPortal.tsx` — 1,005 lines, plus **22 components** under
`src/components/portal/supplier/`. Every one is imported and reachable.

## §24 Final structure (L830–L870) — 19 named modules, mapped

| # | module | verdict | artefact |
|---|---|---|---|
| 1 | AI Command Center | PRESENT | `SupplierInsightBoard.tsx` + `SupplierCommandPalette.tsx` |
| 2 | Supplier Digital Twin | PRESENT | `SupplierTwin.tsx`, `fn_supplier_twin` |
| 3 | Company Profile | PRESENT | `SupplierSettings.tsx` |
| 4 | Product Intelligence | PRESENT | `ProductIntelligence.tsx` |
| 5 | Catalog AI | PRESENT | `SupplierCatalogUpload.tsx` |
| 6 | RFQ Marketplace | PRESENT | `SupplierOpportunities.tsx`, `fn_supplier_opportunities` |
| 7 | Quote Builder | PRESENT | `SupplierQuoteBuilder.tsx` |
| 8 | Negotiation AI | PRESENT | `SupplierNegotiation.tsx`, `fn_supplier_negotiation` |
| 9 | Customer Projects | PRESENT | `CollaborationWorkspace.tsx` |
| 10 | Documents | PRESENT | `SupplierDocumentImpact.tsx`, `fn_supplier_document_impact` |
| 11 | Certifications | PRESENT | `SupplierCertifications.tsx`, `fn_supplier_certifications` |
| 12 | Inventory | PRESENT | `SupplierInventory.tsx` |
| 13 | Analytics | PRESENT | `SupplierInsightBoard.tsx` |
| 14 | Market Intelligence | PRESENT | `MarketIntelligence.tsx`, `fn_supplier_market`, `fn_graph_supplier_market` |
| 15 | Supplier Score | PRESENT | `SupplierTier.tsx`, `fn_supplier_tier`, `supplier_score` **20,470 rows** |
| 16 | AI Assistant | PRESENT | `SupplierAdvisor.tsx`, `fn_supplier_advisor` |
| 17 | Messages | PARTIAL | no supplier-side inbox component; `messages_api` exists |
| 18 | Finance | PARTIAL | `fn_supplier_subscription`, `supplier_dues` **0 rows** |
| 19 | Settings | PRESENT | `SupplierSettings.tsx` |

**17 of 19 PRESENT as named components.** Structurally this is the most completely built spec file
in the contract.

## The section-by-section verdicts that differ from "built but unused"

| spec | claim | verdict | evidence |
|---|---|---|---|
| §1 L35–64 | landing screen with animated supply network, moving connections, world map | PRESENT | `SupplierEntryHero.tsx`, `SupplierNetworkMap.tsx`, `NodeField.tsx` |
| §2 L65–103 | AI onboarding conversation replacing 20 forms; AI extracts company/category/type/location/capability/markets | PRESENT | `SupplierOnboarding.tsx` + `fn_onboarding_gate` + `org_onboarding` 16 rows. **This one has actually run** |
| §3 L105–154 | Digital Twin: strength %, capabilities, product count, certifications, production capacity, best opportunities, risk level | PARTIAL | `SupplierTwin.tsx` renders all seven. **`supplier_capabilities` is 0 rows** and production capacity has no column — two of the seven fields have no source |
| §5 L199–246 | 3D factory environment; click warehouse → available/reserved/production counts | PARTIAL | `SupplierEnvironment.tsx` + `RendererCapability.tsx` (a capability probe before rendering — good practice). Inventory counts read `supplier_product` (**7 rows**) |
| §6 L280–297 | capability map as a visual graph | PRESENT | `SupplierKnowledgeGraph.tsx`, `fn_supplier_knowledge_graph` |
| §7 L298–339 | **"Catalog.pdf 500 pages → 245 products, 18 categories, 12,500 attributes, searchable: YES"** | **CONTRADICTED** | the pipeline exists (`SupplierCatalogUpload.tsx`, `fn_supplier_products`, `supplier_catalog`/`supplier_product`/`supplier_product_variant`). Actual contents: **2 catalogs, 7 products, 4 variants.** The screen is built to show a number in the hundreds and the store holds seven. Marked CONTRADICTED rather than PARTIAL because §7 states a specific transformation ratio as the requirement, and the implemented pipeline has never demonstrated it at any scale |
| §8 L341–383 | AI product cards with capacity, efficiency, certifications, availability, compatible projects, match % | PARTIAL | rendered by `ProductIntelligence.tsx` over 7 products |
| §9–§10 L385–453 | RFQ opportunities ranked by AI match with reasons | PRESENT | `SupplierOpportunities.tsx`, `fn_supplier_opportunities`, `fn_match_capability`. `supplier_opportunity_score` **0 rows** |
| §11 L455–490 | AI quote builder: recommended price, market position, delivery, risk, warranty | PRESENT | `SupplierQuoteBuilder.tsx`, `fn_quote_coach`, `fn_price_confidence`, `fn_quote_structured_score` |
| §12 L492–515 | negotiation assistant computing current margin and possible reduction | PRESENT | `SupplierNegotiation.tsx`, `fn_supplier_negotiation`, `margin_rate`, `supplier_negotiation_policy` (1 row) |
| §13 L517–546 | living performance score across quality / delivery / response / pricing | PRESENT | `supplier_score` **20,470 rows**, `fn_supplier_quality`, `qd_recompute_response`, `recompute_supplier_rating`, `supplier_kpi_snapshots` 34 |
| §14 L548–575 | market intelligence: demand trend, most requested, average market price, competitor count | PARTIAL | `MarketIntelligence.tsx` + `fn_supplier_market`. Demand trend needs an inquiry stream — 0 rows |
| §15 L577–605 | "Why am I losing RFQs?" → loss reason breakdown + recommendation | PARTIAL | `SupplierAdvisor.tsx` + `fn_supplier_advisor`. No RFQ has been lost because none has been run |
| §16 L607–635 | documents alive: status, expiry, "used for 32 RFQs", impact | PRESENT | `SupplierDocumentImpact.tsx` + `fn_supplier_document_impact` + `fn_check_licence_expiry` + `fn_doc_expiry_scan` |
| §17 L637–660 | risk protection monitoring certificate expiry, complaints, response delays, performance drops | PRESENT | `fn_supplier_risk_monitor`, `fn_supplier_exception_open/close/sweep`, `fn_check_licence_activity` |
| §18 L662–692 | per-customer collaboration workspace with files, messages, timeline | PRESENT | `CollaborationWorkspace.tsx` |
| §19 L694–720 | 3D globe showing suppliers, demand, projects, shipments | PARTIAL | `SupplierNetworkMap.tsx` + `fn_supplier_network_map`. Suppliers real; demand, projects and shipments all empty |
| §20 L721–747 | gamified ranking Platinum/Gold/Silver with benefits | PRESENT | `SupplierTier.tsx`, `fn_supplier_tier`, `fn_assign_founding_rank(s)` |
| §21 L748–768 | mobile app, 6-item bottom nav | ABSENT | no mobile app |
| §22 L770–804 | dark theme, glass, holographic layers, 3D maps, animated charts, real-time; "Not sidebar/tables/forms"; floating windows, drag & drop, command palette, context menus | PARTIAL | command palette PRESENT (`SupplierCommandPalette.tsx`); glass and dark PRESENT; **drag & drop ABSENT**; **real-time updates ABSENT** (no realtime subscription anywhere in `src/`) |

## §23 Declared technology stack (L805–L829) — measured against `package.json`

| declared | verdict | installed |
|---|---|---|
| Next.js | PRESENT | `next@16.2.11` |
| React | PRESENT | — |
| Three.js / React Three Fiber | PRESENT | `@react-three/fiber@^9.7.0`, `@react-three/drei@^10.7.8` |
| WebGL | PRESENT | via R3F; `RendererCapability.tsx` probes for support before rendering |
| Framer Motion | **ABSENT** | not installed. `src/components/motion/` implements motion directly |
| D3.js | PARTIAL | only `@types/d3-scale`; charts are hand-rolled SVG (`AreaSpark`, `HBars`, `Funnel`) |
| Blender models / GLTF | ABSENT | no `.gltf`/`.glb` assets in the repo |
| WebGPU | ABSENT | not used |
| OpenRouter | PRESENT | `_shared/llm.ts` |
| Vector Database | PRESENT | pgvector, `kb_chunks` 120,530 |
| Agent Framework | PRESENT | `org_agents` + `fn_ai_route` |
| Document AI | PARTIAL | `fn_register_document`, `fn_doc_diff`; no OCR |
| Knowledge Graph | PRESENT | `graph_nodes` 829, `fn_graph_rebuild` |

**A declared dependency that is not installed is a claim the contract makes about the build, and
Framer Motion, GLTF and WebGPU are three of them.** The substitutions (hand-rolled motion, hand-rolled
SVG charts) are defensible engineering — they are recorded here because the file names the stack, and
"we used something else" is a PARTIAL, not a silent PRESENT.
