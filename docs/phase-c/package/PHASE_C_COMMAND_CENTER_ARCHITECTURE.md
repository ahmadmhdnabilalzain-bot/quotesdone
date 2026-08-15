
# Founder Command Center Architecture

## Canonical interface role

Use `chief_of_staff` as the founder-facing command secretary. Do not create a 91st standing role.

The UI display name may be:

```text
Founder Command Secretary — Chief of Staff
```

## Required interaction

The founder enters a message in the existing Command Center. The system must:

1. authenticate the canonical founder identity;
2. record the exact message append-only;
3. assign a client-message idempotency key;
4. classify it against the command intent registry;
5. identify existing Phase B workflows and exact accountable roles;
6. identify founder-initiated-only or refund-approval semantics;
7. ask one concise clarification if safe routing is impossible;
8. create the command plan and tasks atomically;
9. return task IDs and owners immediately;
10. update progress from workflow/task events;
11. provide evidence-based completion or blocker summaries;
12. allow status, cancel, supersede and reprioritize commands.

## Command objects

Use existing equivalent objects where better. Otherwise support these logical records:

- command session;
- command message;
- founder command;
- command interpretation/version;
- command plan;
- command-to-workflow link;
- command-to-task link;
- clarification request/answer;
- command status history;
- completion summary.

## Routing rules

- A command may map to one or multiple existing workflows.
- One command has one command owner: Chief of Staff.
- Every child task has one exact accountable role.
- Multi-department commands retain one overall command plan and separate child ownership.
- The Chief of Staff coordinates but does not usurp department ownership.
- No task may be assigned to a generic department, title, code runner or inactive identity.
- No low-confidence guess may create work.
- No raw command directly calls a side-effecting executor.

## Zero-cost interpretation

Phase C uses a deterministic registry, structured forms and test fixtures.

The command-interpretation interface must be provider-pluggable, but paid model routes remain disabled. Unsupported language requests clarification rather than an expensive or unsafe guess.

## Immediate task semantics

For safely recognized commands, the API response is successful only when:

- command row exists;
- interpretation version exists;
- workflow links exist;
- all immediate tasks exist;
- owners resolve;
- idempotency and authority checks pass;
- event-outbox records exist;
- trace exists.

These are committed in one transaction. Downstream execution can occur later.

## Refund behavior

A refund command creates or links a refund case. Only the founder can create the final refund decision. The command secretary cannot approve it. Payment execution starts only after the decision record passes integrity checks.

## Safety

- Founder command does not bypass release, privacy, legal, security or financial controls.
- Blanket or unscoped destructive/financial commands are refused or clarified.
- Every change preserves history.
- Cancellation invokes the workflow's cancellation/compensation policy.
- Completed results link to decision/execution traces and evidence.
