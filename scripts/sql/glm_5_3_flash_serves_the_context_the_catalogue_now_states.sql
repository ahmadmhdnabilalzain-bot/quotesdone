-- GLM 5.3 FLASH SERVES THE CONTEXT THE CATALOGUE NOW STATES.
-- Seat: it_engineer. 30 Sep 2026, release operator.
--
-- MEASURED 30 Sep 2026 ~00:10Z. CI's scripts/checks/the_registry_prices_are_the_catalogue_s_prices.test.mjs
-- went red on PR #1147 with ONE finding:
--   z-ai/glm-5.3-flash ctx: file says 1310720, catalogue serves 1048576
-- The catalogue (https://openrouter.ai/api/v1/models) was re-read live from this session:
--   context_length 1048576, prompt 0.00000015 (USD 0.15/Mtok), completion 0.0000005 (USD 0.50/Mtok),
--   input_cache_read 0.00000003 (USD 0.03/Mtok).
-- Production before this file: model_registry context_len 1310720, in 0.15, out 0.50;
--   model_rate usd 0.15 / 0.50, cache_read_aed_per_mtok 0.183625 (USD 0.05, noted "not re-measured").
--
-- WHAT CHANGES: registry context_len 1310720 -> 1048576 (prices restated unchanged, because the price check
-- parses the three together), and model_rate's cache read to the measured USD 0.03 at the 3.6725 peg
-- (0.110175 AED). In and out prices are unchanged. No routine, table or grant. OpenRouter hold untouched.
-- Ends in a PROBE verdict row.

begin;

update public.model_registry set context_len = 1048576, in_per_mtok_usd = 0.15,
       out_per_mtok_usd = 0.50, updated_at = now()
 where model_id = 'z-ai/glm-5.3-flash';

update public.model_rate set
       cache_read_aed_per_mtok = round(0.03 * 3.6725, 6),
       verified_at = date '2026-09-30',
       note = note || ' 30 Sep 2026: context 1,048,576 and cache read USD 0.03 re-read from the catalogue; in/out unchanged.'
 where model = 'z-ai/glm-5.3-flash'
   and usd_per_m_prompt = 0.15 and usd_per_m_output = 0.50;

-- This file writes model_rate, so "no_writer" is no longer true of it: it is exported with the routing tables.
insert into public.table_export_registry (table_name, exported, category, reason, added_by) values
  ('model_rate', true, 'model_routing', 'the USD and AED price per Mtok fn_llm_log prices every call from, re-read from the catalogue', 'it_engineer')
on conflict (table_name) do update set exported = excluded.exported, category = excluded.category,
  reason = excluded.reason, added_by = excluded.added_by;

with c as (
  select
    (select count(*) from public.model_registry where model_id = 'z-ai/glm-5.3-flash' and context_len = 1048576
        and in_per_mtok_usd = 0.15 and out_per_mtok_usd = 0.50) as registry_ok,
    (select count(*) from public.model_rate where model = 'z-ai/glm-5.3-flash' and usd_per_m_prompt = 0.15
        and usd_per_m_output = 0.50 and cache_read_aed_per_mtok = 0.110175) as rate_ok
)
select case when registry_ok = 1 and rate_ok = 1
            then 'PROBE OK :: z-ai/glm-5.3-flash context 1048576, 0.15/0.50, cache read 0.03 USD'
            else 'PROBE FAILED :: want registry_ok 1, rate_ok 1' end as verdict, registry_ok, rate_ok
  from c;

commit;
