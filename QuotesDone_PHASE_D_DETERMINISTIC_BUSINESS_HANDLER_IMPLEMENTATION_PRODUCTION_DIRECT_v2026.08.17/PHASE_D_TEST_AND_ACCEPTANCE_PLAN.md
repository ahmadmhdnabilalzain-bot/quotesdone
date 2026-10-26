# Zero-Cost Test and Acceptance Plan

## Layers

- Static/source caller and direct-DML analysis.
- Database constraints, RLS, states, idempotency, locks, append-only evidence and cancellation.
- Per-step handler contracts.
- Per-workflow deterministic closure/failure/cancel/replay.
- Adversarial catalogue.
- Launch-critical deployed UI/API chain with no external effect.

## Per-step tests

For all 257:

- positive;
- missing input;
- wrong actor;
- invalid state;
- duplicate;
- rule/gate failure;
- malformed output.

Capability/provider handlers use deterministic fixtures and fail closed in real context.

## Workflow tests

For all 30:

- happy path to explicit closure;
- failure/block;
- cancellation;
- idempotent replay;
- no external effect.

## Honest denominators

A test expecting rows is invalid if denominator is zero.

## Required completion counts

257/257 handlers and schemas; 30/30 workflow closures; 56/56 objects; 54/54 rules; 32/32 gates; all effective handoffs; 347/347 events; 100% injected defects refused; zero direct bypasses, creator/reviewer collisions, external effects or paid inference.
