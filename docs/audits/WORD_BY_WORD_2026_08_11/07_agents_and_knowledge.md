# SPEC #7 — `quotesdone agents and knowledge.txt` (1,498 lines)

**The file that never had a scorer.** Audited 2026-08-11 12:22–13:10 UTC against production
`htdblwldjkcgjvmqkbeh`. No verdict below is taken from any scorer. Every PRESENT names an artefact.

| verdict | count |
|---|---|
| PRESENT | 92 |
| PARTIAL | 71 |
| ABSENT | 63 |
| CONTRADICTED | 6 |
| **total claims** | **232** |

---

## §1 — The 22 departments (L1–L205)

The spec names 17 numbered departments plus 5 unnumbered. Production has **25 active**.
The brief warned not to read "25 vs 22" as "three missing". It is not: **all 22 exist, and 3 are extra.**

| # | spec line | claim (verbatim) | verdict | evidence |
|---|---|---|---|---|
| 1 | 2 | CEO Office AI | PRESENT | `org_departments.exec` "Executive Office", 4 agents (`ceo`,`cpo`,`brief`,`strategy_director`) |
| 2 | 7 | Supplier Success Department | PRESENT | `supplier_success`, 3 agents |
| 3 | 19 | Customer Success Department | PRESENT | `customer_success`, 5 agents |
| 4 | 31 | RFQ / Inquiry Intelligence Department | PRESENT | `rfq_intelligence`, 3 agents |
| 5 | 47 | Marketplace Operations | PRESENT | `procurement` "Marketplace & Procurement", 8 agents |
| 6 | 59 | Sales Department | PRESENT | `sales` "Sales & CRM", 3 agents |
| 7 | 66 | Marketing Department | PRESENT | `marketing`, 7 rows / 6 active |
| 8 | 75 | Finance Department | PRESENT | `finance`, 5 agents |
| 9 | 84 | Legal & Compliance | PRESENT | `legal`, 4 agents |
| 10 | 93 | HR Department | PRESENT | `hr` "HR & People Operations", 4 agents |
| 11 | 100 | Administration & Operations | **CONTRADICTED** | the row named "Administration & Operations" has `dept_key = 'knowledge'`. Its 4 agents are `docs`, `ops_director`, `process_improvement_mgr`, `project_coordinator`. A separate `knowledge_eng` department also exists. The key and the name describe two different departments — any code routing on `dept_key='knowledge'` reaches Admin & Ops, and any human reading `dept_key` believes it reached Knowledge. |
| 12 | 108 | Engineering Department | PRESENT | `engineering`, 4 agents |
| 13 | 115 | AI Department | PRESENT | `ai_dept`, 4 agents |
| 14 | 129 | IT & Cybersecurity | PRESENT | `it`, 3 agents |
| 15 | 138 | Data & Analytics | PRESENT | `analytics`, 3 agents |
| 16 | 147 | QA & Testing | PRESENT | `qa`, 3 agents |
| 17 | 154 | Business Development | PRESENT | `bizdev`, 3 agents |
| 18 | 160 | Supplier Knowledge Department | PRESENT | `supplier_knowledge`, 3 agents |
| 19 | 174 | Document Intelligence Department | PRESENT | `doc_intelligence`, 3 agents |
| 20 | 186 | Notification & Communication Department | PRESENT | `comms`, 3 agents |
| 21 | 193 | Payment Department | PRESENT | `payments`, 2 agents (`payments_manager`, `billing_specialist`) |
| 22 | 199 | Trust & Safety | PRESENT | `trust_safety`, 3 agents |

**Three departments exist that the contract does not name:** `evolution` (Evolution),
`intelligence` (Intelligence), `knowledge_eng` (Knowledge Engineering). 22 + 3 = 25. Reported as a
finding, not a defect — the founder may have added them deliberately, but they are outside spec #7.

### The sub-responsibilities inside each department (L11–L205)

The spec lists 108 named sub-responsibilities under the 22 departments (e.g. "Supplier Offboarding",
"Escrow (if introduced)", "Fleet management"). Sampled verdicts on the ones with no artefact:

| spec line | claim | verdict | evidence |
|---|---|---|---|
| 18 | Supplier Offboarding | ABSENT | no routine, no status; `fn_supplier_exception_*` suspends but never offboards |
| 78 | VAT | PARTIAL | `fn_gl_*` posts entries; no VAT return, no FTA filing artefact |
| 79 | Corporate Tax | ABSENT | no routine names corporate tax |
| 80 | Payroll | ABSENT | no payroll table or routine |
| 97 | Training | PARTIAL | `knowledge_exam_questions` 546 / `knowledge_exam_results` 546 — an exam exists; no training programme |
| 98 | Leave management | PARTIAL | `org_agents.available`, `unavailable_until`, `unavailable_reason` columns exist; no request/approval routine |
| 103 | Office management | ABSENT | not modelled |
| 106 | Company assets | PRESENT | `fa_assets`, `fn_fa_acquire`, `fn_fa_depreciate`, `fn_fa_dispose` — **but `fa_assets` is empty (0 rows)** |
| 110 | Frontend | PRESENT | `src/`, Next.js app |
| 111 | Mobile | ABSENT | no mobile app in repo |
| 133 | Identity Management | PRESENT | `fn_authorize`, `org_authority` 518 rows, `fn_control_mode_*` |
| 134 | Disaster Recovery | PARTIAL | `fn_backup_watch`, `fn_phase1_rollback_rehearse`; no DR plan document, no regional failover — see §Additional Components |
| 196 | Refunds | PRESENT | `fn_refund_request/decide/settle/state`, `refunds_api` edge fn — **`refunds` table empty (0 rows)** |
| 197 | Escrow (if introduced) | ABSENT | conditional in the contract; not introduced |
| 198 | Commission Management | ABSENT | `reveal_fee` exists; no commission model |
| 201 | Spam Prevention | PRESENT | `block_disposable_signup`, `is_disposable_email`, `fn_rate_limit` |
| 202 | Fake Suppliers | PRESENT | `fn_fraud_scan`, `fn_supplier_licence_gate` |
| 203 | Fake RFQs | PARTIAL | `recent_duplicate_inquiry`, `trg_block_banned_inquiry` — never exercised, `inquiries` is 0 rows |

