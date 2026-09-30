# QuotesDone — the company roster

Generated 2026-08-14 from `htdblwldjkcgjvmqkbeh` by `scripts/kb/v3_roster_report.mjs`.
Never hand-maintained: re-run it and it tells you what is actually there.

**93 active AI employees** across **25 departments**, plus **86 on-demand category specialists** that are overlays on the route catalogue rather than standing agents.

An agent can hold more than one packaged role identity: where a department has no separate
analyst or reviewer, its director carries that archetype as a second hat. That is why the
archetype column sometimes lists two or three.

## Marketplace & Procurement

`procurement` — packaged as `marketplace_operations` · 8 active

> Run intake->match->quote->reveal at high match & quote quality.

| agent | role | archetype | manager | runs | tasks | readiness |
|---|---|---|---|---|---|---|
| `procurement` | Procurement Director | director | brief | 22 | 29 | restricted_to_advisory |
| `quote_evaluation` | Quote Evaluation Specialist | analyst-controller | procurement | 0 | 6 | restricted_to_advisory |
| `supplier_verification` | Supplier Verification Specialist | reviewer-auditor | procurement | 0 | 4 | restricted_to_advisory |
| `spec_commercial` | Commercial Services Specialist | operations-specialist | procurement | 0 | 4 | restricted_to_advisory |
| `spec_construction` | Construction & Civil Specialist | operations-specialist | procurement | 0 | 6 | restricted_to_advisory |
| `spec_fitout` | Interior & Fit-Out Specialist | operations-specialist | procurement | 0 | 6 | restricted_to_advisory |
| `spec_industrial` | Industrial & Energy Specialist | operations-specialist | procurement | 0 | 6 | restricted_to_advisory |
| `spec_mep` | MEP Specialist | operations-specialist | procurement | 0 | 6 | restricted_to_advisory |

## Marketing

`marketing` — packaged as `marketing` · 6 active (1 inactive)

> Generate qualified demand: content, SEO, social, ads, brand.

| agent | role | archetype | manager | runs | tasks | readiness |
|---|---|---|---|---|---|---|
| `marketing` | Marketing Director | director, reviewer-auditor | brief | 6 | 8 | decision_trace_connected |
| `marketing_analyst` | Marketing Analyst | analyst-controller | marketing | 0 | 5 | live_data_connected |
| `brand_mgr` | Brand Manager | operations-specialist | marketing | 0 | 6 | live_data_connected |
| `marketing_content` | Content Strategist | operations-specialist | marketing | 0 | 7 | live_data_connected |
| `marketing_copy` *(inactive)* | Copywriter | operations-specialist | marketing | 0 | 1 | blocked |
| `marketing_design` | Graphic Design Director | operations-specialist | marketing | 0 | 6 | live_data_connected |
| `marketing_social` | Social Media Manager | operations-specialist | marketing | 0 | 6 | live_data_connected |

## Customer Success

`customer_success` — packaged as `customer_success` · 5 active

> Own the customer journey: activation, response, satisfaction, fair refunds.

| agent | role | archetype | manager | runs | tasks | readiness |
|---|---|---|---|---|---|---|
| `followup` | Customer Success Director | analyst-controller, director, reviewer-auditor | brief | 59 | 2 | restricted_to_advisory |
| `cs_onboarding` | Customer Onboarding Specialist | operations-specialist | followup | 0 | 3 | restricted_to_advisory |
| `cs_retention` | Customer Retention Specialist | operations-specialist | followup | 0 | 5 | restricted_to_advisory |
| `cs_support` | Customer Support Specialist | operations-specialist | followup | 0 | 4 | restricted_to_advisory |
| `rfq_success` | RFQ Success Specialist | operations-specialist | followup | 0 | 1 | restricted_to_advisory |

## Finance

`finance` — packaged as `finance` · 5 active

> Own the money: books correct, cash visible, dues collected, spend controlled.

