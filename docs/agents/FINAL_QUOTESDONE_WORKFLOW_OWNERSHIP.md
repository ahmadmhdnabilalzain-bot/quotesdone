# QuotesDone workflow ownership — who owns which step

Written 15 August 2026. Every claim here is a query against production and staging, and every one
of them is re-run by `scripts/checks/workflow_ownership_alignment.test.mjs` (56/56 on both
projects, zero model calls).

The registry is `workflow_step (workflow_key, step_no, step, actor_role, action_class, gate)`.
`actor_role` is the **accountable owner** of that step and is always a real employee that
`fn_org_agent_resolve` or `fn_org_role_resolve` returns. It is never an overlay and never a
placeholder.

## What was wrong before

| | |
|---|---|
| `rfq_handling` #5 "Select suppliers" | actor was `domain specialist` — resolves to nobody |
| `rfq_handling` #6 "Send RFQ" | actor was `Procurement Director`; `procurement` is a merged-away department key |
| document processing, readiness scoring, supplier-safe approval, message delivery | **no steps existed at all** |
| owners of `rfq_handling` in `employee_workflow` | **ten** |
| roles named by nothing on any of seven surfaces | **20 of 90** |
| `employee_workflow` rows | 157 on production, **0 on staging** |
| `payment` steps 2–5 | the desk that took the money reconciled its own charge |

An overlay cannot be accountable for anything — it has no runtime agent. Letting one own a step is
how `domain specialist` came to own supplier selection.

## Customer inquiry → quotation (`rfq_handling`, 18 steps)

| # | Step | Accountable owner | Gate |
|---|---|---|---|
| 1 | Registration and initial guidance | Customer Onboarding Specialist | — |
| 2 | Inquiry conversation and completeness | RFQ Qualification Manager | — |
| 3 | Route candidates: category and primary trade | Inquiry Router | — |
| 4 | Technical qualification against the matching category overlay (one of the 86, on demand) | Inquiry Router | — |
| 5 | Multi-category conflict: invoke the broad domain specialist for the primary trade, only when no single overlay owns the question | RFQ Qualification Manager | — |
| 6 | Document processing | Document Intelligence Manager | — |
| 7 | BOQ and specification analysis, where supplied | BOQ & Specification Analyst | — |
| 8 | Drawing and CAD analysis, where supplied | Drawing & CAD Analyst | — |
| 9 | Quality and readiness assessment | Inquiry Quality & Scoring Analyst | — |
| 10 | **Supplier-safe payload and file approval** — the actual payload, files and redacted drawings | Marketplace Content & Privacy Reviewer | review |
| 11 | **Supplier eligibility, matching, idempotent assignment, one notification per supplier, reason recorded for every selection and exclusion** | Supplier Matching & Dispatch Operator | — |
| 12 | Message delivery on the consented channel | Lifecycle Channel Operations Specialist | — |
| 13 | Receive quotations and normalise them | Quote Evaluation Specialist | — |
| 14 | Technical comparison, invoking the overlay and a broad specialist only where needed | Quote Evaluation Specialist | — |
| 15 | Recommend the winning quotation | Marketplace Director | dept_head |
| 16 | Keep the customer moving, close the inquiry | RFQ Success Specialist | — |
| 17 | Collect feedback from both sides | Customer Success Director | — |
| 18 | Trace the cause and correct it | Process Improvement Manager | — |

Steps 10 and 11 are the two gaps the instruction names. They did not exist.

**Customer acquisition** sits upstream of this chain in `lead_to_customer`, owned by Growth &
Revenue: CRM & Revenue Operations Manager → Account Manager → Chief Revenue Officer → Brand &
Creative Manager (review) → Customer Onboarding Specialist (handover), with the Government &
Enterprise Relations Manager owning the counterparty step where procurement rules apply.

## Supplier journey (`supplier_onboarding`, 9 steps)

| # | Step | Accountable owner | Gate |
|---|---|---|---|
| 1 | Supplier registration received | Supplier Onboarding Specialist | — |
| 2 | Verify trade licence and its documents | Supplier Verification Reviewer | — |
| 3 | Verify certifications and declared capability | Supplier Verification Reviewer | — |
| 4 | Compliance screen before activation | Compliance & Privacy Officer | review |
| 5 | Approve or reject the supplier | Supplier Verification Reviewer | dept_head |
| 6 | Activate, coach, confirm it can receive an inquiry | Supplier Onboarding Specialist | — |
| 7 | Coverage and category gaps | Supplier Coverage & Liquidity Specialist | — |
| 8 | Disengagement and retention | Supplier Retention Specialist | — |
| 9 | Measure and learn | Process Improvement Manager | — |

