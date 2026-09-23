-- The retired models cannot be called, and the ceilings count real spend.
--
-- Two defects in gpt_sol_takes_every_qwen_class_and_one_gemini_takes_every_gemini_class.sql, both
-- found by the independent review of PR #867 and both measured on production, not argued.
--
-- 1. THE RETIRED MODELS WERE STILL CALLABLE. That file took qwen/qwen3.8-max-0902,
--    google/gemini-3.5-flash and google/gemini-3.1-flash-lite out of every model_policy row, but left
--    them active and approved in model_registry. fn_ai_route does not only read model_policy: when a
--    call REQUIRES a capability (ai_gateway/index.ts:191 marks every input_audio part as needing
--    audio, and transcribe always sends one) its v_fb block searches the whole registry for any
--    active model that has it. Measured before this file:
--      fn_ai_route('speech_transcription', ..., p_require_caps => '{audio}')  -> fallback gemini-3.1-flash-lite
--      customer_communication / wa_inbound with '{audio}'                     -> fallback gemini-3.5-flash
--    and ai_gateway/index.ts:511 retries [model, fallback], so a failed voice note went to a model
--    the founder had just retired. It also made the first file's claim false: "a failed call retries
--    3.8 flash" held only for calls that did not carry audio.
--    FIX: deactivate the three. fn_llm_preflight then refuses them as route_not_registered, and the
--    capability search can no longer find them.
--    The one other place a retired id lived: paid_route_exception 'drawing_boq_confirm' still named
--    gemini-3.1-flash-lite (enabled=false). It would have called a retired model the moment it was
--    switched on; it now names gemini-3.8-flash, still disabled.
--
-- 2. THE CEILINGS NEVER FIRED, AND NEVER HAD. fn_llm_log prices a call ONLY from public.model_rate and
--    records cost_aed = 0 when the model has no row; fn_ai_route measures a department's use as the
--    sum of ai_cost_log.cost_aed. model_rate had no row for ANY model a policy routes to - not Sol,
--    and not gemini-3.8-flash, z-ai/glm-5.3-flash, anthropic/claude-opus-5.5 or openai/gpt-6-luna
--    (the medium degrade target) either. So every call would have counted as AED 0 and no ceiling,
--    old or new, would ever have degraded or halted anything. The gap predates #867; #867 re-derived
--    the ceilings as though spend were counted, which is what made it matter.
--    FIX: a model_rate row for every active registry model that lacked one, USD read live from
--    https://openrouter.ai/api/v1/models on 23 Sep 2026, converted at the 3.6725 peg every other row
--    in the table names. Cache rates are the catalogue's own, not derived.
--
-- 3. SOL'S CACHE-WRITE PRICE. The first file said OpenAI charges no cache-write surcharge and set
--    2.00. The catalogue serves input_cache_write = USD 2.50/Mtok. Corrected here and in the first
--    file's text. The price check compared in/out/context only, which is why it stayed green.
--
-- 4. STALE TEXT ON LIVE ROWS: the speech_transcription, redaction_detection and
--    identity_redaction_verify rationales, and the three model_policy_by_identity notes, still
--    described the models before founder_instruction 854.
--
-- Seat: it_engineer.

begin;

-- 1. Retire the three from the registry, and the one exception that still named one.
update public.model_registry set active = false, updated_at = now(),
       note = coalesce(note, '') || ' | RETIRED 23 Sep 2026 by founder_instruction 854; deactivated so '
              || 'fn_ai_route''s capability search cannot fall back to it.'
 where model_id in ('qwen/qwen3.8-max-0902', 'google/gemini-3.5-flash', 'google/gemini-3.1-flash-lite')
   and active;

update public.paid_route_exception set model_id = 'google/gemini-3.8-flash', updated_at = now()
 where route = 'drawing_boq_confirm' and model_id = 'google/gemini-3.1-flash-lite';

-- 3. Sol's cache write.
update public.model_registry set cache_write_per_mtok_usd = 2.50, updated_at = now()
 where model_id = 'openai/gpt-5.6-sol';

-- 2. A rate for every routed model. Tier is taken from the registry so the two tables cannot disagree.
insert into public.model_rate
  (model, tier, in_aed_per_mtok, out_aed_per_mtok, usd_per_m_prompt, usd_per_m_output,
   cache_read_aed_per_mtok, cache_write_aed_per_mtok, id_verified, source_url, verified_at, note)
