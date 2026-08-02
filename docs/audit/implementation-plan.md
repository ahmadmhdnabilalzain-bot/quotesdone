# Implementation plan â Phase 0 output

**Status: Phase 0 complete. No migration applied. No code changed. Stopping here for your review, as the package requires.**

---

## 1. Where the 86 requirements actually stand

Every requirement in the three supplied traceability CSVs was re-checked against the real repository and the real database. Full row-by-row detail in `requirements-traceability-updated.csv`.

| Verdict | Count | |
|---|---:|---|
| implemented | 9 | 10% |
| partial | 37 | 43% |
| absent | 36 | 42% |
| blocked | 1 | 1% |
| correctly deferred (3D, spatial) | 3 | 4% |

By surface: **OS** 6 implemented / 19 partial / 14 absent. **Supplier** 0 implemented / 10 partial / 13 absent. **Customer** 3 implemented / 8 partial / 9 absent / 1 blocked.

**Zero supplier requirements are fully implemented.** That is the sharpest number in the audit and it matches what the code shows: an 886-line component doing login, onboarding, documents, an RFQ list and a quote form.

---

## 2. The five things that change the plan

**1. The frontend is far smaller than the package assumed â and that is the main risk.**
21 pages, 34 components, and three files carry the whole product: `OsxShell.tsx` (2,210 lines), `SupplierPortal.tsx` (886), `CustomerPortal.tsx` (521). There is no legacy tangle and no second portal, so the "do not build a parallel system" rule is easy to keep. But every P1 OS surface lands in one 2,210-line client component. **Decomposing `OsxShell` is a prerequisite for Phase 3, not part of it.**

**2. There are no tests, and no framework to write them in.**
Zero test files. No Playwright, Vitest or Jest. `package.json` has `dev`, `build`, `start`, `typecheck`. The pack requires unit, contract, integration, idempotency, provider-outage, privacy, Arabic/RTL and staging E2E tests. This is the largest single gap between the repository and the acceptance gates, and it blocks every gate that says "tested".

**3. Arabic in the portals is blocked, not partial.**
Two unrelated translation systems exist. Marketing uses `next-intl` with `messages/{en,ar}.json`. All three portals carry **their own inline EN/AR dictionaries and their own `dir` state**. Visiting `/ar/me` gives an Arabic URL, an Arabic `<html dir>`, and an English portal. "Full Arabic customer journey" cannot be delivered until these are unified â that is a prerequisite, not a feature, and it is small (a few days) compared to what depends on it.

**4. Phase 2 is much cheaper than the roadmap assumes.**
The deterministic engine the roadmap asks for already exists, tested, from today's corpus import: `fn_kb_route_decide` (258/258 English route tests, 86/86 Arabic, zero misroutes), `fn_kb_next_question` (next question EN+AR, completeness, `dispatch_eligible`), `fn_kb_retrieve`, 86 mapped routes, 4,212 bilingual aliases, 16,588 qualification questions, 4,696 validation rules. **None of it is called by any production function yet.** Phase 2 is largely wiring, plus building the deterministic quote scorer.

**5. Autonomy is capped by four missing tables, not by missing executors.**
`org_action_executor` already holds **55 registered action classes**, including real side-effecting ones (`outreach_send`, `invite`, `refund_within_window`, `collections_chase`, `incident_fix`, `pdpl_action`). The package's "only a limited set are wired" understates it. What is missing is: **no `workflow_run` table**, no idempotency key, no lease, no dead-letter queue. Definitions exist (`workflow` 14, `workflow_step` 117) but nothing records that a workflow ever *ran*. Without those four, no action can be safely retried, so 55 executors deliver the autonomy of about five.

---

## 3. Conflicts and duplicate systems to resolve before building

