# Paste this into Claude Code from the QuotesDone repository root

You are the implementation engineer for QuotesDone. Treat the files in this package as a target specification and reference migration, not permission to overwrite working production code.

## Goal

Turn the existing agent framework into a measurable autonomous employee system while reducing OpenRouter spend and preserving safety. Employees must report to managers, own KPIs, act within authority, run controlled improvements, measure outcomes and learn. The founder should monitor routine operations and receive only strategic or exceptional decisions.

## Inputs

- the live QuotesDone repository;
- staging Supabase project;
- the previously supplied 86-category knowledge corpus;
- company-operations corpus;
- OS/portal/autonomy architecture package;
- this AI autonomy/model/tools pack.

## Phase 0 — audit before changing anything

1. Compare the live repo and live staging schema to the July 29 export.
2. Inventory every LLM call, including direct OpenRouter/provider calls.
3. Inventory every employee, manager, KPI, authority rule, executor, event, workflow and cron.
4. Inventory the actual status of these services: Supabase, Vercel, OpenRouter, Resend, GoDaddy, Twilio, Meta Ads, Stripe, GitHub and Postiz.
5. Check for current code dependencies on Dropbox, Apify, CloudConvert, VirusTotal and direct OpenAI image generation.
6. Return a gap report before applying production changes.

## Phase 1 — model routing and cost

1. Update `model_registry` from the current OpenRouter model API; do not trust stale hard-coded availability or pricing.
2. Implement the policies in `04_MODEL_POLICY_BY_TASK_CLASS.csv`.
3. Change `agent_reasoning` from blanket Sonnet/Opus to DeepSeek V4 Flash primary, Sonnet escalation.
4. Keep Chief of Staff, material legal/finance/security and final customer reports on Sonnet, with Opus only through explicit risk triggers.
5. Introduce Qwen3.7 Flash canary for high-volume routing/extraction, then promote only after benchmark acceptance.
6. Use Gemini 3.5 Flash Lite / 3.6 Flash for multimodal document work.
7. Use Qwen3 ASR Flash for speech transcription.
8. Use batch model variants for nightly/weekly non-interactive work.
9. Migrate `resend_inbound` and every remaining chat-completion bypass through `ai_gateway`.
10. Replace model-based health pings with provider health/key/status requests.
11. Add OpenRouter `session_id`, prompt caching, fallbacks and sensitive-data provider policy (`zdr`/no-data-collection) where appropriate.
12. Enforce strict output caps, JSON schemas and retrieval limits.
13. Keep Supabase `gte-small` embeddings unless retrieval benchmark results justify a paid alternative.

## Phase 2 — employee runtime

Implement or adapt:

- employee goals and KPI assignments;
- manager/direct-report hierarchy;
- employee authority per action class;
- employee report schedule;
- experiment registry;
- outcome ledger and KPI attribution;
- autonomy level per employee/action class;
- reputation and improvement plan;
- durable workflow runs and step runs;
- idempotency, retry, dead-letter and compensation;
- unified decision/action trace.

Use Supabase Queues/PGMQ unless a measured limitation requires another orchestrator.

## Phase 3 — smart supplier acquisition

Build the workflow in `09_SUPPLIER_OUTREACH_EXPERIMENT_ENGINE.md`:

- one canonical funnel from discovered company to active supplier;
- campaign/variant/source/channel attribution;
- email verification gate;
- category and emirate coverage diagnosis;
- controlled A/B/canary experiments;
- automatic pause for bounce/complaint thresholds;
- registration and first-quote attribution;
- daily employee report and weekly manager review;
- public company/Google Places/approved directory sourcing;
- no unauthorized LinkedIn scraping.

Connect Apify and/or Google Places through limited credentials and cost caps. Preserve source and collection date.

## Phase 4 — missing runtime tools

Implement the connector matrix. Do not silently create accounts or use production secrets. For every connector:

- least-privilege staging credential;
- health check;
- webhook signature verification;
- rate/cost limit;
- retry and dead-letter behavior;
- usage/cost collection;
- kill switch;
- audit trace.

## Phase 5 — tests and rollout

1. Run current tests and add model-routing, queue, idempotency, compensation, employee-loop and outreach-funnel tests.
2. Benchmark representative real tasks across primary/fallback models.
3. Run shadow mode first.
4. Enable only low-risk reversible action classes as canaries.
5. Produce the acceptance report in `11_ACCEPTANCE_GATES.md`.
6. Stop before production activation and request founder approval with a clear migration/rollback plan.

## Non-negotiable safety

- No model directly moves money or changes ledger state.
- No model silently approves legal/regulatory knowledge.
- No supplier/customer identity leakage.
- No unauthorized LinkedIn scraping.
- No unbounded autonomous spend.
- No production schema migration without backup, dry run and rollback.
- No claim that a task succeeded without verification from the target system.

## Required output

Return:

- audit findings;
- files/schema changed;
- connectors missing or unhealthy;
- model registry and task routing before/after;
- benchmark results and estimated cost impact;
- employee/action coverage matrix;
- test results;
- shadow/canary plan;
- unresolved risks;
- exact rollback procedure.