---

## §2 — The 20 knowledge profiles (L208–L512)

The spec gives 20 profiles, each with an explicit "Knowledge Required" list — **283 named knowledge
items in total.**

### The contract's own gap — reported, not papered over

The spec defines **22 departments** but only **20 knowledge profiles**.
**Notification & Communication (L186) and Payment (L193) have a department and no knowledge
profile.** This is a defect in the contract itself. It is reported here rather than silently
invented, per the brief. The two departments exist in production (`comms`, `payments`) with 3 and 2
agents; those 5 employees are staffed against no stated knowledge requirement.

Note also that the profile numbering shifts: the department list is ordered CEO→BizDev with 5
unnumbered, while the knowledge list is ordered CEO, **RFQ Intelligence (2)**, Supplier Success (3),
Customer Success (4) … so profile numbers do **not** correspond to department numbers. Any code
joining them by ordinal is wrong.

| profile | spec lines | verdict | evidence |
|---|---|---|---|
| 1. CEO Office AI (15 items) | 211–227 | PARTIAL | `employee_knowledge` 900 rows and `ops_knowledge` 3,959 rows carry company/strategy material; "Competitor analysis" and "Market intelligence" resolve only to `market_intel` — **0 rows** |
| 2. RFQ Intelligence (18 items) | 228–248 | PARTIAL | taxonomy/category knowledge is real (`kb_chunks` 120,530; `knowledge_domain` 107); "BOQs", "Technical drawings", "Drawing interpretation" have routines (`fn_scope_*`) but **no BOQ or drawing has ever been processed** — `inquiries` 0 rows |
| 3. Supplier Success (14) | 249–264 | PRESENT | `leads` 20,470, `fn_supplier_score_refresh`, `fn_supplier_tier`, `fn_supplier_certifications`, `fn_supplier_licence_gate` |
| 4. Customer Success (12) | 265–278 | ABSENT | every backing table is empty: `customers` 0, `customer_preference` 0, `customer_score` 0, `feedback` 0, `reviews` 0. `fn_customer_*` (11 routines) exist and can never return a row today |
| 5. Marketplace Operations (13) | 279–293 | PARTIAL | ranking and matching exist (`match_suppliers`, `fn_supplier_quote_recommend`, `fn_marketplace_analytics`); `quotes` 0, `inquiry_matches` 0 |
| 6. Sales (13) | 294–308 | PARTIAL | `fn_category_sales`, `crm_notes` **0 rows**, `fn_customer_forecast` |
| 7. Marketing (16) | 309–326 | PRESENT | `fn_marketing_ai`, `fn_marketing_studio`, `fn_brand_scan`, `fn_marketing_blog_publish`, `content_drafts` (0 rows) |
| 8. Finance (16) | 327–344 | PARTIAL | GL is real (`fn_gl_entry/post/reverse/net_income`); "UAE VAT", "UAE Corporate Tax", "Payroll", "ERP systems" have no artefact |
| 9. Legal (14) | 345–360 | PARTIAL | `fn_legal_ai`, `fn_terms_version`, `fn_terms_integrity`, `fn_scope_clauses`; "UAE Commercial Law", "Labour Law", "Dispute resolution" appear as `kb_chunks` text only, with no routine that applies them |
| 10. HR (12) | 361–374 | PARTIAL | `hr` department with 4 agents and `fn_improvement_plan_refresh`; no payroll, no benefits, no handbook artefact |
| 11. Admin & Operations (13) | 375–389 | PARTIAL | `os_runbooks` 106, `fn_sop_update`, `fn_doc_control`; "Travel management", "Fleet management", "Inventory" → `inv_items` and `inv_stock_moves` **0 rows** |
| 12. Engineering (14) | 390–405 | PRESENT | repo itself, `fn_edge_health_scan`, `run_auto_deploy`, `.github/workflows` |
| 13. AI Department (13) | 406–420 | PRESENT | `fn_ai_route`, `fn_select_model`, `fn_model_benchmark`, `fn_eval_run`, `fn_kb_retrieve`, `kb_chunks` embeddings, `fn_require_grounding` |
| 14. IT & Cybersecurity (14) | 421–436 | PARTIAL | `fn_security_audit`, `fn_security_scan`, `fn_secops_test`, `fn_pdpl_*`; "SIEM", "Endpoint security", "Firewalls", "ISO 27001" have no artefact |
| 15. Data & Analytics (12) | 437–450 | PRESENT | `fn_bi_snapshot`, `fn_data_metrics`, `fn_kpi_scoreboard`, `fn_report_generate`, `fn_report_drilldown` |
| 16. QA & Testing (10) | 451–462 | PRESENT | `fn_p2c1_*` suite (17 routines), `fn_eval_run`, `fn_smoke`, `fn_run_vt`, `scripts/checks/` |
| 17. Business Development (9) | 463–473 | PARTIAL | `bd`, `partnerships_mgr`, `gov_relations_mgr` staffed; `fn_opportunity_scan` exists; no partnership record table |
| 18. Supplier Knowledge (11) | 474–486 | PRESENT | `fn_category_knowledge`, `fn_taxonomy`-side (`category_keyword`, `kb_category_aliases`), `fn_scan_new_supplier_categories` |
| 19. Document Intelligence (12) | 487–500 | PARTIAL | `fn_register_document`, `fn_doc_diff`, `fn_doc_history`, `fn_document_controller`; "CAD drawings", "BIM models", "OCR", "Shop drawings" — **no routine and no edge function names any of them**; `drawing_redaction_runs` 0 rows |
| 20. Trust & Safety (10) | 501–512 | PRESENT | `fn_fraud_scan`, `fn_fraud_resolve`, `fn_flag`, `chat_violations` (0 rows), `mask_contacts` |

