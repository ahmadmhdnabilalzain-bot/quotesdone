
# Claude Code Master Prompt — QuotesDone Phase C Runtime Connection & Command Center

You are implementing **Phase C only** for QuotesDone.

Phase A and Phase B are founder-approved and frozen.

Production project:

`htdblwldjkcgjvmqkbeh`

Reported approved repository baseline at Phase B closure:

`main @ 675c111`

First verify the current approved tags/commits and do not assume the repository has not advanced.

## Zero-cost rule

This phase must use zero paid inference.

Enforce:

```text
NO_PAID_AI=true
OPENROUTER_DISABLED=true
AI_PROVIDER_MODE=mock
```

Do not call OpenRouter, Anthropic, OpenAI, Google/Gemini or another paid model endpoint.

Do not access V3 certification questions or evaluator answer keys.

Do not perform professional-quality scoring.

Any paid inference request is a Phase C failure.

## Founder operating model

QuotesDone is a fully automated company.

The founder's normal involvement is:

1. issue high-level orders through the Command Center;
2. observe status, evidence and outcomes;
3. provide or limit funding;
4. approve or reject specific refund cases.

The founder must not receive routine approval tasks for supplier approval, dispatch, marketing, release, legal, finance, security, hiring, knowledge or other company work.

The only routine founder approval action class is:

`refund_decision`

Founder-reserved constitutional/commercial changes are `founder_initiated_only`, not approval queues.

## Founder Command Center

Use the existing Command Center/OS. Do not create a separate competing console.

Use canonical role:

`chief_of_staff`

as the founder-facing command secretary. The UI may call it **Founder Command Secretary — Chief of Staff** without adding a role.

A safely routable founder instruction must:

- be recorded append-only;
- resolve to existing Phase B workflow(s);
- resolve to exact canonical role(s);
- create the command plan and immediate tasks atomically before the response;
- return command/task IDs, owners, priority and due dates;
- update the command center from task/workflow events;
- support status, explanation, cancellation, supersession and reprioritization;
- ask one clarification and create no task when ambiguous;
- never execute raw text directly.

Phase C uses deterministic command-intent fixtures/registry. Paid model interpretation remains disabled.

## Required read order

1. `START_HERE.md`
2. `PHASE_C_FROZEN_BASELINE_REFERENCE.json`
3. `PHASE_C_MASTER_SPEC.md`
4. `PHASE_C_FOUNDER_AUTONOMY_POLICY.md`
5. `PHASE_C_COMMAND_CENTER_ARCHITECTURE.md`
6. `PHASE_C_AUTHORITY_AND_APPROVAL_MATRIX.csv`
7. all runtime contract files;
8. all binding templates;
9. `PHASE_C_PRODUCTION_DIRECT_PROTOCOL.md`
10. `PHASE_C_ZERO_COST_TEST_PLAN.md`
11. `PHASE_C_INVARIANTS.md`
12. this prompt.

## Stage C0 — Preflight and frozen baseline

Before editing:

- report repo path, branch, HEAD and tracked-tree status;
- verify Phase A and Phase B approved tags/records/checksums/fingerprints;
- verify expected counts;
- verify effective Phase B errata are resolved;
- capture current production schema, routine, edge-function, cron, trigger, queue, event-subscription, portal/API and activation inventories;
- capture paid-provider route state and current cost-log baseline;
- refuse to continue on the wrong project.

Do not discard pre-existing uncommitted work.

Create branch:

`phase-c/runtime-connection-command-center`

## Stage C1 — Complete runtime-component inventory

Inventory every current:

- frontend routed mutation/action;
- API client action;
- Edge Function;
- database function/procedure;
- trigger;
- cron job;
- event subscription;
- queue/outbox worker;
- webhook;
- storage trigger/policy with business behavior;
- agent/task/workflow runner;
- external provider adapter.

Populate:

`PHASE_C_RUNTIME_COMPONENT_CROSSWALK.csv`

For every component identify:

- caller/entry method;
- activation state;
- whether it mutates or delivers state;
- current actor;
- canonical system actor;
- accountable role/department;
- workflow/step or justified system scope;
- authority/action class;
- trace policy;
- idempotency/retry/rollback;
- classification and evidence.

Known issues from Phase B to resolve or explicitly classify:

- hundreds of cron/Edge Function paths without canonical accountability;
- 64 Edge Functions previously reported with no caller/external entry;
- runtime workflows with zero runs;
- W21 with no implementation;
- canonical workflows/steps that exist as registries but not runtime paths.