| agent | role | archetype | manager | runs | tasks | readiness |
|---|---|---|---|---|---|---|
| `cfo` | Finance Director | director, reviewer-auditor | brief | 4 | 15 | restricted_to_advisory |
| `bookkeeper` | Accountant | analyst-controller | cfo | 0 | 5 | restricted_to_advisory |
| `financial_analyst` | Financial Analyst | analyst-controller | cfo | 0 | 5 | restricted_to_advisory |
| `ap_specialist` | Accounts Payable Specialist | operations-specialist | cfo | 0 | 5 | restricted_to_advisory |
| `collections` | Accounts Receivable Specialist | operations-specialist | cfo | 19 | 5 | restricted_to_advisory |

## AI Department

`ai_dept` — packaged as `ai_model_ops` · 4 active

> AI agents, knowledge base, RAG, prompt engineering, model evaluation, agent testing, AI monitoring and AI improvement. The specification states explicitly that this is NOT Engineering.

| agent | role | archetype | manager | runs | tasks | readiness |
|---|---|---|---|---|---|---|
| `ai_director` | AI Director | analyst-controller, director, reviewer-auditor | brief | 3 | 1 | runtime_mapped |
| `ai_architect` | AI Architect | operations-specialist | ai_director | 0 | 1 | knowledge_imported |
| `model_evaluator` | Model Evaluation & Guardrails Specialist | operations-specialist | ai_director | 0 | 0 | knowledge_imported |
| `prompt_engineer` | Prompt Engineer | operations-specialist | ai_director | 0 | 0 | knowledge_imported |

## Engineering

`engineering` — packaged as `engineering` · 4 active

> Backend, frontend, mobile, API and the application itself. Build and ship the platform. Distinct from IT & Cybersecurity, which runs it, and from the AI Department, which owns the intelligence.

| agent | role | archetype | manager | runs | tasks | readiness |
|---|---|---|---|---|---|---|
| `eng_manager` | Engineering Manager | analyst-controller, director, reviewer-auditor | cto | 0 | 0 | runtime_mapped |
| `backend_engineer` | Backend Engineer | operations-specialist | eng_manager | 0 | 4 | knowledge_imported |
| `frontend_engineer` | Frontend Engineer | operations-specialist | eng_manager | 0 | 1 | knowledge_imported |
| `solution_architect` | Solution Architect | operations-specialist | eng_manager | 0 | 1 | knowledge_imported |

## Executive Office

`exec` — packaged as `executive_office` · 4 active

> Run the company against the founder's objectives with minimal founder intervention; be the single interface.

| agent | role | archetype | manager | runs | tasks | readiness |
|---|---|---|---|---|---|---|
| `ceo` | CEO AI | analyst-controller, director, reviewer-auditor | — | 2 | 18 | restricted_to_advisory |
| `brief` | Chief of Staff | operations-specialist | ceo | 91 | 7 | restricted_to_advisory |
| `cpo` | Chief Performance Officer | operations-specialist | ceo | 0 | 16 | restricted_to_advisory |
| `strategy_director` | Strategy & Performance Director | operations-specialist | ceo | 0 | 6 | restricted_to_advisory |

## HR & People Operations

`hr` — packaged as `hr_people` · 4 active

> Recruit, onboard, develop and manage performance of every employee in the company.

| agent | role | archetype | manager | runs | tasks | readiness |
|---|---|---|---|---|---|---|
| `hr_director` | HR Director | analyst-controller, director, reviewer-auditor | brief | 2 | 1 | restricted_to_advisory |
| `culture_performance_mgr` | Culture & Performance Manager | operations-specialist | hr_director | 0 | 1 | restricted_to_advisory |
| `learning_dev_mgr` | Learning & Development Manager | operations-specialist | hr_director | 0 | 0 | restricted_to_advisory |
| `recruitment_specialist` | Recruitment Specialist | operations-specialist | hr_director | 0 | 0 | restricted_to_advisory |

## Intelligence

`intelligence` — packaged as `data_analytics` · 4 active

> Owns analytics, KPI instrumentation, forecasting, and market, competitive, supplier and customer intelligence.