**Verdict on the block:** the knowledge *material* is real and large (120,530 `kb_chunks`, 3,959
`ops_knowledge`, 900 `employee_knowledge`). What is missing is the *mapping*: there is no table that
says "department X requires knowledge items Y" for these 283 items. `employee_knowledge_standard`
holds **12 rows** and `knowledge_module_standard` **14** — neither is a 20-profile × 283-item map.
So the profiles are PARTIAL by construction: the knowledge exists, the requirement is not recorded,
and nothing can report which of the 283 items a department is missing.

---

## §3 — Common knowledge every department should share (L513–L533)

17 named items. The spec's instruction is that **every** department has access.

| verdict | detail |
|---|---|
| PARTIAL | `agent_knowledge.layer='company'` holds **46 rows against exactly 1 agent_key** (`_global`). So a shared company layer exists as a concept and is populated for one pseudo-identity. There is no join proving any of the 94 employees reads it, and `fn_agent_context` is defined twice with different signatures (see the duplicate register). |

Items with no artefact at all: "Employee directory and roles" (PRESENT — `org_agents`),
"Templates (emails, contracts, reports)" (PARTIAL — `fn_report_skeleton` only),
"Company terminology and glossary" (ABSENT), "Escalation matrix and responsibility ownership"
(PRESENT — `org_authority` 518 rows + `fn_should_escalate`), "Integrations (ERP, CRM, payment
gateway, etc.)" (ABSENT — no ERP, no CRM integration exists).

---

## §4 — The layered knowledge architecture (L534–L543) — **CONTRADICTED**

> "Don't create 20 isolated knowledge bases. Instead, build a layered knowledge architecture:
> Layer 1 – Company Core … Layer 2 – Department … Layer 3 – Live Business Data … Layer 4 – External"

`agent_knowledge.layer` **does** have exactly four values, which is why a shape check would pass it.
They are not the four the contract names:

| spec layer | production layer | rows | distinct agent_keys |
|---|---|---|---|
| Layer 1 Company Core | `company` | 46 | 1 |
| Layer 2 Department | — **ABSENT** | — | — |
| Layer 3 Live Business Data | — **ABSENT** | — | — |
| Layer 4 External | — **ABSENT** | — | — |
| (not in spec) | `profession` | 1,959 | 234 |
| (not in spec) | `experience` | 33 | 12 |
| (not in spec) | `state` | 2 | 1 |

**CONTRADICTED, and the count is the trap.** "4 layers exist" is true and meaningless. 96% of the
rows sit in a `profession` layer the contract never names, keyed by 234 distinct `agent_key`s
against an org of 94 employees — **141 of those keys resolve to no employee** (they are `cat:*`
category keys and `_global`). The contract's explicit instruction was to avoid isolated per-domain
knowledge bases; `profession` + 234 keys is precisely a per-domain knowledge base per category.

---

## §5 — QuotesDone OS Knowledge Requirements, the 20 domains (L545–L813)

| # | domain | spec lines | verdict | evidence |
|---|---|---|---|---|
| 1 | Company Knowledge | 546–562 | PRESENT | `fn_company_facts_sync`, `fn_company_state`, `fn_company_brief`, `os_department` 25 |
| 2 | Platform Knowledge | 563–577 | PRESENT | `fn_os_catalog_list/get`, `fn_os_nav`, `fn_os_settings_list`, `os_knowledge_domain` 445 |
| 3 | User Knowledge | 578–591 | PARTIAL | `fn_authorize`, `fn_role_of`, `org_authority`; the spec names 8 user types — customers, suppliers, employees, administrators, sales, finance, management, support. `customers` is **0 rows**, so 1 of 8 is unmodelled in data |
| 4 | Department Knowledge | 593–609 | PARTIAL | `fn_ops_department_context`, `department_objective` 66, `department_budget` 25. "understand how work flows between them" → `fn_org_task_cross_os_guard` exists; no inter-department flow map |
| 5 | AI Agent Knowledge | 611–627 | PARTIAL | 9 sub-claims. Responsibilities PRESENT (`org_agents.responsibilities`); Skills/Limitations ABSENT (no column, no table); Available tools PRESENT (`org_action_executor` 56, `fn_tool_readiness`); Memory PRESENT (`org_memory` 624, `fn_agent_institutional_memory`); Knowledge base PRESENT (`agent_knowledge`); APIs PARTIAL; Escalation rules PRESENT (`fn_should_escalate`); Performance metrics PRESENT (`ai_quality_snapshots` 1,115). "The OS should decide which agent should handle a request" → `fn_ai_route`, `fn_kb_route_decide` PRESENT |
| 6 | Workflow Knowledge | 629–645 | PARTIAL | see §6 below — 11 named, 4 covered |
| 7 | Permission Knowledge | 646–657 | PRESENT | `org_authority` 518, `fn_dept_authority`, `fn_authority_rank`, `fn_approval_policy_match`, `fn_org_authority_guard` |
| 8 | Document Knowledge | 658–673 | PARTIAL | 9 document types named. BOQ/Drawings/RFI have routines but zero instances; Invoices `ap_bills` **0 rows**; Quotations `quotes` **0**; Purchase Orders `po_orders` **0** |
| 9 | Communication Knowledge | 674–684 | PARTIAL | 7 channels named. Email PRESENT (`notifications`), WhatsApp PRESENT (`fn_wa_fanout`), SMS PRESENT (`notify_new_quote_sms`), Push ABSENT, Phone ABSENT, Internal Chat PARTIAL (`chat_threads` **0 rows**), Live Chat ABSENT |
| 10 | Supplier Knowledge | 685–697 | PRESENT | `leads` 20,470, `fn_supplier_products`, `fn_supplier_certifications`, `fn_supplier_tier`, `recompute_supplier_rating` |
| 11 | Customer Knowledge | 698–708 | ABSENT | all seven sub-items resolve to empty tables: `customers` 0, `customer_calls` 0, `crm_notes` 0, `messages` 0 |
| 12 | Marketplace Knowledge | 709–718 | PARTIAL | matching + ranking routines exist; `quotes` 0, `quote_comparisons` 0 |
| 13 | Financial Knowledge | 719–730 | PARTIAL | GL, budgets, AP routines exist; `transactions` 0, `refunds` 0, `reveal_invoices` 0, `budgets` 0, `budget_lines` 0 |
| 14 | Analytics Knowledge | 731–743 | PARTIAL | `fn_kpi_scoreboard`, `fn_goal_attainment`; of the 7 named KPIs, RFQs/Quotes/Revenue/Conversion are all computed over empty tables |
| 15 | Security Knowledge | 744–754 | PRESENT | `fn_security_audit`, `security_audit` immutable trigger, `fn_control_mode_session_mfa_is_real`, `fn_pdpl_*` |
| 16 | Integration Knowledge | 755–768 | PARTIAL | 8 systems named. AI Providers PRESENT (OpenRouter), Email PRESENT (Resend), WhatsApp PRESENT (Twilio), Cloud Storage PRESENT (Dropbox — `fn_dropbox_list`, `fn_enable_dropbox_sync`), Payment Gateway PARTIAL (Stripe — `stripe_events` **0 rows**), CRM ABSENT, ERP ABSENT, Accounting ABSENT |
| 17 | AI Knowledge | 769–780 | PRESENT | `fn_ai_route`, `fn_agent_context`, `fn_promote_memory`, `fn_tool_readiness`, `fn_should_escalate`, `fn_ai_gate`; "Confidence scoring" PRESENT since the 11 Aug `trg_action_gate` fix (`decision_log.confidence`) |
| 18 | Automation Knowledge | 781–793 | PRESENT | `fn_os_automation_list/run/reschedule/set_active` over 185 cron jobs (166 active) |
| 19 | Reporting Knowledge | 794–803 | PARTIAL | `fn_report_generate`, `fn_monthly_report`, `fn_quarterly_report`, `fn_period_report`, `fn_board_report`. "Customer reports" cannot be produced — no customers |
| 20 | Learning Knowledge | 804–813 | PARTIAL | `fn_learning_loop_sweep`, `fn_task_lesson`, `fn_knowledge_decay`, `fn_scan_new_supplier_categories`, `fn_customer_preference_learn` (over an empty table) |