select v.model, r.tier,
       round(v.usd_in  * 3.6725, 6), round(v.usd_out * 3.6725, 6), v.usd_in, v.usd_out,
       round(v.usd_cr * 3.6725, 6), case when v.usd_cw is null then null else round(v.usd_cw * 3.6725, 6) end,
       true, 'https://openrouter.ai/api/v1/models', date '2026-09-23',
       'Converted at 3.6725 AED/USD, the same rate every other row in this table names. USD prices read '
       || 'from the OpenRouter catalogue on 23 Sep 2026. Added because fn_llm_log records cost_aed = 0 for '
       || 'a model with no row here, so no department ceiling could ever fire on this model.'
       || case when v.usd_cw is null then ' The catalogue serves no cache-write price for this model; '
               || 'fn_llm_log coalesces a null to in*1.25.' else '' end
  from (values
    ('openai/gpt-5.6-sol',         2.00, 10.00, 0.200, 2.5000),
    ('anthropic/claude-opus-5.5',  4.00, 20.00, 0.200, 5.0000),
    ('google/gemini-3.8-flash',    0.75,  3.75, 0.075, 0.0417),
    ('z-ai/glm-5.3-flash',         0.15,  0.50, 0.050, null),
    ('openai/gpt-6-luna',          0.10,  0.50, 0.010, 0.1250)
  ) as v(model, usd_in, usd_out, usd_cr, usd_cw)
  join public.model_registry r on r.model_id = v.model
 where not exists (select 1 from public.model_rate m where m.model = v.model);

-- 4. The text on the live rows.
update public.model_policy set rationale =
  'Verbatim speech to text. THE ONE CLASS EXEMPT FROM the plan-A models, and not by choice: only the '
  || 'gemini family carries "audio" in input_modalities (read live 23 Sep 2026). Since founder_instruction '
  || '854 retired gemini-3.5-flash and gemini-3.1-flash-lite, gemini-3.8-flash is the only model that '
  || 'hears, so this class has NO fallback: fn_ai_route returns coalesce(model_fallback, primary), and a '
  || 'failed transcription retries 3.8 flash rather than reaching a model that cannot hear.'
 where task_class = 'speech_transcription';

update public.model_policy set rationale =
  'The second pass over a REDACTED drawing page, asked whether any identity is still legible '
  || '(drawing_redact/index.ts, fn drawing_redact_verify). Founder_instruction 854 put it on '
  || 'openai/gpt-5.6-sol, the same model as the find pass, so on the normal path find and verify share '
  || 'a model; the founder chose that. The fallback is anthropic/claude-opus-5.5, a different model, so '
  || 'the independence returns on the fallback path. drawing_redact fails closed on truncated, '
  || 'unparseable or exception, on every path.'
 where task_class = 'identity_redaction_verify';

update public.model_policy set rationale =
  'Pack: must include independent post-redaction verification and fail closed. No caller today. On '
  || 'google/gemini-3.8-flash since founder_instruction 854 retired flash-lite; fallback '
  || 'openai/gpt-5.6-sol, which reads images.'
 where task_class = 'redaction_detection';

update public.model_policy_by_identity set note =
  'Catch-all for a call from this seat that no model_policy class covers (fn_ai_route applies it only '
  || 'when v_generic). On z-ai/glm-5.3-flash with google/gemini-3.8-flash behind it since 23 Sep 2026: '
  || 'founder_instruction 844 puts internal operations on GLM.'
 where scope = 'current_agent' and identity_key in ('accountant', 'it_engineer');

update public.model_policy_by_identity set note =
  'Catch-all for a call from this seat that no model_policy class covers (fn_ai_route applies it only '
  || 'when v_generic). On openai/gpt-5.6-sol with anthropic/claude-opus-5.5 behind it since 23 Sep 2026: '
  || 'marketing writes what customers and suppliers read, in Arabic, which founder_instruction 844 and '
  || '854 put on the customer-facing model.'
 where scope = 'current_agent' and identity_key = 'marketing';

-- The verdict, measured through the router and the preflight, not only the tables. No raise: it
-- would roll back every write above with the check.
select case when
      (select count(*) from public.model_registry
        where active and model_id in ('qwen/qwen3.8-max-0902','google/gemini-3.5-flash','google/gemini-3.1-flash-lite')) = 0
  and (select public.fn_llm_preflight('google/gemini-3.1-flash-lite') ->> 'allowed') = 'false'
  and coalesce((public.fn_ai_route(p_task_class := 'speech_transcription', p_require_caps := array['audio'])) ->> 'fallback', '-')
        not in ('google/gemini-3.1-flash-lite', 'google/gemini-3.5-flash', 'qwen/qwen3.8-max-0902')
  and coalesce((public.fn_ai_route(p_task_class := 'customer_communication', p_require_caps := array['audio'])) ->> 'fallback', '-')
        not in ('google/gemini-3.1-flash-lite', 'google/gemini-3.5-flash', 'qwen/qwen3.8-max-0902')
  and (select count(*) from public.model_registry r
        where r.active and not exists (select 1 from public.model_rate m where m.model = r.model_id)) = 0
  and (select cache_write_per_mtok_usd from public.model_registry where model_id = 'openai/gpt-5.6-sol') = 2.50
  and (select count(*) from public.paid_route_exception
        where model_id in ('qwen/qwen3.8-max-0902','google/gemini-3.5-flash','google/gemini-3.1-flash-lite')) = 0
then 'PROBE OK :: the three retired models are inactive and refused by preflight, no audio fallback reaches '
     || 'them, every active registry model has a model_rate row, Sol cache write 2.50, no exception names a retired model'
else 'PROBE FAILED :: read the counts - a retired model is still reachable or a routed model has no rate'
end as verdict;

commit;
