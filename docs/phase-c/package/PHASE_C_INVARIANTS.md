
# Phase C Deterministic Invariants

Phase C is ready only when every mandatory invariant returns zero violations.

## Frozen-baseline invariants

- active departments = 10;
- canonical roles = 90;
- category overlays = 86;
- workflows = 30;
- steps = 257;
- handoffs = 161;
- gates = 32;
- rules = 54;
- events = 347;
- Phase A drift = 0;
- Phase B drift = 0;
- unresolved effective Phase B errata = 0.

## Runtime-accountability invariants

- active state-changing components without a canonical system actor = 0;
- active state-changing components without accountable role = 0;
- active state-changing components without workflow/step or explicit justified system scope = 0;
- unclassified Edge Functions = 0;
- unclassified DB functions/triggers = 0;
- unclassified cron jobs = 0;
- unclassified external webhooks/queue consumers = 0;
- active generic actor names used as final owner = 0;
- inactive/unknown employee able to receive/execute current work = 0.

## Binding invariants

- roles without runtime binding row = 0;
- overlays without invocation binding row = 0;
- workflows without runtime binding row = 0;
- steps without runtime binding/classification row = 0;
- handoffs without runtime binding/classification row = 0;
- events without producer/consumer classification = 0;
- gates without enforcement classification = 0;
- hard rules without enforcement classification = 0.

## Founder-command invariants

- founder messages without immutable command record = 0;
- safely routable commands without immediate tasks = 0;
- command tasks without exact canonical owner = 0;
- ambiguous commands that created tasks = 0;
- raw founder messages directly invoking side effects = 0;
- non-refund founder approval requests = 0;
- refund executions without founder decision = 0;
- founder command plans without Chief of Staff owner = 0;
- multi-department child tasks without exact owner = 0.

## Authority/review invariants

- unknown action class allowed = 0;
- creator/reviewer effective-identity collisions = 0;
- reviewer assignment using unresolved alias = 0;
- role action outside authority without refusal/escalation = 0;
- founder-initiated-only commitment without explicit founder command = 0.

## Trace/audit invariants

- completed trace-required command without trace = 0;
- completed trace-required task without trace = 0;
- completed consequential step/action without trace = 0;
- tool claim without stored tool result = 0;
- system execution without accountable role = 0;
- completed trace silently editable = 0.

## State/idempotency invariants

- invalid workflow transitions accepted = 0;
- invalid task transitions accepted = 0;
- duplicate command from same idempotency key = 0;
- duplicate task/assignment/notification/event side effects = 0;
- retry replacing first failure = 0;
- null database row counted as successful insert = 0;
- truncated/invalid output causing state mutation = 0.

## Cost invariants

- OpenRouter request count = 0;
- other paid inference request count = 0;
- paid inference cost = USD 0.00;
- provider route opened during Phase C = 0.