---

## §6 — The 11 named workflows (L629–L645)

Production has a real workflow engine: `workflow` 14 rows, `workflow_step` 117, `workflow_run` 198,
`workflow_step_run` 2,582, driven by `fn_workflow_start`, `fn_workflow_step_done`,
`fn_workflow_step_sweep`, `fn_workflow_start_due`. The engine is PRESENT. The **coverage** is not.

| # | spec workflow | verdict | evidence |
|---|---|---|---|
| 1 | Customer Registration | ABSENT | no `workflow` row; `customers` 0 rows |
| 2 | Supplier Registration | PRESENT | `supplier_onboarding`, 7 steps — **0 runs** |
| 3 | RFQ Creation | PRESENT | `rfq_handling`, trigger `inquiry.created`, 12 steps — **0 runs** |
| 4 | Supplier Matching | PARTIAL | a step inside `rfq_handling`, not a workflow; `match_suppliers` routine exists |
| 5 | Quote Collection | PARTIAL | a step inside `rfq_handling` |
| 6 | Quote Comparison | PARTIAL | a step inside `rfq_handling`; `fn_quote_score_json`, `comparison_run_v2` **0 rows** |
| 7 | Award Process | PARTIAL | "recommends and closes" inside `rfq_handling`; `fn_approval_raise_on_award` exists |
| 8 | Payment | ABSENT | no `workflow` row. `invoice_approval` is accounts payable, not customer payment |
| 9 | Complaint | ABSENT | no `workflow` row, no complaint table |
| 10 | Refund | PARTIAL | 8 routines (`fn_refund_request/decide/settle/state/amount_resolve/quarantine/transition_allowed`) and a `refunds_api` edge function, but **no `workflow` row** and `refunds` is 0 rows |
| 11 | Supplier Suspension | PARTIAL | `fn_supplier_exception_open/close/sweep`, `fn_ban_overdue_dues`; no `workflow` row |

**And the engine's own emptiness is the finding: 9 of 14 workflows have never run.**
Only `employee_task` (123 runs), `metric_lifecycle` (30), `strategic_review` (19),
`improvement_lifecycle` (15) and `knowledge_lifecycle` (11) have any history. Every
customer-facing workflow — `rfq_handling`, `supplier_onboarding`, `lead_to_customer`,
`invoice_approval`, `campaign_publishing`, `contract_review`, `incident_response`,
`change_deployment`, `budget_cycle` — has **0 runs**. The company's internal loops run; the
business's loops have never been exercised once.

---

## §7 — System-level capabilities (L814–L830)

Ten capabilities the brief did not extract. Verdicts:

| capability | spec line | verdict | evidence |
|---|---|---|---|
| Identity & Access Management | 818 | PARTIAL | `fn_authorize`, `org_authority`, `fn_control_mode_*`, Supabase auth. **SSO is ABSENT** |
| Agent Orchestration | 819 | PRESENT | `fn_ai_route`, `fn_agent_handoff_inbox`, `fn_group_dispatch_report`, `fn_should_escalate` |
| Workflow Engine | 820 | PRESENT | `workflow`/`workflow_step`/`workflow_run` + 4 routines (coverage separately PARTIAL, §6) |
| Knowledge Management | 821 | PRESENT | `kb_revisions` 9,355, `fn_kb_submit_revision`, `fn_kb_approve`, `fn_kb_gov_approve`, `fn_knowledge_provenance_stamp` — versioned, approval-gated and source-tracked, exactly as written |
| Document Intelligence | 822 | PARTIAL | parse/classify/compare exist as routines; **validate and extract have never run on a real document** |
| Observability | 823 | PARTIAL | see §Additional Components below |
| Integration Layer | 824 | PARTIAL | 5 of 8 named systems connected; ERP, CRM, accounting ABSENT |
| Security & Compliance | 825 | PRESENT | `fn_security_audit`, `fn_pdpl_export/redact/erase_plan`, `app_secrets` + `fn_protect_app_secret`, immutable audit triggers |
| Notification Engine | 826 | PARTIAL | email/SMS/WhatsApp PRESENT; push and in-app messaging ABSENT |
| Search & Retrieval | 827 | PRESENT | `fn_kb_retrieve`, `kb_match`, `fn_memory_search`, `fn_os_search`, pgvector over 120,530 chunks |
| One-sentence definition | 830 | PARTIAL | "automates the complete RFQ and supplier lifecycle from inquiry to award" — the supplier half is real (20,470 leads); the inquiry→award half has **never executed end to end** |

