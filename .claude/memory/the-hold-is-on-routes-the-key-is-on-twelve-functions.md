---
name: the-hold-is-on-routes-the-key-is-on-twelve-functions
description: "The founder's \"no OpenRouter\" hold lives in llm_route_health and only ai_gateway reads it; 11 other edge functions hold the key directly, and cron job 102 hits openrouter.ai every 15 minutes."
metadata: 
  node_type: memory
  type: project
  originSessionId: 9f1a5f09-0430-4380-80c9-8676a24ac346
  modified: 2026-08-16T10:01:04.172Z
---

Measured 16 Aug 2026. The founder's hold — `llm_route_health.open_until = 2126-08-15`, reason *"HELD BY THE
FOUNDER 15 Aug 2026: no OpenRouter calls until he releases it"* — is enforced by `fn_llm_preflight`, and
**only `ai_gateway` calls it**.

Twelve deployed edge functions read `app_secrets.openrouter_api_key`:
`ai_gateway ai_health archive_rfq cost_snapshot doc_render ea_meeting_summary enrich_capability
gen_category_knowledge gen_category_personas learn_gaps reflect resend_inbound`.
Three of the eleven without a preflight also name `openrouter.ai` directly: `ai_health`, `cost_snapshot`,
`resend_inbound`.

`cron.job` **102 `ai_health_15min`** (`7,22,37,52 * * * *`, active) fetches
`https://openrouter.ai/api/v1/key` on every run — six outbound OpenRouter requests during a 37-minute audit.
`cost_snapshot` jobs 36 and 175 do the same against `/api/v1/credits` but are **inactive**.

Say the distinction out loud whenever this comes up: `/api/v1/key` and `/api/v1/credits` are **free metadata
endpoints, not inference**. Spend really was AED 0.00 on both ledgers (`llm_attempt`, `ai_cost_log`). A gate
worded "OpenRouter requests = 0" still fails; a gate worded "paid inference = 0" passes.

Two further holes: `ai_gateway/index.ts:455` records that `fn_llm_preflight` answers `allowed=true` for a
null/unknown route, and the hold is enumerated per `model_id` over 8 rows — see
[[a-list-with-no-third-answer]]. And the invariant `paid_inference_since_phase_c_started` anchors its window to
`max(recorded_at)` from `phase_c_package_erratum`, so recording an erratum moves the window forward.

**How to apply:** "spend is zero" and "the provider is unreachable" are different claims. Before asserting the
second, list every function that reads the credential and check which of them consult the hold.
