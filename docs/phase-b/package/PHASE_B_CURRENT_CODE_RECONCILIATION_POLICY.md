# Phase B Current-Code Reconciliation Policy

The target workflow package does not prove that current code uses it.

Claude must inspect every current execution path and create a complete crosswalk.

## Sources to inspect

- frontend routes, buttons, forms and API clients;
- Edge Functions;
- database functions and procedures;
- triggers;
- state columns and constraints;
- queues;
- cron jobs;
- event subscriptions;
- workflow/step tables;
- notification functions;
- payment/refund handlers;
- supplier/customer/admin portals;
- direct provider calls.

## Required classifications

- `CANONICAL_KEEP`: current path matches the target and is the chosen future path.
- `CANONICAL_BETTER_KEEP`: current path is demonstrably better while respecting mandatory invariants.
- `CANONICAL_PARTIAL`: current path implements part of the target.
- `DUPLICATE_PATH`: another path makes the same business decision.
- `CONFLICTING_PATH`: current behavior contradicts the canonical process.
- `DEAD_CODE`: no real caller or consumer.
- `UNOWNED`: execution occurs under a code runner/generic identity rather than accountable role.
- `OUT_OF_SCOPE`: unrelated to the 30 workflows.
- `PHASE_C_WIRING_GAP`: target structure exists but runtime is not connected.

## Phase B action

Phase B may:

- establish canonical workflow/step/state/business-rule metadata;
- add deterministic structural constraints;
- correct ownership metadata;
- mark duplicate/conflicting paths;
- preserve historical compatibility.

Phase B must not:

- connect tools/models;
- activate autonomous execution;
- reroute live business traffic;
- send messages;
- run payments/refunds;
- create synthetic business records;
- claim end-to-end behavior.

Actual runtime connection/removal of duplicate execution paths belongs to Phase C.