---

## §8 — The 22 interactive capabilities (L832–L1299)

The OS console is **two files**: `src/components/osx/OsxShell.tsx` (3,347 lines) and
`ControlMode.tsx`. It registers **31 modules** and has a real floating-window layer
(`FloatingWindow`, `WindowLayer`, `bringToTop`, move/size/snap/min/max).

| # | capability | spec lines | verdict | evidence |
|---|---|---|---|---|
| 1 | AI Command Center | 833–847 | PRESENT | `Console()` module + `fn_os_command`; the spec's four example questions are natural-language and the console routes them |
| 2 | Multi-Agent Workspace | 849–885 | **ABSENT** | `AgentsApp`/`AgentDrawer` show agents one at a time. Nothing renders a collaboration. The spec's chain (BOQ → RFQ → Document → Supplier → Legal → Finance → Marketplace → RFQ) exists nowhere as a runnable sequence — see §Contradictions |
| 3 | Smart Windows | 887–917 | PRESENT | `FloatingWindow` + `WindowLayer` + `popOut()`; movable, resizable, snappable, z-ordered |
| 4 | AI Side Panel | 919–932 | ABSENT | no side-panel component; no per-page context assistant |
| 5 | Universal Search | 934–951 | PARTIAL | `fn_os_search` exists and a command palette (`CommandItem`) navigates modules. The spec names 10 searchable types; the palette searches **module names only** |
| 6 | Interactive Knowledge Graph | 953–983 | PARTIAL | `graph_nodes` 829 / 644 edges after the 10 Aug rebuild, `company_os` module renders it. Of the spec's 7-hop chain (Supplier→Products→RFQs→Customers→Contracts→Invoices→Projects), **5 classes are empty tables** |
| 7 | Interactive Timeline | 985–999 | PARTIAL | `company_snapshot` holds 14 days; `ActivityPanel` shows per-entity activity. The spec's supplier timeline (Registered→Verified→Quote→Won→Payment→Complaint→Rating) cannot be drawn — no quotes, no payments, no complaints |
| 8 | Interactive Documents | 1001–1012 | ABSENT | no document viewer, no highlighting, no revision comparison in the UI. `fn_doc_diff` exists server-side with no surface |
| 9 | Drawing Intelligence | 1013–1025 | **ABSENT** | no routine, no edge function and no component names rooms, doors, windows, dimensions or CAD. The single strongest ABSENT in the file |
| 10 | Live Collaboration | 1026–1038 | ABSENT | no realtime channel, no presence |
| 11 | Interactive Dashboard | 1040–1066 | PRESENT | `StatTile`/`HBars`/`Funnel` all take `onClick`/`onBar`/`onStage`; `RecordDrawer` + `FK_ENTITY` map drills from any foreign key to its entity. The drill-down mechanism is real and generic |
| 12 | Drag & Drop Workspace | 1068–1081 | ABSENT | one `draggable` occurrence, no drop target, no "OS determines what to do" |
| 13 | Context Memory | 1083–1109 | PARTIAL | `fn_os_memory`, `org_memory` 624 rows, `fn_agent_context`. The OS remembers *company* history; it does not remember *the user's current window stack* |
| 14 | AI Suggestions | 1111–1122 | PARTIAL | `agent_actions` surfaces pending approvals and `fn_officer_recs` produces recommendations, but of the spec's 6 suggestion types only "Risks" has a producer. "Duplicate RFQs", "Expiring contracts", "Incomplete quotations" have routines over empty tables; "Missing documents" → `fn_expiring_docs` PRESENT |
| 15 | Visual Workflow Builder | 1123–1153 | ABSENT | `Automation` panel lists cron jobs as rows. No visual builder, no progress rendering of the 7-stage chain |
| 16 | Floating AI Tools | 1155–1167 | ABSENT | no text-selection toolbar |
| 17 | Natural Language Navigation | 1168–1179 | PARTIAL | `fn_os_nav` exists; the palette is keyword-matched over module labels, not intent-parsed |
| 18 | Workspace Snapshots | 1180–1197 | ABSENT | window state is not persisted; `company_snapshot` is a business snapshot, not a workspace one |
| 19 | Real-Time Notifications | 1199–1229 | PARTIAL | `NotificationsBell` with a pulse and `fn_ws_notifications`. Cards are not interactive — no AI summary, no suggested actions, no approve/reply/assign from the card |
| 20 | Voice Mode | 1231–1239 | PARTIAL | `IntakeAudio()` module exists and is wired to audio intake. It transcribes an inquiry; it does not carry out the spec's multi-clause instruction ("create an RFQ … attach this drawing … send to qualified suppliers in Dubai … remind me if nobody replies in 24h") |
| 21 | Adaptive Workspace | 1241–1264 | PARTIAL | `MODULES` is a fixed 31-item list rendered for the founder. The supplier and customer portals are separate apps, which satisfies "different workspaces" by having different products, not one adaptive OS |
| 22 | AI Mission Control | 1266–1299 | PARTIAL | `AgentStatus` + `AgentsApp` + `AgentDrawer` show agents and open a drawer. Of the 9 things the spec says clicking an agent must open — tasks, queue, confidence, reasoning, knowledge bases, tools, metrics, and the ability to **intervene / pause / reroute / hand off** — the intervention controls are ABSENT |

**Block score: 3 PRESENT, 11 PARTIAL, 8 ABSENT of 22.**

---

## §9 — Vision statement (L1300–L1307)

