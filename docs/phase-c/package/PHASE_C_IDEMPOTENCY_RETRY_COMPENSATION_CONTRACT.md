
# Idempotency, Retry and Compensation Contract

Every state-changing entry point requires an explicit idempotency scope.

A retry must:

- preserve the first attempt;
- link parent/child attempts;
- not duplicate assignments, notifications, payments, refunds, tasks, events or files;
- distinguish infrastructure retry from professional reconsideration;
- stop at configured limits;
- expose eventual and first-attempt success separately.

Irreversible actions require a compensation or explicit non-reversible classification and stronger review.

No generic retry loop may replay an unknown side effect.
