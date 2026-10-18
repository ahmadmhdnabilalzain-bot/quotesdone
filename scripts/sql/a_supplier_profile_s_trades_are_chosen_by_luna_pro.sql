-- a_supplier_profile_s_trades_are_chosen_by_luna_pro
-- Seat: sales_engineer. 19 Oct 2026, on the founder's instruction for the campaign: "Luna Pro for extraction, Gemini
-- only for voice". Supersedes the route a_supplier_profile_s_trades_are_chosen_by_sonnet_from_our_codes.sql set
-- (applied in the same release, before this file): supplier_trade_choice now runs on openai/gpt-6-luna-pro with
-- openai/gpt-6-luna behind it - no Gemini on this class.
-- Price read from the OpenRouter catalogue on 19 Oct 2026: openai/gpt-6-luna-pro USD 0.10 / 0.50 per Mtok, 1,050,000
-- context - the same as openai/gpt-6-luna (ruling 1218: at the same price, always Pro). Without a model_rate row
-- fn_llm_log books the model's cost as unknown (#1395), so the row is added with it. Applied at merge (release operator).
insert into public.model_registry
  (model_id, provider, tier, in_per_mtok_usd, out_per_mtok_usd,
   cache_read_per_mtok_usd, cache_write_per_mtok_usd, supports_cache, supports_streaming,
   context_len, approved, active, quality_score, supports_vision, supports_audio, supports_tools, note)
values
  ('openai/gpt-6-luna-pro', 'openai', 'small', 0.10, 0.50,
   null, null, false, true, 1050000, true, true, null, true, false, true,
   'Live 19 Oct 2026: $0.10/$0.50 per Mtok, 1,050,000 context, the price of openai/gpt-6-luna (ruling 1218: same price, '
   || 'always Pro). The founder''s model for extraction: a supplier profile''s and catalogue''s trades '
   || '(supplier_trade_choice). NO AUDIO.')
on conflict (model_id) do update set provider = excluded.provider, tier = excluded.tier, in_per_mtok_usd = excluded.in_per_mtok_usd,
  out_per_mtok_usd = excluded.out_per_mtok_usd, context_len = excluded.context_len, approved = true, active = true,
  supports_vision = excluded.supports_vision, supports_audio = excluded.supports_audio, supports_tools = excluded.supports_tools, note = excluded.note;

insert into public.model_rate
  (model, tier, in_aed_per_mtok, out_aed_per_mtok, usd_per_m_prompt, usd_per_m_output,
   cache_read_aed_per_mtok, cache_write_aed_per_mtok, id_verified, source_url, verified_at, note)
values ('openai/gpt-6-luna-pro', 'small', round(0.10 * 3.6725, 6), round(0.50 * 3.6725, 6), 0.10, 0.50,
        null, null, true, 'https://openrouter.ai/api/v1/models', date '2026-10-19',
        'Converted at 3.6725 AED/USD, as every row here. USD prices from the OpenRouter catalogue on 19 Oct 2026. Cache rates not listed: null.')
on conflict (model) do update set in_aed_per_mtok = excluded.in_aed_per_mtok, out_aed_per_mtok = excluded.out_aed_per_mtok,
  usd_per_m_prompt = excluded.usd_per_m_prompt, usd_per_m_output = excluded.usd_per_m_output, verified_at = excluded.verified_at, note = excluded.note;

insert into public.model_policy (task_class, tier, model_primary, model_fallback, max_tokens, rationale, deterministic_alternative, active, cache_ttl_min)
values ('supplier_trade_choice', 'medium', 'openai/gpt-6-luna-pro', 'openai/gpt-6-luna', 3000,
        '19 Oct 2026, founder: Luna Pro for extraction, Gemini only for voice. A supplier profile''s or catalogue''s trades are chosen from our codes, each proven by a quoted line code checks, then checked a second time.',
        'exact code or gte-small meaning confirmed by the trade''s own words (trade_resolve.ts) - measured too imprecise on real profiles',
        true, 0)
on conflict (task_class) do update set tier = excluded.tier, model_primary = excluded.model_primary, model_fallback = excluded.model_fallback,
  max_tokens = excluded.max_tokens, rationale = excluded.rationale, deterministic_alternative = excluded.deterministic_alternative, active = true;

select case when (public.fn_ai_route(p_task_class => 'supplier_trade_choice', p_fn => 'supplier_doc_trades') ->> 'model') = 'openai/gpt-6-luna-pro'
              and (public.fn_ai_route(p_task_class => 'supplier_trade_choice', p_fn => 'supplier_doc_trades') ->> 'fallback') = 'openai/gpt-6-luna'
              and exists (select 1 from public.model_rate where model = 'openai/gpt-6-luna-pro')
            then 'PROBE OK' else 'PROBE FAILED: supplier_trade_choice does not route to luna-pro > luna, or luna-pro has no price' end as verdict;