| agent | role | archetype | manager | runs | tasks | readiness |
|---|---|---|---|---|---|---|
| `intel_director` | Intelligence Director | director | ceo | 8 | 14 | runtime_mapped |
| `forecast_analyst` | Forecasting Analyst | analyst-controller | intel_director | 0 | 1 | knowledge_imported |
| `market_analyst` | Market Intelligence Analyst | analyst-controller | intel_director | 0 | 3 | knowledge_imported |
| `supplier_analyst` | Supplier & Customer Analyst | analyst-controller | intel_director | 0 | 0 | knowledge_imported |

## Administration & Operations

`knowledge` — packaged as `admin_operations` · 4 active

> Process, quality, project coordination and document control across the company.

| agent | role | archetype | manager | runs | tasks | readiness |
|---|---|---|---|---|---|---|
| `ops_director` | Operations Director | director, reviewer-auditor | brief | 0 | 14 | decision_trace_connected |
| `process_improvement_mgr` | Process Improvement Manager | analyst-controller | ops_director | 0 | 11 | live_data_connected |
| `docs` | Documentation Manager | operations-specialist | ops_director | 97 | 7 | decision_trace_connected |
| `project_coordinator` | Project Coordinator | operations-specialist | ops_director | 0 | 7 | live_data_connected |

## Legal & Compliance

`legal` — packaged as `legal_compliance` · 4 active

> Keep the company compliant and defensible; never auto-decide legal judgment.

| agent | role | archetype | manager | runs | tasks | readiness |
|---|---|---|---|---|---|---|
| `legal` | Legal Counsel | analyst-controller, director | brief | 2 | 12 | restricted_to_advisory |
| `compliance_mgr` | Compliance Manager | reviewer-auditor | legal | 0 | 7 | restricted_to_advisory |
| `risk_governance_mgr` | Risk & Governance Manager | reviewer-auditor | legal | 0 | 6 | restricted_to_advisory |
| `contract_specialist` | Contract Specialist | operations-specialist | legal | 0 | 7 | restricted_to_advisory |

## Data & Analytics

`analytics` — packaged as `data_analytics` · 3 active

> Dashboards, KPIs, business intelligence, reporting, supplier analytics, customer analytics and predictive analytics. Own the numbers everybody else argues with.

| agent | role | archetype | manager | runs | tasks | readiness |
|---|---|---|---|---|---|---|
| `analytics_director` | Data & Analytics Director | director, operations-specialist, reviewer-auditor | brief | 1 | 0 | runtime_mapped |
| `analytics` | Data & Analytics Engineer | analyst-controller | analytics_director | 0 | 4 | knowledge_imported |
| `bi_analyst` | Business Intelligence Analyst | analyst-controller | analytics_director | 0 | 3 | knowledge_imported |

## Business Development

`bizdev` — packaged as `business_development` · 3 active

> Partnerships, government relations, new markets and strategic alliances. Grow the company through relationships rather than transactions.

| agent | role | archetype | manager | runs | tasks | readiness |
|---|---|---|---|---|---|---|
| `bd` | Business Development Manager | analyst-controller, director, reviewer-auditor | brief | 0 | 0 | runtime_mapped |
| `gov_relations_mgr` | Government & Enterprise Relations Manager | operations-specialist | bd | 0 | 0 | knowledge_imported |
| `partnerships_mgr` | Partnerships Manager | operations-specialist | bd | 0 | 0 | knowledge_imported |

## Notification & Communication

`comms` — packaged as `communications` · 3 active

> Email, SMS, WhatsApp, push notifications, reminders and follow-ups. One customer brain, many channels: own deliverability, identity and cadence across every one of them.

| agent | role | archetype | manager | runs | tasks | readiness |
|---|---|---|---|---|---|---|
| `comms_manager` | Notification & Communication Manager | analyst-controller, director, reviewer-auditor | brief | 3 | 0 | runtime_mapped |
| `channel_specialist` | Channel & Deliverability Specialist | operations-specialist | comms_manager | 0 | 2 | knowledge_imported |
| `notification_ops` | Notification Operations Specialist | operations-specialist | comms_manager | 0 | 2 | knowledge_imported |

## Document Intelligence

`doc_intelligence` — packaged as `document_intelligence` · 3 active

