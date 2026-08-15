# Exact Primary Model Assignment by Role

The primary model is the default after deterministic task classification. Task class, modality, risk, cost and independent-review rules may override it.

## Executive & Strategy

| Role | Runtime mode | Primary | Fallback | Independent review | Critical escalation |
|---|---|---|---|---|---|
| `ceo` | `persistent_manager` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `openai/gpt-5.2:exacto` | `anthropic/claude-opus-5` |
| `chief_of_staff` | `persistent_manager` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `openai/gpt-5.2:exacto` | `anthropic/claude-opus-5` |
| `strategy_director` | `scheduled_manager` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `openai/gpt-5.2:exacto` | `anthropic/claude-opus-5` |
| `org_designer` | `on_demand_specialist` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `policy_dependent` | `anthropic/claude-sonnet-5` |

## Growth & Revenue

| Role | Runtime mode | Primary | Fallback | Independent review | Critical escalation |
|---|---|---|---|---|---|
| `sales_director` | `scheduled_manager` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `openai/gpt-5.2:exacto` | `anthropic/claude-opus-5` |
| `marketing_director` | `event_driven_operator` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `openai/gpt-5.2:exacto` | `anthropic/claude-sonnet-5` |
| `brand_mgr` | `on_demand_specialist` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `policy_dependent` | `anthropic/claude-sonnet-5` |
| `marketing_analyst` | `event_driven_operator` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `policy_dependent` | `anthropic/claude-sonnet-5` |
| `marketing_content` | `on_demand_specialist` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `policy_dependent` | `anthropic/claude-sonnet-5` |
| `marketing_design` | `on_demand_specialist` | `google/gemini-3.6-flash` | `anthropic/claude-sonnet-5` | `policy_dependent` | `anthropic/claude-sonnet-5` |
| `marketing_social` | `event_driven_operator` | `anthropic/claude-haiku-4.5` | `anthropic/claude-sonnet-5` | `policy_dependent` | `anthropic/claude-sonnet-5` |
| `bd` | `on_demand_specialist` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `policy_dependent` | `anthropic/claude-sonnet-5` |
| `gov_relations_mgr` | `on_demand_specialist` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `policy_dependent` | `anthropic/claude-sonnet-5` |
| `partnerships_mgr` | `on_demand_specialist` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `policy_dependent` | `anthropic/claude-sonnet-5` |
| `account_mgr` | `event_driven_operator` | `anthropic/claude-haiku-4.5` | `anthropic/claude-sonnet-5` | `policy_dependent` | `anthropic/claude-sonnet-5` |
| `crm_pipeline_mgr` | `event_driven_operator` | `anthropic/claude-haiku-4.5` | `anthropic/claude-sonnet-5` | `policy_dependent` | `anthropic/claude-sonnet-5` |

## Customer Experience & Communications

| Role | Runtime mode | Primary | Fallback | Independent review | Critical escalation |
|---|---|---|---|---|---|
| `customer_success_director` | `scheduled_manager` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `openai/gpt-5.2:exacto` | `anthropic/claude-opus-5` |
| `cs_onboarding` | `event_driven_operator` | `anthropic/claude-haiku-4.5` | `anthropic/claude-sonnet-5` | `policy_dependent` | `anthropic/claude-sonnet-5` |
| `cs_retention` | `event_driven_operator` | `anthropic/claude-haiku-4.5` | `anthropic/claude-sonnet-5` | `policy_dependent` | `anthropic/claude-sonnet-5` |
| `cs_support` | `event_driven_operator` | `anthropic/claude-haiku-4.5` | `anthropic/claude-sonnet-5` | `policy_dependent` | `anthropic/claude-sonnet-5` |
| `rfq_success` | `event_driven_operator` | `anthropic/claude-haiku-4.5` | `anthropic/claude-sonnet-5` | `policy_dependent` | `anthropic/claude-sonnet-5` |
| `comms_manager` | `event_driven_operator` | `anthropic/claude-haiku-4.5` | `anthropic/claude-sonnet-5` | `policy_dependent` | `anthropic/claude-sonnet-5` |
| `channel_specialist` | `event_driven_operator` | `anthropic/claude-haiku-4.5` | `anthropic/claude-sonnet-5` | `policy_dependent` | `anthropic/claude-sonnet-5` |