> "I wouldn't build it as a website with AI. I'd build it as an AI operating system where the
> interface is a dynamic workspace rather than a collection of pages."

**PARTIAL.** The floating-window layer, the 31-module dock and the command palette are genuinely
OS-shaped, not page-shaped. But `MODULES` is a static array of 31 pages rendered inside windows, and
`renderModule()` switches on a string id. The window manager is real; the objects inside the windows
are still pages. Per the brief, prose gets a verdict — this is the founder's requirement, and it is
half met.

---

## §10 — Decision Engine (L1311–L1326)

| spec line | decision the OS must make | verdict | evidence |
|---|---|---|---|
| 1317 | Which supplier receives this RFQ? | PARTIAL | `match_suppliers`, `fn_is_matchable`, `fn_matching_strike_limit` — never run on a real RFQ |
| 1318 | Which AI agent should handle this request? | PRESENT | `fn_ai_route`, `fn_kb_route_decide`, `fn_resolve_cat_agent` |
| 1319 | Should this customer be asked for more information? | PARTIAL | `fn_rfq_required_check`, `run_rfq_clarify`, `fn_inquiry_answer_set` — 0 inquiries |
| 1320 | Is the RFQ complete? | PARTIAL | `fn_rfq_required_check`, `trg_rfq_complete` |
| 1321 | Is this supplier eligible? | PRESENT | `fn_supplier_licence_gate`, `fn_supplier_matchable`, `fn_is_matchable` |
| 1322 | Is this invoice valid? | PARTIAL | `fn_ap_bill_dupe_guard`, `fn_ap_duplicate_scan` — `ap_bills` 0 rows |
| 1323 | Should this case be escalated? | PRESENT | `fn_should_escalate`, `decision_log` 1,479 rows |
| 1324 | Is the confidence high enough to act automatically? | PRESENT | `fn_ai_gate`, `trg_action_gate`, `decision_policy` 28 rows, `fn_autonomy_class`. Confidence has been written to `decision_log` since the 11 Aug trigger-order fix |
| 1326 | "Without explicit decision rules and confidence thresholds…" | PRESENT | `decision_policy` 28 rows is the explicit rule table the sentence demands |

---

## §11 — Exception handling, the 16 scenarios (L1328–L1353) — **the largest gap in the file**

`scenario_library` holds **19 scenarios, all 19 with a `last_run`**. That looks like coverage. It is
not: **17 of the 19 are scenarios spec #7 never named**, and of the spec's 16, **13 are absent.**

| # | spec line | scenario | verdict | evidence |
|---|---|---|---|---|
| 1 | 1336 | OpenAI is unavailable | PARTIAL | `scenario_library.openrouter_outage` covers the **aggregator**, not the vendor. The company does not call OpenAI directly, so the mapping is defensible — but nothing tests an OpenAI-specific failure |
| 2 | 1337 | Anthropic is unavailable | ABSENT | no scenario. `fn_model_autoswitch` exists as a mechanism; it has never been rehearsed against a vendor outage |
| 3 | 1338 | Your vector database fails | ABSENT | no scenario. pgvector is in-database; a failure mode is not modelled |
| 4 | 1339 | Email delivery stops | ABSENT | no scenario. `fn_notifications_dead_letter_held` is a mechanism with no rehearsal |
| 5 | 1340 | WhatsApp API is down | ABSENT | no scenario |
| 6 | 1341 | Payment gateway is unavailable | ABSENT | no scenario; `stripe_events` 0 rows |
| 7 | 1342 | A supplier's website is offline | ABSENT | no scenario |
| 8 | 1343 | OCR fails | ABSENT | no scenario, no OCR routine at all |
| 9 | 1344 | A PDF is corrupted | ABSENT | no scenario |
| 10 | 1345 | Customer uploads a ZIP instead of a PDF | ABSENT | no scenario; `_shared/attachment.ts` validates type — never tested against this case |
| 11 | 1346 | A supplier responds in Arabic | PARTIAL | `fn_p2c1_lang_parity_suite` and `fn_p2c1_run_lang_case` exist and test language parity. No `scenario_library` row |
| 12 | 1347 | Two agents disagree | PRESENT | `scenario_library.rfq_classified_differently` and `marketing_legal_disagree`; `fn_decision_conflict_scan`; `fn_challenge` |
| 13 | 1348 | A database record is locked | ABSENT | no scenario |
| 14 | 1349 | A supplier doesn't reply within 24 hours | PARTIAL | `run_no_quote_nudges`, `qd_reveal_nudges`, `fn_sla_watch` are real mechanisms; no scenario row and no RFQ has ever waited |
| 15 | 1350 | A supplier uploads the wrong quotation | PARTIAL | `scenario_library.wrong_trade_licence` is the wrong **document**, not the wrong **quotation**. Nearest, not equal |
| 16 | 1351 | Customer changes requirements after quotations are received | ABSENT | no scenario. `fn_edit_inquiry` and `fn_inquiry_answer_supersede` exist; the post-quote case is not modelled |

> L1353: "Every one of these scenarios needs a predefined recovery strategy." — **ABSENT for 13 of 16.**

### And the runner does not do what the green tick implies

`fn_scenario_run` writes `last_run` and a verdict on all 19. Its own recorded output reads:

> "ORG READINESS READY … Checked against `org_departments` and `org_agents` … **This verifies the
> organisation can answer the scenario; it does not claim the failure itself was rehearsed.**"

The runner checks that the named departments exist, are active, are staffed and are managed. It does
not inject the failure. That honesty is in the data and is to the previous session's credit — but it
means **0 of the 16 exception scenarios has ever been executed as a failure.** Any report reading
"19/19 scenarios ran" is reading a staffing check.

---

## §12 — Self-healing, the 8 examples (L1355–L1370)