> Understand every uploaded file: BOQs, drawings, CAD, PDFs, images, specifications, datasheets and contracts. Turn documents into structured requirements the rest of the company can act on.

| agent | role | archetype | manager | runs | tasks | readiness |
|---|---|---|---|---|---|---|
| `doc_intel_manager` | Document Intelligence Manager | director, operations-specialist, reviewer-auditor | brief | 0 | 2 | runtime_mapped |
| `boq_analyst` | BOQ & Specification Analyst | analyst-controller | doc_intel_manager | 0 | 3 | knowledge_imported |
| `drawing_analyst` | Drawing & CAD Analyst | analyst-controller | doc_intel_manager | 0 | 0 | knowledge_imported |

## Evolution

`evolution` — packaged as `strategy_evolution` · 3 active

> Owns innovation intake, the improvement loop, the outcome ledger, performance and cost optimisation, and organisational design.

| agent | role | archetype | manager | runs | tasks | readiness |
|---|---|---|---|---|---|---|
| `innovation_mgr` | Innovation Manager | director, reviewer-auditor | cpo | 0 | 11 | knowledge_imported |
| `optimisation_eng` | Optimisation Engineer | analyst-controller | cpo | 0 | 11 | knowledge_imported |
| `org_designer` | Organisational Designer | operations-specialist | cpo | 0 | 8 | knowledge_imported |

## IT & Cybersecurity

`it` — packaged as `it_cybersecurity` · 3 active

> Networks, cloud, security, identity management, disaster recovery, monitoring and compliance. Run the platform and keep it safe. Also formally owns AI Model Operations jointly with the AI Department: routing policy, per-department AI budgets, cache policy and cost telemetry, as implemented in ai_gateway / fn_ai_route / model_policy / ai_cost_log.

| agent | role | archetype | manager | runs | tasks | readiness |
|---|---|---|---|---|---|---|
| `cto` | CTO AI | analyst-controller, director | brief | 0 | 13 | restricted_to_advisory |
| `security` | Cybersecurity Manager | reviewer-auditor | cto | 1244 | 6 | restricted_to_advisory |
| `it` | DevOps & Infrastructure Manager | operations-specialist | cto | 5 | 7 | restricted_to_advisory |

## Knowledge Engineering

`knowledge_eng` — packaged as `knowledge_learning` · 3 active

> Owns everything the company knows: the knowledge base, retrieval, embeddings, validation, decay and the auto-learning exam loop.

| agent | role | archetype | manager | runs | tasks | readiness |
|---|---|---|---|---|---|---|
| `knowledge_director` | Knowledge Director | analyst-controller, director | ceo | 0 | 10 | decision_trace_connected |
| `knowledge_validator` | Knowledge Validator | reviewer-auditor | knowledge_director | 0 | 11 | live_data_connected |
| `kb_engineer` | Knowledge Engineer | operations-specialist | knowledge_director | 0 | 10 | live_data_connected |

## QA & Testing

`qa` — packaged as `qa_testing` · 3 active

> Software QA, AI QA, regression testing, RFQ accuracy testing and automation testing. Own the gate that says a change is safe to ship.

| agent | role | archetype | manager | runs | tasks | readiness |
|---|---|---|---|---|---|---|
| `qa_manager` | Quality Assurance Manager | analyst-controller, director, operations-specialist | brief | 0 | 7 | runtime_mapped |
| `ai_qa_specialist` | AI Quality Assurance Specialist | reviewer-auditor | qa_manager | 0 | 6 | knowledge_imported |
| `test_automation_eng` | Test Automation Engineer | reviewer-auditor | qa_manager | 0 | 6 | knowledge_imported |

## RFQ & Inquiry Intelligence

`rfq_intelligence` — packaged as `rfq_intelligence` · 3 active

> The core product. Own inquiry intake, qualification, missing-information detection, document and drawing analysis, inquiry scoring and the routing of every RFQ to the right specialist desk.