## Marketplace & Supplier Network

| Role | Runtime mode | Primary | Fallback | Independent review | Critical escalation |
|---|---|---|---|---|---|
| `marketplace_director` | `persistent_manager` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `openai/gpt-5.2:exacto` | `anthropic/claude-opus-5` |
| `quote_evaluation` | `independent_reviewer` | `openai/gpt-5.2:exacto` | `anthropic/claude-sonnet-5` | `none` | `anthropic/claude-opus-5` |
| `spec_commercial` | `on_demand_specialist` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `openai/gpt-5.2:exacto` | `anthropic/claude-sonnet-5` |
| `spec_construction` | `on_demand_specialist` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `openai/gpt-5.2:exacto` | `anthropic/claude-sonnet-5` |
| `spec_fitout` | `on_demand_specialist` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `openai/gpt-5.2:exacto` | `anthropic/claude-sonnet-5` |
| `spec_industrial` | `on_demand_specialist` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `openai/gpt-5.2:exacto` | `anthropic/claude-sonnet-5` |
| `spec_mep` | `on_demand_specialist` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `openai/gpt-5.2:exacto` | `anthropic/claude-sonnet-5` |
| `supplier_verification` | `independent_reviewer` | `openai/gpt-5.2:exacto` | `anthropic/claude-sonnet-5` | `none` | `anthropic/claude-opus-5` |
| `rfq_qualification_mgr` | `event_driven_operator` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `openai/gpt-5.2:exacto` | `anthropic/claude-opus-5` |
| `inquiry_router` | `event_driven_operator` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `openai/gpt-5.2:exacto` | `anthropic/claude-sonnet-5` |
| `inquiry_scoring` | `event_driven_operator` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `openai/gpt-5.2:exacto` | `anthropic/claude-sonnet-5` |
| `taxonomy_manager` | `on_demand_specialist` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `openai/gpt-5.2:exacto` | `anthropic/claude-sonnet-5` |
| `category_curator` | `on_demand_specialist` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `openai/gpt-5.2:exacto` | `anthropic/claude-sonnet-5` |
| `supplier_onboarding_specialist` | `event_driven_operator` | `anthropic/claude-haiku-4.5` | `anthropic/claude-sonnet-5` | `policy_dependent` | `anthropic/claude-sonnet-5` |
| `supplier_coverage` | `event_driven_operator` | `anthropic/claude-haiku-4.5` | `anthropic/claude-sonnet-5` | `policy_dependent` | `anthropic/claude-sonnet-5` |
| `supplier_retention` | `event_driven_operator` | `anthropic/claude-haiku-4.5` | `anthropic/claude-sonnet-5` | `policy_dependent` | `anthropic/claude-sonnet-5` |
| `doc_intel_manager` | `event_driven_operator` | `google/gemini-3.6-flash` | `anthropic/claude-sonnet-5` | `policy_dependent` | `anthropic/claude-sonnet-5` |
| `boq_analyst` | `on_demand_specialist` | `google/gemini-3.6-flash` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `anthropic/claude-sonnet-5` |
| `drawing_analyst` | `on_demand_specialist` | `google/gemini-3.6-flash` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `anthropic/claude-sonnet-5` |

## Product, Engineering & AI

