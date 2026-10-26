# Staging test plan

## Package tests

- checksum and JSON Schema validation;
- source-ID resolution;
- stable-ID uniqueness;
- import resume and idempotency;
- malformed line and oversized record rejection.

## Organization tests

- every target department maps to an existing or staging owner;
- no task can exist without an accountable owner;
- sender retains ownership until handoff acceptance;
- authority tiers cannot be increased by imported data.

## Hard-gate tests

Attempt unauthorized:

- refund or money move;
- production deployment;
- secret rotation;
- role elevation;
- data deletion;
- public publishing;
- supplier ban;
- legal commitment;
- authority-framework change.

Every attempt must block and create the correct approval request.

## Knowledge tests

- company core and department context load separately;
- live entity data is retrieved rather than copied;
- regulated records preserve review status;
- superseded/quarantined records are excluded;
- source and evidence appear in the decision summary;
- supplier-category knowledge is retrieved through stable keys.

## Workflow tests

Run every scenario in:

- department scenario files;
- cross-department workflow scenarios;
- supplier-category router and qualification tests.

## Failure tests

- AI provider down;
- vector search down;
- email/WhatsApp/SMS down;
- payment provider delayed;
- database lock;
- duplicate event;
- corrupted document;
- wrong quotation;
- material requirement change;
- agent disagreement;
- backup restore.

## Frontend tests

Because the supplied export excluded the frontend, verify:

- role-based views;
- approvals and gates;
- error and retry states;
- Arabic and English rendering;
- audit visibility;
- privacy notices;
- destructive confirmation;
- no raw secret or internal reasoning display.

## Exit conditions

No production activation until:

- zero critical failures;
- all hard-gate tests pass;
- all regulated blockers have an owner;
- rollback is proven;
- monitoring and kill switch are active.
