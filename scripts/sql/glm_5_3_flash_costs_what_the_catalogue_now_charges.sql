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
--   4. ONE ROUTE PINNED so the price cannot move it: sales_engineer's catch-all (see ROUTING below).
--   5. The AED budget arithmetic, re-derived below. It moves by under half a dirham a month and no
--      ceiling changes, so department_budget is NOT written.
--
-- ═══ ROUTING: WHAT THE NEW PRICE MOVES, AND WHAT IS PINNED ═══════════════════════════════════════
--
-- At 0.045 GLM becomes the CHEAPEST SMALL ROW (live small rows, in USD/Mtok: openai/gpt-6-luna 0.10,
-- GLM 0.15, openai/gpt-5.6-luna 0.20, qwen/qwen3.7-plus 0.32). Every pick that orders the registry by
-- in_per_mtok_usd therefore moves from gpt-6-luna to GLM wherever both are eligible, and they are
-- eligible together everywhere: both active, approved, small, vision, tools, no audio. (An earlier
-- draft of this header said routing did not change; the independent review of #968 measured
-- otherwise, and it was right.)
--
-- The price-ordered picks, read from the live definitions on 24 Sep 2026:
--   fn_routing_tier_model      cheapest active approved row in the role's registry tier
--   fn_ai_route  substitution  cheapest row in the policy's tier when the policy model is unregistered
--   fn_ai_route  capability    at-or-above tier, then closest tier, then cheapest
--   fn_ai_route  fallback      the same order, when the policy fallback lacks a required capability
--   fn_ai_route  confidence    cheapest MEDIUM row - GLM is small, so this one cannot move
--   fn_llm_log   could_be_cheaper  cheapest model_rate row - an advisory flag, not a route
--   fn_ai_route_review_for     fixed ranks, no price order - cannot move
--
-- ENUMERATED, read-only, by calling fn_ai_route and fn_routing_tier_model as they stand and keeping
-- every answer that is gpt-6-luna or came from a price-ordered pick (every GLM-eligible pick that
-- returns gpt-6-luna today returns GLM at 0.045, because GLM is eligible wherever gpt-6-luna is):
--   * every active model_policy class x caps {none, vision, audio, tools, vision+tools} x escalate
--     {false, true}: 82 classes, 820 routes
--   * all 6 active org_agents seats and the 3 current_agent identity rows, through the generic path
--     (an unmapped fn), x caps {none, vision, tools}
--
--   route                                                    before              after
--   ────────────────────────────────────────────────────────────────────────────────────────────
--   sales_engineer, any unmapped fn / unpolicied class        openai/gpt-6-luna   z-ai/glm-5.3-flash
--     (org_agents.routing_tier operations_specialist -> fn_routing_tier_model -> cheapest small;
--      same with vision or tools caps; fallback google/gemini-3.8-flash both before and after)
--     -> PINNED to openai/gpt-6-luna below. The sales engineer answers customers and suppliers,
--        in Arabic too, and the founder's ruling of 23 Sep keeps those routes where they are.
--   speech_transcription, FALLBACK when called with vision   openai/gpt-6-luna   z-ai/glm-5.3-flash
--     or tools caps and no audio
--     -> NOT pinned: unreachable. transcribe always sends an input_audio part and ai_gateway marks
--        every one as needing audio; with the audio cap the fallback is null before and after
--        (only gemini-3.8-flash hears). Its rationale says it has NO fallback, and a pinned
--        fallback would contradict that on the one path that is ever taken.
--   fn_llm_log could_be_cheaper (advisory)                    compares to gpt-6-luna compares to GLM
--     -> NOT a route. At AED 0.165263 the 2x threshold is AED 0.3305, so gpt-6-luna calls
--        (AED 0.36725) are now flagged "could be cheaper" where before only gpt-5.6-luna and dearer
--        were. It changes a column in ai_cost_log, not a model.
--
--   UNCHANGED, measured: every other class, including every customer-, supplier- and Arabic-facing
--   one (quote_comparison, customer_communication, supplier_communication, visitor_chat, wa_inbound,
--   customer_portal_assistant, translation, marketing_copy ...) - their primaries are named models
--   (openai/gpt-5.6-sol, with anthropic/claude-opus-5.5 behind), never a price pick, and every audio
--   substitution goes to google/gemini-3.8-flash, the only row that hears. ceo (director -> medium
--   -> gemini-3.8-flash), accountant, marketing and it_engineer (current_agent rows name a model) do
--   not move. The GLM classes were already GLM.
--
-- Internal reasoning moving to GLM is what the founder asked for (23 Sep: internal think() on the
-- GLM class). Nothing internal is pinned; only the route a customer or supplier reads.
--
-- ─── WHAT IT DELIBERATELY DOES NOT CHANGE ────────────────────────────────────────────────────────
--
--   * No other model. The CI run found every other price and context length matching.
--   * GLM's cache-read price (USD 0.05, AED 0.183625). The check compares in/out/context only, so no
--     measurement of cache read exists; changing it would be a guess.
--   * Any class's policy. The pin is a current_agent row, which fn_ai_route reads only on the generic
--     path; sales_engineer's agent_reasoning calls go to routine_employee_reasoning, whose policy
--     names GLM and did so before this file (not a price pick, so not this file's to move).
--   * The applied files that record the 23 Sep price (the_catalogue_names_every_model_...,
--     every_seat_gets_the_model_its_own_work_needs, a_ceiling_exists_before_the_door_is_opened,
--     gpt_sol_takes_every_qwen_class_..., four_judgements_move_to_glm_...,
--     the_retired_models_cannot_be_called_...). They state what was true when they were applied;
--     this file is the correction and the price check reads it last.
--   * The OpenRouter hold. llm_route_health is untouched.
--
-- ═══ THE BUDGET ARITHMETIC, RE-DERIVED ══════════════════════════════════════════════════════════
--
-- The live table, read 24 Sep 2026: marketplace 1,300, marketing 100, exec 60, customer_experience
-- 60, finance 40, it 40 = AED 1,600/month. Its arithmetic is gpt_sol_takes_every_qwen_class_and_one_
-- gemini_takes_every_gemini_class.sql section 6 (marketing and marketplace were later set by
-- the_marketing_seat_gets_a_model_ceiling_and_every_class_it_thinks_with.sql, on no GLM line). Same
-- call mix, same token estimates, same 3.6725 peg; only GLM's two prices change, and GLM carries two
-- lines of it:
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
--   CUSTOMER_EXP  customer_communication 10.00 + intent_detection 0.3675 = 10.3675 USD
--                 = AED 38.07 (was 38.45) x1.5 = 57.11 -> 60, UNCHANGED
--   IT            0.138 USD = AED 0.51 (was 0.59) x1.5 = 0.76, below the floor -> 40, UNCHANGED
--
--   Expected spend: 903.64 + 39.93 + 38.07 + 13.02 + 12.12 + 0.51 = AED 1,007.29 a month
--                   (was 903.64 + 39.93 + 38.45 + 13.02 + 12.12 + 0.59 = AED 1,007.75; -0.46)
--   TOTAL CEILING:  1,300 + 100 + 60 + 60 + 40 + 40 = AED 1,600 / month, UNCHANGED.
--
-- AND THE CEILING NO LONGER ACTS: since founder_instruction 987 (24 Sep 2026) fn_ai_route has NO HALT
-- AND NO DEGRADE; budget_pct is reported only. So this arithmetic sizes what the books will show, not
-- a limit any call meets.
--
-- GLM IS A SMALL SHARE: AED 1.86 of AED 1,007.29 expected, 0.18% (was 2.33, 0.23%). On these two
-- lines the input cut outweighs the output rise, so a GLM call is ~23% cheaper (triage, 0.3675 vs
-- 0.4750) and ~14% cheaper (engineering, 0.138 vs 0.160). A class that writes more than it reads
-- would go the other way: input saves USD 0.105 per Mtok and output costs USD 0.10 more, so the
-- break-even is 0.105 x in = 0.10 x out -> out/in = 1.05. The eleven other GLM policy classes have
-- no measured caller and were never in the arithmetic; the same holds for them now. None of these
-- figures is a measured cost: ai_cost_log still has no real tokens, and the re-derivation from real
-- traffic the budget files call for is still owed.
--
-- Seat: it_engineer.

begin;

-- 0. THE PIN, written BEFORE the price moves so its gate reads the route as it stands. sales_engineer
-- has no current_agent row, so on the generic path fn_ai_route asks fn_routing_tier_model, which
-- answers "cheapest small row" - openai/gpt-6-luna today, GLM the moment the update below lands. A
-- current_agent row is read first (fn_ai_route: `v_idp.identity_key is null` guards the tier
-- branch), so this row keeps the route exactly where it is: same primary, same fallback (general_
-- drafting's google/gemini-3.8-flash), same max_tokens (null here -> general_drafting's 900), same
-- tier (general_drafting is small, as the tier branch set). Gated on the old value: it inserts only
-- while the row is absent AND the tier pick still reads gpt-6-luna, so re-applying is a no-op.
-- trg_identity_policy_is_a_live_seat_and_a_known_model accepts it: sales_engineer is a live seat,
-- and both models are registered and under the hold.
insert into public.model_policy_by_identity
  (identity_key, scope, department, title, deterministic_first, primary_model, fallback_model,
   escalation_model, max_output_tokens, reasoning_effort, note, package_version)
select 'sales_engineer', 'current_agent', null, 'Sales engineer', 'Yes',
       'openai/gpt-6-luna', 'google/gemini-3.8-flash', null, null, null,
       'Catch-all for a call from this seat that no model_policy class covers (fn_ai_route applies it only '
       || 'when v_generic). PINNED 24 Sep 2026 to the model the routing tier chose before GLM was re-priced '
       || 'to $0.045 and became the cheapest small row: the sales engineer answers customers and suppliers, '
       || 'in Arabic too, and the founder''s ruling of 23 Sep keeps those routes where they are while '
       || 'internal reasoning moves to GLM. glm_5_3_flash_costs_what_the_catalogue_now_charges.sql.',
       '1.0.0'
 where not exists (select 1 from public.model_policy_by_identity
                    where identity_key = 'sales_engineer' and scope = 'current_agent')
   and public.fn_routing_tier_model('sales_engineer') ->> 'model' = 'openai/gpt-6-luna';

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

-- The verdict, as a result set (a raise would roll back every write above with it). The counts are
-- columns so a FAILED verdict says which part failed.
with c as (
  select
    (select count(*) from public.model_registry
      where model_id = 'z-ai/glm-5.3-flash' and in_per_mtok_usd = 0.045 and out_per_mtok_usd = 0.60
        and context_len = 1310720 and note not like '%13x cheaper%') as registry_repriced,       -- want 1
    (select count(*) from public.model_rate
      where model = 'z-ai/glm-5.3-flash' and usd_per_m_prompt = 0.045 and usd_per_m_output = 0.60
        and in_aed_per_mtok = 0.165263 and out_aed_per_mtok = 2.2035) as rate_repriced,          -- want 1
    (select count(*) from public.model_policy
      where rationale like '%$0.15/$0.50,%' or rationale like '%at $0.15/Mtok,%') as stale_rationales, -- want 0
    -- The pinned route, through the router itself, on every caps shape the enumeration used.
    (select count(*) from unnest(array[null::text, 'vision', 'tools']) cap,
            lateral public.fn_ai_route(null, null, null, 'glm_reprice_probe_unmapped_fn', false,
                                       case when cap is null then null else array[cap] end,
                                       'sales_engineer') r
      where r ->> 'model' = 'openai/gpt-6-luna'
        and r ->> 'fallback' = 'google/gemini-3.8-flash') as sales_engineer_unmoved,          -- want 3
    -- Every customer-, supplier- and Arabic-facing class still answers with its named primary.
    (select count(*) from public.model_policy p
       cross join unnest(array[null::text, 'vision']) cap
       cross join lateral public.fn_ai_route(p.task_class, null, null, null, false,
                                             case when cap is null then null else array[cap] end, null) r
      where p.active
        and p.task_class in ('quote_comparison', 'customer_communication', 'supplier_communication',
                             'visitor_chat', 'wa_inbound', 'customer_portal_assistant', 'translation',
                             'translation_general', 'marketing_copy', 'inquiry_qualification_conversation',
                             'support_ai')
        and r ->> 'model' is distinct from p.model_primary) as facing_classes_moved             -- want 0
)
select case when registry_repriced = 1 and rate_repriced = 1 and stale_rationales = 0
              and sales_engineer_unmoved = 3 and facing_classes_moved = 0
            then 'PROBE OK :: z-ai/glm-5.3-flash is 0.045/0.60 in the registry and the rate table, no '
                 || 'rationale quotes $0.15/$0.50, sales_engineer still routes to openai/gpt-6-luna, and no '
                 || 'customer- or supplier-facing class moved'
            else 'PROBE FAILED :: read the columns - want 1, 1, 0, 3, 0'
       end as verdict,
       registry_repriced, rate_repriced, stale_rationales, sales_engineer_unmoved, facing_classes_moved
  from c;

commit;