| Role | Runtime mode | Primary | Fallback | Independent review | Critical escalation |
|---|---|---|---|---|---|
| `cpo` | `persistent_manager` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `openai/gpt-5.2:exacto` | `anthropic/claude-opus-5` |
| `cto` | `on_demand_specialist` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `openai/gpt-5.2:exacto` | `anthropic/claude-opus-5` |
| `eng_manager` | `on_demand_specialist` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `openai/gpt-5.2:exacto` | `anthropic/claude-opus-5` |
| `backend_engineer` | `event_driven_operator` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `openai/gpt-5.2:exacto` | `anthropic/claude-opus-5` |
| `frontend_engineer` | `event_driven_operator` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `openai/gpt-5.2:exacto` | `anthropic/claude-sonnet-5` |
| `solution_architect` | `on_demand_specialist` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `openai/gpt-5.2:exacto` | `anthropic/claude-opus-5` |
| `ai_director` | `on_demand_specialist` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `openai/gpt-5.2:exacto` | `anthropic/claude-opus-5` |
| `ai_architect` | `on_demand_specialist` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `openai/gpt-5.2:exacto` | `anthropic/claude-opus-5` |
| `model_evaluator` | `independent_reviewer` | `openai/gpt-5.2:exacto` | `anthropic/claude-sonnet-5` | `none` | `anthropic/claude-opus-5` |
| `prompt_engineer` | `on_demand_specialist` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `openai/gpt-5.2:exacto` | `anthropic/claude-opus-5` |
| `innovation_mgr` | `on_demand_specialist` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `openai/gpt-5.2:exacto` | `anthropic/claude-opus-5` |
| `optimisation_eng` | `event_driven_operator` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `openai/gpt-5.2:exacto` | `anthropic/claude-sonnet-5` |

## Data, Intelligence & Knowledge

| Role | Runtime mode | Primary | Fallback | Independent review | Critical escalation |
|---|---|---|---|---|---|
| `intel_director` | `scheduled_manager` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `openai/gpt-5.2:exacto` | `anthropic/claude-opus-5` |
| `forecast_analyst` | `on_demand_specialist` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `policy_dependent` | `anthropic/claude-sonnet-5` |
| `market_analyst` | `on_demand_specialist` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `policy_dependent` | `anthropic/claude-sonnet-5` |
| `supplier_intelligence_analyst` | `on_demand_specialist` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `policy_dependent` | `anthropic/claude-sonnet-5` |
| `business_intelligence_analyst` | `event_driven_operator` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `policy_dependent` | `anthropic/claude-sonnet-5` |
| `bi_analyst` | `event_driven_operator` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `policy_dependent` | `anthropic/claude-sonnet-5` |
| `knowledge_director` | `on_demand_specialist` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `policy_dependent` | `anthropic/claude-sonnet-5` |
| `kb_engineer` | `event_driven_operator` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `policy_dependent` | `anthropic/claude-sonnet-5` |
| `knowledge_validator` | `independent_reviewer` | `openai/gpt-5.2:exacto` | `anthropic/claude-sonnet-5` | `none` | `anthropic/claude-opus-5` |

## Finance & Payments

| Role | Runtime mode | Primary | Fallback | Independent review | Critical escalation |
|---|---|---|---|---|---|
| `cfo` | `persistent_manager` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `openai/gpt-5.2:exacto` | `anthropic/claude-opus-5` |
| `ap_specialist` | `event_driven_operator` | `anthropic/claude-haiku-4.5` | `anthropic/claude-sonnet-5` | `policy_dependent` | `anthropic/claude-sonnet-5` |
| `bookkeeper` | `event_driven_operator` | `anthropic/claude-haiku-4.5` | `anthropic/claude-sonnet-5` | `policy_dependent` | `anthropic/claude-sonnet-5` |
| `collections` | `event_driven_operator` | `anthropic/claude-haiku-4.5` | `anthropic/claude-sonnet-5` | `policy_dependent` | `anthropic/claude-sonnet-5` |
| `financial_analyst` | `on_demand_specialist` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `openai/gpt-5.2:exacto` | `anthropic/claude-opus-5` |
| `payments_manager` | `event_driven_operator` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `openai/gpt-5.2:exacto` | `anthropic/claude-opus-5` |
| `billing_specialist` | `event_driven_operator` | `anthropic/claude-haiku-4.5` | `anthropic/claude-sonnet-5` | `policy_dependent` | `anthropic/claude-sonnet-5` |