| spec line | claim | verdict | evidence |
|---|---|---|---|
| 1361 | Restart failed AI agents | PARTIAL | `fn_watch_failed_runs`, `fn_runner_silence_watch`, `fn_agent_silence_watch` detect; nothing restarts |
| 1362 | Retry failed API calls with backoff | PARTIAL | `org_action_executor` carries retry/timeout columns — the executor table **implements none of them**; `fn_notifications_release_held` retries notifications only |
| 1363 | Switch to a backup AI provider | PARTIAL | `fn_model_autoswitch`, `fn_select_model` with `fallback_model` in `model_policy_by_identity`; never triggered by an outage |
| 1364 | Queue work during outages | PRESENT | `org_tasks` 834, `agent_actions` queue, `fn_action_queue_sweep` |
| 1365 | Rebuild search indexes | PARTIAL | `fn_graph_rebuild` rebuilds the graph; `fn_index_slowdown_watch` detects; no embedding-index rebuild routine |
| 1366 | Retry failed notifications | PRESENT | `fn_notifications_dead_letter_held`, `fn_notifications_release_held` |
| 1367 | Detect duplicate jobs | PARTIAL | `fn_cron_liveness`, `fn_cron_ran`; `idempotency_key` UNIQUE on the executor. No cross-job duplicate detector |
| 1368 | Recover interrupted workflows | PRESENT | `fn_workflow_step_sweep`, `fn_execution_sweep`, `fn_org_task_execute_sweep` |

---

## §13 — Continuous monitoring, the 11 signals (L1372–L1390)

| spec line | signal | verdict | evidence |
|---|---|---|---|
| 1378 | Agent health | PRESENT | `fn_ai_quality_watch`, `ai_quality_snapshots` 1,115, `fn_agent_silence_watch` |
| 1379 | CPU and memory usage | ABSENT | not measured anywhere — Supabase-managed, but the contract asks for it |
| 1380 | API latency | PARTIAL | `fn_edge_health_scan` measures reachability; no latency series |
| 1381 | Error rates | PRESENT | `fn_watch_failed_runs`, `agent_runs.status` |
| 1382 | Queue lengths | PRESENT | `fn_action_queue_sweep`, `org_tasks` depth |
| 1383 | Storage capacity | ABSENT | not measured |
| 1384 | Token usage | PRESENT | `fn_llm_log`, `fn_ai_spend_guard`, `fn_check_spend`, `cost_snapshot` |
| 1385 | Response times | PARTIAL | `qd_recompute_response` is supplier response time, not system response time |
| 1386 | Supplier response rates | PRESENT | `qd_recompute_response`, `fn_supplier_quality` |
| 1387 | Payment failures | ABSENT | `stripe_events` 0 rows; no failure monitor |
| 1388 | Security events | PRESENT | `fn_security_scan`, `sec_incident`, `security_audit` |
| 1390 | "respond automatically before users notice" | PARTIAL | detection is broad, automatic response is narrow — `fn_ai_spend_guard` and `fn_notifications_release_held` are the only two that act without a human |

---

## §14 — Learning & adaptation, the 6 examples (L1392–L1405)

| spec line | claim | verdict | evidence |
|---|---|---|---|
| 1398 | Learn new supplier categories | PRESENT | `fn_scan_new_supplier_categories`, `ensure_category_agent`, `fn_category_knowledge_promote` |
| 1399 | Improve routing | PARTIAL | `kb_operational_route_test` 344 rows and `fn_kb_route_test_run` measure routing; no routine changes a route from an outcome |
| 1400 | Refine qualification questions | PARTIAL | `fn_category_questions`, `fn_bump_exam_question`; refines exam questions, not qualification questions |
| 1401 | Identify repeated failure patterns | PRESENT | `fn_task_lesson`, `fn_org_task_root_cause_guard`, `fn_ingest_case_lessons` |
| 1402 | Detect emerging customer needs | ABSENT | no customers, no inquiry stream — the "rising keyword" gap already recorded against `s29` |
| 1403 | Flag outdated knowledge for review | PRESENT | `fn_knowledge_decay`, `agent_knowledge.review_due`, `valid_until`, `validation_status` |
| 1405 | "For regulated content … learning should propose updates rather than silently changing approved knowledge" | PRESENT | `fn_kb_submit_revision` → `fn_kb_gov_approve`; `kb_revisions` 9,355 rows; `fn_policy_lint_kb_chunks`. This is one of the most faithfully implemented sentences in the contract |

---

## §15 — The six additional platform components (L1407–L1498)

| component | spec lines | verdict | evidence |
|---|---|---|---|
| **AI Governor** | 1411–1420 | PRESENT | all six sub-claims land: allowed actions → `org_action_executor` 56 + `fn_action_policies`; what requires approval → `fn_approval_policy_match`, `decision_policy` 28; spending limits → `fn_budget_available`, `fn_ai_spend_guard`, `department_budget` 25; communication rules → `fn_lint_outbound`; safety policies → `fn_autonomy_control_guard`; confidence thresholds → `fn_ai_gate` |
| **AI Scheduler** | 1421–1430 | PRESENT | 185 cron jobs, 166 active, surfaced by `fn_os_automation_list`. All six named jobs exist: nightly maintenance, knowledge sync (`kb_sync`), DB cleanup (`fn_audit_prune`), KPI generation (`fn_kpi_scoreboard`), supplier performance (`fn_supplier_score_refresh`), health checks (`run_health_check`) |
| **AI Auditor** | 1431–1440 | PARTIAL | policy compliance → `fn_policy_consistency_check` PRESENT; decision consistency → `fn_decision_conflict_scan` PRESENT; unauthorized actions → `fn_autonomy_audit` PRESENT; security events → `fn_security_audit` PRESENT; financial anomalies → `fn_ap_duplicate_scan` PARTIAL (0 bills); **AI hallucination indicators → PARTIAL**: `fn_require_grounding` enforces citation, but nothing scores hallucination |
| **AI Memory Manager** | 1441–1450 | PARTIAL | long-term → `org_memory` 624 + `fn_promote_memory`; short-term context → `fn_agent_context_capped`; knowledge freshness → `fn_knowledge_decay`; versioning → `kb_revisions` 9,355. **Conversation history ABSENT** (`chat_threads` 0, `messages` 0); **archiving PARTIAL** (`fn_audit_prune`, `archive_rfq` over 0 RFQs) |
| **Disaster Recovery** | 1451–1460 | PARTIAL | database failures → `fn_backup_watch` + `fn_phase1_rollback_rehearse` PRESENT; data corruption → immutability triggers PRESENT. **Regional outages ABSENT, cloud provider failures PARTIAL** (`scenario_library.supabase_outage` is a staffing check, not a failover), **cyberattacks PARTIAL** (`sec_incident` records; no response plan), **AI provider failures PARTIAL** (`fn_model_autoswitch`, never rehearsed) |
| **Observability** | 1461–1498 | **CONTRADICTED** | see below |