Do not call inactive historical machinery dead merely because it is off. Classify it accurately.

Required:

- zero active state-changing components without accountable role;
- zero active unclassified components;
- zero unknown/generic final owners.

## Stage C2 — Canonical identity boundary

Make one resolver mandatory at all live actor boundaries.

It must safely resolve:

- canonical role ID;
- legacy key;
- merged key;
- packaged role identity;
- approved title alias;
- registered system actor.

It must refuse inactive/unknown identities.

Inventory every function/API that accepts agent, role, actor, reviewer, manager, owner or assignee. Connect all before context, task, authority, review, tool, workflow, KPI or trace behavior.

New writes use canonical IDs only.

Add CI/static/runtime guards preventing new bypasses.

## Stage C3 — Workflow and step runtime binding

Populate and implement/reconcile:

- 30 workflow bindings;
- 257 step bindings;
- 161 handoff bindings;
- 347 event bindings;
- 32 gate bindings;
- 54 rule bindings;
- 90 role runtime bindings;
- 86 overlay bindings.

Keep demonstrably better current code as `CANONICAL_BETTER_KEEP`.

Do not create duplicate engines merely to match filenames.

Where full business implementation belongs to Phase D or later, use an explicit `DEFERRED_RUNTIME_IMPLEMENTATION` status with:

- accountable owner;
- existing safe entry boundary;
- no active bypass;
- exact missing implementation;
- future work item.

No unknown/unowned gap may remain.

## Stage C4 — Workflow/task/event/handoff runtime core

Reuse or repair existing runtime objects so that:

- workflow state changes only through the canonical guard;
- tasks have exact canonical owners/managers/criteria;
- handoffs are accepted/rejected explicitly;
- events are written atomically with business state;
- duplicate/out-of-order delivery is safe;
- blockers, SLAs, cancellation and supersession are visible;
- first attempts and retries remain distinct;
- closure requires frozen Phase B criteria.

Connect real writers and readers. A correct table with zero callers is not implementation.

## Stage C5 — Founder Command Center

Implement the architecture and command schemas in the package.

Required supported behaviors:

- founder authentication;
- append-only message and command;
- deterministic command intent routing across all 30 workflows;
- command owner = Chief of Staff;
- exact child task owners;
- atomic immediate task creation;
- status/explain/cancel/reprioritize/supersede;
- multi-department plans;
- ambiguous-command clarification with no task;
- founder-initiated-only change request behavior;
- refund approval behavior;
- progress/completion updates from runtime events;
- full traceability.

Run every row in `PHASE_C_COMMAND_ROUTING_ACCEPTANCE_CASES.csv` with zero paid inference.

Do not add a secretary role. Use `chief_of_staff`.

## Stage C6 — Authority and approval

Implement or reconcile one authoritative authority gate using:

`PHASE_C_AUTHORITY_AND_APPROVAL_MATRIX.csv`

Hard requirements:

- unknown actions fail closed;
- effective identity used for reviewer independence;
- only `refund_decision` can create a founder manual approval request;
- non-refund founder approval request is rejected by database/runtime constraint;
- founder-initiated-only actions require explicit founder command origin;
- internal roles/reviewers decide all routine work;
- raw founder command does not bypass gates;
- refund executor and reconciler differ;
- no role approves its own consequential output.

## Stage C7 — Trace and observability boundary

Implement meaningful trace-required classification and writers/readers.

Do not use a denominator that mixes unrelated execution populations.

Every Phase C fixture that is command, task, workflow, step, handoff, consequential action, review, tool call or state-changing system execution must have the required trace.

Completed trace evidence must be immutable/versioned.

Management and the Command Center must be able to retrieve relevant traces.

## Stage C8 — Tool and knowledge interfaces

Inventory current tools and knowledge-scope paths.

Connect the boundary contracts and mocks without paid/provider calls.

Required:

- role authorization;
- stable input/output contracts;
- explicit result/error states;
- result IDs/hashes;
- trace links;
- null is not success;
- no fabricated result;
- no embedding/model calls;
- no knowledge-content changes;
- zero orphan role/overlay scope mappings.

This stage connects interfaces, not professional intelligence.

## Stage C9 — Output, idempotency, retry and cost guards

Implement/reconcile:

- versioned output validation;
- deterministic truncation/incomplete detection;
- fail-closed state mutation;
- idempotency for every state-changing entry point;
- first-attempt preservation;
- safe retry/compensation;
- duplicate event/task/notification/assignment protection;
- provider network denial in Phase C;
- cost guard proving zero paid inference.