Quotation completeness and normalisation is `rfq_handling` #13–14 (Quote Evaluation Specialist);
technical comparison invokes the category overlay first and a broad domain specialist only where
the comparison needs one.

## Comparison, reveal and post-reveal (`payment`, 8 steps)

| # | Step | Accountable owner |
|---|---|---|
| 1 | Customer chooses a quote and requests the reveal | RFQ Success Specialist |
| 2 | Compute the reveal fee from the quote and the live fee policy | Payments & Billing Manager |
| 3 | Take payment through Stripe | Payments & Billing Manager |
| 4 | Write the transaction; release supplier contact details **only** on a confirmed charge | Payments & Billing Manager |
| 5 | Reconcile the charge and flag any charge without a reveal | Billing & Reconciliation Specialist |
| 6 | Post to the ledger, issue the receipt | Financial Controller |
| 7 | Start the supplier response clock | Customer Success Director |
| 8 | Measure conversion, feed revenue_annual | Chief Financial Officer |

**The reveal-fee percentage itself is founder-reserved.** Step 2 applies it; nothing in the company
may set it — enforced by `trg_org_role_no_reserved_decision`.

The split at step 5 is the correction. Before, steps 2–4 were the Billing & Reconciliation
Specialist and step 5 was "the Accountant" — which is a recorded alias of the same employee
(`Accountant` → `bookkeeper`, and so is `financial_controller`). Reconciliation exists to flag a
charge that should not have happened; a desk cannot flag its own.

Refund, dispute and fraud escalate through `refund` (10 steps), where step 7 is an absolute,
non-delegable founder gate: **no agent may execute a Stripe refund.**

## Company learning

| Concern | Workflow | Owner |
|---|---|---|
| Metric collection and instrumentation | `metric_lifecycle` | Data & Intelligence Director, Forecasting Analyst |
| Reporting the actual to whoever must act | `metric_lifecycle` #7 | Business Intelligence Analyst |
| Company and department diagnosis | `metric_lifecycle`, `strategic_review` | Chief Performance Officer, department heads |
| Corrective task assignment | `improvement_lifecycle` | the responsible manager |
| Competency remediation | `improvement_lifecycle` #10 | Agent & Prompt Engineer, then offline evaluation |
| Structural remediation | `improvement_lifecycle` #9 | Organisation Design Lead |
| Knowledge remediation | `knowledge_lifecycle` | Knowledge Engineer, Knowledge Validator |
| Category coverage / taxonomy | `knowledge_lifecycle` #8–9 | Category Knowledge Curator, Taxonomy Governance Manager |
| Budget and resource decisions | `budget_cycle` | CFO within authority; above it, the founder |

## Change and release (`change_deployment`, 9 steps)

Producing the evidence and ruling on it are now separate steps, because they were not:

3 Implement (Engineering Manager) → 4 Offline evaluation (Model Evaluation Reviewer) → 5 Build and
run the suites (Test Automation Engineer) → 6 Deploy to preview (Frontend Engineer) → **7 Release
go/no-go (QA & Release Management Director), reading evidence it did not produce** → 8 Promote
(CTO) → 9 Grade against the baseline; reverse if worse (Chief Performance Officer).

## One accountable owner per workflow

`employee_workflow.role_in_workflow = 'owner'` is now exactly one agent per workflow:
`rfq_handling` → Marketplace Director, `supplier_onboarding` → Supplier Onboarding Specialist,
`invoice_approval` → CFO, `campaign_publishing` → Marketing Director.

**`employee_task` is the deliberate exception** and keeps its 43 owners: it is the generic
per-employee task loop, so every employee owns their own instance. Its steps name `owner` and
`Director` as placeholders bound per run — and 2,901 recorded step runs show them binding to real
employees, never staying as the placeholder. One row did not bind: a department-head review queued
since 10 August, addressed to "Director", which no employee answers to. It has been bound to the
head its own run already recorded, and `trg_step_run_actor_is_a_real_employee` now refuses to queue
a step to an actor that resolves to nobody.

## Cost and orchestration

A typical inquiry invokes only the roles its state needs. Deterministic code — not a model — decides
permissions, eligibility filters, capability matching, completeness, idempotency and state
transitions: `fn_inquiry_dispatch_eligible`, `fn_match_capability`, `a00_unsafe_match_eligibility`,
`fn_freeze_supplier_brief`. The Supplier Matching & Dispatch Operator is on
`routine_employee_reasoning`, the cheapest tier, because the adjudication happens in
`route_inquiry` and what is left for a model is summarising a refusal. The 86 category overlays and
the four broad specialists are on-demand and are invoked only when a workflow reaches them.