### The observability trace (L1467–L1498) — CONTRADICTED

The contract specifies an exact, checkable trace:

> RFQ #4582 → Created → Document AI analysed BOQ → HVAC Agent qualified inquiry → Supplier Matching
> Agent selected 12 suppliers → Notification Agent sent invitations → 7 quotations received →
> Comparison AI ranked quotations → Award recommendation generated.
> "Every step should be logged with timestamps and reasons."

Every one of the eight steps has a routine. **Not one step has ever executed**, because
`inquiries` = 0, `quotes` = 0, `inquiry_matches` = 0. `workflow_run` for `rfq_handling` = **0**.

This is CONTRADICTED rather than ABSENT because `fn_emit_rfq_classified`, `enqueue_supplier_invites`
and `fn_supplier_quote_recommend` all exist and would each log — but the trace the founder wrote as
the acceptance test for observability **cannot be produced today**, and the OS's health screens
report the observability stack as healthy. The instrument is green over an event stream that has
never had an event.

---

## §16 — The one contract claim that is actively false in production

**`model_policy_by_identity` — 96 keys, 0 resolve, and it is not what the brief said it was.**

The brief called them "target-employee keys". The column is `scope`, and the value is
`target_employee`:

| scope | rows | resolve to `org_agents` | to `org_departments` | to `org_agent_alias` |
|---|---|---|---|---|
| `current_agent` | 24 | **23** | 3 | 0 |
| `target_employee` | **96** | **0** | **0** | **0** |

The 96 are `<department-slug>-<role>` over **24 departments × 4 roles** (`director`,
`analyst-controller`, `operations-specialist`, `reviewer-auditor`). Production has 25 departments
and 94 employees with short keys (`ceo`, `cfo`, `procurement`, `spec_mep`).

Re-measured rather than assumed: **48 of the 96 already match a slugified `org_departments.name`.**
The other 48 fail on two drifts, both mechanical:

- **`&` vs `and`** — `hr-and-people-operations` vs slug `hr-people-operations`; same for
  `administration-and-operations`, `legal-and-compliance`, `qa-and-testing`, `trust-and-safety`,
  `notification-and-communications` (also plural drift), `sales-and-crm`.
- **genuine renames** — `ai-and-model-operations` (row is "AI Department"),
  `it-sre-and-cybersecurity` ("IT & Cybersecurity"), `marketplace-operations`
  ("Marketplace & Procurement"), `payments-and-revenue-operations` ("Payment"),
  `strategy-performance-and-evolution` ("Evolution").

So this is **not 96 unknown identities**. It is one package authored against a 24-department org
whose names have since drifted, landing in a table with no foreign key to catch it. Every row is
dead configuration: a fallback model, an escalation model, a token cap and a reasoning effort that
no lookup can ever reach.

**This is instance 5 of the recurring root cause** — a complete thing addressed to an identity the
system does not model. The fix shape already in this codebase is `org_agent_alias` +
`fn_org_agent_resolve` applied at the write boundary, and `org_agent_alias` holds only 21 rows today.

---

## §17 — The same shape, measured everywhere else it occurs

Every column in the database that names an actor, checked against `org_agents`:

| column | rows | rows unresolved | distinct keys | distinct unresolved | verdict |
|---|---|---|---|---|---|
| `kb_usage_log.agent` | 80 | **0** | 12 | **0** | clean |
| `ai_quality_snapshots.agent` | 1,115 | 171 | 35 | 7 | PARTIAL — 7 stale keys |
| `agent_actions.agent` | 2,450 | 415 | 54 | 28 | PARTIAL |
| `agent_expectations.agent` | 121 | 108 | 121 | 108 | **not a defect** — holds job names (`cost_snapshot`, `backup`, `ai_health`, `day_conductor`), the same vocabulary as `agent_runs` |
| `agent_runs.agent` | 20,530 | 17,911 | 123 | 109 | **not a defect** — documented in `cost_snapshot/index.ts` as "a JOB name, not an employee key" |
| `agent_knowledge.agent_key` | 2,040 | 1,741 | 234 | **141** | **not employees** — `cat:*` category keys and `_global` |
| `model_policy_by_identity.identity_key` (`target_employee`) | 96 | **96** | 96 | **96** | **CONTRADICTED** — matches no vocabulary at all |

**The real systemic finding is narrower and sharper than "orphan employees".** A column named
`agent` or `agent_key` carries **four different vocabularies** across this database — employee keys,
cron job names, `cat:<category>` keys, and `_global` — with **no discriminator column and no foreign
key anywhere**. `model_policy_by_identity` is the only one whose keys match *none* of the four, and
that is why it is the only CONTRADICTED row in this table. The other counts are not orphans; they
are a naming collision that makes every one of these joins unverifiable by inspection.

The brief's figures for two of these (`ai_quality_snapshots` 754/1,066 and `agent_expectations`
29/36) do not reproduce. Current measurements are in the table above.

---

## Carried forward to the contradictions register

1. `dept_key='knowledge'` names "Administration & Operations" (§1 #11).
2. The 4-layer knowledge architecture has four layers, none of them the four specified (§4).
3. `model_policy_by_identity`: 96 dead rows (§16).
4. The observability trace cannot be produced (§15).
5. `fn_scenario_run` verifies staffing and is read as scenario coverage (§11).
6. 9 of 14 workflows have never run; all customer-facing ones are among them (§6).
