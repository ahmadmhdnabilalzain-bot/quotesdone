-- DEEPSEEK V4.1 FLASH COSTS WHAT THE CATALOGUE NOW CHARGES.
-- Seat: it_engineer. 30 Sep 2026, release operator.
--
-- MEASURED 30 Sep 2026 ~10:10Z. scripts/checks/the_registry_prices_are_the_catalogue_s_prices.test.mjs went red on
-- every branch with two findings and no others:
--   deepseek/deepseek-v4.1-flash in:  file says 0.3, catalogue serves 0.0198
--   deepseek/deepseek-v4.1-flash out: file says 1.2, catalogue serves 0.396
-- Re-read live from this session (https://openrouter.ai/api/v1/models): prompt 0.0000000198, completion 0.000000396,
-- input_cache_read 0.00000000291, context 1048576 (unchanged). Every other ACTIVE registry row matched on in/out.
--
-- WHAT CHANGES: model_registry in/out for deepseek/deepseek-v4.1-flash, context restated unchanged (the price check
-- parses the three together). No model_rate row exists for it (read live), so none is written. No route moves:
-- deepseek is every other seat's named plan B (founder_instruction 1056); one price-ordered pick moves, below.
-- ROUTES, measured in an aborted transaction (582 class x caps x escalate and seat x caps routes, before vs after):
-- only marketing_geo_search called WITH vision or tools caps moves, openai/gpt-6-luna -> deepseek/deepseek-v4.1-flash
-- (its :online primary lacks those caps, so a price-ordered substitution runs). DeepSeek is already marketing's
-- named plan B under the founder's matrix (1056), so this stays inside it. Every other route is unchanged.
-- No routine, table or grant. OpenRouter hold untouched. No begin/commit: a replaying check must not commit it.
-- Ends in a PROBE verdict row.


update public.model_registry set context_len = 1048576, in_per_mtok_usd = 0.0198,
       out_per_mtok_usd = 0.396, updated_at = now()
 where model_id = 'deepseek/deepseek-v4.1-flash';

select case when (select count(*) from public.model_registry where model_id = 'deepseek/deepseek-v4.1-flash'
                    and context_len = 1048576 and in_per_mtok_usd = 0.0198 and out_per_mtok_usd = 0.396) = 1
            then 'PROBE OK :: deepseek/deepseek-v4.1-flash is 0.0198/0.396, context 1048576'
            else 'PROBE FAILED :: the deepseek registry row did not take the catalogue price' end as verdict;

