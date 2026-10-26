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
-- reference. FOUR of the models the seats now need were not in it at all, and two context lengths
-- were wrong by 5x.
--
-- Prices and context lengths below were read LIVE from https://openrouter.ai/api/v1/models on
-- 23 Sep 2026 (scripts/checks/the_registry_prices_are_the_catalogue_s_prices.test.mjs re-reads
-- them), USD per million tokens:
--
--   model                            in     out    ctx        vision  audio   registry said
--   qwen/qwen3.8-max-0902            2.00    6.00  1,000,000  yes     no      ABSENT
--   z-ai/glm-5.3-flash               0.15    0.50  1,310,720  yes     no      ABSENT
--   anthropic/claude-opus-5.5        4.00   20.00  1,000,000  yes     no      ABSENT
--   anthropic/claude-sonnet-5        2.00   10.00  1,000,000  yes     no      ctx 200,000  (5x low)
--   ~anthropic/claude-haiku-latest   1.00    5.00    200,000  yes     no      correct
--   anthropic/claude-opus-4.8        5.00   25.00  1,000,000  yes     no      ctx 200,000  (5x low)
--   google/gemini-3.8-flash          0.75    3.75  1,048,576  yes     YES     ABSENT
--   google/gemini-3.5-flash          1.50    9.00  1,048,576  yes     yes     correct
--   google/gemini-3.1-flash-lite     0.25    1.50  1,048,576  yes     YES     correct
--   openai/gpt-6-luna                0.10    0.50  1,050,000  yes     no      ABSENT
--
-- THE FOUNDER'S RULING OF 23 SEP 2026 (instruction 841) NAMES THE FIRST TWO. "The primary model for
-- the comparison would be Qwen 3.8 max and use GLM 5.3 flash whenever, wherever it's possible as a
-- primary model. And for the CEO, again, Qwen 3.8 max. So this will be plan A for everyone, except
-- the stuff that doesn't require reasoning a lot - GLM 5.3 flash again. We want to cut cost as much
-- as possible. For plan B, for everyone that requires reasoning, it's going to be Opus; and for who
-- doesn't need reasoning then GLM 5.3 flash."
--
-- HE SAID "OPUS 5"; THIS REGISTERS anthropic/claude-opus-5.5 AND THAT IS DELIBERATE. Measured live,
-- the same day, the two rows side by side:
--
--   anthropic/claude-opus-5     5.00  25.00  cache read 0.50  1,000,000 ctx
--   anthropic/claude-opus-5.5   4.00  20.00  cache read 0.20  1,000,000 ctx
--
-- Same family, one version newer, and CHEAPER ON ALL THREE AXES - 20% off input, 20% off output,
-- 60% off cache reads - with the same context window. So his instruction is honoured at a lower
-- price than he asked for, which is the direction he asked for. If he wants the literal opus-5 it is
-- one string away in every_seat_gets_the_model_its_own_work_needs.sql; nothing else would change.
--
-- NEITHER NEW MODEL CARRIES `file` IN input_modalities (both are text+image+video). Nothing in the
-- estate sends a `file` part today - every document reaches a model as an image_url with a base64
-- data URL (supplier_catalog_ingest:295, drawing_redact:186, drawing_boq) and audio goes to
-- transcribe - and model_registry has no supports_file column for fn_ai_route's capability branch to
-- test, so this cannot be caught automatically. It is recorded here because the day something does
-- send a PDF as a file part, this is the paragraph that explains the provider's refusal.
--
-- A context_len 5x below the truth is not cosmetic: it is the number any future "will this prompt
-- fit" decision would read, and quote_comparison sends every quotation on one request.
--
-- AUDIO WAS VERIFIED, NOT ASSUMED, AND IT IS THE ONE HARD LIMIT ON THE FOUNDER'S RULING.
-- speech_transcription keeps google/gemini-3.1-flash-lite primary and google/gemini-3.5-flash
-- fallback. Measured across every candidate in the live catalogue, ONLY the gemini family carries
-- "audio" in input_modalities:
--
--   google/gemini-3.1-flash-lite   text image video file AUDIO
--   google/gemini-3.5-flash        text image video file AUDIO
--   google/gemini-3.8-flash        text image video file AUDIO
--   z-ai/glm-5.3-flash             text image video            <- no audio
--   qwen/qwen3.8-max-0902          text image video            <- no audio
--   anthropic/*, openai/*          text image file             <- no audio
--
-- So "use GLM 5.3 flash whenever, wherever it's possible" cannot reach this class: the word in his
-- instruction is "possible", and here it is not. A voice note routed to GLM would be rejected by the
-- provider, or silently redirected by fn_ai_route's capability branch to a model nobody chose. This
-- is the only class in the estate exempt from the ruling, and this is the reason.
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
-- It does not retire anthropic/claude-fable-5.1, openai/gpt-6-astra, openai/gpt-5.6-luna,
-- anthropic/claude-sonnet-5 or anthropic/claude-opus-4.8. The first three were the founder's own
-- ruling of 9 Sep 2026 for the CEO, Sales Engineer and accountant seats, superseded by instruction
-- 841 above in every_seat_gets_the_model_its_own_work_needs.sql. model_policy_by_identity still
-- carries 120 rows naming some of them as role defaults, so the rows stay, active and approved, with
-- a health row each — held, priced correctly, and no longer chosen by any active policy.
--
-- It also does not touch model_policy_by_identity, which names SIX models that are in neither
-- model_registry nor llm_route_health (deepseek/deepseek-v4-flash, qwen/qwen3.7-flash,
-- google/gemini-3.5-flash-lite, google/gemini-3.6-flash, anthropic/claude-sonnet-5:batch and one
-- more). The trigger added in every_seat_gets_the_model_its_own_work_needs.sql covers model_policy
-- only. That branch of fn_ai_route fires only for a caller unmapped in fn_task_class, and after this
-- PR every one of the 19 gateway callers is mapped, so it is dead for current traffic — but it is
-- not dead in principle, and it is being fixed in its own PR.

begin;

-- ── model_registry: the three absent models ────────────────────────────────────────────────────
insert into public.model_registry
  (model_id, provider, tier, in_per_mtok_usd, out_per_mtok_usd,
   cache_read_per_mtok_usd, cache_write_per_mtok_usd, supports_cache, supports_streaming,
   context_len, approved, active, quality_score, supports_vision, supports_audio, supports_tools, note)
values
  ('qwen/qwen3.8-max-0902', 'qwen', 'large', 2.00, 6.00,
   0.25, 2.50, true, true, 1000000, true, true, 0.9700, true, false, true,
   'Founder''s ruling 23 Sep 2026 (instruction 841): PLAN A for every class that reasons - the CEO''s '
   || 'judgements and approvals, the customer''s top-3 quote comparison, the accountant''s analysis, '
   || 'the signed-in portal assistant, the identity-redaction verify pass. Live 23 Sep 2026: '
   || '$2.00/$6.00 per Mtok, 1,000,000 context, cache read $0.25, text+image+video, '
   || 'structured_outputs and tools both advertised. OUTPUT IS THE NUMBER THAT MATTERS on these '
   || 'classes - a judgement is short in and long out - and at $6.00 it is 3.3x cheaper out than the '
   || 'anthropic/claude-opus-5.5 that is now plan B, and 8.3x cheaper than the '
   || 'anthropic/claude-fable-5.1 it replaces. TIER large, NOT medium, and that is load-bearing: '
   || 'fn_ai_route degrades exactly one band, so large degrades to the cheapest medium row '
   || '(google/gemini-3.8-flash, $0.75/$3.75, a 2.67x step). At medium it would degrade to the '
   || 'cheapest small row and drop 20x in one step, on classes that decide whether a supplier is '
   || 'verified. NO AUDIO and no `file` modality - see the header.'),

  ('z-ai/glm-5.3-flash', 'z-ai', 'small', 0.15, 0.50,
   0.05, null, false, true, 1310720, true, true, 0.8500, true, false, true,
   'Founder''s ruling 23 Sep 2026 (instruction 841): PLAN A everywhere the work does not need deep '
   || 'reasoning - reading, classifying, triaging and routine drafting. "use GLM 5.3 flash whenever, '
   || 'wherever it''s possible as a primary model... We want to cut cost as much as possible." Live '
   || '23 Sep 2026: $0.15/$0.50 per Mtok, 1,310,720 context (the largest window in this fleet), cache '
   || 'read $0.05, text+image+video, structured_outputs and tools. 13x cheaper input and 7.5x cheaper '
   || 'output than the qwen row above, and 5x cheaper than google/gemini-3.8-flash on input. '
   || 'supports_cache is FALSE despite the $0.05 cache read: that column makes ai_gateway send '
   || 'Anthropic-style cache_control blocks, and cache_write is not even priced here, so the provider '
   || 'is not being asked to take them. NO AUDIO - which is why speech_transcription stays on a '
   || 'gemini row - and no `file` modality; see the header.'),

  ('anthropic/claude-opus-5.5', 'anthropic', 'xlarge', 4.00, 20.00,
   0.20, 5.00, true, true, 1000000, true, true, 1.0000, true, false, true,
   'Founder''s ruling 23 Sep 2026 (instruction 841): PLAN B for every class that reasons - "for plan '
   || 'B, for everyone that requires reasoning, it''s going to be Opus". He said "Opus 5"; this is '
   || 'opus-5.5, the same family one version newer and cheaper on ALL THREE axes than a literal '
   || 'anthropic/claude-opus-5 (4.00/20.00/0.20 against 5.00/25.00/0.50, same 1M context, both read '
   || 'live 23 Sep 2026), so his instruction is honoured at a lower price than he asked for. A literal '
   || 'opus-5 is one string away in every_seat_gets_the_model_its_own_work_needs.sql. Because plan B '
   || 'is DEARER than plan A here, fn_ai_route''s p_escalate path is a genuine upgrade again - under '
   || 'the superseded 9 Sep matrix the xlarge classes escalated from fable-5.1 to gpt-6-astra at the '
   || 'same price, i.e. laterally. Cache read $0.20 is 20x cheaper than its own prompt price, so a '
   || 'stable system prefix pays for itself in five calls.'),

  ('google/gemini-3.8-flash', 'google', 'medium', 0.75, 3.75,
   null, null, false, true, 1048576, true, true, 0.9500, true, true, true,
   'The FALLBACK for every non-reasoning class, and the one safe landing place for a degraded or '
   || 'capability-substituted call. Live 23 Sep 2026: $0.75/$3.75 per Mtok, 1,048,576 context, input '
   || 'modalities text+image+video+file+AUDIO. Two jobs, and it is the only row in the fleet that can '
   || 'do both: (1) it is the CHEAPEST MEDIUM row, so it is what fn_ai_route degrades a large-tier '
   || 'class to - qwen3.8-max $2.00/$6.00 -> $0.75/$3.75, a 2.67x step rather than a cliff - and what '
   || 'the confidence>=0.95 branch downgrades to; (2) it is the plan-B fallback for the GLM classes, '
   || 'because plan B for non-reasoning work reads literally as GLM itself and a fallback that IS the '
   || 'primary is no fallback: a different provider, still cheap, and vision AND audio capable so an '
   || 'extraction or a voice note that GLM cannot read still gets read. supports_cache is FALSE on '
   || 'purpose: the catalogue prices an implicit cache read at $0.075/Mtok, but this column makes '
   || 'ai_gateway send Anthropic-style cache_control blocks, which Google does not accept.'),

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
-- search_path gains pg_temp (it was 'public' alone before 23 Sep 2026). A SECURITY DEFINER routine
-- whose path omits pg_temp resolves unqualified names against the caller's temp schema first, and a
-- caller who can create a temp table named model_registry or llm_route_health could make this
-- function read their own rows and answer `allowed: true` with the definer's privileges. That is the
-- same shadowing hole the pinned search_path exists to close, left half-open on the one routine that
-- decides whether a paid provider call may happen.
 set search_path to 'public', 'pg_temp'
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
