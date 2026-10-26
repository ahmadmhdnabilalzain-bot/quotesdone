# Paste this into Claude Code from the QuotesDone repository root

You are the implementation lead for QuotesDone. You have been given the folder `QuotesDone_Autonomous_Company_Upgrade_v2026.07.31` plus the supplier-category and company-operations knowledge corpora.

## Non-negotiable first step: audit, do not code yet

1. Read `00_START_HERE.md`, `01_MASTER/01_EXECUTIVE_AUDIT.md`, all three traceability CSVs, and `01_MASTER/03_FRONTEND_REPOSITORY_AUDIT.md`.
2. Inspect the actual Next.js repository and deployed-backend integration.
3. Produce:
   - `docs/audit/frontend-current-state.md`
   - `docs/audit/backend-current-state.md`
   - `docs/audit/requirements-traceability-updated.csv`
   - `docs/audit/implementation-plan.md`
4. Map every existing route, component, edge-function action, RPC, table, policy and cron before proposing schema changes.
5. Report conflicts, duplicate systems and dead code. Stop and show the Phase 0 report before applying migrations.

## Implementation principles

- Reuse and extend existing tables/functions. Do not build a parallel OS, customer portal or supplier portal.
- Use migrations only. Never edit production database objects manually.
- Use staging first and preserve rollback.
- Preserve all security hardening, redaction, RLS and kill switches.
- Default founder experience is **Observe Mode**. Manual mutations require a short-lived MFA-protected Control Mode.
- Routine, reversible, low-risk work should execute automatically through explicit policy and executor registrations.
- High-risk actions remain gated: large spend, money movement, pricing/fee policy, legal commitments, production deployment, destructive data changes, mass communication, user bans and authority changes.
- Every workflow must be idempotent, retry-safe, traceable and recoverable.
- Every action must have correlation ID, actor, policy, authority decision, knowledge/evidence references, result and outcome status.
- Never expose customer identity to suppliers before the reveal gate.
- Do not use an LLM for deterministic routing, required-question sequencing, compliance gates, scoring or arithmetic when corpus rules/SQL can decide.
- Do not load the large knowledge corpora into chat. Stream JSONL from disk with the provided ingestion instructions.

## Required implementation order

### Phase 0 — audit
Complete the repository audit described above.

### Phase 1 — shared autonomy foundation
Implement/adapt the specification in `05_SHARED_AUTONOMY_FOUNDATION`:
- reliable event outbox and canonical event schema;
- workflow run and step runtime;
- action execution registry and executor coverage report;
- unified decision trace;
- idempotency, leases, retry/backoff, compensation and dead-letter behavior;
- Observe Mode / Control Mode governance;
- end-to-end audit APIs.

### Phase 2 — category integration and quote comparison
- Replace `profile_ai` legacy categories with the 86-route taxonomy.
- Connect corpus aliases/questions/rules to inquiry routing and qualification.
- Build deterministic quote normalization, mandatory-compliance gates, evaluated-cost scoring and top-three ranking.
- Use an AI model only to explain the calculated ranking in clear English/Arabic.
- Return a deterministic fallback report when every model provider is unavailable.

### Phase 3 — Executive OS
Implement `02_OS_COMMAND_CENTER` using existing OS RPCs where possible. Build Executive Home v2, live activity, organization/employee workspaces, trace explorer, simulation workspace and default Observe Mode.

### Phase 4 — Supplier Portal
Implement `03_SUPPLIER_PORTAL` in launch phases. Prioritize product intelligence, opportunity ranking, quote quality and supplier self-service. Defer 3D and native mobile.

### Phase 5 — Customer Portal
Implement `04_CUSTOMER_PORTAL`. Prioritize the procurement workspace, project/inquiry lifecycle, all-quote access, auditable top-three comparison, Arabic, document vault and privacy.

## Required testing

- Unit tests for every deterministic rule/scorer.
- Contract tests for every edge action/RPC.
- Integration tests for event -> workflow -> executor -> trace.
- Idempotency tests that run the same event/action twice.
- Provider-outage tests proving deterministic customer/supplier flows still work.
- Privacy tests proving no pre-reveal identity leakage.
- Arabic/RTL tests for customer routes and reports.
- End-to-end staging tests for registration, inquiry, dispatch, quotation, comparison, reveal, message and reporting.
- Performance and cost report before production.

## Delivery format after each phase

Return:
1. Files changed.
2. Migrations added.
3. APIs changed.
4. Tests and results.
5. Remaining gaps.
6. Security/privacy impact.
7. Estimated OpenRouter calls removed.
8. Screenshots for frontend work.
9. Rollback instructions.

Do not deploy to production without explicit founder approval after the staging acceptance report.
