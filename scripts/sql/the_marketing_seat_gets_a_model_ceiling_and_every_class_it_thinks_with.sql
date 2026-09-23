-- THE MARKETING SEAT GETS A MODEL CEILING, AND EVERY CLASS IT THINKS WITH.
-- marketing, 23 September 2026. Founder instructions 865, 866 and 867 (build-plan items 6-10, item 10 here).
--
-- WHAT WAS MEASURED (production, 23 Sep 2026 08:15 UTC)
--   * department_budget 'marketing' = AED 40/month, degrade 70 %, halt 85 %.
--   * fn_task_class: 'marketing_social_inbox' -> marketing_copy (dept marketing), and an ORPHAN
--     'marketing_draft' -> content_drafting with dept_key NULL. fn_ai_route finds the ceiling through
--     fn_task_class.dept_key when the caller names none, so a marketing_draft call was outside every ceiling.
--   * model_policy has marketing_copy and content_drafting on openai/gpt-5.6-sol (instruction 854) and no row
--     for any class this build adds; fn_ai_route would have sent each to general_drafting.
--   * internal_credential fn.marketing has scope ['marketing'] only, so llm.ts presenting cred_fn_marketing to
--     ai_gateway would be refused (HTTP 403) -- the seat could not have called a model the day the hold opens.
--   * model_registry: google/gemini-3.8-flash active, vision + audio, USD 0.75/3.75 per Mtok; the only OTHER
--     audio+vision row is google/gemini-3.5-flash, which is INACTIVE. openai/gpt-5.6-sol is text+image+file.
--
-- WHAT THIS CHANGES
--   1. The ceiling: AED 150/month (degrade 70 %, halt 85 % unchanged). Arithmetic below.
--   2. The orphan: marketing_draft carries dept_key 'marketing'.
--   3. Seven task classes in model_policy, each with its reason (the founder's ruling: customer-facing or a
--      judgement -> openai/gpt-5.6-sol, purely internal -> z-ai/glm-5.3-flash; 867: perception -> a model that
--      can watch AND listen).
--   4. fn.marketing may present its credential to ai_gateway (widened, not a second credential -- the same
--      move as fn.ceo_agent in the_ceo_plans_every_day_and_directs_the_seats.sql).
--
-- WHAT THIS DOES NOT CHANGE: the founder's hold. llm_route_health stays open_until 2126-08-15 on every route;
-- nothing here opens a circuit. ORGANIC ONLY (866): this ceiling is model spend; the seat has no ad budget line.
--
-- ═══ THE COST ESTIMATE THE CEILING IS SET FROM ═══════════════════════════════════════════════════════
-- Catalogue prices, USD/Mtok (in/out): gpt-5.6-sol 2.00/10.00, gemini-3.8-flash 0.75/3.75, opus-5.5 4/20.
-- AED at gl_settings usd_to_aed 3.6725. Video tokens: Gemini samples 1 frame/s at ~258 tokens + ~32 audio
-- tokens/s, so a 28 s master is ~8.1k tokens (the 12 masters are 24-28 s, 3.0-4.1 MB, sent base64 because
-- OpenRouter's Gemini providers do not fetch arbitrary URLs).
--
--   job (cadence)                         in tok   out tok   USD/run   runs/mo   AED/mo   x3 reasoning out
--   marketing_watch (per new asset)        9,100    2,000     0.0143     12        0.63      1.46
--   marketing_quality_review (per asset)   8,000    1,500     0.0310     12        1.37      3.02
--   marketing_research (weekly)           20,000    2,000     0.0600      4.3      0.95      2.53
--   marketing_evaluate (monthly)          15,000    3,000     0.0600      1        0.22      0.55
--   marketing_plan + _defend (<=3 turns)  15,000    3,000     0.0600      3        0.66      1.65
--   ceo_marketing_review, opus (<=3)      15,000    3,000     0.1200      3        1.32      3.30   (class cap AED 50)
--                                                                     TOTAL      5.15     12.51
-- Worst case: every call fails over once to opus-5.5 (2x price) and reasoning triples output: ~AED 25/month.
-- The audit's ~AED 28 (sol, before reasoning overhead) assumed daily copy drafting as well; with that added
-- the realistic bound is ~AED 55-85. AED 150 leaves the degrade line (AED 105) above the worst case measured
-- here, so the ceiling bounds a runaway loop, not normal work. The CEO's review turn is charged to 'marketing'
-- (ceo_agent passes dept 'marketing'): the whole month's planning conversation sits under ONE ceiling.
--
-- THE CEO'S REVIEW MODEL (founder_instruction 873 + the founder's approval, 23 Sep 2026): the reviewer runs on a
-- DIFFERENT model family from the author. Marketing thinks on openai/ and watches on google/, so the CEO's
-- ceo_marketing_review runs on anthropic/claude-opus-5.5 (fallback anthropic/claude-sonnet-5), capped at AED 50 a
-- month for the class (fn_marketing_class_ceiling, in the other file) inside the marketing ceiling. The general
-- cross-seat review build (it_engineer, seat_deliberation) will enforce the family rule for every seat; this row
-- already satisfies it.