| agent | role | archetype | manager | runs | tasks | readiness |
|---|---|---|---|---|---|---|
| `rfq_qualification_mgr` | RFQ Qualification Manager | director, reviewer-auditor | brief | 3 | 0 | runtime_mapped |
| `inquiry_scoring` | Inquiry Scoring & Validation Analyst | analyst-controller | rfq_qualification_mgr | 0 | 1 | knowledge_imported |
| `inquiry_router` | AI Inquiry Router | operations-specialist | rfq_qualification_mgr | 0 | 6 | knowledge_imported |

## Sales & CRM

`sales` — packaged as `sales_crm` · 3 active

> Own pipeline, partnerships and revenue growth against the company revenue goal.

| agent | role | archetype | manager | runs | tasks | readiness |
|---|---|---|---|---|---|---|
| `sales_director` | Sales Director | analyst-controller, director, reviewer-auditor | brief | 1 | 10 | restricted_to_advisory |
| `account_mgr` | Account Manager | operations-specialist | sales_director | 0 | 5 | restricted_to_advisory |
| `crm_pipeline_mgr` | CRM & Pipeline Manager | operations-specialist | sales_director | 0 | 5 | restricted_to_advisory |

## Supplier Knowledge

`supplier_knowledge` — packaged as `supplier_knowledge` · 3 active

> Own the supplier taxonomy, category definitions, industry standards and product catalogues. Keep the 84 trade categories and the knowledge behind each of them current, deduplicated and complete.

| agent | role | archetype | manager | runs | tasks | readiness |
|---|---|---|---|---|---|---|
| `taxonomy_manager` | Supplier Taxonomy Manager | director, reviewer-auditor | brief | 0 | 0 | runtime_mapped |
| `supplier_intel_analyst` | Supplier Intelligence Analyst | analyst-controller | taxonomy_manager | 0 | 3 | knowledge_imported |
| `category_curator` | Category Knowledge Curator | operations-specialist | taxonomy_manager | 0 | 3 | knowledge_imported |

## Supplier Success

`supplier_success` — packaged as `supplier_success` · 3 active

> Acquire, onboard, verify, activate and retain suppliers.

| agent | role | archetype | manager | runs | tasks | readiness |
|---|---|---|---|---|---|---|
| `onboarding` | Supplier Success Manager | director, reviewer-auditor | procurement | 1273 | 8 | runtime_mapped |
| `supplier_coverage` | Supplier Coverage Specialist | analyst-controller | onboarding | 0 | 0 | knowledge_imported |
| `supplier_retention` | Supplier Retention Specialist | operations-specialist | onboarding | 0 | 0 | knowledge_imported |

## Trust & Safety

`trust_safety` — packaged as `trust_safety` · 3 active

> Fraud detection, spam prevention, fake suppliers and fake RFQs, content moderation and user verification. Own the risk score behind every account on the platform.

| agent | role | archetype | manager | runs | tasks | readiness |
|---|---|---|---|---|---|---|
| `trust_safety_mgr` | Trust & Safety Manager | analyst-controller, director, operations-specialist | brief | 0 | 0 | runtime_mapped |
| `fraud_analyst` | Fraud & Risk Analyst | reviewer-auditor | trust_safety_mgr | 0 | 0 | knowledge_imported |
| `moderation_specialist` | Content Moderation Specialist | reviewer-auditor | trust_safety_mgr | 0 | 0 | knowledge_imported |

## Payment

`payments` — packaged as `payments_revenue` · 2 active

> Payment gateway, subscription management, refunds, commission management and reconciliation of money in and out of the platform.

| agent | role | archetype | manager | runs | tasks | readiness |
|---|---|---|---|---|---|---|
| `payments_manager` | Payments Manager | analyst-controller, director, reviewer-auditor | cfo | 0 | 0 | runtime_mapped |
| `billing_specialist` | Billing & Reconciliation Specialist | operations-specialist | payments_manager | 0 | 0 | knowledge_imported |

## On-demand category specialists

These are the 86 packaged category identities. They are not standing agents — the company
does not run 182 employees. Each is an overlay retrieved at inquiry time by
`fn_category_checklist`, and each owns its own question bank, mandatory-field list and
never-infer list.

