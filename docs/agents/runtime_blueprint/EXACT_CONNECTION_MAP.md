# Exact QuotesDone Agent Connection Map

## Core relationship

```text
Founder policy and funding
  → CEO
  → 10 department heads / executive committee
  → 90 accountable role identities
  → one task owner per execution
  → optional internal specialists and category overlays
  → independent reviewer for consequential work
  → approved action or handoff
  → KPI outcome
  → management review
  → validated learning
```

A **role identity** is not a model. A role carries responsibility, knowledge, tools, KPIs, authority and reporting. The model is selected for each task from the task class and risk.

## Runtime population

- 10 active canonical departments
- 90 accountable standing roles
- 86 category overlays
- 6 persistent managers
- 6 scheduled managers
- 33 event-driven operators
- 35 on-demand functional specialists
- 10 independent reviewers

## Mandatory runtime boundary

```text
input/event
→ canonical identity resolution
→ active role/department/manager
→ authority and risk
→ relevant knowledge retrieval
→ deterministic tool requirement
→ live tool execution when required
→ task-class model routing
→ structured output validation
→ append-only decision trace
→ independent review when required
→ action/handoff/refusal
→ KPI and outcome
```

No employee path may skip these stages.

## Executive & Strategy (`exec`)

- Head: `ceo`
- Accountable roles: **4**
- Runtime modes: on_demand_specialist 1, persistent_manager 2, scheduled_manager 1
- Outcome: Translate the AED 1,000,000 revenue target into company priorities, resolve cross-company constraints, allocate resources and hold departments accountable.
- Roles: `ceo`, `chief_of_staff`, `strategy_director`, `org_designer`

## Growth & Revenue (`growth_revenue`)

- Head: `sales_director`
- Accountable roles: **12**
- Runtime modes: event_driven_operator 5, on_demand_specialist 6, scheduled_manager 1
- Outcome: Acquire qualified customers and suppliers, create demand, convert pipeline and improve commercial performance.
- Roles: `sales_director`, `marketing_director`, `brand_mgr`, `marketing_analyst`, `marketing_content`, `marketing_design`, `marketing_social`, `bd`, `gov_relations_mgr`, `partnerships_mgr`, `account_mgr`, `crm_pipeline_mgr`

## Customer Experience & Communications (`customer_experience_communications`)

- Head: `customer_success_director`
- Accountable roles: **7**
- Runtime modes: event_driven_operator 6, scheduled_manager 1
- Outcome: Move customers from onboarding to successful inquiry, quotation, reveal, retention and advocacy with clear lifecycle communication.
- Roles: `customer_success_director`, `cs_onboarding`, `cs_retention`, `cs_support`, `rfq_success`, `comms_manager`, `channel_specialist`

## Marketplace & Supplier Network (`marketplace_supplier_network`)

- Head: `marketplace_director`
- Accountable roles: **19**
- Runtime modes: event_driven_operator 7, independent_reviewer 2, on_demand_specialist 9, persistent_manager 1
- Outcome: Turn customer needs into supplier-ready briefs, maintain supplier liquidity and quality, and produce quoteable, comparable marketplace outcomes.
- Roles: `marketplace_director`, `quote_evaluation`, `spec_commercial`, `spec_construction`, `spec_fitout`, `spec_industrial`, `spec_mep`, `supplier_verification`, `rfq_qualification_mgr`, `inquiry_router`, `inquiry_scoring`, `taxonomy_manager`, `category_curator`, `supplier_onboarding_specialist`, `supplier_coverage`, `supplier_retention`, `doc_intel_manager`, `boq_analyst`, `drawing_analyst`

## Product, Engineering & AI (`product_engineering_ai`)

- Head: `cpo`
- Accountable roles: **12**
- Runtime modes: event_driven_operator 3, independent_reviewer 1, on_demand_specialist 7, persistent_manager 1
- Outcome: Build, operate and improve the QuotesDone product, agent runtime, integrations and AI systems safely and efficiently.
- Roles: `cpo`, `cto`, `eng_manager`, `backend_engineer`, `frontend_engineer`, `solution_architect`, `ai_director`, `ai_architect`, `model_evaluator`, `prompt_engineer`, `innovation_mgr`, `optimisation_eng`

## Data, Intelligence & Knowledge (`data_intelligence_knowledge`)

- Head: `intel_director`
- Accountable roles: **9**
- Runtime modes: event_driven_operator 3, independent_reviewer 1, on_demand_specialist 4, scheduled_manager 1
- Outcome: Convert company data, market evidence and validated knowledge into decisions, forecasts and reusable organizational intelligence.
- Roles: `intel_director`, `forecast_analyst`, `market_analyst`, `supplier_intelligence_analyst`, `business_intelligence_analyst`, `bi_analyst`, `knowledge_director`, `kb_engineer`, `knowledge_validator`

## Finance & Payments (`finance`)

- Head: `cfo`
- Accountable roles: **7**
- Runtime modes: event_driven_operator 5, on_demand_specialist 1, persistent_manager 1
- Outcome: Protect cash, accounting integrity, revenue assurance, payment operations, forecasts, budgets and investor-quality financial reporting.
- Roles: `cfo`, `ap_specialist`, `bookkeeper`, `collections`, `financial_analyst`, `payments_manager`, `billing_specialist`

## Legal, Compliance, Risk & Trust (`legal`)

- Head: `general_counsel`
- Accountable roles: **7**
- Runtime modes: event_driven_operator 2, independent_reviewer 3, on_demand_specialist 1, scheduled_manager 1
- Outcome: Protect legal, regulatory, privacy, contractual, fraud, trust and governance boundaries while enabling lawful growth.
- Roles: `general_counsel`, `compliance_mgr`, `contract_specialist`, `risk_governance_mgr`, `trust_safety_mgr`, `fraud_analyst`, `moderation_specialist`

## People & Company Operations (`people_company_operations`)

- Head: `ops_director`
- Accountable roles: **8**
- Runtime modes: event_driven_operator 1, on_demand_specialist 6, persistent_manager 1
- Outcome: Keep the autonomous company organized, staffed, documented, coordinated and continuously improved.
- Roles: `ops_director`, `document_operations_specialist`, `process_improvement_mgr`, `project_coordinator`, `hr_director`, `culture_performance_mgr`, `learning_dev_mgr`, `recruitment_specialist`

## Independent Assurance, Security & Reliability (`assurance_security_reliability`)

- Head: `qa_manager`
- Accountable roles: **5**
- Runtime modes: event_driven_operator 1, independent_reviewer 3, scheduled_manager 1
- Outcome: Independently verify quality, security, privacy, model safety and reliability, with authority to block unsafe work.
- Roles: `qa_manager`, `ai_qa_specialist`, `test_automation_eng`, `it_operations_engineer`, `cybersecurity_engineer`

## Category overlays

All 86 overlays are invoked internally by the marketplace chain:

```text
Marketplace Director
→ RFQ Qualification Manager
→ Inquiry Router
→ category overlay(s)
→ missing fields, never-infer rules, documents, pricing drivers, risks
→ RFQ Qualification Manager
```

The overlay never dispatches, exposes identity, approves suppliers, moves money or overrides a regulatory/privacy gate.

## Cross-department work

Use `CROSS_DEPARTMENT_HANDOFFS.csv` and `schemas/handoff.schema.json`. The origin retains one accountable owner until the receiving department accepts the evidence and the closure criteria are met.
