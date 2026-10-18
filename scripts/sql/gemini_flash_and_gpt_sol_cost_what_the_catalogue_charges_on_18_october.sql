-- GEMINI-3.8-FLASH AND GPT-5.6-SOL COST WHAT THE CATALOGUE CHARGES ON 18 OCTOBER.
-- Seat: it_engineer. 18 Oct 2026. A PRICE-RECORD UPDATE ONLY: no model_policy row, no routing, no routine, no grant.
--
-- MEASURED 18 Oct 2026 (GET https://openrouter.ai/api/v1/models, no key): the_registry_prices_are_the_catalogue_s_prices
-- was red on main and every branch with exactly these four findings, and no others:
--   google/gemini-3.8-flash  prompt 0.000000825 (was 0.00000075), completion 0.000004125 (was 0.00000375), ctx 1048576,
--                            cache read 0.0000000825 (was 0.000000075), cache write 0.0000000416666 (unchanged)
--     /endpoints: AI Studio and Vertex global still serve 0.75/3.75; Vertex us serves 0.825/4.125 (+10%). The headline
--     is the regional endpoint's price, not a list-price rise; the registry carries the headline, as for every row.
--   openai/gpt-5.6-sol       prompt 0.000004 (was 0.000002), completion 0.00002 (was 0.00001), ctx 1050000,
--                            cache read 0.0000004, cache write 0.000005; >272k-prompt override 8/30 (not the 2x)
--     /endpoints: OpenAI standard and Azure serve 4/20; only OpenAI "flex" serves the old 2/10. Same model id, no new
--     variant and not a long-context tier: the standard route is now 4/20.
-- AED at 3.6725 AED/USD. No begin/commit. A probe raises on mismatch, so a half-taken file rolls back.

update public.model_registry set context_len = 1048576, in_per_mtok_usd = 0.825,
       out_per_mtok_usd = 4.125, updated_at = now()
 where model_id = 'google/gemini-3.8-flash';

update public.model_registry set context_len = 1050000, in_per_mtok_usd = 4,
       out_per_mtok_usd = 20, updated_at = now()
 where model_id = 'openai/gpt-5.6-sol';

update public.model_rate set usd_per_m_prompt = 0.825, usd_per_m_output = 4.125,
       in_aed_per_mtok = 3.02981250, out_aed_per_mtok = 15.14906250,
       cache_read_aed_per_mtok = 0.30298125,
       verified_at = date '2026-10-18', note = 'Re-derived at 3.6725 AED/USD after the catalogue headline moved to 0.825/4.125 (18 Oct 2026).'
 where model = 'google/gemini-3.8-flash';

update public.model_rate set usd_per_m_prompt = 4, usd_per_m_output = 20,
       in_aed_per_mtok = 14.69, out_aed_per_mtok = 73.45,
       cache_read_aed_per_mtok = 1.469, cache_write_aed_per_mtok = 18.3625,
       verified_at = date '2026-10-18', note = 'Re-derived at 3.6725 AED/USD after the catalogue re-priced gpt-5.6-sol to 4/20 (18 Oct 2026).'
 where model = 'openai/gpt-5.6-sol';

do $probe$
begin
  if (select count(*) from public.model_registry
       where (model_id = 'google/gemini-3.8-flash' and in_per_mtok_usd = 0.825 and out_per_mtok_usd = 4.125)
          or (model_id = 'openai/gpt-5.6-sol' and in_per_mtok_usd = 4 and out_per_mtok_usd = 20)) <> 2
     or (select count(*) from public.model_rate
          where (model = 'google/gemini-3.8-flash' and usd_per_m_prompt = 0.825 and usd_per_m_output = 4.125)
             or (model = 'openai/gpt-5.6-sol' and usd_per_m_prompt = 4 and usd_per_m_output = 20)) <> 2 then
    raise exception 'PROBE FAILED :: a registry or rate row did not take the catalogue price';
  end if;
end
$probe$;

select 'PROBE OK :: gemini-3.8-flash 0.825/4.125, gpt-5.6-sol 4/20' as verdict;
