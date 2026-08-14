# Reporting and committee graph

Generated from `htdblwldjkcgjvmqkbeh` at 2026-08-14 13:21:25.48994 UTC by `scripts/agents/export_org_docs.mjs`. Every line is read
from `org_role`, `org_role_committee` and `org_departments`; nothing here is authored twice.

Exactly one primary manager per role, no cycles (enforced by `a10_org_role_no_cycle`), and the
only role without a manager is the CEO, whose boundary is the founder.

## Reporting chain

- **ceo** — Chief Executive (AI) (exec, scheduled_manager, runs as `ceo`)
  - **chief_of_staff** — Chief of Staff (exec, scheduled_manager, runs as `brief`)
    - **chief_revenue_officer** — Chief Revenue Officer (growth, scheduled_manager, runs as `sales_director`)
      - **account_management** — Account Manager (growth, on_demand_specialist, runs as `account_mgr`)
      - **business_development** — Business Development Manager (growth, event_driven_operator, runs as `bd`)
        - **government_relations** — Government & Enterprise Relations Manager (growth, on_demand_specialist, runs as `gov_relations_mgr`)
        - **partnerships** — Partnerships Manager (growth, on_demand_specialist, runs as `partnerships_mgr`)
      - **crm_and_revenue_operations** — CRM & Revenue Operations Manager (growth, event_driven_operator, runs as `crm_pipeline_mgr`)
      - **marketing_director** — Marketing Director (growth, event_driven_operator, runs as `marketing`)
        - **brand_and_creative** — Brand & Creative Manager (growth, event_driven_operator, runs as `brand_mgr`)
        - **content_strategy_and_copy** — Content Strategy & Copy Specialist (growth, on_demand_specialist, runs as `marketing_content`)
        - **marketing_performance_analyst** — Marketing Performance Analyst (growth, event_driven_operator, runs as `marketing_analyst`)
        - **social_media_and_community** — Social Media & Community Manager (growth, event_driven_operator, runs as `marketing_social`)
        - **visual_design** — Visual Design Director (growth, on_demand_specialist, runs as `marketing_design`)
    - **customer_success_director** — Customer Success Director (customer_experience, scheduled_manager, runs as `followup`)
      - **communications_manager** — Communications Manager (customer_experience, event_driven_operator, runs as `comms_manager`)
        - **lifecycle_channel_operations** — Lifecycle Channel Operations Specialist (customer_experience, event_driven_operator, runs as `channel_specialist`)
      - **customer_onboarding** — Customer Onboarding Specialist (customer_experience, event_driven_operator, runs as `cs_onboarding`)
      - **customer_retention** — Customer Retention Specialist (customer_experience, event_driven_operator, runs as `cs_retention`)
      - **customer_support** — Customer Support Specialist (customer_experience, event_driven_operator, runs as `cs_support`)
      - **rfq_success** — RFQ Success Specialist (customer_experience, event_driven_operator, runs as `rfq_success`)
    - **marketplace_director** — Marketplace Director (marketplace, scheduled_manager, runs as `procurement`)
      - **document_intelligence_manager** — Document Intelligence Manager (marketplace, event_driven_operator, runs as `doc_intel_manager`)
        - **boq_analyst** — BOQ & Specification Analyst (marketplace, on_demand_specialist, runs as `boq_analyst`)
        - **drawing_analyst** — Drawing & CAD Analyst (marketplace, on_demand_specialist, runs as `drawing_analyst`)
      - **quote_evaluation** — Quote Evaluation Specialist (marketplace, event_driven_operator, runs as `quote_evaluation`)
      - **rfq_qualification_manager** — RFQ Qualification Manager (marketplace, event_driven_operator, runs as `rfq_qualification_mgr`)
        - **inquiry_quality_analyst** — Inquiry Quality & Scoring Analyst (marketplace, event_driven_operator, runs as `inquiry_scoring`)
        - **inquiry_router** — Inquiry Router (marketplace, event_driven_operator, runs as `inquiry_router`)
      - **spec_commercial** — Commercial Services Specialist (marketplace, on_demand_specialist, runs as `spec_commercial`)
      - **spec_construction** — Construction & Civil Specialist (marketplace, on_demand_specialist, runs as `spec_construction`)
      - **spec_fitout** — Interior & Fit-Out Specialist (marketplace, on_demand_specialist, runs as `spec_fitout`)
      - **spec_industrial** — Industrial & Energy Specialist (marketplace, on_demand_specialist, runs as `spec_industrial`)
      - **spec_mep** — MEP Specialist (marketplace, on_demand_specialist, runs as `spec_mep`)
      - **supplier_onboarding_specialist** — Supplier Onboarding Specialist (marketplace, event_driven_operator, runs as `onboarding`)
        - **supplier_coverage** — Supplier Coverage & Liquidity Specialist (marketplace, on_demand_specialist, runs as `supplier_coverage`)
        - **supplier_retention** — Supplier Retention Specialist (marketplace, on_demand_specialist, runs as `supplier_retention`)
      - **supplier_verification** — Supplier Verification Reviewer (marketplace, independent_reviewer, runs as `supplier_verification`)
    - **cto** — Chief Technology Officer (product_eng, scheduled_manager, runs as `cto`)
      - **ai_director** — AI Director (product_eng, on_demand_specialist, runs as `ai_director`)
        - **ai_architect** — AI Architect (product_eng, on_demand_specialist, runs as `ai_architect`)
        - **model_evaluator** — Model Evaluation Reviewer (product_eng, independent_reviewer, runs as `model_evaluator`)
        - **prompt_engineer** — Agent & Prompt Engineer (product_eng, on_demand_specialist, runs as `prompt_engineer`)
      - **engineering_manager** — Engineering Manager (product_eng, on_demand_specialist, runs as `eng_manager`)
        - **backend_engineer** — Backend Engineer (product_eng, on_demand_specialist, runs as `backend_engineer`)
        - **frontend_engineer** — Frontend Engineer (product_eng, on_demand_specialist, runs as `frontend_engineer`)
        - **solution_architect** — Solution Architect (product_eng, on_demand_specialist, runs as `solution_architect`)
      - **product_manager** — Product Manager (product_eng, event_driven_operator, runs as `innovation_mgr`)
      - **product_optimization_engineer** — Product Optimisation Engineer (product_eng, event_driven_operator, runs as `optimisation_eng`)
    - **cfo** — Chief Financial Officer (finance, scheduled_manager, runs as `cfo`)
      - **accounts_payable** — Accounts Payable Specialist (finance, event_driven_operator, runs as `ap_specialist`)
      - **collections_and_revenue_assurance** — Collections & Revenue Assurance Specialist (finance, event_driven_operator, runs as `collections`)
      - **financial_controller** — Financial Controller (finance, event_driven_operator, runs as `bookkeeper`)
      - **fpna_analyst** — FP&A Analyst (finance, on_demand_specialist, runs as `financial_analyst`)
      - **payments_and_billing_manager** — Payments & Billing Manager (finance, event_driven_operator, runs as `payments_manager`)
        - **billing_operations** — Billing & Reconciliation Specialist (finance, event_driven_operator, runs as `billing_specialist`)
    - **general_counsel** — General Counsel (legal, scheduled_manager, runs as `legal`)
      - **compliance_and_privacy_officer** — Compliance & Privacy Officer (legal, independent_reviewer, runs as `compliance_mgr`)
      - **contract_manager** — Contract Manager (legal, on_demand_specialist, runs as `contract_specialist`)
      - **risk_and_governance_manager** — Risk & Governance Manager (legal, independent_reviewer, runs as `risk_governance_mgr`)
      - **trust_and_safety_manager** — Trust & Safety Manager (legal, event_driven_operator, runs as `trust_safety_mgr`)
        - **fraud_analyst** — Fraud Reviewer (legal, independent_reviewer, runs as `fraud_analyst`)
        - **moderation_specialist** — Content Moderation Reviewer (legal, independent_reviewer, runs as `moderation_specialist`)
    - **chief_operating_officer** — Chief Operating Officer (people_ops, scheduled_manager, runs as `ops_director`)
      - **document_operations_specialist** — Document Operations Specialist (people_ops, event_driven_operator, runs as `docs`)
      - **hr_director** — HR Director (people_ops, on_demand_specialist, runs as `hr_director`)
        - **culture_and_performance_manager** — Culture & Performance Manager (people_ops, on_demand_specialist, runs as `culture_performance_mgr`)
        - **learning_and_development_manager** — Learning & Development Manager (people_ops, on_demand_specialist, runs as `learning_dev_mgr`)
        - **recruitment_specialist** — Recruitment Specialist (people_ops, on_demand_specialist, runs as `recruitment_specialist`)
      - **process_improvement_manager** — Process Improvement Manager (people_ops, event_driven_operator, runs as `process_improvement_mgr`)
      - **project_coordinator** — Project Coordinator (PMO) (people_ops, event_driven_operator, runs as `project_coordinator`)
    - **quality_and_release_director** — QA & Release Management Director (assurance, scheduled_manager, runs as `qa_manager`)
      - **ai_quality_reviewer** — AI Quality Assurance Reviewer (assurance, independent_reviewer, runs as `ai_qa_specialist`)
      - **cybersecurity_engineer** — Cybersecurity Engineer (assurance, independent_reviewer, runs as `security`)
      - **it_operations_engineer** — IT Operations & Site Reliability Engineer (assurance, event_driven_operator, runs as `it`)
      - **test_automation_engineer** — Test Automation Reviewer (assurance, independent_reviewer, runs as `test_automation_eng`)
  - **chief_performance_officer** — Chief Performance Officer (exec, scheduled_manager, runs as `cpo`)
    - **organization_designer** — Organisation Design Lead (exec, on_demand_specialist, runs as `org_designer`)
  - **strategy_director** — Strategy Director (exec, on_demand_specialist, runs as `strategy_director`)
  - **data_intelligence_director** — Data & Intelligence Director (data_intel, scheduled_manager, runs as `intel_director`)
    - **business_intelligence_analyst** — Business Intelligence Analyst (data_intel, on_demand_specialist, runs as `bi_analyst`)
    - **category_curator** — Category Knowledge Curator (data_intel, event_driven_operator, runs as `category_curator`)
    - **data_engineer** — Data Engineer (data_intel, on_demand_specialist, runs as `analytics`)
    - **forecasting_analyst** — Forecasting Analyst (data_intel, on_demand_specialist, runs as `forecast_analyst`)
    - **knowledge_director** — Knowledge Director (data_intel, event_driven_operator, runs as `knowledge_director`)
      - **knowledge_engineer** — Knowledge Engineer (data_intel, event_driven_operator, runs as `kb_engineer`)
      - **knowledge_validator** — Knowledge Validator (data_intel, independent_reviewer, runs as `knowledge_validator`)
    - **market_intelligence_analyst** — Market Intelligence Analyst (data_intel, on_demand_specialist, runs as `market_analyst`)
    - **supplier_intelligence_analyst** — Supplier Intelligence Analyst (data_intel, on_demand_specialist, runs as `supplier_analyst`)
    - **taxonomy_manager** — Taxonomy Governance Manager (data_intel, on_demand_specialist, runs as `taxonomy_manager`)

