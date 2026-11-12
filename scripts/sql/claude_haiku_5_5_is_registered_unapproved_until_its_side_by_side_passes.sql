-- CLAUDE HAIKU 5.5 IS REGISTERED, UNAPPROVED AND INACTIVE, UNTIL ITS SIDE-BY-SIDE PASSES.
-- Seat: it_engineer (cost). 11 Nov 2026. Founder rulings 1619 ("cut the ~45,000 tokens per AI call without affecting
-- quality ... the budget is drained") and 1618 (model choice is IT's, switched only after a side-by-side on identical inputs
-- shows the difference is minimal). Report: docs/reports/2026-11-11-prompt-diet.md.
--
-- MEASURED BEFORE WRITING (production htdblwldjkcgjvmqkbeh, read-only, 10-11 Nov 2026):
--   * model_registry has NO anthropic/claude-haiku-5.5 row. The one Haiku row is '~anthropic/claude-haiku-latest' (medium,
--     USD 0.10 / 0.50, approved and active, routed by no model_policy row).
--   * 46 of 100 model_policy rows fall back to anthropic/claude-sonnet-5.5 (USD 2.00 / 10.00); review_pool rank 1 is Sonnet 5.5.
--     Sonnet 5.5 cost AED 18.04 of the 7-day AED 41.71 (83 calls), mostly reviews and the other-family rung.
--
-- WHAT THIS FILE DOES: one model_registry row for anthropic/claude-haiku-5.5 at the price the paid round was planned with
-- (USD 0.10 in / 0.50 out per Mtok), approved = false and active = false, so no router branch can choose it (fn_ai_route reads
-- active and approved rows; fn_ai_route_review_for rejects "inactive or unapproved"). Tier 'medium', as the Haiku row beside
-- it: at Luna Pro's price a 'small' row would tie Luna Pro for "the cheapest small model" the day it is activated.
-- READ FROM THE OPENROUTER CATALOGUE BEFORE APPLYING (12 Nov 2026, https://openrouter.ai/api/v1/models, anthropic/claude-haiku-5.5):
-- prompt USD 0.10 and completion USD 0.50 per Mtok (as planned), cache read USD 0.01 and cache write USD 0.125 per Mtok,
-- context_length 1,000,000, input modalities text, image and file (so supports_vision is true, supports_audio false).
-- The catalogue also lists a HIGHER price above 100,000 prompt tokens (USD 0.50 in / 2.50 out per Mtok). model_registry has no
-- column for a tiered price, so 0.10 / 0.50 understates a long prompt five-fold: settle that before the row is ever activated.
-- supports_cache is true because the gateway sends Anthropic cache_control only on that flag, as every Claude row.
--
-- NOT HERE, ON PURPOSE: no model_policy, review_pool, model_rate or llm_route_health row. Those follow the side-by-side
-- (scripts/eval/prompt_diet_eval.mjs, parts P4 reviewer and P5 fallback) in their own file, and only for INTERNAL classes:
-- ledger 1217 keeps customer chat off the small Claude model, so conversation_reply, visitor_chat and the portal assistant
-- keep Sonnet 5.5 as their fallback whatever the eval says.
--
-- Before applying: read the model's live price, context and modalities from the OpenRouter catalogue; correct this file if
-- they differ; then add it to OWNING_SQLS in scripts/checks/the_registry_prices_are_the_catalogue_s_prices.test.mjs.
--   applied when its pending note says: node scripts/apply_sql.mjs scripts/sql/claude_haiku_5_5_is_registered_unapproved_until_its_side_by_side_passes.sql --apply --ddl --seat it_engineer

insert into public.model_registry (model_id, provider, tier, in_per_mtok_usd, out_per_mtok_usd,
  cache_read_per_mtok_usd, cache_write_per_mtok_usd, supports_cache, supports_streaming, context_len, approved, active,
  quality_score, note, supports_vision, supports_audio, supports_tools)
values
  ('anthropic/claude-haiku-5.5', 'anthropic', 'medium', 0.10, 0.50,
   0.01, 0.125, true, true, 1000000, false, false, null,
   'Registered 11 Nov 2026, NOT approved and NOT active (rulings 1619, 1618): the candidate reviewer and fallback of the INTERNAL classes that fall back to Sonnet 5.5, pending the side-by-side in scripts/eval/prompt_diet_eval.mjs (P4 reviewer, P5 fallback). Never a customer-chat route (ledger 1217). USD 0.10 / 0.50 per Mtok, cache 0.01 / 0.125, context 1,000,000, text+image+file: read from the OpenRouter catalogue on 12 Nov 2026.',
   true, false, true)
on conflict (model_id) do nothing;

-- VERDICT (read-only; never raises): the row exists and nothing can route to it.
select case
  when not exists (select 1 from public.model_registry where model_id = 'anthropic/claude-haiku-5.5')
    then 'PROBE FAILED: the anthropic/claude-haiku-5.5 row is missing'
  when exists (select 1 from public.model_registry where model_id = 'anthropic/claude-haiku-5.5' and (approved or active))
    then 'PROBE FAILED: anthropic/claude-haiku-5.5 already existed approved or active; this file changed nothing, read the row before routing'
  when exists (select 1 from public.model_policy where 'anthropic/claude-haiku-5.5' in (model_primary, model_fallback))
    then 'PROBE FAILED: a model_policy row names anthropic/claude-haiku-5.5 before its side-by-side passed'
  else 'PROBE OK: anthropic/claude-haiku-5.5 registered, unapproved and inactive; no policy names it'
end as verdict;
