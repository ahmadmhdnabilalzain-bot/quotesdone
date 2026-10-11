-- HAIKU-LATEST COSTS WHAT THE CATALOGUE CHARGES ON 12 OCTOBER.
-- Seat: it_engineer. 12 Oct 2026, release operator.
--
-- MEASURED 12 Oct 2026 (https://openrouter.ai/api/v1/models, read live): the_registry_prices_are_the_catalogue_s_prices
-- was red on main and on every branch with exactly these findings:
--   ~anthropic/claude-haiku-latest   prompt 0.0000001, completion 0.0000005, context 1000000
--     (the catalogue adds a >100k-prompt-token override of 0.5/2.5; the registry carries the base price, as for every row)
--   deepseek/deepseek-v4.1-flash     prompt 0.0000003, completion 0.0000012, context 1048576
-- deepseek/deepseek-v4.1-flash also differs from the old file trail, but matrix v2 retired it (active = false), so it
-- is not a claim and is left alone.
-- No routine, table or grant. OpenRouter stays on (ruling 1175). No begin/commit. Ends in a PROBE verdict row.

update public.model_registry set context_len = 1000000, in_per_mtok_usd = 0.1,
       out_per_mtok_usd = 0.5, updated_at = now()
 where model_id = '~anthropic/claude-haiku-latest';

update public.model_rate set usd_per_m_prompt = 0.1, usd_per_m_output = 0.5,
       in_aed_per_mtok = 0.36725, out_aed_per_mtok = 1.83625,
       cache_read_aed_per_mtok = 0.036725, cache_write_aed_per_mtok = 0.45906250,
       verified_at = date '2026-10-12', note = 'Re-derived from model_registry at 3.6725 AED/USD after the catalogue re-priced haiku-latest (12 Oct 2026).'
 where model = '~anthropic/claude-haiku-latest';

select case when (select count(*) from public.model_registry
                   where (model_id = '~anthropic/claude-haiku-latest' and context_len = 1000000 and in_per_mtok_usd = 0.1 and out_per_mtok_usd = 0.5)) = 1
             and (select count(*) from public.model_rate where model = '~anthropic/claude-haiku-latest' and usd_per_m_prompt = 0.1) = 1
            then 'PROBE OK :: haiku-latest 0.1/0.5 ctx 1000000'
            else 'PROBE FAILED :: a registry or rate row did not take the catalogue price' end as verdict;
