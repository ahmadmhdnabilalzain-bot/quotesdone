-- GPT Sol takes every Qwen class, and one Gemini takes every Gemini class.
--
-- WHAT THE FOUNDER SAID, 23 Sep 2026 (founder_instruction 854), after reviewing the live matrix:
--   "replace gemini 3.5 flash and gemini flash lite to gemini 3.8 flash.
--    checking customers identity was hidden, change it to gpt sol 5.6
--    and all qwen 3.8 max to gpt sol 5.6"
-- GPT Sol 5.6 was already one of the two models his instruction 844 named for customer-facing,
-- Arabic and document-reading work ("Qwen 3.8 Max or GPT Sol 5.6, depending which one is cheaper").
-- The first matrix picked Qwen on price (output USD 6 vs 10 per Mtok). This picks Sol.
--
-- WHAT CHANGES
--   1. openai/gpt-5.6-sol is REGISTERED and put UNDER THE HOLD. It was in neither model_registry nor
--      llm_route_health, and trg_model_policy_names_a_known_route refuses any policy naming such a
--      model. Read live from https://openrouter.ai/api/v1/models on 23 Sep 2026: USD 2.00 in /
--      10.00 out per Mtok, cache read 0.20, context 1,050,000, input text+image+file, NO audio and
--      NO video. OpenAI charges no cache-write surcharge, so cache write = the input price.
--      TIER large, exactly as qwen3.8-max was: fn_ai_route degrades one band, so large degrades to
--      the cheapest medium row (gemini-3.8-flash). At medium it would drop about 20x in one step on
--      the classes that rank quotes and decide approvals.
--   2. All 36 model_policy classes whose primary was qwen/qwen3.8-max-0902 now run openai/gpt-5.6-sol.
--      Their fallback stays anthropic/claude-opus-5.5.
--   3. identity_redaction_verify: primary anthropic/claude-opus-5.5 -> openai/gpt-5.6-sol, as he
--      asked. Its fallback was qwen, which this file retires, and a fallback may not equal its
--      primary (trg_model_policy_names_a_known_route), so the fallback is anthropic/claude-opus-5.5.
--      RECORDED, NOT RE-ARGUED: the FIND pass (drawing_redact, document classes) now also runs Sol,
--      so on the normal path find and verify are the same model. That independence was the reason
--      the verify had been on Opus; the founder decided with that in front of him. On the FALLBACK
--      path the verify still reaches a different model.
--   4. Every Gemini class runs google/gemini-3.8-flash. redaction_detection and speech_transcription
--      were on gemini-3.1-flash-lite with gemini-3.5-flash behind them. Moving both primaries to 3.8
--      would make 3.8 its own fallback, so:
--        redaction_detection  -> fallback openai/gpt-5.6-sol (it reads images and text)
--        speech_transcription -> fallback NULL. Only the Gemini family hears audio, and 3.8 flash is
--                                now the only Gemini any policy names. With no fallback fn_ai_route
--                                answers coalesce(model_fallback, primary): a failed call retries
--                                3.8 flash rather than landing on a model that cannot hear.
--   5. The three model_policy_by_identity rows are aligned to 844's audience split. They are the
--      CATCH-ALL for a call from that seat that no model_policy class covers (fn_ai_route applies
--      them only when v_generic), and they still named models nobody chose for those seats:
--        accountant   opus-5.5 / sonnet-5     -> z-ai/glm-5.3-flash / google/gemini-3.8-flash (internal)
--        it_engineer  sonnet-5 / haiku-latest -> z-ai/glm-5.3-flash / google/gemini-3.8-flash (internal)
--        marketing    sonnet-5 / haiku-latest -> openai/gpt-5.6-sol / anthropic/claude-opus-5.5 (it
--                     writes what customers and suppliers read, in Arabic)
--   6. The ceilings move with the price. Re-derived from the SAME per-class table as
--      a_ceiling_exists_before_the_door_is_opened.sql, only the output price changed (6 -> 10) and
--      the verify's model (opus -> sol). USD -> AED at the peg, 3.6725. x1.5 headroom, AED 40 floor,
--      rounded up to 10.
--        MARKETPLACE  quote_comparison 4,910 x (0.012 + 0.030) = 206.22   (was 147.30)
--                     agent_reasoning  1,306 x (0.008 + 0.020) =  36.57   (was  26.12)
--                     document_extraction 86 x (0.006 + 0.020) =  2.24   (was   1.55)
--                     visitor_chat        64 x (0.004 + 0.006) =  0.64   (was   0.49)
--                     identity_verify     28 x (0.006 + 0.008) =  0.39   (was   0.78, opus)
--                     = USD 246.06 = AED 903.64 x1.5 = 1,355.46  ->  1,360   (was 980)
--        EXEC         ceo 300 x (0.016 + 0.020) = 10.80; json_extraction 8 x 0.009 = 0.07
--                     = USD 10.87 = AED 39.93 x1.5 = 59.89       ->     60   (was  50)
--        CUSTOMER_EXP customer_communication 1,000 x 0.010 = 10.00; intent_detection (glm) 0.47
--                     = USD 10.47 = AED 38.45 x1.5 = 57.68       ->     60   (was  50)
--        FINANCE      USD 3.54 = AED 13.02 x1.5 = 19.52, below the floor ->  40  (unchanged)
--        MARKETING    USD 3.30 = AED 12.12 x1.5 = 18.18, below the floor ->  40  (unchanged)
--        IT           unchanged (glm only)                                  ->  40  (unchanged)
--        TOTAL        AED 1,600 / month ceiling (was 1,200). Expected spend ~AED 1,008 (was ~726).
--      WHY THE CEILING HAD TO MOVE: at 980, marketplace's expected AED 904 is 92% of the cap, and
--      its degrade threshold is 70% (AED 686) - quote comparison would have dropped to the degraded
--      model around day 23 of every month.
--
-- WHAT THIS DOES NOT KNOW. Every figure above counts VISIBLE output only. The gateway
-- (_shared/llm.ts) sends no reasoning setting, so Sol runs at its provider's default reasoning
-- effort, and hidden reasoning tokens are billed as output at USD 10. The same was true of Qwen.
-- It cannot be measured while the hold stands; it is the first number to read off ai_cost_log
-- when the hold opens, and the ceilings above are the line that will show it.
--
-- NOTHING CALLS A MODEL AFTER THIS FILE. Every route, Sol's included, is held until
-- (select max(open_until) from llm_route_health) = 2126-08-15. Opening it is the founder's.
--
-- Seat: it_engineer.