-- ── 1. THE CEILING ───────────────────────────────────────────────────────────────────────────────
update public.department_budget set monthly_aed = 150, updated_at = now() where dept_key = 'marketing';

-- ── 2. THE ORPHAN, AND ANY FUTURE ONE ─────────────────────────────────────────────────────────────
update public.fn_task_class set dept_key = 'marketing', updated_at = now()
 where (fn like 'marketing%' or task_class like 'marketing%') and dept_key is distinct from 'marketing';

-- ── 3. THE CLASSES ───────────────────────────────────────────────────────────────────────────────
insert into public.model_policy (task_class, tier, model_primary, model_fallback, max_tokens, rationale, deterministic_alternative, active, cache_ttl_min) values
 ('marketing_watch', 'medium', 'google/gemini-3.8-flash', null, 2500,
  'Founder 867: the seat must SEE and HEAR each post, not read numbers. The whole video with its soundtrack goes in and a structured timeline comes out (marketing_asset_perception). WHY gemini-3.8-flash: it is the ONLY active model_registry row with vision AND audio (23 Sep 2026); gpt-5.6-sol reads text+image+file and cannot hear. FALLBACK NULL ON PURPOSE: the only other audio+vision row, google/gemini-3.5-flash, is inactive, and a fallback that cannot watch would describe a video it never saw. Internal perception feeding a judgement, never published, so the cheap perceiver is right. 2500 tokens: a 28 s timeline with every caption line.',
  'Deterministic features first (marketing_asset_feature: ffprobe/ffmpeg/tesseract) - they cross-check what the model claims', true, 0),
 ('marketing_quality_review', 'large', 'openai/gpt-5.6-sol', 'anthropic/claude-opus-5.5', 2000,
  'A senior creative judging each post: hook, pacing, legibility, music fit, voice-over, and what next month changes, citing the perception row, the measured features, key frames and the post''s real results. A JUDGEMENT that decides what the company publishes next month -> the founder''s judgement row (gpt-5.6-sol, instruction 854), opus-5.5 behind it as a stronger second opinion. Reads images (key frames), which sol does.', null, true, 0),
 ('marketing_research', 'large', 'openai/gpt-5.6-sol', 'anthropic/claude-opus-5.5', 2500,
  'The weekly synthesis of competitor posts (market_intel, one row per post with its URL) into marketing_insight_note. A JUDGEMENT on what the market does and what that means for our plan, over UAE posts that are often Arabic -> the judgement/Arabic row. The fetch and storage are deterministic; only the synthesis calls the model.', 'Fetch + store per post is code (fn_marketing_intel_upsert)', true, 0),
 ('marketing_evaluate', 'large', 'openai/gpt-5.6-sol', 'anthropic/claude-opus-5.5', 3000,
  'The month''s verdict: what worked and why, from the scorecard, the asset reviews and the market notes. A JUDGEMENT the next month''s plan stands on -> judgement row.', 'fn_marketing_scorecard is the deterministic half', true, 0),
 ('marketing_plan', 'large', 'openai/gpt-5.6-sol', 'anthropic/claude-opus-5.5', 4000,
  'The next month''s plan and content brief (topics, formats, music, voice-over, length, count, cadence), proposed to the CEO with its reasons and evidence (866). A JUDGEMENT; the brief is what the founder produces the videos from. 4000 tokens: the plan plus its reasoning, bounded.', null, true, 0),
 ('marketing_plan_defend', 'large', 'openai/gpt-5.6-sol', 'anthropic/claude-opus-5.5', 3000,
  'Marketing''s answer to EACH of the CEO''s asks: concede and adjust, or defend with evidence (866). A JUDGEMENT, same row as the plan it defends.', null, true, 0),
 ('ceo_marketing_review', 'xlarge', 'anthropic/claude-opus-5.5', 'anthropic/claude-sonnet-5', 3000,
  'The CEO judging marketing''s plan on five criteria (goal, evidence strength, production cost, truth and brand fit, risk if wrong) from the same videos, frames and results marketing used (866, 867). THE FOUNDER APPROVED THIS MODEL, 23 Sep 2026: anthropic/claude-opus-5.5, because ruling 873 requires the reviewer to run on a DIFFERENT model family from the author (marketing thinks on openai/ and watches on google/). The fallback stays anthropic (sonnet-5) for the same reason: a fallback onto openai/ would review marketing with marketing''s own model. Capped at AED 50/month for this class (fn_marketing_class_ceiling), inside the marketing ceiling; spend is logged by ai_gateway through fn_llm_log into ai_cost_log.', null, true, 0)