| # | route | category identity | readiness |
|---|---|---|---|
| 1 | `opcat-001` | Construction Materials Suppliers | decision_trace_connected |
| 2 | `opcat-002` | Steel & Reinforcement Suppliers | decision_trace_connected |
| 3 | `opcat-003` | Cement & Concrete Suppliers | decision_trace_connected |
| 4 | `opcat-004` | Formwork & Scaffolding Suppliers | decision_trace_connected |
| 5 | `opcat-005` | Waterproofing Suppliers | decision_trace_connected |
| 6 | `opcat-006` | Insulation Suppliers | decision_trace_connected |
| 7 | `opcat-007` | Roofing Suppliers | decision_trace_connected |
| 8 | `opcat-008` | MEP Suppliers / Electromechanical Suppliers | decision_trace_connected |
| 9 | `opcat-009` | HVAC Suppliers | decision_trace_connected |
| 10 | `opcat-010` | Electrical Suppliers | decision_trace_connected |
| 11 | `opcat-011` | Plumbing & Sanitaryware Suppliers | decision_trace_connected |
| 12 | `opcat-012` | Fire Fighting Equipment Suppliers | decision_trace_connected |
| 13 | `opcat-013` | Fire Alarm & Life Safety Suppliers | decision_trace_connected |
| 14 | `opcat-014` | ELV & Security Systems Suppliers | decision_trace_connected |
| 15 | `opcat-015` | Smart Home & Home Automation Suppliers | decision_trace_connected |
| 16 | `opcat-016` | Fit-Out Contractors / Interior Fit-Out Suppliers | decision_trace_connected |
| 17 | `opcat-017` | Gypsum & False Ceiling Suppliers | decision_trace_connected |
| 18 | `opcat-018` | Flooring Suppliers | decision_trace_connected |
| 19 | `opcat-019` | Aluminium & Glass Suppliers | decision_trace_connected |
| 20 | `opcat-020` | Joinery & Carpentry Suppliers | decision_trace_connected |
| 21 | `opcat-021` | Paints & Finishing Materials Suppliers | decision_trace_connected |
| 22 | `opcat-022` | Interior Decoration | decision_trace_connected |
| 23 | `opcat-023` | Furniture Suppliers / FF&E Suppliers | decision_trace_connected |
| 24 | `opcat-024` | Kitchen & Bathroom Suppliers | decision_trace_connected |
| 25 | `opcat-025` | Swimming Pool Suppliers & Contractors | decision_trace_connected |
| 26 | `opcat-026` | Cold Room & Refrigeration Suppliers | decision_trace_connected |
| 27 | `opcat-027` | Catering Companies | decision_trace_connected |
| 28 | `opcat-028` | Hospitality Supplies Companies | decision_trace_connected |
| 29 | `opcat-029` | Bakery Equipment Suppliers | decision_trace_connected |
| 30 | `opcat-030` | Food Processing Equipment Suppliers | decision_trace_connected |
| 31 | `opcat-031` | Event Management Companies | decision_trace_connected |
| 32 | `opcat-032` | Exhibition Stand Contractors | decision_trace_connected |
| 33 | `opcat-033` | AV & Media Equipment Suppliers | decision_trace_connected |
| 34 | `opcat-034` | Marketing & Advertising Agencies | decision_trace_connected |
| 35 | `opcat-035` | IT Companies / IT Services Providers | decision_trace_connected |
| 36 | `opcat-036` | Data Centre Suppliers & Service Providers | decision_trace_connected |
| 37 | `opcat-037` | Telecommunication Companies | decision_trace_connected |
| 38 | `opcat-038` | Accounting & Audit Firms | decision_trace_connected |
| 39 | `opcat-039` | Tax Consultants | decision_trace_connected |
| 40 | `opcat-040` | Corporate Service Providers / PRO Services | decision_trace_connected |
| 41 | `opcat-041` | Law Firms | decision_trace_connected |
| 42 | `opcat-042` | Management Consulting Firms | decision_trace_connected |
| 43 | `opcat-043` | HR & Recruitment Agencies | decision_trace_connected |
| 44 | `opcat-044` | Staffing Companies | decision_trace_connected |
| 45 | `opcat-045` | Facilities Management Companies | decision_trace_connected |
| 46 | `opcat-046` | Cleaning Companies | decision_trace_connected |
| 47 | `opcat-047` | Security Companies | decision_trace_connected |
| 48 | `opcat-048` | Business Centres & Coworking Spaces | decision_trace_connected |
| 49 | `opcat-049` | Logistics & Freight Forwarding Companies | decision_trace_connected |
| 50 | `opcat-050` | Warehousing & 3PL Companies | decision_trace_connected |
| 51 | `opcat-051` | Oil & Gas Equipment Suppliers | decision_trace_connected |
| 52 | `opcat-052` | Industrial Equipment Suppliers | decision_trace_connected |
| 53 | `opcat-053` | Industrial Automation Suppliers | decision_trace_connected |
| 54 | `opcat-054` | Bearings & Power Transmission Suppliers | decision_trace_connected |
| 55 | `opcat-055` | Fasteners & Fixings Suppliers | decision_trace_connected |
| 56 | `opcat-056` | Tools & Abrasives Suppliers | decision_trace_connected |
| 57 | `opcat-057` | Air Compressor & Pneumatic Suppliers | decision_trace_connected |
| 58 | `opcat-058` | Chemical Suppliers | decision_trace_connected |
| 59 | `opcat-059` | Laboratory Equipment Suppliers | decision_trace_connected |
| 60 | `opcat-060` | Cleanroom Suppliers & Contractors | decision_trace_connected |
| 61 | `opcat-061` | Medical Equipment Suppliers | decision_trace_connected |
| 62 | `opcat-062` | Pharmaceutical Suppliers | decision_trace_connected |
| 63 | `opcat-063` | Education Equipment Suppliers | decision_trace_connected |
| 64 | `opcat-064` | Aviation & Ground Support Suppliers | decision_trace_connected |
| 65 | `opcat-065` | Marine Equipment & Marine Safety Suppliers | decision_trace_connected |
| 66 | `opcat-066` | Offshore & Marine Construction Companies | decision_trace_connected |
| 67 | `opcat-067` | Renewable Energy Companies (Solar, EV, Battery) | decision_trace_connected |
| 68 | `opcat-068` | Real Estate Agencies | decision_trace_connected |
| 69 | `opcat-069` | Property Management Companies | decision_trace_connected |
| 70 | `opcat-070` | Textile & Uniform Suppliers | decision_trace_connected |
| 71 | `opcat-071` | Beauty & Spa Equipment Suppliers | decision_trace_connected |
| 72 | `opcat-072` | Gym & Sports Equipment Suppliers | decision_trace_connected |
| 73 | `opcat-073` | Jewelry Suppliers / Gold & Diamond Traders | decision_trace_connected |
| 74 | `opcat-074` | Luxury & Concierge Service Providers | decision_trace_connected |
| 75 | `opcat-075` | Travel Agencies | decision_trace_connected |
| 76 | `opcat-076` | Domestic Services Companies (Maids, Care) | decision_trace_connected |
| 77 | `opcat-077` | Pet Care & Veterinary Services | decision_trace_connected |
| 78 | `opcat-078` | Translation & Interpretation Companies | decision_trace_connected |
| 79 | `opcat-079` | Tender & Bid Management Consultants | decision_trace_connected |
| 80 | `opcat-080` | Testing, Inspection & Certification Companies | decision_trace_connected |
| 81 | `opcat-081` | Modular & Prefab Building Suppliers | decision_trace_connected |
| 82 | `opcat-082` | Gas Systems Suppliers (LPG, Medical Gas, Industrial Gas) | decision_trace_connected |
| 83 | `opcat-083` | Utility Contractors (DEWA / SEWA / FEWA approved) | decision_trace_connected |
| 84 | `opcat-084` | Wastewater & Drainage Contractors | decision_trace_connected |
| 85 | `opcat-085` | Signage & Printing Suppliers | decision_trace_connected |
| 86 | `opcat-086` | Lifts & Escalator Suppliers | decision_trace_connected |