begin;

-- The state this file was written against. If the matrix moved since, stop rather than guess.
do $$
declare n_qwen int; n_lite int; n_idp int;
begin
  select count(*) into n_qwen from public.model_policy where active and model_primary = 'qwen/qwen3.8-max-0902';
  select count(*) into n_lite from public.model_policy where active and model_primary = 'google/gemini-3.1-flash-lite';
  select count(*) into n_idp  from public.model_policy_by_identity;
  if n_qwen <> 36 or n_lite <> 2 or n_idp <> 3 then
    raise exception 'CHK<<stale: expected 36 qwen primaries, 2 flash-lite primaries, 3 identity rows; found %, %, %. Re-derive.>>',
      n_qwen, n_lite, n_idp;
  end if;
end $$;

-- 1. Register Sol, then hold it with the rest of the fleet.
insert into public.model_registry
  (model_id, provider, tier, in_per_mtok_usd, out_per_mtok_usd,
   cache_read_per_mtok_usd, cache_write_per_mtok_usd, supports_cache, supports_streaming,
   context_len, approved, active, quality_score, supports_vision, supports_audio, supports_tools, note)
values
  ('openai/gpt-5.6-sol', 'openai', 'large', 2.00, 10.00,
   0.20, 2.00, true, true, 1050000, true, true, 0.9700, true, false, true,
   'Founder''s ruling 23 Sep 2026 (instruction 854): PLAN A for every class instruction 844 put on '
   || 'the customer-facing, Arabic, document-reading and judgement side - it replaces '
   || 'qwen/qwen3.8-max-0902 on all 36. Live 23 Sep 2026: $2.00/$10.00 per Mtok, 1,050,000 context, '
   || 'cache read $0.20, input text+image+file, structured_outputs and tools advertised. NO AUDIO and '
   || 'NO VIDEO. TIER large for the same reason qwen was: fn_ai_route degrades one band. '
   || 'quality_score 0.97 is copied from the row it replaces, NOT measured on this estate.')
on conflict (model_id) do update set
  provider = excluded.provider, tier = excluded.tier,
  in_per_mtok_usd = excluded.in_per_mtok_usd, out_per_mtok_usd = excluded.out_per_mtok_usd,
  cache_read_per_mtok_usd = excluded.cache_read_per_mtok_usd,
  cache_write_per_mtok_usd = excluded.cache_write_per_mtok_usd,
  context_len = excluded.context_len, approved = true, active = true,
  supports_vision = excluded.supports_vision, supports_audio = excluded.supports_audio,
  supports_tools = excluded.supports_tools, note = excluded.note, updated_at = now();