on conflict (task_class) do update set tier = excluded.tier, model_primary = excluded.model_primary,
  model_fallback = excluded.model_fallback, max_tokens = excluded.max_tokens, rationale = excluded.rationale,
  deterministic_alternative = excluded.deterministic_alternative, active = excluded.active, cache_ttl_min = excluded.cache_ttl_min;

-- ── 4. THE SEAT MAY PRESENT ITS CREDENTIAL TO THE GATEWAY ─────────────────────────────────────────
update public.internal_credential
   set scope = array(select distinct x from unnest(scope || array['ai_gateway']) x order by x)
 where context = 'fn.marketing' and active and not (scope @> array['ai_gateway']);

-- ── VERDICT ──────────────────────────────────────────────────────────────────────────────────────
select case
  when (select monthly_aed from public.department_budget where dept_key = 'marketing') <> 150
    then 'PROBE FAILED: marketing budget is not 150'
  when exists (select 1 from public.fn_task_class where (fn like 'marketing%' or task_class like 'marketing%') and dept_key is distinct from 'marketing')
    then 'PROBE FAILED: a marketing task class is still outside the marketing ceiling'
  when (select count(*) from public.model_policy where active and task_class in ('marketing_watch','marketing_quality_review',
        'marketing_research','marketing_evaluate','marketing_plan','marketing_plan_defend','ceo_marketing_review')) <> 7
    then 'PROBE FAILED: not all seven classes are active in model_policy'
  when (select model_primary from public.model_policy where task_class = 'ceo_marketing_review') not like 'anthropic/%'
    then 'PROBE FAILED: the CEO reviewer is not on a different family from the marketing author (873)'
  when not exists (select 1 from public.internal_credential where context = 'fn.marketing' and active and scope @> array['ai_gateway'])
    then 'PROBE FAILED: fn.marketing cannot present to ai_gateway'
  when exists (select 1 from public.llm_route_health where open_until is null or open_until < now() + interval '50 years')
    then 'PROBE FAILED: a route is no longer held - this file must not open the hold'
  else 'PROBE OK' end as verdict;
