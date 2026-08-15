# Claude Code Master Prompt — QuotesDone Phase B Business Workflow Closure

You are closing **Phase B: Business Workflow Architecture** for QuotesDone.

This is a zero-paid-inference, production-direct structural phase.

## Required input

Use the attached Phase B package as the authoritative target.

Read in order:

1. `START_HERE.md`
2. `PHASE_B_PRODUCTION_DIRECT_PROTOCOL.md`
3. `PHASE_B_MASTER_SPEC.md`
4. `PHASE_B_INVARIANTS.md`
5. `PHASE_B_CURRENT_CODE_RECONCILIATION_POLICY.md`
6. all machine-readable registries
7. all 30 files in `workflows/`

## Phase A is frozen

Before editing, verify:

- active departments = 10;
- canonical roles = 90;
- category overlays = 86;
- `fn_phase_a_organization_violations()` returns zero;
- founder-approved Phase A baseline exists.

Do not alter departments, roles, managers, reviewers, overlays or founder-reserved decisions.

If the workflow analysis reveals a genuine organizational defect, create a formal Phase A change request and stop that specific change. Do not reopen Phase A silently.

## Phase B objective

Implement and verify the canonical business-process structure:

- 30 workflows;
- 257 steps;
- 161 handoffs;
- 56 business objects;
- workflow and step state machines;
- business rules;
- gates;
- exceptions;
- SLA policies;
- events;
- founder boundaries;
- current-code crosswalk.

Do not merely import CSV files.

The structural registries must be represented in the current QuotesDone architecture, have real deterministic readers/validators, and be the declared source of truth for Phase C.

## Zero-cost development rule

This phase must not call OpenRouter or another paid inference provider.

Enforce:

```text
NO_PAID_AI=true
OPENROUTER_DISABLED=true
AI_PROVIDER_MODE=mock_or_disabled
```

Remove paid-provider credentials from the Phase B test process where feasible.

Any paid inference request during Phase B is a phase failure.

Final required measurements:

- OpenRouter requests = 0;
- paid inference requests = 0;
- paid inference cost = USD 0.00.

## Production-direct rule

There is no staging dependency.

Follow `PHASE_B_PRODUCTION_DIRECT_PROTOCOL.md`.

You may:

- inspect production read-only;
- build locally;
- create committed forward migration and exact rollback;
- run deterministic tests;
- rehearse committed SQL in an aborted production transaction;
- deploy the committed structural changes to production after all gates pass;
- immediately verify and roll back on failure.

You must not:

- create synthetic business data;
- execute a real workflow;
- activate cron jobs;
- send notifications;
- invoke providers;
- process payments/refunds;
- activate routes or autonomy;
- work on knowledge, tools, models, traces or certification.

## Step 1 — Package verification

Verify all files and checksums.

Required exact counts:

- workflows: 30
- steps: 257
- handoffs: 161
- cross-department handoffs: 47
- business objects: 56
- business rules: 54
- exceptions: 50
- SLA policies: 34
- gates: 32
- events: 347
- workflow states: 14
- workflow transitions: 35
- step states: 11
- step transitions: 19

Reject the package if counts, IDs, references or checksums do not match.

## Step 2 — Inventory current workflow estate

Inspect the repository and production database.

Inventory every:

- frontend workflow entry point;
- API client action;
- Edge Function;
- database function/procedure;
- trigger;
- cron job;
- event subscription;
- queue;
- workflow/state table;
- notification path;
- payment/refund path;
- customer portal path;
- supplier portal path;
- OS/admin path.

Do not infer a connection because compatible objects exist.

Populate:

`PHASE_B_CURRENT_TO_TARGET_WORKFLOW_CROSSWALK.csv`

Classify every path using the exact statuses in the reconciliation policy.

## Step 3 — Reconcile current structures

Compare existing workflow definitions, state machines and owners to the package.

Use:

- `EXISTING_BETTER_KEEP` only with deterministic evidence that the current design satisfies all mandatory invariants and is structurally stronger;
- `CANONICAL_PARTIAL` for incomplete structures;
- `DUPLICATE_PATH` for multiple implementations of the same decision;
- `CONFLICTING_PATH` for behavior that contradicts the canonical workflow;
- `PHASE_C_WIRING_GAP` for unconnected runtime code.

Do not preserve a bad structure merely because it exists.

Do not delete history.

## Step 4 — Implement the canonical workflow registry

Reuse current tables where safe.

The production structure must represent:

- workflow registry;
- ordered steps;
- accountable owner;
- contributors;
- reviewer;
- start/end states;
- business objects;
- states and transitions;
- handoffs;
- gates;
- rules;
- exceptions;
- SLA references;
- events;
- founder boundaries;
- version and active/superseded status.

Add deterministic constraints or validation functions that reject:

- unknown/inactive owners;
- duplicate workflow/step IDs;
- multiple accountable owners;
- invalid transitions;
- missing prerequisites;
- incomplete handoffs;
- creator/reviewer collisions;
- category-overlay authority violations;
- founder-boundary bypass;
- terminal closure with unresolved mandatory steps.

Do not add runtime provider calls.

## Step 5 — Reconcile workflow ownership

Every one of the 257 steps must resolve to:

- one active canonical standing role;
- `founder`, only for an explicit founder decision;
- or `relevant_category_overlay`, only for the declared technical overlay step.

All 90 roles must appear in at least one accountable, contributor or reviewer responsibility.

