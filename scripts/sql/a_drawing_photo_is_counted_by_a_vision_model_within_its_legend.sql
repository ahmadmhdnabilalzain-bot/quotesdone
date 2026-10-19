-- a_drawing_photo_is_counted_by_a_vision_model_within_its_legend — 19 Oct 2026. Assigned: sales_engineer.
-- Founder ledger 580, 1177; ruling 1260 (OpenRouter stays on; spend approved); coordinator: Sonnet 5.5 or Luna Pro,
-- never Gemini; ships OFF (release operator): switched on only after the bench passes with real models. Measured before: template matching on a phone photo of the sample sheet read
-- 53 call points against 10. drawing_boq mode 'vision_count' (vision_count.ts) sends the REDACTED page only.
-- Apply at merge (never before). Rollback: delete the two rows below and set the app_secrets value to 'off'.
insert into public.model_policy (task_class, tier, model_primary, model_fallback, max_tokens, rationale, deterministic_alternative, active, cache_ttl_min)
values ('drawing_vision_count', 'small', 'anthropic/claude-sonnet-5.5', 'openai/gpt-6-luna-pro', 600,
        'Count each legend symbol on a redacted drawing photo or scan where template matching cannot (founder 580, 1177, ruling 1260).',
        'symbol_count.ts template counts, to be confirmed by the customer', true, 0)
on conflict (task_class) do update set model_primary = excluded.model_primary, model_fallback = excluded.model_fallback, max_tokens = excluded.max_tokens, active = true;

insert into public.paid_route_exception (route, enabled, model_id, max_tokens_per_call, daily_cap_aed, authority_instruction_id, note)
values ('drawing_vision_count', false, 'anthropic/claude-sonnet-5.5', 600, 10.00, null,
        'One vision call per photographed or scanned drawing page, counting its legend symbols. Ships OFF; switched on only after the drawing bench passes with real models.')
on conflict (route) do update set model_id = excluded.model_id;

insert into public.app_secrets (key, value) values ('drawing_vision_count_enabled', 'off')
on conflict (key) do nothing;
