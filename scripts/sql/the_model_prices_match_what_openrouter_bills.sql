-- THE MODEL PRICES MATCH WHAT OPENROUTER BILLS (it_engineer, 3 Nov 2026)
--
-- MEASURED: USD 11.79 billed by OpenRouter in the 7 days to 3 Nov that ai_cost_log did not price. Part of it is our own
-- price list. Read live from OpenRouter GET /api/v1/models on 3 Nov 2026:
--   anthropic/claude-sonnet-5.5  input_cache_write_1h 0.000004 per token = USD 4.00/Mtok (2x input). The chat callers that
--                                write Sonnet's cache ask for the 1-hour tier (ai_gateway cache_ttl '1h'); the ledger
--                                booked those writes at the 5-minute USD 2.50.
--   openai/gpt-6-luna-pro        input_cache_read 0.00000001 = USD 0.01/Mtok, input_cache_write 0.000000125 = USD 0.125/Mtok.
--                                It caches (OpenAI caches a repeated prefix by itself); the ledger had no cache price for it,
--                                so fn_model_cost_usd billed its cached reads at the full input price.
-- model_rate (AED, what fn_llm_log prices with) follows at the fixed peg 3.6725; model_registry (USD) is the same figure.
--
-- NOT CHANGED, deliberately:
--   * supports_cache stays FALSE for Luna Pro: that column makes ai_gateway send Anthropic-style cache_control blocks.
--   * a 5-minute Sonnet write (the few non-chat Sonnet callers) is now booked at the 1-hour price: an overstatement of
--     USD 1.50/Mtok on those writes, never an understatement.
--   * the knowledge_validation route. It was proposed to move the independent check off Sonnet; ruling 1241 (18 Oct 2026,
--     the founder's model matrix v3) keeps Gemini to the hearing routes and the review route at Sonnet 5.5 with Luna Pro
--     behind it (every_seat_runs_the_founders_model_matrix_probe.sql), and fn_ai_route_review_for already gives an
--     Anthropic author the Luna Pro reviewer. The saving for that class is made in code instead (_shared/think.ts
--     figuresGrounded: a seat's own answer whose every figure is printed in one of its sources is agreed without a model).
--
--   node scripts/apply_sql.mjs scripts/sql/the_model_prices_match_what_openrouter_bills.sql --apply --ddl

update public.model_registry set cache_write_per_mtok_usd = 4.00, updated_at = now()
 where model_id = 'anthropic/claude-sonnet-5.5';
update public.model_registry set cache_read_per_mtok_usd = 0.01, cache_write_per_mtok_usd = 0.125, updated_at = now()
 where model_id = 'openai/gpt-6-luna-pro';

update public.model_rate set cache_write_aed_per_mtok = round(4.00 * 3.6725, 6)
 where model = 'anthropic/claude-sonnet-5.5';
update public.model_rate set cache_read_aed_per_mtok = round(0.01 * 3.6725, 6), cache_write_aed_per_mtok = round(0.125 * 3.6725, 6)
 where model = 'openai/gpt-6-luna-pro';

-- PROBE (verdict row; reads only): the prices read back.
select case
  when (select cache_write_aed_per_mtok from public.model_rate where model = 'anthropic/claude-sonnet-5.5') is distinct from round(4.00 * 3.6725, 6)
    then 'PROBE FAILED: the Sonnet 1-hour cache write is not booked at USD 4.00/Mtok'
  when (select cache_read_aed_per_mtok from public.model_rate where model = 'openai/gpt-6-luna-pro') is distinct from round(0.01 * 3.6725, 6)
    then 'PROBE FAILED: Luna Pro has no cache-read price in model_rate'
  when (select cache_read_per_mtok_usd from public.model_registry where model_id = 'openai/gpt-6-luna-pro') is distinct from 0.01
    then 'PROBE FAILED: Luna Pro has no cache-read price in model_registry'
  else 'PROBE OK' end as verdict;
