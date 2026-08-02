# Phase 2 — approved architecture and workstream order

**Founder decision, 2 August 2026. Start from `0fd5b00` on `feature/phase1-safety-and-decisions`.**
**This is the operative specification. Return evidence after each step, not completion statements.**

---

## 1. MEP is a prerequisite, not a parallel workstream

P2-C1 must be settled **before** the harness architecture is finalised, because trade identification and cross-workstream deduplication are harness features, not router features. Building the harness first means building it twice.

**The harness must support both shapes from the start:**

1. ordinary single-route inquiries;
2. multi-trade inquiries with separate but coordinated workstreams.

**MEP model — implement first:**

- trade identification
- shared project fields asked **once**
- separate HVAC, electrical, plumbing, fire and ELV workstreams
- cross-workstream duplicate-question prevention
- trade-level completeness
- overall MEP completeness
- trade-level **and** overall dispatch eligibility
- one coordinated MEP RFQ **or** linked trade RFQs
- document-derived answers assigned to the **correct** workstream
- the ability to add a trade detected in drawings but absent from the customer's text

**Explicitly forbidden:** combining all child-route questions into one list. That is the 1,146-question behaviour the crosswalk exposed.

**Required MEP scenarios (new, in addition to the 3,324):**

| # | Scenario |
|---|---|
| 1 | Complete MEP package |
| 2 | HVAC only |
| 3 | Electrical plus plumbing |
| 4 | Vague "MEP works" request |
| 5 | Customer changes the selected trades mid-flow |
| 6 | Drawing contains a trade not mentioned in the text |
| 7 | One trade complete while another is incomplete |
| 8 | Duplicate project-level questions across trades |
| 9 | Coordinated RFQ versus linked RFQs |

## 2. Regulatory status for the activation cohort

**Do not mark 23 Furniture / FF&E or 46 Cleaning as `confirmed_none`.** Review each and mark `confirmed_covered` only after scope-specific regulatory and escalation triggers exist. Ordinary low-risk scopes may then proceed without escalation.

**Route 23 — Furniture / FF&E triggers, where relevant:**
fire-rated or upholstered products · healthcare furniture · educational furniture · outdoor and public-area furniture · electrical or motorised furniture · certificate and project-approval requirements.

**Route 46 — Cleaning triggers:**
healthcare and food-premises cleaning · chemical handling · facade or high-level access · hazardous-material cleaning · pest-control overlap · waste handling · any activity requiring municipality or specialist approval.

This is the right correction. The mechanical rule read "no named authority" as "no regulation"; the truth is that both routes are mostly benign **and** contain scopes that are not — a hospital ward clean and an office clean are the same route and different risks. The trigger sits on the scope, not the route.

## 3. Workstream order

1. Implement **P2-C1** MEP umbrella architecture.
2. Finalise the generic single-route **and** multi-workstream harness design.
3. Run a **small smoke suite** covering routes 23, 46 and MEP.
4. Build the complete scenario runner.
5. Execute **all 3,324** imported scenarios **plus** the new MEP scenarios.
6. Complete **P2-C2** before activating affected regulated routes.
7. Complete **P2-C3** (flooring aliases) and **P2-C4** (corporate gifts under route 85) in parallel; include their tests before broad routing activation.

## 4. Expectation changes must be ledgered, never silent

No existing expected outcome may be altered quietly. Any scenario whose expected result changes **because of the approved MEP architecture** must retain, together:

- its **original** expectation
- the **new** expectation
- the **reason** for the change
- the **approving work item** (`P2-C1`)

Implement this as a table, not a convention — an expectation that can be edited without leaving a row is an expectation that will be. Suggested shape: `scenario_expectation_change(scenario_id, original_expected, new_expected, reason, work_item, changed_by, changed_at)`, with the runner reading the current expectation through a view that joins it, so the original is never overwritten in place.

This is the mechanism that makes the acceptance thresholds meaningful. Without it, "99% exact-route accuracy" is a number anyone can reach by editing the target.

## 5. Acceptance thresholds — carried over verbatim

- exact-route accuracy **≥ 99%**
- **zero** incorrect routes into regulated categories
- **zero** privacy / redaction-gate failures
- **zero** incorrect `dispatch_eligible = true` results
- **zero** missing mandatory qualification questions
- **zero** duplicate mandatory questions
- English / Arabic outcome parity **≥ 99%**
- **zero** crashed or technically unexecuted scenarios
- every remaining failure **individually explained**

A scenario that cannot be executed counts as a failure, not an omission.

## 6. Field-key priority (2,537 optional gaps — do not attempt all of them)

In order: price and cost drivers · technical specifications · quantities and units · delivery and programme · installation scope · testing and commissioning · warranty and maintenance · documents and approvals · brand/model and approved-equivalent rules · exclusions and deviations.

## 7. Standing gates

- The **router stays off** until: harness complete, all 3,324 run, thresholds met, shadow results reported, rollback demonstrated.
- `fn_kb_route_activation_blocked` currently blocks **all 86 routes**, including 23 and 46, because `requires_review` is the default. Shadow mode is unaffected — it only observes.
- **WI-001** (shared `inbound_secret`) remains P0 and independent. Shadow development may proceed; **no broad autonomous production execution** until it is separated and verified.
- Do not re-import either corpus. Do not activate company-operations workflows. Do not promote records to approved.

## 8. State at handoff

| | |
|---|---|
| Branch | `feature/phase1-safety-and-decisions` |
| Start commit | `0fd5b00` |
| CI | green (run #5, `d54fc12`); `npm test` 31/31 |
| Routes | 86 mapped, 86 with Arabic aliases, 0 mandatory questions without field keys |
| Activation | all 86 blocked pending regulatory review |
| Open work items | P2-C1 (P0), P2-C2 (P0), P2-C3, P2-C4, WI-001 (P0) |
| Stripe | handler ready for four refund events and a test-mode endpoint; configuration outstanding — `docs/security/STRIPE_WEBHOOK_SETUP.md` |
