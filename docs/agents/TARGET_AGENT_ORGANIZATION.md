# The target agent organisation

Generated from `htdblwldjkcgjvmqkbeh` at 2026-08-14 13:21:25.48994 UTC. Ten primary departments, 90 accountable
roles and 86 category overlays.

Every role belongs to one primary department, reports to one primary manager, owns defined
responsibilities, has measurable KPIs, has explicit decision authority, uses named tools and
knowledge scopes, records evidence, and contributes to the AED 1,000,000 revenue objective by
31 August 2027.

## Runtime modes

| mode | roles | what it means |
|---|---|---|
| `knowledge_overlay` | 86 | specialist knowledge loaded into the invoking manager; no model instance |
| `on_demand_specialist` | 35 | invoked by a manager as a tool; no standing state |
| `event_driven_operator` | 33 | wakes on a named event and executes inside its authority |
| `scheduled_manager` | 12 | owns a department outcome and reviews on a cadence |
| `independent_reviewer` | 10 | holds stop authority and never approves work it authored |

## The ten departments

### Executive & Strategy (`exec`)

Owns company direction and the machinery that keeps it honest: strategy, the objective cascade from the AED 1,000,000 revenue target down to role KPIs, corporate performance diagnosis and correction, organisation design, and the chief-of-staff office that turns the founder's intent into assigned work. Does not duplicate a department head because that head attends the executive committee: committee seats are recorded against the one role, in org_role_committee.

- **North star:** AED 1,000,000 by 31 August 2027, with every department's objectives tracing to it
- **Head:** `ceo`
- **Health function:** `fn_ws_company`
- **Absorbed:** evolution
- **Staff:** 5 employees, 5 canonical roles
- **Company goals owned:** 2 · **department objectives:** 10 · **open work:** 115

| role | mode | authority | runs as | KPIs |
|---|---|---|---|---|
| **ceo** — Chief Executive (AI) | scheduled_manager | execute_high | `ceo` | 1 |
| **chief_of_staff** — Chief of Staff | scheduled_manager | execute_high | `brief` | 2 |
| **chief_performance_officer** — Chief Performance Officer | scheduled_manager | execute_medium | `cpo` | 5 |
| **organization_designer** — Organisation Design Lead | on_demand_specialist | advisory | `org_designer` | 1 |
| **strategy_director** — Strategy Director | on_demand_specialist | advisory | `strategy_director` | 1 |

### Growth & Revenue (`growth`)

Owns every step from a stranger hearing about QuotesDone to money received against a won quotation: brand, content, design, social, campaigns and marketing performance; outbound sales, account management, CRM and revenue operations; business development, partnerships and government relations. One funnel, one accountable revenue owner. Customer service after the sale belongs to Customer Experience; supplier acquisition belongs to Marketplace & Supplier Network.

- **North star:** AED 1,000,000 in revenue by 31 August 2027
- **Head:** `sales_director`
- **Health function:** `fn_ws_marketing`
- **Absorbed:** bizdev, marketing, sales
- **Staff:** 12 employees, 12 canonical roles
- **Company goals owned:** 5 · **department objectives:** 9 · **open work:** 63

| role | mode | authority | runs as | KPIs |
|---|---|---|---|---|
| **account_management** — Account Manager | on_demand_specialist | execute_low | `account_mgr` | 1 |
| **brand_and_creative** — Brand & Creative Manager | event_driven_operator | execute_low | `brand_mgr` | 1 |
| **business_development** — Business Development Manager | event_driven_operator | execute_low | `bd` | 1 |
| **chief_revenue_officer** — Chief Revenue Officer | scheduled_manager | execute_medium | `sales_director` | 1 |
| **content_strategy_and_copy** — Content Strategy & Copy Specialist | on_demand_specialist | execute_low | `marketing_content` | 2 |
| **crm_and_revenue_operations** — CRM & Revenue Operations Manager | event_driven_operator | execute_low | `crm_pipeline_mgr` | 1 |
| **government_relations** — Government & Enterprise Relations Manager | on_demand_specialist | advisory | `gov_relations_mgr` | 1 |
| **marketing_director** — Marketing Director | event_driven_operator | execute_low | `marketing` | 3 |
| **marketing_performance_analyst** — Marketing Performance Analyst | event_driven_operator | advisory | `marketing_analyst` | 2 |
| **partnerships** — Partnerships Manager | on_demand_specialist | execute_low | `partnerships_mgr` | 1 |
| **social_media_and_community** — Social Media & Community Manager | event_driven_operator | execute_low | `marketing_social` | 3 |
| **visual_design** — Visual Design Director | on_demand_specialist | execute_low | `marketing_design` | 2 |

