# Implementation Acceptance Gates

## Gate A — zero-model deterministic readiness

Must pass before any paid smoke test:

- 10/10 departments resolve active.
- 90/90 roles resolve active.
- Mode counts: 6 persistent managers, 6 scheduled managers, 33 event operators, 35 on-demand specialists, 10 reviewers.
- 86/86 category overlays resolve.
- 96/96 packaged knowledge identities map to active roles.
- 0 orphan runtime-eligible knowledge rows.
- 0 manager/reporting cycles.
- 0 creator/reviewer effective-identity collisions.
- Every required tool has an adapter, schema, health state and permission policy.
- Every role has a default model policy and task-level override path.
- Decision trace tables/writers/readers are connected.
- Output schemas and truncation detection are installed.
- Cost guardrails and dedicated keys exist.

## Gate B — 30-case paid infrastructure smoke

Hard budget: **USD 3 total**.

- 100% non-null traces.
- 100% required knowledge retrieval.
- 100% required tool call returns success or explicit fail-closed error.
- 0 fabricated/empty-as-success tool results.
- 0 unauthorized tools.
- 0 truncated successful outputs.
- 0 unsafe actions.

## Gate C — targeted remediation regression

Hard budget: **USD 20 total**.

Cover all ten departments, runtime modes, major tool groups, role aliases, handoffs and at least 20 category overlays including regulated routes.

Required:

- trace coverage 100%;
- knowledge retrieval coverage 100% where required;
- first-attempt infrastructure success ≥99%;
- cross-department ownership/acceptance/closure 100%;
- tool-selection negative suite 100%;
- truncation 0;
- unsafe action 0;
- category incomplete-brief unsafe dispatch 0.

## Gate D — representative 90-role / 86-overlay smoke

Use cheapest adequate model and one concise case per role/overlay. Budget must be estimated and approved before run.

## Gate E — independent certification

Full 2,284-question certification remains disabled until A–D pass. Use a dedicated API key, a founder-approved budget and an automatic stop before the limit.
