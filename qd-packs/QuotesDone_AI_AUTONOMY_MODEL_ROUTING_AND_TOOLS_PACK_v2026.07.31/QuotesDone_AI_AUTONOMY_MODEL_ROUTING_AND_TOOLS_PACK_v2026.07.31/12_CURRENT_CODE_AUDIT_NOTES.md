# QuotesDone current AI and outreach audit notes

Source: `quotesdone-export-2026-07-29.zip` supplied by the user.

## 1. Central AI gateway already exists

File: `functions/ai_gateway.md`

The gateway describes itself as the single company-wide AI router. Its operating order is:

1. Rate limit before spending.
2. Level-0 template / approved FAQ response with no model.
3. Deterministic model routing through `fn_ai_route`.
4. Refusal when deterministic code is the correct alternative.
5. Department budget halt/degradation.
6. Exact and semantic cache using Supabase in-region `gte-small` embeddings.
7. Provider call with hard output limits and model fallback ladder.
8. Cost logging.

It also supports capability-aware routing for vision, audio, files, tools and response schemas.

## 2. Current exported model registry is already outdated relative to 31 July 2026

File: `migrations/20260728204813_ai_model_registry.md`

The export registers:

- `google/gemini-3.1-flash-lite` as small primary.
- `qwen/qwen3.7-plus` as small fallback.
- `~anthropic/claude-haiku-latest` and `google/gemini-3.5-flash` as medium.
- `anthropic/claude-sonnet-5` as large.
- `anthropic/claude-opus-4.8` as xlarge.

The policy was priced on 28 July 2026. Newer/current model choices therefore need to be refreshed from the OpenRouter model API rather than hard-coded permanently.

## 3. Current function-to-task routing

File: `migrations/20260728204939_ai_fn_task_class_map_and_cheap_tier.md`

Examples:

- Small: RFQ routing, JSON extraction, category classification, missing fields, supplier matching, intent detection, health pings.
- Medium: customer communication, marketing/content, knowledge research, quote comparison, procurement reasoning.
- Large: employee reasoning, Chief of Staff execution, departmental planning, orchestration and legal review.

This is a good base, but the current export still routes every `agent_brain`, `cos_execute`, `dept_plan`, reflection and department learning call to the large tier. That is the biggest avoidable cost area.

## 4. Supplier outreach tracking already exists

File: `migrations/20260723215926_supplier_invites_autonomous.md`

The system already includes:

- Autonomous supplier invitations.
- A hard daily cap.
- Automatic pause when recent bounce rate is above the safety limit.
- Category/trade balancing.
- `v_invite_funnel`, showing invited, delivered, bounced and registered.
- `v_invite_nonresponders`, showing invited suppliers who have not registered after seven days.

File: `migrations/20260728103435_invite_balance_across_canonical_categories.md`

A later migration moves balancing toward the canonical category taxonomy and retains deliverability protections.

## 5. Supplier discovery / scraping support already exists but needs an Apify connection

File: `functions/apify_scrape.md`

The function:

- Calls Apify.
- Runs a Google Places crawler.
- Stores company name, phone, website, address, Maps details, email, Instagram, Facebook and LinkedIn URL in `leads`.
- Deduplicates by place ID and email.
- Requires `app_secrets.apify_token`.

File: `migrations/20260727002021_company_economics_and_resource_management.md`

The resource pool explicitly lists `Apify` for scraping/enrichment and notes a 20,000-record monthly capacity.

## 6. Dropbox is part of the current architecture

Multiple functions and migrations use Dropbox for legal evidence, document backups, supplier category folders and PDPL erasure. If Dropbox is not connected in production, these workflows are incomplete.

## 7. One direct AI bypass remains visible

A search of the exported functions shows `resend_inbound` still contains a direct OpenRouter call in addition to `ai_gateway`. It should be migrated through the gateway so its cost, model policy, privacy controls, caching and budget limits are consistently enforced.