### Customer Experience & Communications (`customer_experience`)

Owns the customer after the inquiry exists: onboarding, support, retention, RFQ success, and every lifecycle message the company sends on any channel — email, WhatsApp, SMS and in-product — including deliverability, sender reputation, the outbox and the digest. Acquisition messaging belongs to Growth & Revenue; the quality of the inquiry itself belongs to Marketplace & Supplier Network.

- **North star:** Every customer who posts an inquiry receives comparable quotations and comes back
- **Head:** `followup`
- **Health function:** `fn_ws_customers`
- **Absorbed:** comms, customer_success
- **Staff:** 7 employees, 7 canonical roles
- **Company goals owned:** 7 · **department objectives:** 7 · **open work:** 18

| role | mode | authority | runs as | KPIs |
|---|---|---|---|---|
| **communications_manager** — Communications Manager | event_driven_operator | execute_low | `comms_manager` | 1 |
| **customer_onboarding** — Customer Onboarding Specialist | event_driven_operator | execute_low | `cs_onboarding` | 1 |
| **customer_retention** — Customer Retention Specialist | event_driven_operator | execute_low | `cs_retention` | 1 |
| **customer_success_director** — Customer Success Director | scheduled_manager | execute_medium | `followup` | 2 |
| **customer_support** — Customer Support Specialist | event_driven_operator | execute_low | `cs_support` | 1 |
| **lifecycle_channel_operations** — Lifecycle Channel Operations Specialist | event_driven_operator | execute_low | `channel_specialist` | 1 |
| **rfq_success** — RFQ Success Specialist | event_driven_operator | execute_low | `rfq_success` | 1 |

### Marketplace & Supplier Network (`marketplace`)

Owns the inquiry-to-quotation workflow end to end and the supplier network that answers it: intake, qualification, routing, scoring, dispatch, quote evaluation and reveal; supplier verification, onboarding, coverage, liquidity and retention; and the document intelligence — BOQ, drawings, specifications — that turns an attachment into a quotable requirement. One accountable Marketplace Director for the whole chain.

- **North star:** Every qualified inquiry reaches enough confirmed suppliers to produce comparable quotations
- **Head:** `procurement`
- **Health function:** `fn_ws_marketplace`
- **Absorbed:** doc_intelligence, procurement, rfq_intelligence, supplier_knowledge, supplier_success
- **Staff:** 17 employees, 103 canonical roles
- **Company goals owned:** 16 · **department objectives:** 24 · **open work:** 57

| role | mode | authority | runs as | KPIs |
|---|---|---|---|---|
| **boq_analyst** — BOQ & Specification Analyst | on_demand_specialist | advisory | `boq_analyst` | 1 |
| **document_intelligence_manager** — Document Intelligence Manager | event_driven_operator | execute_low | `doc_intel_manager` | 1 |
| **drawing_analyst** — Drawing & CAD Analyst | on_demand_specialist | advisory | `drawing_analyst` | 1 |
| **inquiry_quality_analyst** — Inquiry Quality & Scoring Analyst | event_driven_operator | advisory | `inquiry_scoring` | 1 |
| **inquiry_router** — Inquiry Router | event_driven_operator | execute_low | `inquiry_router` | 1 |
| **marketplace_director** — Marketplace Director | scheduled_manager | execute_medium | `procurement` | 2 |
| **quote_evaluation** — Quote Evaluation Specialist | event_driven_operator | execute_low | `quote_evaluation` | 1 |
| **rfq_qualification_manager** — RFQ Qualification Manager | event_driven_operator | execute_low | `rfq_qualification_mgr` | 1 |
| **spec_commercial** — Commercial Services Specialist | on_demand_specialist | advisory | `spec_commercial` | 1 |
| **spec_construction** — Construction & Civil Specialist | on_demand_specialist | advisory | `spec_construction` | 1 |
| **spec_fitout** — Interior & Fit-Out Specialist | on_demand_specialist | advisory | `spec_fitout` | 1 |
| **spec_industrial** — Industrial & Energy Specialist | on_demand_specialist | advisory | `spec_industrial` | 1 |
| **spec_mep** — MEP Specialist | on_demand_specialist | advisory | `spec_mep` | 1 |
| **supplier_coverage** — Supplier Coverage & Liquidity Specialist | on_demand_specialist | advisory | `supplier_coverage` | 2 |
| **supplier_onboarding_specialist** — Supplier Onboarding Specialist | event_driven_operator | execute_low | `onboarding` | 7 |
| **supplier_retention** — Supplier Retention Specialist | on_demand_specialist | execute_low | `supplier_retention` | 2 |
| **supplier_verification** — Supplier Verification Reviewer | independent_reviewer | stop_authority | `supplier_verification` | 1 |

