-- NO CLASS BUT VOICE FALLS BACK TO GEMINI; SONNET 5.5 IS THE FALLBACK (it_engineer, 19 Oct 2026; rulings 1241, 1218).
--
-- Measured 19 Oct 2026 00:56 UTC in ai_cost_log (last 3 h): 6 non-voice calls answered by google/gemini-3.8-flash
-- (4 internal_judgement 22:17, 2 customer_communication 00:10 and 00:17, one cut at the 900-token ceiling) and 132 by
-- plain openai/gpt-6-luna, every one reading "[matrix v2] ... luna with gemini behind it". The last of either is
-- 00:20:47; from 00:21:26 every call names matrix v3 (Luna Pro > Sonnet 5.5). model_policy, model_policy_by_identity,
-- review_pool (active) and model_fallback_chain already conform at the time of writing, so this file is a
-- convergence guard: it rewrites whatever has drifted back and proves the two rules, and is a no-op on a clean estate.
--
-- A class HEARS when its primary is Gemini (speech_transcription, marketing_watch); it keeps Gemini and no fallback.
-- Every other class: a Gemini or plain-luna fallback becomes Sonnet 5.5 (Luna Pro where Sonnet is the primary, so a
-- class never falls back to itself); a plain-luna primary becomes Luna Pro.
select set_config('app.change_reason', 'it_engineer: no class but voice falls back to Gemini (rulings 1241, 1218)', true);

update public.model_policy set model_primary = 'openai/gpt-6-luna-pro'
 where model_primary = 'openai/gpt-6-luna';

update public.model_policy
   set model_fallback = case when model_primary = 'anthropic/claude-sonnet-5.5' then 'openai/gpt-6-luna-pro'
                             else 'anthropic/claude-sonnet-5.5' end
 where model_primary not like 'google/gemini%'
   and (model_fallback like 'google/gemini%' or model_fallback = 'openai/gpt-6-luna');

update public.model_policy_by_identity set primary_model = 'openai/gpt-6-luna-pro' where primary_model = 'openai/gpt-6-luna';
update public.model_policy_by_identity
   set fallback_model = case when primary_model = 'anthropic/claude-sonnet-5.5' then 'openai/gpt-6-luna-pro'
                             else 'anthropic/claude-sonnet-5.5' end
 where fallback_model like 'google/gemini%' or fallback_model = 'openai/gpt-6-luna';
update public.model_policy_by_identity set escalation_model = 'anthropic/claude-opus-5.5'
 where escalation_model like 'google/gemini%' or escalation_model = 'openai/gpt-6-luna';

select set_config('app.change_reason', '', true);

-- PROBE. Fails the transaction (and so the rewrite) if either rule is broken anywhere fn_ai_route reads a route.
do $probe$ declare v text; begin
  select string_agg(r, '; ') into v from (
    select 'model_policy ' || task_class || ' names Gemini outside a recording' r from public.model_policy
     where active and model_primary not like 'google/gemini%' and coalesce(model_fallback, '') like 'google/gemini%'
    union all select 'model_policy ' || task_class || ' names plain luna' from public.model_policy
     where active and 'openai/gpt-6-luna' in (model_primary, coalesce(model_fallback, ''))
    union all select 'model_policy_by_identity ' || identity_key || ' names Gemini or plain luna' from public.model_policy_by_identity
     where concat_ws('|', primary_model, fallback_model, escalation_model) ~ '(google/gemini|openai/gpt-6-luna(\||$))'
    union all select 'review_pool names ' || model_id from public.review_pool
     where active and (model_id like 'google/gemini%' or model_id = 'openai/gpt-6-luna')
    union all select 'model_fallback_chain ' || purpose || ' names ' || model from public.model_fallback_chain
     where active and ((model like 'google/gemini%' and purpose <> 'whatsapp_voice_note') or model = 'openai/gpt-6-luna')
  ) q;
  if v is not null then raise exception 'CHK<<PROBE FAILED: %>>', v; end if;
end $probe$;

select 'PROBE OK: no non-voice route names Gemini and no route names plain luna' as verdict;
