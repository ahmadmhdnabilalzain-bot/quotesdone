-- GLM 5.3 FLASH COSTS WHAT THE CATALOGUE NOW CHARGES.
-- it_engineer, 24 September 2026.
--
-- ─── WHAT WAS MEASURED ───────────────────────────────────────────────────────────────────────────
--
-- scripts/checks/the_registry_prices_are_the_catalogue_s_prices.test.mjs re-reads
-- https://openrouter.ai/api/v1/models on every CI run. On 24 Sep 2026 (~19:10 UTC) it went red on
-- every branch, main included, with exactly two findings and no others:
--
--   z-ai/glm-5.3-flash in:  file says 0.15, catalogue serves 0.045
--   z-ai/glm-5.3-flash out: file says 0.5,  catalogue serves 0.6
--
-- The same run compared context_length and found NO difference, so 1,310,720 still stands, and
-- found no other model moved. The provider re-priced one model; nothing in this repository changed.
-- (The catalogue could not be re-read from the session that wrote this file: the egress proxy
-- refuses openrouter.ai. The values above are the CI run's measurement, not a second one.)
--
-- Production, read-only, 24 Sep 2026, before this file:
--   model_registry  z-ai/glm-5.3-flash  context_len 1310720, in 0.15, out 0.50
--   model_rate      z-ai/glm-5.3-flash  usd 0.15 / 0.50, aed 0.550875 / 1.836250, verified 2026-09-23
--   model_policy    11 rationales read "plan A z-ai/glm-5.3-flash at $0.15/$0.50", and
--                   knowledge_ingestion reads "at $0.15/Mtok"
--
-- ─── WHAT WAS WRONG ──────────────────────────────────────────────────────────────────────────────
--
-- Input is now 3.3x CHEAPER (0.15 -> 0.045) and output 1.2x DEARER (0.50 -> 0.60). model_rate is the
-- one that costs money if left: fn_llm_log prices every call from it and fn_ai_route sums that into
-- the department ceilings, so a stale rate makes the ceilings count the wrong spend. The registry row
-- is what fn_ai_route's cheapest-in-band choices read. The text on the live rows states a price that
-- is no longer true.
--
-- ─── WHAT CHANGES ────────────────────────────────────────────────────────────────────────────────
--
--   1. model_registry: in 0.045, out 0.60 for z-ai/glm-5.3-flash. context_len restated at 1,310,720
--      (unchanged) because the price check parses the three together.
--   2. model_rate: usd 0.045 / 0.60, aed at the same 3.6725 peg every row names, verified 24 Sep 2026.
--   3. The GLM registry note, and the 12 model_policy rationales that quote the old price.
--   4. The AED budget arithmetic, re-derived below. It moves by less than one dirham a month and no
--      ceiling changes, so department_budget is NOT written.
--
-- ─── WHAT IT DELIBERATELY DOES NOT CHANGE ────────────────────────────────────────────────────────
--
--   * No other model. The CI run found every other price and context length matching.
--   * GLM's cache-read price (USD 0.05, AED 0.183625). The check compares in/out/context only, so no
--     measurement of cache read exists; changing it would be a guess.
--   * Routing. GLM is still the cheapest capable small row on input; on output it is now dearer than
--     openai/gpt-6-luna (0.50), where before the two were equal. Which model a class runs on is
--     the founder's ruling (instructions 841/844/854), not a price-follows decision, so no policy row
--     moves here.
--   * The applied files that record the 23 Sep price (the_catalogue_names_every_model_...,
--     every_seat_gets_the_model_its_own_work_needs, a_ceiling_exists_before_the_door_is_opened,
--     four_judgements_move_to_glm_..., the_retired_models_cannot_be_called_...). They state what was
--     true when they were applied; this file is the correction and the price check reads it last.
--   * The OpenRouter hold. llm_route_health is untouched.
--
-- ═══ THE BUDGET ARITHMETIC, RE-DERIVED ══════════════════════════════════════════════════════════
--
-- Derived in a_ceiling_exists_before_the_door_is_opened.sql (the "AED 1,170/month" the price check
-- names is that file's 841 draft; its final figure is AED 1,200/month). Same call mix, same token
-- estimates, same 3.6725 peg; only GLM's two prices change. GLM carries two lines of it:
--
--   intent_detection (triage)   1,000 calls/mo, est 1,500 in / 500 out
--     was  1,500/1e6 x 0.15  + 500/1e6 x 0.50 = 0.000225  + 0.000250 = 0.000475  USD/call
--          x 1,000 = 0.4750 USD = AED 1.74
--     now  1,500/1e6 x 0.045 + 500/1e6 x 0.60 = 0.0000675 + 0.000300 = 0.0003675 USD/call
--          x 1,000 = 0.3675 USD = AED 1.35
--   engineering_reasoning         100 calls/mo, est 4,000 in / 2,000 out
--     was  4,000/1e6 x 0.15  + 2,000/1e6 x 0.50 = 0.00060 + 0.00100 = 0.00160 USD/call
--          x 100 = 0.160 USD = AED 0.59
--     now  4,000/1e6 x 0.045 + 2,000/1e6 x 0.60 = 0.00018 + 0.00120 = 0.00138 USD/call
--          x 100 = 0.138 USD = AED 0.51
--
--   CUSTOMER_EXPERIENCE  7.60 + 0.3675 = 7.9675 USD = AED 29.26 (was 29.66)
--                        x1.5 -> 43.89 -> monthly_aed 50, UNCHANGED   (fill 58.5%, was 59.3%)
--   IT                   0.138 USD = AED 0.51 (was 0.59)
--                        x1.5 -> 0.76, below the floor -> monthly_aed 40, UNCHANGED (fill 1.3%)
--
--   Estimated spend before headroom: AED 726.16 -> 725.68 a month (-0.48).
--   TOTAL CEILING: 980 + 50 + 50 + 40 + 40 + 40 = AED 1,200 / month, UNCHANGED.
--
-- GLM IS A SMALL SHARE: AED 1.86 of AED 725.68 estimated, 0.26% (was 2.33, 0.32%). On these two
-- lines the input cut outweighs the output rise, so a GLM call is ~23% cheaper (triage, 0.3675 vs
-- 0.4750) and ~14% cheaper (engineering, 0.138 vs 0.160). A class that writes far more than it reads
-- would go the other way: input saves USD 0.105 per Mtok and output costs USD 0.10 more, so the
-- break-even is 0.105 x in = 0.10 x out -> out/in = 1.05, i.e. a call that writes more than it reads. Either way it is immaterial to every ceiling. The eleven other GLM policy classes have no measured caller and were
-- never in the arithmetic; the same holds for them now. None of these figures is a measured cost:
-- ai_cost_log still has no real tokens (see the budget file), and the re-derivation from real traffic
-- it calls for is still owed.
--
-- Seat: it_engineer.

begin;

-- 1. The registry row. Shape kept to the one the price check parses (context_len, in, out together).
update public.model_registry set context_len = 1310720, in_per_mtok_usd = 0.045,
       out_per_mtok_usd = 0.60, updated_at = now()
 where model_id = 'z-ai/glm-5.3-flash';

update public.model_registry set note =
       replace(replace(note,
         'Live 23 Sep 2026: $0.15/$0.50 per Mtok,',
         'Live 23 Sep 2026: $0.15/$0.50 per Mtok; RE-PRICED by the catalogue by 24 Sep 2026 to '
         || '$0.045/$0.60 (input 3.3x cheaper, output 1.2x dearer; context unchanged),'),
         '13x cheaper input and 7.5x cheaper output than the qwen row above, and 5x cheaper than '
         || 'google/gemini-3.8-flash on input.',
         'At the 24 Sep price: 44x cheaper input and 10x cheaper output than the (since retired) qwen '
         || 'row above, and 16.7x cheaper than google/gemini-3.8-flash on input.'),
       updated_at = now()
 where model_id = 'z-ai/glm-5.3-flash'
   and note like '%Live 23 Sep 2026: $0.15/$0.50 per Mtok,%';

-- 2. The rate fn_llm_log prices every call from. Cache read untouched (not measured, see header).
update public.model_rate set
       usd_per_m_prompt = 0.045, usd_per_m_output = 0.60,
       in_aed_per_mtok  = round(0.045 * 3.6725, 6), out_aed_per_mtok = round(0.60 * 3.6725, 6),
       verified_at = date '2026-09-24',
       note = note || ' RE-PRICED 24 Sep 2026: the catalogue now serves USD 0.045 in / 0.60 out '
              || '(was 0.15 / 0.50), measured by the_registry_prices_are_the_catalogue_s_prices in CI. '
              || 'Cache read not re-measured and left as it was.'
 where model = 'z-ai/glm-5.3-flash'
   and usd_per_m_prompt = 0.15 and usd_per_m_output = 0.50;

-- 3. The text on the live policy rows.
update public.model_policy set rationale =
       replace(rationale, 'plan A z-ai/glm-5.3-flash at $0.15/$0.50,',
               'plan A z-ai/glm-5.3-flash at $0.045/$0.60 (catalogue re-price of 24 Sep 2026; $0.15/$0.50 '
               || 'when ruled),')
 where rationale like '%plan A z-ai/glm-5.3-flash at $0.15/$0.50,%';

update public.model_policy set rationale =
       replace(rationale, 'in one request at $0.15/Mtok,',
               'in one request at $0.045/Mtok input (catalogue re-price of 24 Sep 2026; was $0.15),')
 where task_class = 'knowledge_ingestion'
   and rationale like '%in one request at $0.15/Mtok,%';

-- The verdict, as a result set (a raise would roll back every write above with it).
select case when
      (select count(*) from public.model_registry
        where model_id = 'z-ai/glm-5.3-flash' and in_per_mtok_usd = 0.045 and out_per_mtok_usd = 0.60
          and context_len = 1310720 and note not like '%$0.15/$0.50 per Mtok,%13x cheaper%') = 1
  and (select count(*) from public.model_rate
        where model = 'z-ai/glm-5.3-flash' and usd_per_m_prompt = 0.045 and usd_per_m_output = 0.60
          and in_aed_per_mtok = 0.165263 and out_aed_per_mtok = 2.2035) = 1
  and (select count(*) from public.model_policy where rationale like '%$0.15/$0.50,%'
          or rationale like '%at $0.15/Mtok,%') = 0
then 'PROBE OK :: z-ai/glm-5.3-flash is 0.045/0.60 in the registry and the rate table, and no policy '
     || 'rationale still quotes $0.15/$0.50'
else 'PROBE FAILED :: read the three counts - a GLM price or a rationale still states the 23 Sep price'
end as verdict;

commit;