### Product, Engineering & AI (`product_eng`)

Owns what the product is and how it is built: product discovery, prioritisation and experimentation; architecture, backend, frontend and delivery; the AI layer — agent design, prompts, model evaluation and routing; and product optimisation including cost per decision. Release quality gates and production reliability belong to Independent Assurance, Security & Reliability, deliberately, so the team that ships does not certify its own release.

- **North star:** Ship the capability the revenue objective needs, at a cost per decision that falls
- **Head:** `cto`
- **Health function:** `fn_ws_ai`
- **Absorbed:** ai_dept, engineering
- **Staff:** 11 employees, 11 canonical roles
- **Company goals owned:** 0 · **department objectives:** 3 · **open work:** 3

| role | mode | authority | runs as | KPIs |
|---|---|---|---|---|
| **ai_architect** — AI Architect | on_demand_specialist | execute_low | `ai_architect` | 1 |
| **ai_director** — AI Director | on_demand_specialist | execute_low | `ai_director` | 1 |
| **backend_engineer** — Backend Engineer | on_demand_specialist | execute_low | `backend_engineer` | 1 |
| **cto** — Chief Technology Officer | scheduled_manager | execute_medium | `cto` | 1 |
| **engineering_manager** — Engineering Manager | on_demand_specialist | execute_low | `eng_manager` | 1 |
| **frontend_engineer** — Frontend Engineer | on_demand_specialist | execute_low | `frontend_engineer` | 1 |
| **model_evaluator** — Model Evaluation Reviewer | independent_reviewer | stop_authority | `model_evaluator` | 1 |
| **product_manager** — Product Manager | event_driven_operator | execute_low | `innovation_mgr` | 1 |
| **product_optimization_engineer** — Product Optimisation Engineer | event_driven_operator | execute_low | `optimisation_eng` | 2 |
| **prompt_engineer** — Agent & Prompt Engineer | on_demand_specialist | execute_low | `prompt_engineer` | 1 |
| **solution_architect** — Solution Architect | on_demand_specialist | advisory | `solution_architect` | 1 |

### Data, Intelligence & Knowledge (`data_intel`)

Owns turning information into decisions and into durable company knowledge: data engineering, business intelligence, forecasting, market, competitive, supplier and customer intelligence; the knowledge corpus, its engineering, validation and freshness; and the trade taxonomy and category curation that every route and every category specialist depends on. Owns metric DEFINITIONS; the departments own their own numbers.

- **North star:** Every company goal has a measured actual, and every agent retrieves knowledge that is current
- **Head:** `intel_director`
- **Health function:** `fn_ws_knowledge`
- **Absorbed:** analytics, intelligence, knowledge_eng
- **Staff:** 11 employees, 11 canonical roles
- **Company goals owned:** 0 · **department objectives:** 5 · **open work:** 43

| role | mode | authority | runs as | KPIs |
|---|---|---|---|---|
| **business_intelligence_analyst** — Business Intelligence Analyst | on_demand_specialist | advisory | `bi_analyst` | 1 |
| **category_curator** — Category Knowledge Curator | event_driven_operator | execute_low | `category_curator` | 1 |
| **data_engineer** — Data Engineer | on_demand_specialist | advisory | `analytics` | 1 |
| **data_intelligence_director** — Data & Intelligence Director | scheduled_manager | execute_medium | `intel_director` | 2 |
| **forecasting_analyst** — Forecasting Analyst | on_demand_specialist | advisory | `forecast_analyst` | 1 |
| **knowledge_director** — Knowledge Director | event_driven_operator | execute_low | `knowledge_director` | 2 |
| **knowledge_engineer** — Knowledge Engineer | event_driven_operator | execute_low | `kb_engineer` | 1 |
| **knowledge_validator** — Knowledge Validator | independent_reviewer | stop_authority | `knowledge_validator` | 1 |
| **market_intelligence_analyst** — Market Intelligence Analyst | on_demand_specialist | advisory | `market_analyst` | 1 |
| **supplier_intelligence_analyst** — Supplier Intelligence Analyst | on_demand_specialist | advisory | `supplier_analyst` | 1 |
| **taxonomy_manager** — Taxonomy Governance Manager | on_demand_specialist | execute_low | `taxonomy_manager` | 1 |