| # | Conflict | Recommendation |
|---|---|---|
| 1 | `/os` â¡ `/console`, `/portal` â¡ `/supplier` â four routes, two products | Keep `/os` and `/portal`; make the other two permanent redirects |
| 2 | Six decision/audit stores (`decision_log` 986, `decision_record` 3, `agent_actions` 1,991, `os_audit_log` 2,925, `agent_action_log` 28, `security_audit_log` 1,664) | The unified decision trace must **read from these**, not become a seventh |
| 3 | Two i18n systems | Move portal strings into `messages/*.json`; delete the local `lang`/`rtl` state |
| 4 | Two workflow shapes â `workflow`/`workflow_step` vs `employee_workflow` (157 rows, **3 columns**) | `employee_workflow` records only that a workflow exists. The 236 corpus SOPs supersede it |
| 5 | 8 of 10 hard gates have no `org_authority` row | **Your decision** â filling them is itself an authority change. Safe today only because the new check fails closed |
| 6 | Monitoring-only vs approval console | Already decided this session: operational console, with `v_founder_inbox` splitting 9 blocking items from 71 automation gaps. Observe/Control Mode is still unbuilt |
| 7 | `profile_ai` on 16 legacy categories | The 86-route taxonomy is imported and unused. Straight swap, P0 |
| 8 | No `refunds` table | Refunds are implied by `stripe_transactions` + a `decision_record`. Payments & Revenue cannot report a refund rate |
| 9 | 9 of 35 `os_api` actions unreachable from the UI | Two of them â `nav` and `search` â are exactly what the Command Palette needs and are already built |
| 10 | `org_objectives` has 0 rows | Chief-of-Staff objective decomposition is described as implemented; the table is empty |

---

## 4. Recommended order â and where it differs from the package

The package's Phase 1â5 order is right. Three amendments:

**Phase 0.5 â prerequisites the roadmap does not list (do these first)**
- **Add a test framework.** Vitest for units, Playwright for E2E. Without it, no acceptance gate can be closed.
- **Unify i18n.** Portal strings into `messages/*.json`; delete local `dir` state. Unblocks the Arabic requirement.
- **Decompose `OsxShell`.** Split 2,210 lines into route segments before adding six more surfaces.
- **Retire the duplicate routes.** Two redirects.

*Nothing here is a feature. All of it is load-bearing for everything after.*

**Phase 1 â shared autonomy foundation (unchanged priority, narrower scope)**
Build the four missing tables, not a new executor system: `event_outbox`, `workflow_run` + run-level `workflow_step_run`, `idempotency_key` + `lease`, `dead_letter`. Then a unified `decision_trace` **view** over the six existing stores. The 55 registered executors then become genuinely retry-safe.

**Phase 2 â category integration and quote comparison (cheaper than estimated)**
Point `inquiry_intake` / `route_inquiry` at `fn_kb_route_decide`, and the missing-field logic at `fn_kb_next_question`. Replace `profile_ai`'s 16 categories with the 86-route taxonomy. Then build the deterministic quote scorer â normalise line items, apply category compliance gates from `kb_stage.validation_rules`, compute evaluated cost, rank, and only then ask a model to explain the ranking in English and Arabic. The model-free fallback is achievable because every input is now relational.

**Phase 3â5 â as specified**, after the above. Observe/Control Mode belongs at the start of Phase 3, since every other OS surface has to respect it.

---

## 5. Estimated OpenRouter reduction

| Change | Effect |
|---|---|
| Inquiry field sequencing â `fn_kb_next_question` | Removes a model call **on every customer turn** â the one that scales with traffic |
| Category routing â `fn_kb_route_decide` | Removes first-pass classification; model only when the router asks for clarification |
| Quote comparison â deterministic scorer | Removes the single largest per-transaction call; model explains, does not decide |
| Department context â `fn_ops_department_context` | Targets `agent_brain`, currently 14,600â22,000 input tokens/call and AED 22.56 over 129 calls â the largest AI cost in the company |
| `gen_category_knowledge` for mapped categories | Currently pays to regenerate what the corpus already holds, without source lineage |

Nothing is removed until its replacement passes tests behind a feature flag.

---

## 6. What I need from you before Phase 1

1. **Approve or amend this plan**, in particular Phase 0.5 â it adds work the roadmap does not list, and I would rather argue for it now than discover mid-Phase-3 that nothing can be tested.
2. **The eight missing hard-gate authority rows** (conflict 5). An authority change is hard-gated, so it is yours.
3. **Staging.** The package says staging first. There is one Supabase project. Either a second project, or an explicit decision that staging means "schema-additive, disabled by default, in the same project" â which is what both corpus imports did today.
4. **Screenshots.** The sandbox has no egress to `quotesdone.com`, so none were captured; `scripts/audit-screenshots.mjs` is committed and takes one command on any normal machine. Responsive and mobile quality remain unverified until it runs.

---

## 7. What was and was not done in this phase

**Done:** both archives read; the four required audit documents produced; every route, component, edge-function call, `os_api` action, table, function, trigger, RLS posture and cron job inventoried; all 86 requirements re-verified; conflicts and duplicate systems reported.

**Deliberately not done:** no migration, no schema change, no code change, no deployment, no requirement re-scored upward without evidence, and no screenshot claimed that was not taken.
