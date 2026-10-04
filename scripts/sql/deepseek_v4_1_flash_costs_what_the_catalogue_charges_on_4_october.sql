-- DEEPSEEK V4.1 FLASH COSTS WHAT THE CATALOGUE CHARGES ON 4 OCTOBER.
-- Seat: it_engineer. 4 Oct 2026, release operator.
--
-- MEASURED 4 Oct 2026 ~20:20Z. scripts/checks/the_registry_prices_are_the_catalogue_s_prices.test.mjs went red on
-- every branch (#1147, #1149, #1177) with two findings and no others:
--   deepseek/deepseek-v4.1-flash in:  file says 0.0198, catalogue serves 0.003
--   deepseek/deepseek-v4.1-flash out: file says 0.396, catalogue serves 2.4
-- Re-read live from this session (https://openrouter.ai/api/v1/models): prompt 0.000000003, completion 0.0000024,
-- input_cache_read 0.000000003, context 1048576 (unchanged). Production before this file: 1048576, 0.0198, 0.396.
--
-- WHAT CHANGES: model_registry in/out for deepseek/deepseek-v4.1-flash, context restated unchanged (the price check
-- parses the three together). No model_rate row exists for it (read live 4 Oct), so none is written.
-- ROUTES, measured in one aborted transaction before vs after: 800 routes (every active model_policy class and every
-- active seat, x caps none / vision / tools / vision+tools, x escalate false / true) - 0 moved.
-- No routine, table or grant. OpenRouter hold untouched. No begin/commit: a replaying check must not commit it.
-- Ends in a PROBE verdict row.

update public.model_registry set context_len = 1048576, in_per_mtok_usd = 0.003,
       out_per_mtok_usd = 2.4, updated_at = now()
 where model_id = 'deepseek/deepseek-v4.1-flash';

select case when (select count(*) from public.model_registry where model_id = 'deepseek/deepseek-v4.1-flash'
                    and context_len = 1048576 and in_per_mtok_usd = 0.003 and out_per_mtok_usd = 2.4) = 1
            then 'PROBE OK :: deepseek/deepseek-v4.1-flash is 0.003/2.4, context 1048576'
            else 'PROBE FAILED :: the deepseek registry row did not take the catalogue price' end as verdict;