### Finance & Payments (`finance`)

Owns the money end to end: revenue recognition, the ledger, reconciliation and financial controls, accounts payable and receivable, collections and revenue assurance, budgets, runway, forecasts and investor reporting, and the payment and billing rails themselves. Payment is an operating function of finance, not a separate department.

- **North star:** Every dirham earned is recognised, reconciled and collected
- **Head:** `cfo`
- **Health function:** `fn_ws_finance`
- **Absorbed:** payments
- **Staff:** 7 employees, 7 canonical roles
- **Company goals owned:** 12 · **department objectives:** 8 · **open work:** 27

| role | mode | authority | runs as | KPIs |
|---|---|---|---|---|
| **accounts_payable** — Accounts Payable Specialist | event_driven_operator | execute_low | `ap_specialist` | 1 |
| **billing_operations** — Billing & Reconciliation Specialist | event_driven_operator | execute_low | `billing_specialist` | 1 |
| **cfo** — Chief Financial Officer | scheduled_manager | execute_medium | `cfo` | 2 |
| **collections_and_revenue_assurance** — Collections & Revenue Assurance Specialist | event_driven_operator | execute_low | `collections` | 2 |
| **financial_controller** — Financial Controller | event_driven_operator | execute_low | `bookkeeper` | 1 |
| **fpna_analyst** — FP&A Analyst | on_demand_specialist | advisory | `financial_analyst` | 1 |
| **payments_and_billing_manager** — Payments & Billing Manager | event_driven_operator | execute_low | `payments_manager` | 1 |

### Legal, Compliance, Risk & Trust (`legal`)

Owns legal risk and platform trust as one function: contracts, corporate and regulatory compliance including UAE PDPL and explicit data-protection ownership, risk and governance, and trust and safety — fraud, moderation, disputes, policy and enforcement. Legal exposure and platform abuse are the same risk surface and are governed together.

- **North star:** No regulatory breach, no unremediated fraud, no unenforced policy
- **Head:** `legal`
- **Health function:** `fn_ws_governance`
- **Absorbed:** trust_safety
- **Staff:** 7 employees, 7 canonical roles
- **Company goals owned:** 4 · **department objectives:** 4 · **open work:** 23

| role | mode | authority | runs as | KPIs |
|---|---|---|---|---|
| **compliance_and_privacy_officer** — Compliance & Privacy Officer | independent_reviewer | stop_authority | `compliance_mgr` | 1 |
| **contract_manager** — Contract Manager | on_demand_specialist | execute_low | `contract_specialist` | 1 |
| **fraud_analyst** — Fraud Reviewer | independent_reviewer | stop_authority | `fraud_analyst` | 1 |
| **general_counsel** — General Counsel | scheduled_manager | execute_medium | `legal` | 1 |
| **moderation_specialist** — Content Moderation Reviewer | independent_reviewer | stop_authority | `moderation_specialist` | 1 |
| **risk_and_governance_manager** — Risk & Governance Manager | independent_reviewer | stop_authority | `risk_governance_mgr` | 1 |
| **trust_and_safety_manager** — Trust & Safety Manager | event_driven_operator | execute_low | `trust_safety_mgr` | 1 |

### People & Company Operations (`people_ops`)

Owns how the company runs itself: operations management, process improvement, project coordination and the PMO, controlled documents and document operations; and the people system — recruitment, learning and development, culture and performance for the agent workforce. Owns internal operating capability, not customer-facing or marketplace work.

- **North star:** Work is assigned, owned, finished and learned from, without the founder chasing it
- **Head:** `ops_director`
- **Health function:** `fn_ws_operations`
- **Absorbed:** hr, knowledge
- **Staff:** 8 employees, 8 canonical roles
- **Company goals owned:** 7 · **department objectives:** 8 · **open work:** 32

| role | mode | authority | runs as | KPIs |
|---|---|---|---|---|
| **chief_operating_officer** — Chief Operating Officer | scheduled_manager | execute_medium | `ops_director` | 1 |
| **culture_and_performance_manager** — Culture & Performance Manager | on_demand_specialist | advisory | `culture_performance_mgr` | 1 |
| **document_operations_specialist** — Document Operations Specialist | event_driven_operator | execute_low | `docs` | 1 |
| **hr_director** — HR Director | on_demand_specialist | execute_low | `hr_director` | 1 |
| **learning_and_development_manager** — Learning & Development Manager | on_demand_specialist | execute_low | `learning_dev_mgr` | 1 |
| **process_improvement_manager** — Process Improvement Manager | event_driven_operator | execute_low | `process_improvement_mgr` | 1 |
| **project_coordinator** — Project Coordinator (PMO) | event_driven_operator | execute_low | `project_coordinator` | 1 |
| **recruitment_specialist** — Recruitment Specialist | on_demand_specialist | execute_low | `recruitment_specialist` | 1 |

