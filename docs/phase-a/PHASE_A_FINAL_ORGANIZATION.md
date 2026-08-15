# QuotesDone — the organisation after Phase A

15 August 2026, deployed directly to production `htdblwldjkcgjvmqkbeh`. There is no staging project.

**10 active primary departments · 90 canonical accountable standing roles · 86 on-demand category
overlays.** All three were already true before Phase A ran. Phase A is not a rebuild; it is four
role corrections, two registries the invariants require, and one independence fix.

---

## The ten departments

| department | head | accountable roles |
|---|---|---|
| Executive & Strategy | Chief Executive — AI CEO | 4 |
| Marketplace & Supplier Network | Marketplace Director | 17 |
| Growth & Revenue | Chief Revenue Officer | 11 |
| Data, Intelligence & Knowledge | Data & Intelligence Director | 11 |
| Product, Engineering & AI | Chief Product & Technology Officer | 11 |
| People & Company Operations | Chief Operating Officer | 9 |
| Finance & Payments | CFO | 7 |
| Legal, Compliance, Risk & Trust | General Counsel | 7 |
| Customer Experience & Communications | Customer Success Director | 7 |
| Independent Assurance, Security & Reliability | QA & Release Management Director | 6 |

`4, 17, 11, 11, 11, 9, 7, 7, 7, 6` — the package's target multiset, matched exactly. Every head is
an active member of the department it leads.

## What Phase A changed

| | change | why |
|---|---|---|
| 1 | **RENAME** Chief Performance Officer → **Corporate Performance Director** | "Avoid CPO ambiguity and define KPI/target-gap ownership." The physical runtime key `cpo` is unchanged, so no log line, KPI row or routine literal is orphaned. |
| 2 | **MERGE** Partnerships Manager + Government & Enterprise Relations Manager → **Strategic Partnerships & Government Relations Manager** | One role, reporting to the Chief Revenue Officer rather than to Business Development. A partnership that binds the company commercially should not be scoped by the person developing the pipeline. |
| 3 | **MOVE** Model Evaluation Reviewer → **Independent Assurance** | The independence fix. See below. |
| 4 | **CREATE** Product/UX Designer | The one target role production held in no form. |
| 5 | **RETIRE** UAE Tax Overlay | Not in the 86-entry registry, and declared none of the governance fields an overlay must have. The work moves to the Financial Controller's expanded scope, per the package. |

### The one that matters: the model evaluator was not independent

The invariant is *"model/prompt creation and model evaluation are separate"*. The **Model Evaluation
Reviewer** sat inside Product, Engineering & AI — the same department as the AI Architect and the
Agent & Prompt Engineer whose work it grades — reporting to the **AI Director**, the manager who
owns that output.

It already held `stop_authority`. What it did not have was a manager with no stake in the verdict.
It now sits in Independent Assurance under the QA & Release Management Director. Nothing had failed;
no run had been overruled. The structure simply made a captured verdict possible, and now does not.

## Nothing was deleted

Three superseded roles are **retired**, not removed, and every one keeps an alias:

| retired | resolves to |
|---|---|
| `chief_performance_officer` | `corporate_performance_director` |
| `partnerships` | `strategic_partnerships_government_relations_manager` |
| `government_relations` | `strategic_partnerships_government_relations_manager` |
| `tax_overlay_uae` | `financial_controller` |

A post-deployment invariant refuses to pass if any retired role resolves to nobody. All 32
historical department rows — the 22 merged away plus the 10 live — are untouched.

## Two registries that did not exist

**`org_role.necessity_status` and `necessity_reason`.** The invariant "every role has a necessity
status and explicit reason" had no column to read. It was not passing; it was unmeasurable. All 176
active roles now carry both — the 90 from the package registry, the 86 overlays derived from theirs
(on-demand, one category each, with the invocation role, knowledge owner, validator and what it may
not decide).

**`org_workflow_ownership`.** The 30 organizational workflows, one accountable owner each, enforced
by the primary key rather than by a check that has to run. Contributors are recorded and are
deliberately not owners. A constraint refuses a reviewer who is the owner.

This is a different subject from `workflow_step`, which models the 19 runtime workflows as ordered
steps — that table says who acts at step 4, not who is accountable for the workflow.

## Founder boundaries

Eleven founder-reserved decisions are recorded in `founder_reserved_decision`, and **no active role
owns any of them** — enforced by the `a00_org_role_no_reserved_decision` trigger, which refuses the
write rather than reporting it afterwards. See `PHASE_A_FOUNDER_RESERVED_DECISIONS.md`.

## Cost

**0 OpenRouter requests. 0 paid model requests. USD 0.00.** Every provider route remains
open-circuit in `llm_route_health`; Phase A did not release one. The local verification opened no
socket at all.

---

*Registries exported from the deployed database, not copied from the package:
`PHASE_A_DEPARTMENT_REGISTRY.csv`, `PHASE_A_CANONICAL_ROLE_REGISTRY.csv`,
`PHASE_A_REPORTING_GRAPH.csv`, `PHASE_A_EXECUTIVE_COMMITTEE.csv`,
`PHASE_A_CATEGORY_OVERLAY_REGISTRY.csv`, `PHASE_A_WORKFLOW_OWNERSHIP.csv`. Where a canonical id
differs from the package's, the package id is carried in a `package_role_id` column so nothing
diverges silently.*
