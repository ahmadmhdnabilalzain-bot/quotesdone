# Phase A — current to final, every role accounted for

The package registries use their own canonical ids. Production uses ids that are already referenced
by workflow steps, aliases, KPI rows, tool grants and routine literals. The master prompt allows for
exactly this: *"If current stable database IDs are technically safer, keep them and map the target
title/purpose through aliases. Record `EXISTING_BETTER_KEEP`; do not silently diverge."*

**EXISTING_BETTER_KEEP is recorded for every live id that already resolves to a package role.**
Renaming 87 role ids across the estate would have carried real risk — a merged-away key empties an
exact-match scope silently — for no organizational gain. `role_id` is the clear name, `agent_key`
the physical one, and both resolve through `org_role_alias` and `org_agent_alias`.

## How the 90 package roles were matched

| matched by | count |
|---|---|
| canonical id, identical on both sides | 41 |
| legacy alias already recorded in the database | 0 |
| display title | 28 |
| unmatched before Phase A — the work | 3 |

Matching was by name where ids differ, never by position. The `package_role_id` column in
`PHASE_A_CANONICAL_ROLE_REGISTRY.csv` carries the package's id for every role, so the two can be
diffed at any time.

## The four that did not match, and what happened to each

| package role | production before | action |
|---|---|---|
| `corporate_performance_director` | `chief_performance_officer` | **RENAME**. New canonical id, old id retired and aliased. Physical key `cpo` unchanged. |
| `strategic_partnerships_government_relations_manager` | `partnerships` + `government_relations` | **MERGE**. Union of both mandates and both forbidden lists — a merge that drops a forbidden decision widens authority. Reports to the CRO. |
| `product_ux_designer` | *(nothing)* | **CREATE**. Structure only; see `PHASE_A_UNRESOLVED_DECISIONS.md` §1. |
| `model_evaluation_reviewer` | `model_evaluator` in `product_eng` | **MOVE** to `assurance` under the QA & Release Director. The independence fix. |

## The ten other change rows in the package, already true before Phase A

`CURRENT_TO_FINAL_ROLE_CHANGES.csv` lists 14 changes. Ten were already applied by the 14–15 Aug
organisational pass and were verified rather than reapplied: the Organisation Design Lead already
sits in People & Company Operations; `data_engineer` already exists; the CTO already carries
"Chief Product & Technology Officer"; the Commercial Services Specialist is already the Supplier
Matching & Dispatch Operator; Content Moderation is already the Marketplace Content & Privacy
Reviewer; `marketing_copy` is already merged into the Content Strategy & Copy Specialist; the
Visual Design Director, the Test Automation Reviewer and the HR Director already carry their
narrowed titles; and the broad domain specialists are already on-demand.

The fourteenth — *"Expand scope | Financial Controller | UAE VAT/corporate-tax coordination"* — is
what retiring `tax_overlay_uae` implements.

## Department mapping

The package and the database use different department keys. They were matched on department **name**,
which both carry, rather than on id:

`exec`→`exec` · `marketplace_supplier_network`→`marketplace` · `growth_revenue`→`growth` ·
`data_intelligence_knowledge`→`data_intel` · `product_engineering_ai`→`product_eng` ·
`finance_payments`→`finance` · `legal_compliance_risk_trust`→`legal` ·
`customer_experience_communications`→`customer_experience` · `people_company_operations`→`people_ops` ·
`assurance_security_reliability`→`assurance`

All ten resolved. None was created, renamed or deleted by Phase A.
