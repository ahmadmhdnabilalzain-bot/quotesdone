-- a_supplier_profile_s_trades_are_chosen_by_sonnet_from_our_codes
-- Seat: sales_engineer (the reading); it_engineer (the build). 13 Oct 2026.
-- The model route for _shared/supplier_trade_choice.ts: a supplier's company profile or catalogue is read once per
-- supplier, its trades chosen from our active codes with a quoted line each, then checked a second time. The strongest
-- sensible model: anthropic/claude-sonnet-5.5, google/gemini-3.8-flash behind it. Measured on 29 real UAE profiles
-- (ACCURACY_real_profiles.md): about AED 0.08 a profile for both calls (the definitions are the cached system block).
-- Without this row fn_ai_route would fall back to the catch-all class. Applied at merge (release operator).
insert into public.model_policy (task_class, tier, model_primary, model_fallback, max_tokens, rationale, deterministic_alternative, active, cache_ttl_min)
values ('supplier_trade_choice', 'medium', 'anthropic/claude-sonnet-5.5', 'google/gemini-3.8-flash', 3000,
        '13 Oct 2026 (coordinator, on rulings 1175/1177/890): a supplier profile''s or catalogue''s trades are chosen by the model from our 213 codes, each proven by a quoted line that code checks, then checked a second time. Code-only mapping measured 7/29 files exact with 37 wrong trades.',
        'exact code or gte-small meaning confirmed by the trade''s own words (trade_resolve.ts) - measured too imprecise on real profiles',
        true, 0)
on conflict (task_class) do update set tier = excluded.tier, model_primary = excluded.model_primary, model_fallback = excluded.model_fallback,
  max_tokens = excluded.max_tokens, rationale = excluded.rationale, deterministic_alternative = excluded.deterministic_alternative, active = true;

select case when (select model_primary from public.model_policy where task_class = 'supplier_trade_choice') = 'anthropic/claude-sonnet-5.5'
              and (public.fn_ai_route(p_task_class => 'supplier_trade_choice', p_fn => 'supplier_doc_trades') ->> 'model') = 'anthropic/claude-sonnet-5.5'
            then 'PROBE OK' else 'PROBE FAILED: supplier_trade_choice does not route to sonnet 5.5' end as verdict;