The 86 category overlays all report to **inquiry_router** and are omitted from the tree above; they
are listed in `RUNTIME_MODE_ASSIGNMENTS.csv`. They are not departments and do not report to the
CEO individually.

## Committees

A committee seat is a row in `org_role_committee`, never a second role. The unique index
`org_role_one_per_agent_ux` makes a duplicate role for the same runtime agent unrepresentable.

### Executive Committee (`exec_committee`)

Company direction, capital, priorities and cross-department conflict. Attendance never creates a second role record.

- **Chair:** ceo
- **Cadence:** weekly
- **Seats:** ceo (chair), cfo (member), chief_operating_officer (member), chief_performance_officer (member), chief_revenue_officer (member), cto (member), customer_success_director (member), data_intelligence_director (member), general_counsel (member), marketplace_director (member), quality_and_release_director (observer), chief_of_staff (secretary)

### Knowledge Council (`knowledge_council`)

Corpus freshness, taxonomy changes, category coverage and what the company has actually learned.

- **Chair:** knowledge_director
- **Cadence:** weekly
- **Seats:** knowledge_director (chair), category_curator (member), data_intelligence_director (member), knowledge_validator (member), marketplace_director (member), taxonomy_manager (member)

### Release Gate (`release_gate`)

Independent go/no-go on releases, model changes and migrations. Chaired outside the department that ships.

