-- a_supplier_profile_s_trades_are_chosen_by_luna_pro
-- Seat: sales_engineer. 19 Oct 2026, on the founder's instruction for the campaign: "Luna Pro for extraction, Gemini
-- only for voice". Supersedes the route a_supplier_profile_s_trades_are_chosen_by_sonnet_from_our_codes.sql set
-- (applied in the same release, before this file): supplier_trade_choice runs on matrix v3's extraction pair,
-- openai/gpt-6-luna-pro > anthropic/claude-sonnet-5.5 (a backup from another provider; ruling 1218 retires plain luna).
-- The luna-pro model_registry and model_rate rows belong to matrix v3
-- (gemini_only_hears_and_every_other_class_runs_luna_pro_and_the_5_6_generation_leaves.sql, #1433), which must be
-- applied first; this file only names the route. Applied at merge (release operator).
insert into public.model_policy (task_class, tier, model_primary, model_fallback, max_tokens, rationale, deterministic_alternative, active, cache_ttl_min)
values ('supplier_trade_choice', 'medium', 'openai/gpt-6-luna-pro', 'anthropic/claude-sonnet-5.5', 3000,
        '19 Oct 2026, founder: Luna Pro for extraction, Gemini only for voice; matrix v3 extraction pair. A supplier profile''s or catalogue''s trades are chosen from our codes, each proven by a quoted line code checks, then checked a second time.',
        'exact code or gte-small meaning confirmed by the trade''s own words (trade_resolve.ts) - measured too imprecise on real profiles',
        true, 0)
on conflict (task_class) do update set tier = excluded.tier, model_primary = excluded.model_primary, model_fallback = excluded.model_fallback,
  max_tokens = excluded.max_tokens, rationale = excluded.rationale, deterministic_alternative = excluded.deterministic_alternative, active = true;

select case when (public.fn_ai_route(p_task_class => 'supplier_trade_choice', p_fn => 'supplier_doc_trades') ->> 'model') = 'openai/gpt-6-luna-pro'
              and (public.fn_ai_route(p_task_class => 'supplier_trade_choice', p_fn => 'supplier_doc_trades') ->> 'fallback') = 'anthropic/claude-sonnet-5.5'
              and exists (select 1 from public.model_rate where model = 'openai/gpt-6-luna-pro')
            then 'PROBE OK' else 'PROBE FAILED: supplier_trade_choice does not route to luna-pro > sonnet, or matrix v3 (luna-pro price) is not applied' end as verdict;
