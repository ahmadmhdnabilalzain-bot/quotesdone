# Phase 2 kickoff brief — for a fresh session

**Branch:** `feature/phase1-safety-and-decisions` · **Start from:** `1266c05`
**Do not re-import either corpus. Do not activate company-operations workflows. Do not activate the router until the crosswalk is approved.**

---

## What is already built and live

Everything Phase 2 needs is in production and committed. Nothing needs to be created from scratch.

| Asset | Where | State |
|---|---|---|
| Supplier corpus | `kb_stage` — 108,818 records, 16,588 questions, 12,929 decision rules, 4,696 validations, 3,324 scenario tests | imported, unapproved, not on the REST API |
| 86 operational routes | `public.kb_operational_route` + 426 route→subcategory maps + 4,212 bilingual aliases | all MAPPED |
| Deterministic router | `fn_kb_route_decide` | 258/258 EN route tests, 86/86 AR, zero misroutes |
| Question sequencer | `fn_kb_next_question` | next question EN+AR, completeness, `dispatch_eligible` |
| Retrieval | `fn_kb_retrieve` | OR'd prefix terms, `ts_rank` ordered |
| Test runner | `npm test` → `scripts/checks/`, Node built-in runner | 31 checks |
| Build gate | `.github/workflows/checks.yml` | green on run #5 |

**None of the three runtime functions is called by any production function yet.** Phase 2 is wiring plus a harness, not building an engine.

## Known state that shapes the work

- **2,537 of 16,588 questions still have no field key** (14,051 do, including all 7,079 mandatory). Item 6 of the brief targets the highest-impact optional ones. Three deterministic derivation passes already ran; anything left needs judgement, not another pass.
- **`profile_ai` still uses 16 legacy categories.** The 86-route taxonomy is imported and unused. That swap is the largest single source of routing disagreement to expect in shadow mode, and it is a straight replacement.
- **30 `category_specs` rows lack field keys** — carried over, unresolved.
- **Six decision/audit stores** exist. The shadow comparison should read from them, not add a seventh.
- **`org_objectives` has 0 rows**; Chief-of-Staff decomposition is described as implemented but has nothing to decompose.

## Constraints that carry forward

- Never expose customer identity to a supplier before the reveal gate. Privacy and dispatch gates stay **fail-closed**.
- No LLM for anything SQL can decide — routing, sequencing, gating, scoring, arithmetic.
- The corpora stay off PostgREST; `SECURITY DEFINER` RPCs are the only doors.
- No secrets in knowledge tables, migrations, logs or prompts.
- **WI-001 blocks broad autonomous production execution.** Shadow work may proceed.
- Every migration additive; every activation behind a flag with a demonstrated rollback.

## The order given

1. Founder-readable crosswalk for all 86 routes — number, name, production slug, mapped packages, mapped subcategories, mandatory/optional question counts, unresolved field-key gaps, regulation and source coverage, review recommendation. **Router stays off until this is reviewed.**
2. End-to-end scenario harness: informal request → route candidates → clarification when ambiguous → customer answers → document-derived answers → duplicate-question prevention → next question → validation → completeness → `dispatch_eligible`.
3. Execute all 3,324 scenarios. Group failures by category, route error, wrong clarification, missing field key, duplicate question, validation failure, incorrect dispatch eligibility, EN/AR discrepancy, regulatory escalation failure.
4. **No hiding failures by weakening thresholds or editing expected outcomes without writing down why.**
5. Resolve high-impact optional questions lacking field keys — supplier briefs, quote normalisation, technical comparison, pricing drivers, documents and approvals.
6. Feature-flag the three functions; run in shadow against the live path; do not change the customer-visible answer.
7. Measure: route agreement, exact-route accuracy, clarification accuracy, duplicate-question rate, completeness accuracy, dispatch eligibility accuracy, EN/AR parity, latency, OpenRouter calls avoided, input/output tokens avoided, estimated AED saved, fallback-model frequency.
8. One low-risk cohort for controlled activation, with the reasoning and an immediate rollback flag.
9. No broad routing until: crosswalk approved, failures inside an agreed threshold, gates still fail-closed, rollback demonstrated.

## A note on the threshold

Point 4 deserves a decision *before* the 3,324 scenarios run, not after. Once the failure list exists there is a pull toward calling whatever it says acceptable. Better to name the number first — my proposal: **≥99% exact-route accuracy, zero misroutes into a regulated category, zero privacy-gate failures, and every remaining failure individually explained** — and then find out whether it is met.

## Where the evidence lives

`docs/phases/` — `PHASE1_REPORT.md`, `PHASE1_HARDENING_REPORT.md`, `PHASE1_FINAL_ACTIONS.md`.
`docs/security/` — `WI-001-inbound-secret-separation.md`, `STRIPE_WEBHOOK_SETUP.md`.
`docs/audit/` — Phase 0 frontend, backend, plan, traceability.
