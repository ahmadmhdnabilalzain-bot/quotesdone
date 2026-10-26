# What remains after the previous architecture packages are implemented

Implementing the knowledge, OS, portal and workflow packages makes QuotesDone **architecture-complete**, but not automatically production-autonomous. The following items still have to be proven with real executions.

## 1. Runtime action coverage

Every employee needs real, typed tools—not only the ability to draft a plan. For each role, create an allow-listed action registry with:

- action class;
- required inputs and validation schema;
- authority tier;
- budget ceiling;
- idempotency key;
- rollback or compensation action;
- verification query;
- audit event;
- KPI outcome link.

A task is not complete because an agent wrote a recommendation. It is complete only when the authorized action occurred and its result was verified.

## 2. Durable work execution

Use a queue and workflow-run model for all multi-step work. Every run needs:

- correlation ID;
- workflow version;
- current step;
- lease/visibility timeout;
- idempotency key;
- retry policy;
- dead-letter state;
- compensation state;
- evidence;
- outcome record.

Use Supabase Queues/PGMQ first. Add an external workflow platform only if the measured workload outgrows the Postgres-native design.

## 3. Outcome attribution and controlled experimentation

Employees cannot improve merely by saving a memory. They need an experiment and outcome engine:

- baseline KPI;
- hypothesis;
- intervention;
- control/canary group;
- budget and maximum exposure;
- success and stop conditions;
- measurement window;
- result and confidence;
- promote, revise or retire decision;
- lesson linked to the employee, manager, workflow and KPI.

## 4. Management and reporting rhythm

Each employee reports to a manager. Each manager reviews the team's evidence, KPIs, rework, cost and risks. The Chief of Staff consolidates department reports and sends the founder only:

- decisions beyond delegated authority;
- serious risks;
- material budget changes;
- persistent KPI failures;
- opportunities requiring strategic judgment.

Routine success should be visible in the Command Center but should not require founder approval.

## 5. Live-data proof

No autonomous employee should receive more authority solely because the code exists. Autonomy must be earned through:

- shadow-mode accuracy;
- successful canary actions;
- low rework and incident rate;
- KPI improvement;
- consistent audit evidence;
- acceptable cost per outcome.

Recommended progression:

1. **Shadow:** recommend only; compare with real outcomes.
2. **Constrained:** execute reversible, low-risk actions within small budgets.
3. **Expanded:** execute standard operational workflows after meeting quality thresholds.
4. **Monitor-only founder experience:** founder handles exceptions and strategic decisions.

## 6. Knowledge approval and freshness

The corpora are research-complete drafts, not blanket professional approval. Before regulated records become autonomous authority:

- UAE legal/tax/privacy records require legal/compliance review;
- engineering and regulatory records require relevant SME review;
- dynamic certificates, prices, product models and authority procedures require refresh jobs;
- every retrieved answer must preserve source, version, date, confidence and escalation rule.

## 7. Observability, security and disaster recovery

Before unattended operation, prove:

- frontend and edge-function error tracing;
- queue and workflow health;
- provider latency and cost visibility;
- backup restore tests;
- model-provider outage fallback;
- Stripe/Twilio/Resend/Postiz failure recovery;
- secrets rotation;
- privacy and redaction fail-closed behavior;
- penetration testing and incident runbooks.

## 8. Frontend completion

The supplied export did not include the Next.js frontend. Claude must audit the actual repository and verify that the Command Center, supplier portal and customer portal expose the required data and controls. Backend objects alone do not prove the UX exists.

## End state

The practical target is not unrestricted AI. It is a policy-governed company in which 90%+ of routine work is completed without founder involvement, while financial, legal, privacy, security and irreversible decisions remain within explicit authority limits.