Do not report zero cost from a caught query error. Verify using the network guard and valid cost logs.

## Stage C10 — Zero-cost tests

Run all gates in `PHASE_C_ZERO_COST_TEST_PLAN.md`.

Use local tests, mocks, recorded fixtures and aborted transactions.

Do not create persistent business demo data.

Inject failures for:

- unresolved/inactive identity;
- unknown action;
- self-review through aliases;
- non-refund founder approval;
- raw command side effect;
- ambiguous command;
- duplicate command/task/event;
- null insert result;
- invalid transition;
- incomplete handoff;
- missing trace;
- tool null/error;
- truncated/malformed output;
- event delivery retry/out-of-order;
- founder-initiated-only action without founder command.

Every defect must be refused with unchanged protected business state.

## Stage C11 — Production-direct deployment

Follow `PHASE_C_PRODUCTION_DIRECT_PROTOCOL.md` exactly.

- Commit first.
- Rehearse exact committed DB SQL in aborted production transaction.
- Prove fingerprint unchanged after rehearsal.
- Verify deploy hashes and rollback versions for code/functions.
- Deploy incrementally.
- Run all Phase A, Phase B and Phase C invariants immediately.
- Roll back the affected component on mandatory failure.
- Preserve current activation states unless an explicit Phase C change is required.
- Do not enable paid providers or previously disabled business automation.

The Command Center deterministic founder path may be enabled only for the founder identity after its tests pass.

## Required deliverables

Create in `docs/phase-c/`:

1. `PHASE_C_RUNTIME_COMPONENT_CROSSWALK.csv`
2. `PHASE_C_ROLE_RUNTIME_BINDING.csv`
3. `PHASE_C_CATEGORY_OVERLAY_RUNTIME_BINDING.csv`
4. `PHASE_C_WORKFLOW_RUNTIME_BINDING.csv`
5. `PHASE_C_STEP_RUNTIME_BINDING.csv`
6. `PHASE_C_HANDOFF_RUNTIME_BINDING.csv`
7. `PHASE_C_EVENT_RUNTIME_BINDING.csv`
8. `PHASE_C_GATE_ENFORCEMENT_BINDING.csv`
9. `PHASE_C_RULE_ENFORCEMENT_BINDING.csv`
10. `PHASE_C_EXECUTOR_ACCOUNTABILITY.csv`
11. `PHASE_C_FOUNDER_COMMAND_CENTER_REPORT.md`
12. `PHASE_C_IDENTITY_RESOLUTION_REPORT.md`
13. `PHASE_C_WORKFLOW_TASK_EVENT_REPORT.md`
14. `PHASE_C_AUTHORITY_APPROVAL_REPORT.md`
15. `PHASE_C_TRACE_COVERAGE_REPORT.md`
16. `PHASE_C_TOOL_KNOWLEDGE_INTERFACE_REPORT.md`
17. `PHASE_C_IDEMPOTENCY_OUTPUT_REPORT.md`
18. `PHASE_C_ZERO_COST_TEST_EVIDENCE.md`
19. `PHASE_C_PRODUCTION_DEPLOYMENT_REPORT.md`
20. `PHASE_C_PHASE_D_HANDOFF.md`

Commit code, migrations, rollback, tests and documentation.

## Final measurements

Return exact measured values for:

- Phase A/B drift;
- runtime components inventoried;
- active state-changing components;
- unowned active components;
- unclassified components;
- roles bound 90/90;
- overlays bound 86/86;
- workflows bound 30/30;
- steps bound/classified 257/257;
- handoffs bound/classified 161/161;
- events classified 347/347;
- gates classified/enforced 32/32;
- rules classified/enforced 54/54;
- founder command acceptance cases;
- command-to-task atomic success;
- non-refund founder approval requests;
- refund executions without founder decision;
- trace-required fixtures with trace;
- tool claims without result;
- duplicate side effects;
- invalid transitions accepted;
- creator/reviewer collisions;
- unknown/inactive identities able to act;
- OpenRouter requests;
- other paid inference requests;
- paid inference cost;
- production pre/post fingerprints;
- repo/deployed/database parity;
- activation-state changes;
- remaining Phase D gaps.

## Stop condition

Stop after Phase C deployment and verification.

Do not begin Phase D, knowledge work, model routing, synthetic company simulation or certification.

End exactly with:

```text
PHASE_C_READY_FOR_FOUNDER_APPROVAL
```

or:

```text
PHASE_C_NOT_READY
```
