# Phase B Production-Direct Protocol

There is no staging dependency.

Phase B changes only canonical workflow structure, metadata, constraints and reconciliation records. It must not activate business automation or invoke providers.

## Required order

### 1. Preflight

- Verify the production Supabase project reference.
- Verify the Phase A approved counts and `fn_phase_a_organization_violations() = 0`.
- Record repository branch, commit and clean-tree status.
- Record production workflow-related fingerprints.
- Record current workflow, step, ownership, state, trigger, cron and event inventories.
- Confirm OpenRouter and all paid-provider routes are unavailable to the Phase B test process.

### 2. Build locally

- Parse and verify this package.
- Create the canonical workflow registry, step registry, state/transition registry, business-rule registry, handoff registry, gate registry, exception matrix and structural constraints.
- Create the current-to-target workflow crosswalk.
- Do not create synthetic customers, suppliers, inquiries, payments or notifications.
- Do not call an LLM.

### 3. Deterministic validation

Run only zero-cost tests:

- CSV/JSON/SQL parsing;
- stable-ID uniqueness;
- owner resolution;
- department coverage;
- workflow graph validation;
- state-transition validation;
- prerequisite graph validation;
- handoff completeness;
- reviewer-independence validation;
- founder-boundary validation;
- current-path classification;
- migration replay against a disposable local database where available.

### 4. Commit before production

Commit:

- forward migration;
- exact rollback;
- registries;
- deterministic tests;
- reconciliation report;
- Phase B documents.

No uncommitted migration may be applied.

### 5. Production baseline and aborted rehearsal

Before applying:

- capture the current production fingerprint;
- run the exact committed migration inside an aborted transaction where supported;
- run all preconditions and postconditions inside the rehearsal;
- prove production fingerprint and row counts are unchanged after abort;
- refuse the real deployment if any assertion fails.

### 6. Direct production deployment

Once all gates pass:

- apply only the committed migration;
- do not activate cron jobs;
- do not deploy provider routes;
- do not create workflow runs;
- do not execute business events;
- do not send notifications;
- do not modify customer/supplier/financial data.

### 7. Immediate post-deployment verification

Re-run:

- all Phase A invariants;
- all Phase B package counts;
- workflow/step owner resolution;
- graph and state-transition validation;
- handoff completeness;
- founder-boundary validation;
- production/repository parity;
- zero paid-provider usage;
- zero new active cron/provider/route/automation records.

### 8. Automatic rollback

Run the committed rollback if any mandatory Phase A or Phase B invariant fails after deployment.

After rollback:

- verify the pre-deployment fingerprint is restored;
- keep the failed migration and evidence;
- report `PHASE_B_NOT_READY`.

## Prohibited in Phase B

- OpenRouter calls;
- other paid inference;
- knowledge ingestion or retrieval changes;
- tool connections;
- decision-trace implementation;
- model routing;
- synthetic user/data creation;
- real business workflow execution;
- autonomous activation;
- email/SMS/WhatsApp sending;
- payment/refund tests;
- cron activation;
- Phase A organization changes.
