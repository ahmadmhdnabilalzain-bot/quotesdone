-- THE CATALOGUE NAMES EVERY MODEL THE SEATS RUN, AND THE HOLD COVERS ALL OF THEM.
-- it_engineer, 23 September 2026.
--
-- Three measured defects in the one door (ai_gateway -> fn_ai_route -> model_policy ->
-- model_registry -> llm_route_health), all in the same place: the catalogue and the breaker
-- disagree about which models exist.
--
-- ─── 1. THE HOLD WAS BYPASSABLE ON EXACTLY THE EXPENSIVE ROUTES ──────────────────────────────────
--
-- fn_llm_preflight answered `allowed: true, reason: 'registered, breaker closed'` for any model
-- that is an active model_registry row and has NO llm_route_health row at all. Measured on
-- production 23 Sep 2026:
--
--   select model_primary from model_policy where active and model_primary <> 'none'
--   except select model_id from llm_route_health;
--     anthropic/claude-fable-5.1        <- ceo_approval_decision, ceo_strategic_planning,
--                                          customer_portal_assistant, sales_engineer_reasoning
--     openai/gpt-5.6-luna               <- every accountant class
--   ... and the same query over model_fallback adds openai/gpt-6-astra.
--
-- llm_route_health holds 8 rows, all with open_until 2126-08-15 — the founder's hold on
-- OpenRouter. It covered haiku, sonnet, opus-4.8, both gemini rows, qwen and 'none'. It did NOT
-- cover fable-5.1 at $10/$50, gpt-6-astra at $10/$50 or gpt-5.6-luna, because those three were
-- added to model_policy and model_registry after the hold rows were written and nobody added a
-- breaker row for them. A breaker whose default answer is "allowed" is not a breaker; it is a
-- breaker with a hole shaped exactly like whatever was added last.
--
-- The absence of a health row is the absence of a MEASUREMENT, not evidence of health. This file
-- makes fn_llm_preflight FAIL CLOSED on it, and gives every registry model a health row so the
-- fail-closed branch is a guard rather than a wall.
--
-- THE HOLD IS NOT LIFTED HERE. Every row this file inserts into llm_route_health carries the SAME
-- open_until as the rows already there (read from the table, not typed), so a model added by this
-- file is held exactly as the others are. The founder opens the hold separately, after this is
-- applied and verified.
--
-- ─── 2. model_registry WAS A NINE-MODEL ISLAND WITH STALE CONTEXT LENGTHS ────────────────────────
--
-- fn_ai_route SUBSTITUTES when a policy names a model the registry does not hold ("WARNING: policy
-- model ... is not in model_registry; substituted ..."), so the registry is a gate, not a
-- reference. Two of the models the seats now need were not in it at all, and two context lengths
-- were wrong by 5x.
--
-- Prices and context lengths below were read LIVE from https://openrouter.ai/api/v1/models on
-- 23 Sep 2026 (scripts/checks/the_registry_prices_are_the_catalogue_s_prices.test.mjs re-reads
-- them), USD per million tokens:
--
--   model                            in     out    ctx        vision  audio   registry said
--   anthropic/claude-opus-5.5        4.00   20.00  1,000,000  yes     no      ABSENT
--   anthropic/claude-sonnet-5        2.00   10.00  1,000,000  yes     no      ctx 200,000  (5x low)
--   ~anthropic/claude-haiku-latest   1.00    5.00    200,000  yes     no      correct
--   anthropic/claude-opus-4.8        5.00   25.00  1,000,000  yes     no      ctx 200,000  (5x low)
--   google/gemini-3.8-flash          0.75    3.75  1,048,576  yes     YES     ABSENT
--   google/gemini-3.5-flash          1.50    9.00  1,048,576  yes     yes     correct
--   google/gemini-3.1-flash-lite     0.25    1.50  1,048,576  yes     YES     correct
--   openai/gpt-6-luna                0.10    0.50  1,050,000  yes     no      ABSENT
--
-- A context_len 5x below the truth is not cosmetic: it is the number any future "will this prompt
-- fit" decision would read, and quote_comparison sends every quotation on one request.
--
-- AUDIO WAS VERIFIED, NOT ASSUMED. speech_transcription keeps google/gemini-3.1-flash-lite
-- primary and google/gemini-3.5-flash fallback because the live catalogue lists "audio" in
-- input_modalities for both (and for gemini-3.8-flash); no anthropic/ or openai/ row in this
-- fleet does. The capability branch in fn_ai_route would refuse the call otherwise, which is the
-- correct behaviour and not one to lean on.
--
-- CACHE COLUMNS ARE LEFT ALONE ON THE GOOGLE ROWS, DELIBERATELY. The live catalogue prices an
-- implicit cache read for the gemini models, but supports_cache in this table is read by
-- ai_gateway to decide whether to send Anthropic-style cache_control blocks, which Google does not
-- take. Setting supports_cache true from a price would break a working call to record a saving.
-- gemini-3.8-flash is therefore inserted with supports_cache false and its cache prices recorded
-- in the note rather than in columns that would change behaviour.
--
-- ─── 3. WHAT THIS FILE DOES NOT DO ──────────────────────────────────────────────────────────────
--
-- It does not retire anthropic/claude-fable-5.1, openai/gpt-6-astra or openai/gpt-5.6-luna. They
-- were the founder's own ruling of 9 Sep 2026 for the CEO, Sales Engineer and accountant seats,
-- superseded by his ruling of 23 Sep 2026 (reasoning quality first, cost second) in
-- every_seat_gets_the_model_its_own_work_needs.sql. model_policy_by_identity still carries 120
-- rows naming some of them as role defaults, so the rows stay, active and approved, with a health
-- row each — held, priced correctly, and no longer chosen by any active policy.

begin;

-- ── model_registry: the three absent models ────────────────────────────────────────────────────
insert into public.model_registry
  (model_id, provider, tier, in_per_mtok_usd, out_per_mtok_usd,
   cache_read_per_mtok_usd, cache_write_per_mtok_usd, supports_cache, supports_streaming,
   context_len, approved, active, quality_score, supports_vision, supports_audio, supports_tools, note)
values
  ('anthropic/claude-opus-5.5', 'anthropic', 'xlarge', 4.00, 20.00,
   0.20, 5.00, true, true, 1000000, true, true, 1.0000, true, false, true,
   'Founder''s ruling 23 Sep 2026: the reasoning model for every judgement the company makes — CEO '
   || 'approvals and strategy, the customer''s top-3 quote comparison, the signed-in portal '
   || 'assistant, and anything touching money. Live 23 Sep 2026: $4.00/$20.00 per Mtok, 1M context, '
   || 'cache read $0.20 (20x cheaper than its own prompt price, so a stable system prefix pays for '
   || 'itself in five calls). Cheaper on BOTH axes than the anthropic/claude-fable-5.1 + '
   || 'openai/gpt-6-astra pair it replaces ($10/$50 each) while being the stronger reasoner: this '
   || 'is not a cost trade, it is the better model at 2.5x less.'),

  ('google/gemini-3.8-flash', 'google', 'medium', 0.75, 3.75,
   null, null, false, true, 1048576, true, true, 0.9500, true, true, true,
   'Founder''s ruling 23 Sep 2026: the eyes of the estate — document extraction, drawing reading, '
   || 'catalogue ingest, email triage. Live 23 Sep 2026: $0.75/$3.75 per Mtok, 1,048,576 context, '
   || 'input modalities text+image+video+file+AUDIO. Half the price of google/gemini-3.5-flash on '
   || 'both axes and the same context, so it replaces it as the medium default and becomes the '
   || 'cheapest medium row — which is also fn_ai_route''s degrade target for the large tier and its '
   || 'confidence>=0.95 downgrade target. supports_cache is FALSE on purpose: the catalogue prices '
   || 'an implicit cache read at $0.075/Mtok, but this column makes ai_gateway send Anthropic-style '
   || 'cache_control blocks, which Google does not accept.'),

  ('openai/gpt-6-luna', 'openai', 'small', 0.10, 0.50,
   null, null, false, true, 1050000, true, true, 0.8000, true, false, true,
   'Live 23 Sep 2026: $0.10/$0.50 per Mtok, 1,050,000 context — the cheapest row in this fleet on '
   || 'both axes, half of openai/gpt-5.6-luna. Named only as the FALLBACK for intent_detection and '
   || 'email_triage, where the answer is one label out of a known set and a wrong one is retried by '
   || 'code, never sent. It therefore becomes the answer to every "cheapest active+approved small" '
   || 'query in fn_ai_route (degrade-one-tier, substitution, capability ordering) — which is the '
   || 'intent: a degraded route should be cheap, not merely cheaper. NO AUDIO, so the capability '
   || 'branch routes transcription past it.')
on conflict (model_id) do update set
  provider = excluded.provider, tier = excluded.tier,
  in_per_mtok_usd = excluded.in_per_mtok_usd, out_per_mtok_usd = excluded.out_per_mtok_usd,
  context_len = excluded.context_len, approved = excluded.approved, active = excluded.active,
  supports_vision = excluded.supports_vision, supports_audio = excluded.supports_audio,
  supports_tools = excluded.supports_tools, note = excluded.note, updated_at = now();

-- ── model_registry: the stale context lengths and prices on the rows the seats keep running ────
-- Read live 23 Sep 2026. Only context_len and the two per-token prices are touched; the cache
-- columns and supports_cache stay as they are for the reason in the header.
update public.model_registry set context_len = 1000000, in_per_mtok_usd = 2.00,
       out_per_mtok_usd = 10.00, cache_read_per_mtok_usd = 0.20, cache_write_per_mtok_usd = 2.50,
       updated_at = now()
 where model_id = 'anthropic/claude-sonnet-5';

update public.model_registry set context_len = 1000000, in_per_mtok_usd = 5.00,
       out_per_mtok_usd = 25.00, cache_read_per_mtok_usd = 0.50, cache_write_per_mtok_usd = 6.25,
       updated_at = now()
 where model_id = 'anthropic/claude-opus-4.8';

update public.model_registry set context_len = 200000, in_per_mtok_usd = 1.00,
       out_per_mtok_usd = 5.00, cache_read_per_mtok_usd = 0.10, cache_write_per_mtok_usd = 1.25,
       updated_at = now()
 where model_id = '~anthropic/claude-haiku-latest';

update public.model_registry set context_len = 1048576, in_per_mtok_usd = 1.50,
       out_per_mtok_usd = 9.00, updated_at = now()
 where model_id = 'google/gemini-3.5-flash';

update public.model_registry set context_len = 1048576, in_per_mtok_usd = 0.25,
       out_per_mtok_usd = 1.50, updated_at = now()
 where model_id = 'google/gemini-3.1-flash-lite';

update public.model_registry set context_len = 1000000, in_per_mtok_usd = 10.00,
       out_per_mtok_usd = 50.00, updated_at = now()
 where model_id = 'anthropic/claude-fable-5.1';

update public.model_registry set context_len = 1050000, in_per_mtok_usd = 10.00,
       out_per_mtok_usd = 50.00, updated_at = now()
 where model_id = 'openai/gpt-6-astra';

update public.model_registry set context_len = 1050000, in_per_mtok_usd = 0.20,
       out_per_mtok_usd = 1.20, updated_at = now()
 where model_id = 'openai/gpt-5.6-luna';

-- ── llm_route_health: a breaker row for every registry model, HELD exactly as the others are ──
-- open_until is COPIED from the rows already in the table, never typed, so this cannot lift or
-- shorten the founder's hold by a typo. If the table were somehow empty the coalesce would leave
-- the new rows open — and the check below refuses that state, so it cannot pass unnoticed.
insert into public.llm_route_health
  (model_id, consecutive_failures, failure_threshold, cooldown_seconds, open_until, opened_reason)
select r.model_id, 0, 3, 300,
       (select max(h.open_until) from public.llm_route_health h),
       'held with the rest of the fleet: added to llm_route_health 23 Sep 2026 because '
       || 'fn_llm_preflight used to answer allowed=true for a registered model with no row here, '
       || 'so the founder''s hold did not reach it'
  from public.model_registry r
 where not exists (select 1 from public.llm_route_health h where h.model_id = r.model_id)
on conflict (model_id) do nothing;

-- ── fn_llm_preflight: FAIL CLOSED when there is no health row to read ──────────────────────────
-- CREATE OR REPLACE, so the existing ACL is preserved (a DROP + CREATE would grant EXECUTE to
-- PUBLIC again). search_path stays pinned. The only change is the new branch, third from the top:
-- a registered model with no llm_route_health row is REFUSED with its own class_key, so the log
-- says which of the two reasons stopped it.
create or replace function public.fn_llm_preflight(p_model text)
 returns jsonb
 language sql
 stable security definer
 set search_path to 'public'
as $function$
  select case
    when p_model is null or p_model in ('none','none/deterministic')
      then jsonb_build_object('allowed', true, 'reason', 'deterministic path, no provider call')
    when not exists (select 1 from model_registry r where r.model_id = p_model and r.active)
      then jsonb_build_object('allowed', false, 'class_key', 'route_not_registered',
             'reason', 'model ' || p_model || ' is not an active row in model_registry')
    -- NO HEALTH ROW IS NOT HEALTH. Before 23 Sep 2026 this fell through to the `else` and answered
    -- allowed=true, so the hold was bypassable on anthropic/claude-fable-5.1, openai/gpt-6-astra
    -- and openai/gpt-5.6-luna — the three most expensive routes in the fleet — purely because they
    -- were added after the hold rows were written. Absence of a measurement is not a pass.
    when not exists (select 1 from llm_route_health h where h.model_id = p_model)
      then jsonb_build_object('allowed', false, 'class_key', 'route_not_measured',
             'reason', 'model ' || p_model || ' has no llm_route_health row, so no breaker state '
                       || 'exists for it. Refusing: an unmeasured route is not a healthy one. Add '
                       || 'the row (see the_catalogue_names_every_model_the_seats_run_and_the_hold'
                       || '_covers_all_of_them.sql) before routing to it.')
    when exists (select 1 from llm_route_health h
                 where h.model_id = p_model and h.open_until is not null and h.open_until > now())
      then jsonb_build_object('allowed', false, 'class_key', 'route_open',
             'reason', 'circuit open until '
                       || (select h.open_until from llm_route_health h where h.model_id = p_model)
                       || ' after ' || (select h.consecutive_failures from llm_route_health h where h.model_id = p_model)
                       || ' consecutive failures (' || coalesce((select h.opened_class from llm_route_health h where h.model_id = p_model),'?') || ')',
             'open_until', (select h.open_until from llm_route_health h where h.model_id = p_model))
    else jsonb_build_object('allowed', true, 'reason', 'registered, breaker closed')
  end;
$function$;

revoke execute on function public.fn_llm_preflight(text) from public, anon, authenticated;

-- ── THE PROBE ──────────────────────────────────────────────────────────────────────────────────
-- It returns a verdict ROW: never `raise notice` (the management API discards NOTICE, so 35 files
-- once carried a verdict nobody could read) and never `raise exception` (it would roll back the
-- DDL above, proving and un-building in one file).
--
-- ZERO CANNOT TELL A DEAD GUARD FROM AN IDLE SYSTEM. After the inserts above, every active
-- registry row HAS a health row, so "count the registered models preflight lets through with no
-- health row" is vacuously 0 whether the fix works or not. So the probe MAKES the condition
-- occur: one ZZ DEMO registry row with no health row, which cannot reach a person or a provider
-- (nothing routes to it; it is not approved), asserted refused, then deleted and the deletion
-- asserted.
create temporary table probe_preflight (k text primary key, v text) on commit drop;

insert into public.model_registry
  (model_id, provider, tier, in_per_mtok_usd, out_per_mtok_usd, context_len, approved, active, note)
values ('zzdemo/probe-unmeasured-route', 'zzdemo', 'small', 0, 0, 1000, false, true,
        'Transient probe row, deleted in the same transaction by '
        || 'the_catalogue_names_every_model_the_seats_run_and_the_hold_covers_all_of_them.sql. '
        || 'approved=false so no fn_ai_route select can reach it.');

insert into probe_preflight
select 'allowed', coalesce(public.fn_llm_preflight('zzdemo/probe-unmeasured-route') ->> 'allowed', '(null)');
insert into probe_preflight
select 'class_key', coalesce(public.fn_llm_preflight('zzdemo/probe-unmeasured-route') ->> 'class_key', '(null)');

delete from public.model_registry where model_id = 'zzdemo/probe-unmeasured-route';

insert into probe_preflight
select 'left_behind', (select count(*) from public.model_registry where provider = 'zzdemo')::text;

with hold as (select max(open_until) o from public.llm_route_health),
gaps as (
  select count(*) n from (
    select model_primary m from public.model_policy where active and model_primary <> 'none'
    union select model_fallback from public.model_policy where active and coalesce(model_fallback,'none') <> 'none'
  ) z where not exists (select 1 from public.llm_route_health h where h.model_id = z.m)
),
unreg as (
  select count(*) n from (
    select model_primary m from public.model_policy where active and model_primary <> 'none'
  ) z where not exists (select 1 from public.model_registry r where r.model_id = z.m and r.active)
),
held as (
  -- every model the seats can route to must still be refused while the hold stands
  select count(*) n from public.model_registry r
   where r.active and (public.fn_llm_preflight(r.model_id) ->> 'allowed') = 'true'
)
select case
  when (select n from gaps)  > 0 then 'PROBE FAILED: ' || (select n from gaps)::text || ' active-policy model(s) still have no llm_route_health row'
  when (select n from unreg) > 0 then 'PROBE FAILED: ' || (select n from unreg)::text || ' active-policy primary model(s) are not an active model_registry row'
  when (select v from probe_preflight where k = 'allowed') <> 'false'
    then 'PROBE FAILED: fn_llm_preflight answered allowed=' || (select v from probe_preflight where k = 'allowed')
         || ' for a registered model with no llm_route_health row — the hold is still bypassable'
  when (select v from probe_preflight where k = 'class_key') <> 'route_not_measured'
    then 'PROBE FAILED: the refusal came back as class_key '
         || (select v from probe_preflight where k = 'class_key')
         || ', not route_not_measured — the reason a call was stopped must be readable in the log'
  when (select v from probe_preflight where k = 'left_behind') <> '0'
    then 'PROBE FAILED: the probe left ' || (select v from probe_preflight where k = 'left_behind')
         || ' zzdemo row(s) in model_registry'
  when (select n from held)  > 0 then 'PROBE FAILED: ' || (select n from held)::text || ' model(s) are ALLOWED — the hold was lifted, which this file must never do'
  when (select o from hold) < now() then 'PROBE FAILED: the hold has expired (' || (select o from hold)::text || ') — not this file''s business, but nothing below is held'
  else 'PROBE OK: every model named by an active policy is a registered, measured route; '
       || (select count(*) from public.model_registry where active)::text || ' active registry rows, '
       || (select count(*) from public.llm_route_health)::text || ' breaker rows, all held until '
       || (select o from hold)::text
  end as verdict;

commit;