insert into public.llm_route_health
  (model_id, consecutive_failures, failure_threshold, cooldown_seconds, open_until, opened_reason)
select 'openai/gpt-5.6-sol', 0, 3, 300,
       (select max(h.open_until) from public.llm_route_health h),
       'held with the rest of the fleet from the moment it was registered (founder_instruction 854): '
       || 'opening the hold is the founder''s'
where not exists (select 1 from public.llm_route_health h where h.model_id = 'openai/gpt-5.6-sol');

-- 2-4. The policies. The three classes whose fallback would otherwise equal their primary are set
-- in ONE statement each, primary and fallback together, so the per-row guard never sees a
-- half-written row.
update public.model_policy
   set model_primary = 'openai/gpt-5.6-sol', model_fallback = 'anthropic/claude-opus-5.5'
 where task_class = 'identity_redaction_verify';

update public.model_policy
   set model_primary = 'google/gemini-3.8-flash', model_fallback = 'openai/gpt-5.6-sol'
 where task_class = 'redaction_detection';

update public.model_policy
   set model_primary = 'google/gemini-3.8-flash', model_fallback = null
 where task_class = 'speech_transcription';

update public.model_policy
   set model_primary = 'openai/gpt-5.6-sol'
 where model_primary = 'qwen/qwen3.8-max-0902';

update public.model_policy set model_fallback = 'openai/gpt-5.6-sol'
 where model_fallback = 'qwen/qwen3.8-max-0902';

update public.model_policy set model_primary = 'google/gemini-3.8-flash'
 where model_primary in ('google/gemini-3.5-flash', 'google/gemini-3.1-flash-lite');

update public.model_policy set model_fallback = 'google/gemini-3.8-flash'
 where model_fallback in ('google/gemini-3.5-flash', 'google/gemini-3.1-flash-lite')
   and model_primary <> 'google/gemini-3.8-flash';

-- 5. The seat catch-alls.
update public.model_policy_by_identity
   set primary_model = 'z-ai/glm-5.3-flash', fallback_model = 'google/gemini-3.8-flash', escalation_model = null
 where scope = 'current_agent' and identity_key in ('accountant', 'it_engineer');

update public.model_policy_by_identity
   set primary_model = 'openai/gpt-5.6-sol', fallback_model = 'anthropic/claude-opus-5.5', escalation_model = null
 where scope = 'current_agent' and identity_key = 'marketing';

-- 6. The ceilings.
update public.department_budget set monthly_aed = 1360, updated_at = now() where dept_key = 'marketplace';
update public.department_budget set monthly_aed =   60, updated_at = now() where dept_key = 'exec';
update public.department_budget set monthly_aed =   60, updated_at = now() where dept_key = 'customer_experience';

-- The verdict. No raise here: a raise would roll back every write above along with the check.
select case when
      (select count(*) from public.model_policy where active and 'qwen/qwen3.8-max-0902' in (model_primary, model_fallback)) = 0
  and (select count(*) from public.model_policy where active
         and (model_primary in ('google/gemini-3.5-flash','google/gemini-3.1-flash-lite')
           or model_fallback in ('google/gemini-3.5-flash','google/gemini-3.1-flash-lite'))) = 0
  and (select count(*) from public.model_policy where active and model_primary = 'openai/gpt-5.6-sol') = 37
  and (select count(*) from public.model_policy where active and model_fallback = model_primary
         and model_primary not in ('none','none/deterministic')) = 0
  and (select model_primary || '/' || coalesce(model_fallback,'-') from public.model_policy where task_class = 'identity_redaction_verify')
        = 'openai/gpt-5.6-sol/anthropic/claude-opus-5.5'
  and (select coalesce(model_fallback,'-') from public.model_policy where task_class = 'speech_transcription') = '-'
  and (select count(*) from public.model_policy_by_identity
        where primary_model in ('z-ai/glm-5.3-flash','openai/gpt-5.6-sol')) = 3
  and (select count(*) from public.llm_route_health where model_id = 'openai/gpt-5.6-sol' and open_until > now()) = 1
  and (select sum(monthly_aed) from public.department_budget) = 1600
then 'PROBE OK :: 37 classes on gpt-5.6-sol (36 ex-qwen + the verify), 0 on qwen, 0 on gemini 3.5 / flash-lite, '
     || 'speech on gemini-3.8-flash with no fallback, 0 self-fallbacks, 3 seat catch-alls on glm/sol, '
     || 'Sol registered and held, ceilings AED 1,600/month'
else 'PROBE FAILED :: the matrix did not land as written - read the counts above'
end as verdict;

commit;
