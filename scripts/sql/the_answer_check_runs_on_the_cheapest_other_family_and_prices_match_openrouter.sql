-- THE ANSWER CHECK RUNS ON THE CHEAPEST MODEL OF ANOTHER FAMILY, AND OUR PRICES MATCH OPENROUTER'S (it_engineer, 3 Nov 2026)
--
-- MEASURED (ai_cost_log, 7 days to 3 Nov): knowledge_validation - think()'s independent check of a high-stakes answer -
-- ran 52 times on anthropic/claude-sonnet-5.5 at 23-48k mostly uncached prompt tokens for an ~18-token verdict. The check
-- needs a model of ANOTHER family than the author (fn_ai_route_review_for), not Sonnet: openai/gpt-6-luna-pro (USD 0.10 in /
-- 0.50 out per Mtok, model_registry) reviews every Anthropic author, and google/gemini-3.8-flash (0.825 / 4.125) reviews a
-- Luna author, where Sonnet (2.00 / 10.00) did before. The code-first half is in _shared/think.ts (figuresGrounded): a
-- seat's own answer whose every figure is printed in its sources is agreed by code and never sent here.
--
-- PRICES, read live from OpenRouter GET /api/v1/models on 3 Nov 2026:
--   anthropic/claude-sonnet-5.5  input_cache_write_1h 0.000004 per token = USD 4.00/Mtok (2x input). The chat callers that
--                                write Sonnet's cache ask for the 1-hour tier (ai_gateway cache_ttl '1h'); the ledger
--                                booked those writes at the 5-minute 2.50.
--   openai/gpt-6-luna-pro        input_cache_read 0.00000001 = USD 0.01/Mtok, input_cache_write 0.000000125 = USD 0.125/Mtok.
--                                It caches (OpenAI caches a repeated prefix by itself); the ledger had no cache price for it,
--                                so fn_model_cost_usd billed cached reads at the full input price.
-- supports_cache stays FALSE for Luna on purpose: that column makes ai_gateway send Anthropic-style cache_control blocks.
-- The AED columns of model_rate (what fn_llm_log prices with) follow at the fixed peg 3.6725.
--
-- NOT CHANGED: a 5-minute Sonnet write (rare: the non-chat Sonnet callers) is now booked at the 1-hour price, an
-- overstatement of USD 1.50/Mtok on those writes, never an understatement.
--
--   node scripts/apply_sql.mjs scripts/sql/the_answer_check_runs_on_the_cheapest_other_family_and_prices_match_openrouter.sql --apply --ddl

update public.model_policy
   set model_primary = 'openai/gpt-6-luna-pro', model_fallback = 'google/gemini-3.8-flash'
 where task_class in ('knowledge_validation', 'ceo__knowledge_validation', 'sales_engineer__knowledge_validation');

update public.model_registry set cache_write_per_mtok_usd = 4.00, updated_at = now()
 where model_id = 'anthropic/claude-sonnet-5.5';
update public.model_registry set cache_read_per_mtok_usd = 0.01, cache_write_per_mtok_usd = 0.125, updated_at = now()
 where model_id = 'openai/gpt-6-luna-pro';

update public.model_rate set cache_write_aed_per_mtok = round(4.00 * 3.6725, 6)
 where model = 'anthropic/claude-sonnet-5.5';
update public.model_rate set cache_read_aed_per_mtok = round(0.01 * 3.6725, 6), cache_write_aed_per_mtok = round(0.125 * 3.6725, 6)
 where model = 'openai/gpt-6-luna-pro';

-- PROBE (verdict row; reads only): the three check classes route to two families, neither of them Sonnet, and the prices read back.
select case
  when (select count(*) from public.model_policy
         where task_class in ('knowledge_validation', 'ceo__knowledge_validation', 'sales_engineer__knowledge_validation')
           and model_primary = 'openai/gpt-6-luna-pro' and model_fallback = 'google/gemini-3.8-flash') <> 3
    then 'PROBE FAILED: a knowledge_validation class did not move to luna-pro / gemini-flash'
  when (select cache_write_aed_per_mtok from public.model_rate where model = 'anthropic/claude-sonnet-5.5') <> round(4.00 * 3.6725, 6)
    then 'PROBE FAILED: the Sonnet 1-hour cache write is not booked at USD 4.00/Mtok'
  when (select cache_read_per_mtok_usd from public.model_registry where model_id = 'openai/gpt-6-luna-pro') is distinct from 0.01
    then 'PROBE FAILED: Luna Pro has no cache-read price'
  else 'PROBE OK' end as verdict;
