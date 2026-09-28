-- glm_5_3_flash_is_back_at_the_price_it_was_ruled_at.sql
-- Seat: it_engineer. 28 Sep 2026, release operator.
--
-- MEASURED 28 Sep 2026 ~12:05Z by scripts/checks/the_registry_prices_are_the_catalogue_s_prices.test.mjs:
-- the OpenRouter catalogue serves z-ai/glm-5.3-flash at USD 0.15 in / 0.50 out again, context unchanged.
-- glm_5_3_flash_costs_what_the_catalogue_now_charges.sql (#968, applied the same morning) had moved the
-- registry and the rate table to the 24 Sep price of 0.045 / 0.60. This file puts both back to what the
-- catalogue serves. The model_policy rationales it rewrote keep their "(catalogue re-price of 24 Sep; $0.15/$0.50
-- when ruled)" wording, which stays true as history. The sales_engineer pin it inserted is kept: at 0.15 the
-- routing tier picks openai/gpt-6-luna for that seat anyway, so the pin changes nothing today and holds the
-- customer-facing route if GLM is re-priced down again.
-- No table, routine or grant is created. Ends in a PROBE verdict row.

begin;

update public.model_registry set context_len = 1310720, in_per_mtok_usd = 0.15,
       out_per_mtok_usd = 0.50, updated_at = now()
 where model_id = 'z-ai/glm-5.3-flash';

update public.model_registry set note = note || ' BACK at $0.15/$0.50 per Mtok on 28 Sep 2026 (catalogue measured).',
       updated_at = now()
 where model_id = 'z-ai/glm-5.3-flash' and note not like '%BACK at $0.15/$0.50%';

update public.model_rate set
       usd_per_m_prompt = 0.15, usd_per_m_output = 0.50,
       in_aed_per_mtok  = round(0.15 * 3.6725, 6), out_aed_per_mtok = round(0.50 * 3.6725, 6),
       verified_at = date '2026-09-28',
       note = note || ' BACK 28 Sep 2026: the catalogue serves USD 0.15 in / 0.50 out again.'
 where model = 'z-ai/glm-5.3-flash'
   and usd_per_m_prompt = 0.045 and usd_per_m_output = 0.60;

with c as (
  select
    (select count(*) from public.model_registry
      where model_id = 'z-ai/glm-5.3-flash' and in_per_mtok_usd = 0.15 and out_per_mtok_usd = 0.50) as registry_ok,  -- want 1
    (select count(*) from public.model_rate
      where model = 'z-ai/glm-5.3-flash' and usd_per_m_prompt = 0.15 and usd_per_m_output = 0.50)       as rate_ok,      -- want 1
    (select count(*) from unnest(array[null::text, 'vision', 'tools']) cap,
            lateral public.fn_ai_route(null, null, null, 'glm_reprice_probe_unmapped_fn', false,
                                       case when cap is null then null else array[cap] end,
                                       'sales_engineer') r
      where r ->> 'model' = 'openai/gpt-6-luna')                                                          as se_unmoved    -- want 3
)
select case when registry_ok = 1 and rate_ok = 1 and se_unmoved = 3
            then 'PROBE OK :: z-ai/glm-5.3-flash is 0.15/0.50 in the registry and the rate table; sales_engineer still routes to openai/gpt-6-luna'
            else 'PROBE FAILED :: want 1, 1, 3'
       end as verdict, registry_ok, rate_ok, se_unmoved
  from c;

commit;
