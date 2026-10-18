-- DEEPSEEK V4.1 FLASH COSTS WHAT THE CATALOGUE CHARGES ON 5 OCTOBER.
-- Seat: it_engineer. 5 Oct 2026, release operator.
--
-- MEASURED 5 Oct 2026 ~06:10Z: scripts/checks/the_registry_prices_are_the_catalogue_s_prices.test.mjs red on #1214 with
--   deepseek/deepseek-v4.1-flash in: file says 0.003, catalogue serves 0.3 / out: file says 2.4, catalogue serves 1.2
-- Re-read live (https://openrouter.ai/api/v1/models): prompt 0.0000003, completion 0.0000012, cache read 0.000000006,
-- context 1048576. This is the price of 29 Sep; the catalogue has moved this model three times in six days
-- (0.3/1.2 -> 0.0198/0.396 -> 0.003/2.4 -> 0.3/1.2). The daily sync (#1187) is the lasting answer.
-- ROUTES, one aborted transaction before vs after, 800 routes (every active class and seat x caps x escalate):
-- 6 move, all marketing_geo_search under a vision/tools capability override, deepseek/deepseek-v4.1-flash ->
-- openai/gpt-6-luna: the price-ordered substitute it used before 30 Sep. Every other route is unchanged.
-- No routine, table or grant. No begin/commit. Ends in a PROBE verdict row.

update public.model_registry set context_len = 1048576, in_per_mtok_usd = 0.3,
       out_per_mtok_usd = 1.2, updated_at = now()
 where model_id = 'deepseek/deepseek-v4.1-flash';

select case when (select count(*) from public.model_registry where model_id = 'deepseek/deepseek-v4.1-flash'
                    and context_len = 1048576 and in_per_mtok_usd = 0.3 and out_per_mtok_usd = 1.2) = 1
            then 'PROBE OK :: deepseek/deepseek-v4.1-flash is 0.3/1.2, context 1048576'
            else 'PROBE FAILED :: the deepseek registry row did not take the catalogue price' end as verdict;
