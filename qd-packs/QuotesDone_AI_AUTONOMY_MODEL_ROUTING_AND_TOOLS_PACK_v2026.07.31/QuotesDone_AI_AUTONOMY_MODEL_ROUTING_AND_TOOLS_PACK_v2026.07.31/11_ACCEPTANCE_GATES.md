# Acceptance gates

Claude must not call the company autonomous until these gates pass in staging and then in controlled production canaries.

## AI cost and routing

- 100% of chat/model calls flow through `ai_gateway` or an explicitly audited non-chat provider endpoint.
- 0 active policy rows reference unavailable model IDs.
- At least 70% of routine business decisions complete with deterministic code/cache/no LLM after the knowledge corpus is connected.
- At least 90% of high-volume classification/extraction calls use the cheap tier unless a benchmarked confidence rule escalates them.
- Opus use remains below the configured ceiling and always carries an escalation reason.
- Every call logs model, task, agent, tokens, latency, cost, cache and outcome.
- Sensitive tasks enforce the approved provider data policy.

## Employee behavior

- Every active employee has a manager, responsibilities, KPIs, authority, knowledge, tools, report cadence and improvement plan.
- Every task links to a goal/KPI or an incident/obligation.
- Every external action has pre/post events, idempotency and verification.
- Every manager receives periodic evidence-based reports.
- Every completed improvement experiment has a baseline, result and verdict.
- Employees may propose improvements unprompted but may not exceed authority.

## Workflow resilience

- Queue redelivery, duplicate delivery and worker crash tests pass.
- Dead-letter and retry dashboards work.
- Compensation is tested for at least one action in every irreversible workflow family.
- Provider outage drills pass for OpenRouter, Resend, Twilio, Stripe, Vercel and Supabase-dependent workers.
- Restore-from-backup drill is documented and tested.

## Supplier outreach

- Contact source and verification date are stored.
- Bounce, reply, registration, verification and first-quote funnel metrics are reproducible.
- Hard-bounce/complaint thresholds auto-pause affected campaigns.
- Variant and source attribution works.
- The employee can change only approved low-risk variables inside a cost/exposure cap.
- No LinkedIn scraping or prohibited data extraction exists in code or configured actors.
- Opt-out and suppression gates pass.

## Marketplace and privacy

- 86-category routing tests pass.
- Inquiry qualification can complete representative scenarios without live web research.
- Quote comparison ranks all quotes deterministically before AI explanation.
- Customer and supplier identities remain protected until authorized reveal.
- Redaction and attachment tests fail closed.

## Founder experience

- Default Command Center mode is observe-first.
- Founder receives only material exceptions, risks and strategic approvals.
- Every recommendation exposes evidence, assumptions, alternatives, expected impact, confidence and cost.
- The company timeline and decision trace can reconstruct any automated action.