- **Chair:** quality_and_release_director
- **Cadence:** on_event
- **Seats:** quality_and_release_director (chair), ai_quality_reviewer (member), cybersecurity_engineer (member), it_operations_engineer (member), test_automation_engineer (member), cto (observer)

### Revenue Council (`revenue_council`)

One reading of the acquisition-to-cash funnel: marketing, sales, business development, customer retention and collections against the AED 1,000,000 objective.

- **Chair:** chief_revenue_officer
- **Cadence:** weekly
- **Seats:** chief_revenue_officer (chair), business_development (member), cfo (member), collections_and_revenue_assurance (member), customer_success_director (member), marketing_director (member), marketing_performance_analyst (member)

### Risk & Trust Council (`risk_and_trust_council`)

Legal, compliance, privacy, fraud, moderation and security risk reviewed together, because they are one risk surface.

- **Chair:** general_counsel
- **Cadence:** weekly
- **Seats:** general_counsel (chair), compliance_and_privacy_officer (member), cybersecurity_engineer (member), fraud_analyst (member), risk_and_governance_manager (member), trust_and_safety_manager (member)

## Independence

`fn_pick_reviewer(dept, author)` never returns the author. Where the department head is the
author, review routes to that department's independent reviewer; where there is none, it climbs one
level. Measured on all ten departments, the head is never returned as its own reviewer.

| department | head | reviewer when the head is the author |
|---|---|---|
| exec | ceo | (escalates — none available) |
| growth | sales_director | brief |
| customer_experience | followup | brief |
| marketplace | procurement | supplier_verification |
| product_eng | cto | model_evaluator |
| data_intel | intel_director | knowledge_validator |
| finance | cfo | brief |
| legal | legal | compliance_mgr |
| people_ops | ops_director | brief |
| assurance | qa_manager | ai_qa_specialist |