### Independent Assurance, Security & Reliability (`assurance`)

Independent control function with stop authority. Owns QA and release management, test automation, AI quality assurance, IT operations, site reliability and cybersecurity. May block a release, a model change, a migration or a deployment on a critical security failure, a privacy violation, a failed release gate, an unsafe model regression, a corrupt migration or an unreconciled financial-integrity defect. Reports outside Product, Engineering & AI so that the team that ships never certifies its own work, and is never measured on release speed alone.

- **North star:** No unsafe change reaches production, and the platform is healthy essentially all the time
- **Head:** `qa_manager`
- **Health function:** `fn_ws_ai`
- **Absorbed:** it, qa
- **Staff:** 5 employees, 5 canonical roles
- **Company goals owned:** 10 · **department objectives:** 7 · **open work:** 49

| role | mode | authority | runs as | KPIs |
|---|---|---|---|---|
| **ai_quality_reviewer** — AI Quality Assurance Reviewer | independent_reviewer | stop_authority | `ai_qa_specialist` | 1 |
| **cybersecurity_engineer** — Cybersecurity Engineer | independent_reviewer | stop_authority | `security` | 1 |
| **it_operations_engineer** — IT Operations & Site Reliability Engineer | event_driven_operator | execute_medium | `it` | 2 |
| **quality_and_release_director** — QA & Release Management Director | scheduled_manager | stop_authority | `qa_manager` | 1 |
| **test_automation_engineer** — Test Automation Reviewer | independent_reviewer | stop_authority | `test_automation_eng` | 1 |

## Category specialists

All 86 are kept as on-demand knowledge overlays. They are not departments and none of them reports
to the CEO individually.

**Operational chain:** `marketplace_director` → `rfq_qualification_manager` → `inquiry_router` →
the relevant category overlay, resolved by `fn_overlay_for_category(category_key)`.

**Knowledge governance:** `knowledge_director` / `taxonomy_manager` own category source quality,
freshness, aliases, rules and evaluations.

Each overlay owns route and subcategory knowledge, minimum sufficient questions, mandatory and
optional fields, never-infer rules, pricing drivers, required documents, technical comparison
fields, regulatory triggers, quote-readiness criteria and escalation rules.

No overlay may dispatch, approve a supplier, expose customer identity, draw an unsupported legal
conclusion, override a privacy, authority or regulatory gate, or take over the customer
conversation. The inquiry-facing manager keeps the conversation and invokes the overlay internally,
through `fn_specialist_invoke`, which records the invocation and leaves the manager accountable.

## The objective cascade

```
{
  "note": "links are written only where a department owns exactly one active goal or objective; the remainder are reported unlinked rather than guessed",
  "open_work": 430,
  "role_kpis": 118,
  "company_goals": 63,
  "unlinked_role_kpis": 26,
  "department_objectives": 85,
  "revenue_objective_aed": 1000000,
  "role_kpis_linked_upward": 92,
  "company_goals_measurable": 31,
  "unlinked_department_objectives": 29,
  "role_kpis_with_a_measured_actual": 85,
  "open_work_with_one_accountable_owner": 325,
  "department_objectives_linked_to_a_company_goal": 56
}
```

Links are written only where a department owns exactly one active goal or objective. The rest are
reported unlinked rather than guessed: a fabricated link makes the cascade look complete while
explaining nothing.

## Enforcement

`fn_org_role_violations()` returns 0 row(s) at generation time. It checks: department
active, exactly one primary manager, manager active, a runtime executor for every non-overlay role,
that executor active, KPIs present, knowledge present, authority present, tools present, an
evaluation suite named, an independent reviewer actually holding stop authority, no duplicate role
for the same runtime agent, and no active employee without a canonical role.

Structural rules are constraints rather than reports: unique `role_id` (primary key), exactly one
`primary_department_id` (not-null foreign key), exactly one `manager_role_id`, no self-management
(`org_role_no_self_manage_ck`), no reporting cycles (`a10_org_role_no_cycle`), one active role per
runtime agent (`org_role_one_per_agent_ux`), and no self-approval
(`review_chain_no_self_approval_ck`).
