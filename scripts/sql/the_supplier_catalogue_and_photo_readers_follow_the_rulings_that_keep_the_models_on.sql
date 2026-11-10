-- the_supplier_catalogue_and_photo_readers_follow_the_rulings_that_keep_the_models_on
-- Seat: sales_engineer (the supplier's Services tab and catalogue reading). 10 Nov 2026.
--
-- MEASURED ON PRODUCTION, 10 Nov 2026: decision_policy supplier_catalogue_model_enabled and supplier_photo_vision_enabled
-- are {"enabled": false}, last updated 21 Sep 2026 16:30 UTC, and their own descriptions give the reason: "OFF while the
-- OpenRouter hold stands". A supplier whose profile is prose code cannot read was told "Reading the rest is waiting on the
-- language model, which is switched off for now" (supplier_api services_rewrite; docs/reports/2026-11-10-launch-verification.md
-- should-fix 2).
--
-- THE RULINGS (public.founder_instruction, both 'standing'):
--   1175, 7 Oct 2026: "from now on keep open router always on" - the paid-model hold lifted permanently on every route.
--   1260, 19 Oct 2026: "all tests need to be done with AI. from now on open router stays on"
--   (.claude/memory/openrouter-stays-on-all-tests-with-ai.md: never stub, hold or switch the models off again).
-- The hold these two switches waited on ended with 1175, and 1260 says it does not come back. Leaving them off contradicts
-- both, so this file switches both ON. Spend is bounded as for every other model call: the sales_engineer route through
-- ai_gateway (_shared/llm.ts makeLlmRich, max 600 output tokens per read), under the production spend ceilings; a read
-- is a proposal the supplier confirms, and only active taxonomy keys survive parseModelRead.
-- The off line the supplier would see if a switch were ever turned off again no longer promises "for now" or "waiting on"
-- anything; it asks him to describe the rest in his own words (_shared/catalogue_model.ts OFF_MESSAGE).
--
-- Prevented by: supabase/functions/_shared/catalogue_read.test.ts (the off line promises nothing and asks for his words;
-- this file is the last word on both switches and turns them on).

set local app.actor = 'sales_engineer: rulings 1175 and 1260 keep the models on (10 Nov 2026)';

update public.decision_policy
   set value = '{"enabled": true}'::jsonb,
       description = 'Supplier catalogue model path (_shared/catalogue_model.ts): a catalogue or description code could not read (no text layer, free-form prose) sent to ai_gateway on the sales_engineer route for {product_types, services, confidence, reason}, a proposal the supplier confirms. ON since 10 Nov 2026 under founder rulings 1175 and 1260 (OpenRouter stays on); the hold it waited on was lifted on 7 Oct 2026.',
       updated_at = now()
 where key = 'supplier_catalogue_model_enabled';

update public.decision_policy
   set value = '{"enabled": true}'::jsonb,
       description = 'Supplier photo vision path (_shared/catalogue_model.ts): what a product photo SHOWS, sent to ai_gateway on the sales_engineer route, a proposal the supplier confirms. The text IN a photo is read free in the supplier''s browser (tesseract.js) whatever this says. ON since 10 Nov 2026 under founder rulings 1175 and 1260 (OpenRouter stays on).',
       updated_at = now()
 where key = 'supplier_photo_vision_enabled';

-- verdict (reads only)
select case
  when (select count(*) from public.decision_policy
         where key in ('supplier_catalogue_model_enabled', 'supplier_photo_vision_enabled') and value = '{"enabled": true}'::jsonb) <> 2
    then 'PROBE FAILED: both supplier reader switches must be on'
  when exists (select 1 from public.decision_policy
                where key in ('supplier_catalogue_model_enabled', 'supplier_photo_vision_enabled') and description ilike '%hold stands%')
    then 'PROBE FAILED: a description still gives the lifted hold as its reason'
  else 'PROBE OK' end as verdict;