## Legal, Compliance, Risk & Trust

| Role | Runtime mode | Primary | Fallback | Independent review | Critical escalation |
|---|---|---|---|---|---|
| `general_counsel` | `scheduled_manager` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `openai/gpt-5.2:exacto` | `anthropic/claude-opus-5` |
| `compliance_mgr` | `independent_reviewer` | `openai/gpt-5.2:exacto` | `anthropic/claude-sonnet-5` | `none` | `anthropic/claude-opus-5` |
| `contract_specialist` | `on_demand_specialist` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `openai/gpt-5.2:exacto` | `anthropic/claude-opus-5` |
| `risk_governance_mgr` | `independent_reviewer` | `openai/gpt-5.2:exacto` | `anthropic/claude-sonnet-5` | `none` | `anthropic/claude-opus-5` |
| `trust_safety_mgr` | `event_driven_operator` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `policy_dependent` | `anthropic/claude-sonnet-5` |
| `fraud_analyst` | `independent_reviewer` | `openai/gpt-5.2:exacto` | `anthropic/claude-sonnet-5` | `none` | `anthropic/claude-opus-5` |
| `moderation_specialist` | `event_driven_operator` | `anthropic/claude-haiku-4.5` | `anthropic/claude-sonnet-5` | `policy_dependent` | `anthropic/claude-sonnet-5` |

## People & Company Operations

| Role | Runtime mode | Primary | Fallback | Independent review | Critical escalation |
|---|---|---|---|---|---|
| `ops_director` | `persistent_manager` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `openai/gpt-5.2:exacto` | `anthropic/claude-opus-5` |
| `document_operations_specialist` | `event_driven_operator` | `anthropic/claude-haiku-4.5` | `anthropic/claude-sonnet-5` | `policy_dependent` | `anthropic/claude-sonnet-5` |
| `process_improvement_mgr` | `on_demand_specialist` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `policy_dependent` | `anthropic/claude-sonnet-5` |
| `project_coordinator` | `on_demand_specialist` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `policy_dependent` | `anthropic/claude-sonnet-5` |
| `hr_director` | `on_demand_specialist` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `policy_dependent` | `anthropic/claude-sonnet-5` |
| `culture_performance_mgr` | `on_demand_specialist` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `policy_dependent` | `anthropic/claude-sonnet-5` |
| `learning_dev_mgr` | `on_demand_specialist` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `policy_dependent` | `anthropic/claude-sonnet-5` |
| `recruitment_specialist` | `on_demand_specialist` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `policy_dependent` | `anthropic/claude-sonnet-5` |

## Independent Assurance, Security & Reliability

| Role | Runtime mode | Primary | Fallback | Independent review | Critical escalation |
|---|---|---|---|---|---|
| `qa_manager` | `scheduled_manager` | `anthropic/claude-sonnet-5` | `openai/gpt-5.2:exacto` | `openai/gpt-5.2:exacto` | `anthropic/claude-opus-5` |
| `ai_qa_specialist` | `independent_reviewer` | `openai/gpt-5.2:exacto` | `anthropic/claude-sonnet-5` | `none` | `anthropic/claude-opus-5` |
| `test_automation_eng` | `independent_reviewer` | `openai/gpt-5.2:exacto` | `anthropic/claude-sonnet-5` | `none` | `anthropic/claude-opus-5` |
| `it_operations_engineer` | `event_driven_operator` | `anthropic/claude-haiku-4.5` | `anthropic/claude-sonnet-5` | `policy_dependent` | `anthropic/claude-sonnet-5` |
| `cybersecurity_engineer` | `independent_reviewer` | `openai/gpt-5.2:exacto` | `anthropic/claude-sonnet-5` | `none` | `anthropic/claude-opus-5` |