All 10 departments must appear.

All 86 overlays must retain only the Phase A-approved scope.

## Step 6 — Reconcile state machines

Implement one canonical workflow state model and one canonical step state model.

Reject undeclared transitions.

Prove:

- cancellation preserves history;
- retry creates a new attempt;
- expiry is explicit;
- rejection does not become silent success;
- completed records are not rewritten;
- supersession links old and new versions;
- closure is impossible while a mandatory step/blocker/handoff remains open.

## Step 7 — Reconcile handoffs

Create or update the canonical 161 handoff contracts.

For each owner change require:

- sender;
- receiver;
- source workflow/step;
- exact output/version;
- required evidence packet;
- acceptance criteria;
- rejection condition;
- return owner;
- SLA;
- acceptance/rejection status.

A queued event/message is not handoff acceptance.

## Step 8 — Reconcile business rules and gates

Implement deterministic structural validation for all 54 business rules and 32 global gates where Phase B can represent them.

When a rule requires future runtime wiring, record:

`PHASE_C_WIRING_GAP`

Do not falsely mark it enforced.

At minimum, structural design must make these impossible to omit:

- quote readiness before dispatch;
- approved safe package before dispatch;
- approved supplier before assignment;
- unique assignment/idempotency requirement;
- notification derived from successful assignment;
- customer identity hidden before reveal;
- reconciled payment before reveal;
- independent supplier verification;
- payment executor/reconciler separation;
- independent release approval;
- founder-boundary escalation.

## Step 9 — Exceptions, timers and closure

Represent all 50 exception patterns and 34 SLA policies.

Every waiting state must have:

- waiting reason;
- responsible external/internal party;
- due date;
- reminder/escalation owner;
- expiry behavior;
- terminal or return path.

No exception may disappear into an unread, ownerless queue.

## Step 10 — Deterministic tests

Do not call an LLM.

Create deterministic tests for every invariant in `PHASE_B_INVARIANTS.md`.

At minimum test:

- counts;
- unique IDs;
- owner resolution;
- role and department coverage;
- overlay authority;
- graph reachability;
- state transitions;
- prerequisite cycles;
- handoff completeness;
- reviewer independence;
- founder gates;
- workflow closure;
- crosswalk completeness;
- no production activation;
- zero provider usage.

The test suite must fail on injected defects, including:

- missing owner;
- two owners;
- inactive owner;
- unknown step target;
- invalid state transition;
- missing handoff acceptance;
- creator/reviewer alias collision;
- category overlay granted dispatch authority;
- missing founder gate;
- completed workflow with open blocker.

## Step 11 — Commit and direct production deployment

Create a focused branch:

`phase-b/business-workflow-closure`

Commit:

- source changes;
- migration;
- rollback;
- tests;
- registries;
- crosswalk;
- evidence documents.

Run the exact committed migration in an aborted production transaction.

Deploy directly to production only after all preconditions and rehearsal assertions pass.

Immediately run all Phase A and Phase B invariants.

Rollback automatically if any mandatory invariant fails.

Do not begin Phase C.

## Required deliverables

Create:

1. `docs/phase-b/PHASE_B_FINAL_WORKFLOW_ARCHITECTURE.md`
2. `docs/phase-b/PHASE_B_WORKFLOW_REGISTRY.csv`
3. `docs/phase-b/PHASE_B_WORKFLOW_STEP_REGISTRY.csv`
4. `docs/phase-b/PHASE_B_WORKFLOW_STATE_MODEL.csv`
5. `docs/phase-b/PHASE_B_WORKFLOW_TRANSITIONS.csv`
6. `docs/phase-b/PHASE_B_HANDOFF_REGISTRY.csv`
7. `docs/phase-b/PHASE_B_BUSINESS_OBJECT_REGISTRY.csv`
8. `docs/phase-b/PHASE_B_BUSINESS_RULE_REGISTRY.csv`
9. `docs/phase-b/PHASE_B_GATE_REGISTRY.csv`
10. `docs/phase-b/PHASE_B_EXCEPTION_ESCALATION_MATRIX.csv`
11. `docs/phase-b/PHASE_B_SLA_POLICY.csv`
12. `docs/phase-b/PHASE_B_CURRENT_TO_TARGET_WORKFLOW_CROSSWALK.csv`
13. `docs/phase-b/PHASE_B_CURRENT_PATH_DUPLICATES_AND_GAPS.md`
14. `docs/phase-b/PHASE_B_INVARIANT_RESULTS.md`
15. `docs/phase-b/PHASE_B_PRODUCTION_DEPLOYMENT_EVIDENCE.md`
16. `scripts/sql/phase_b_workflow_closure_rollback.sql`

## Final response

Return:

- branch;
- final commit;
- clean-tree status;
- production project ref;
- forward migration and checksum;
- rollback and checksum;
- pre/post fingerprint;
- workflow count;
- step count;
- role coverage;
- department coverage;
- overlay coverage;
- handoff count;
- cross-department handoff count;
- state/transition results;
- owner/reviewer/founder-boundary results;
- current-path classification totals;
- duplicate/conflicting paths;
- Phase C wiring gaps;
- provider/cron/automation activation counts;
- OpenRouter requests;
- paid inference cost;
- unresolved founder-level workflow decisions.

End with exactly:

`PHASE_B_READY_FOR_FOUNDER_APPROVAL`

or

`PHASE_B_NOT_READY`

Stop after Phase B.
