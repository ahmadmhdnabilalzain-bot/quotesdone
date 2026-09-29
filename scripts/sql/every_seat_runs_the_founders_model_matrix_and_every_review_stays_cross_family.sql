-- EVERY SEAT RUNS THE FOUNDER'S MODEL MATRIX, AND EVERY REVIEW STAYS CROSS-FAMILY.
-- Seat: sales_engineer (started for its own routes, extended to every seat on the coordinator's instruction).
-- 29 Sep 2026. Founder_instruction 1056, which supersedes 1055 and the 23 Sep rulings 841/844/854 for routing:
--   CEO             HARD work (judgement, strategy, approvals, planning, executive reports, reviewing other seats)
--                   anthropic/claude-opus-5.5; EASY work google/gemini-3.8-flash; fallback openai/gpt-6-luna.
--   SALES ENGINEER  everything google/gemini-3.8-flash, EXCEPT the comparison report (quote_comparison) on
--                   anthropic/claude-opus-5.5; fallback openai/gpt-6-luna for all of it.
--   EVERY OTHER SEAT (customer_support, accountant, it_engineer, marketing, and unowned or shared classes)
--                   google/gemini-3.8-flash; fallback deepseek/deepseek-v4.1-flash.
--   speech stays on Gemini (only Gemini hears). A REVIEW runs on the author seat's plan-B family with a
--   fallback from a third family: sales engineer reviews gpt-6-luna -> opus-5.5, other seats' reviews
--   deepseek-v4.1-flash -> gpt-6-luna, the CEO's reviews of other seats opus-5.5 -> gpt-6-luna.
--
-- MEASURED BEFORE THIS FILE (production htdblwldjkcgjvmqkbeh, read-only, 29 Sep 2026):
--   * 85 model_policy rows; every judgement / customer-facing class on openai/gpt-5.6-sol -> opus-5.5, every
--     internal class on z-ai/glm-5.3-flash -> gemini-3.8-flash. identity_redaction_verify Sol -> gemini.
--   * think() (supabase/functions/_shared/think.ts), the engine every seat reasons through, bills a step to a
--     class chosen by WHAT the step is (routine_employee_reasoning, customer_communication, supplier_communication,
--     knowledge_validation), never by WHO asks - so a per-seat matrix could not be expressed at all. The seat
--     reaches ai_gateway as `agent` and fn_ai_route as p_agent_key, and nothing read it for a named class.
--   * The sales engineer's own functions route by fn_task_class onto SHARED classes: document_extraction
--     (quote_extract, doc_extract, license_extract, extract_text, supplier_catalog_ingest, drawing_boq,
--     drawing_redact), json_extraction (inquiry_parse, supplier_review), procurement_reasoning (inquiry_ai,
--     project_consultant, supplier_onboard), customer_communication (customer_api, messages_api),
--     agent_reasoning (inquiry_intake).
--   * deepseek/deepseek-v4.1-flash was in neither model_registry nor llm_route_health. Read live from
--     https://openrouter.ai/api/v1/models on 29 Sep 2026: USD 0.30 in / 1.20 out per Mtok, cache read 0.006,
--     context 1,048,576, input text+image, NO file, NO audio, response_format / structured_outputs / tools.
--   * review_pool: gpt-5.6-sol rank 1, opus-5.5 rank 2 (gemini rank 3, inactive). fn_ai_route_review_for tries
--     the class primary, then the pool, then the class fallback - so with Sol first a class's own fallback
--     was never reached while Sol was of another family.
--   * paid_route_exception drawing_boq_confirm pins google/gemini-3.8-flash (disabled).
--   * ai_cost_log holds no call with real tokens (the hold), so nothing below is measured spend.
--
-- WHAT THIS FILE CHANGES
--   1. Registers deepseek/deepseek-v4.1-flash and HOLDS it with the fleet (open_until read from the table).
--   2. review_pool = gpt-6-luna 1, opus-5.5 2, deepseek-v4.1-flash 3; gpt-5.6-sol leaves the rotation (kept in
--      the registry, unused). The pool is now DEPTH behind a class's own pair (3b).
--   3. fn_ai_route learns THE SEAT'S OWN ROUTE: a policy row named '<seat>__<class>' holds that seat's models for
--      <class>, taken when the caller names the seat (or an alias of it) as its agent, and never allowing fewer
--      tokens than the class. The CLASS the route returns (and ai_cost_log records) stays <class>: the response
--      cache, the confidence prior and every author proof key on it, and ai_cost_log.seat already says who asked.
--      The row travels as policy_class, which the review router reads (3b). Without such a row, a seat's PLAN B is
--      still its own: the fallback of its catch-all row in model_policy_by_identity replaces the class's (not for a
--      review, whose pair is chosen against its author, nor for a class with no fallback on purpose). And the
--      confidence-prior downgrade no longer touches 'xlarge' - now only the founder's named hard routes on Opus.
--      Two more changes, both found in review of this file: a capability
--      substitute is never an ':online' variant (google/gemini-3.8-flash:online is the only other active model
--      that hears, so speech would have fallen back to a web-grounded measurement engine billed per search), and
--      a model_id tie-break on the four cheapest-first lookups (gemini-3.8-flash and its :online variant are both
--      medium at USD 0.75, and the pick between them was left to the planner).
--   3b. fn_ai_route_review_for takes the pair from policy_class (a seat's own review row), and tries the review
--      class's OWN FALLBACK before the pool. It tried the pool first,
--      which was harmless while the pool was exactly the two judgement models; under 1056 a review names its
--      fallback on purpose (a third family), and pool-first skipped it whenever a pool model of another family
--      came earlier - measured on the CEO's self-check over a Gemini author: Opus instead of DeepSeek. Every
--      family rule is unchanged: nothing of an author's family is ever picked, and the last resorts are as they were.
--      Every pair is proved by scripts/sql/every_seat_runs_the_founders_model_matrix_probe.sql.
--   4. model_policy follows the matrix, class by class (the table in section 4 IS the matrix), with 7 new
--      classes: internal_judgement (think's own answer or decision, split out of routine_employee_reasoning so
--      the CEO's judgement can run on Opus while its planning steps run on Gemini), sales_engineer__document_
--      extraction / __json_extraction / __procurement_reasoning (the sales engineer's functions, as the brief asks),
--      and the two seat rows that change a primary or a review pair: ceo__internal_judgement (Opus),
--      sales_engineer__knowledge_validation and ceo__knowledge_validation.
--   5. fn_task_class moves the sales engineer's functions onto its own classes.
--   6. model_policy_by_identity (the catch-all for an unmapped call) follows the matrix; the CEO and
--      customer_support get a row (without one, an unmapped call took fn_routing_tier_model's cheapest-in-tier
--      pick, which can still be z-ai/glm-5.3-flash).
--   7. The disabled drawing_boq_confirm exception pins the class's new primary.
--   6b. The model-consumer register (it_model_consumer, fn_it_model_consumer_listed) follows the functions to
--      their new classes and knows think()'s classes, seat routes included - or every think() call and every
--      moved sales engineer function would be flagged an unlisted consumer the day the hold lifts.
--
-- WHAT IT DOES NOT CHANGE
--   * THE HOLD. llm_route_health.open_until is not touched except deepseek's new row, which copies the fleet's.
--     app_secrets is not read or written. No model is called; every route stays held.
--   * The measurement classes: marketing_geo_search (perplexity/sonar IS what is measured), marketing_geo_online
--     (the :online Gemini is what is measured), marketing_watch (video with its soundtrack: only Gemini watches
--     and hears, so it has no fallback, like speech_transcription), marketing_image (inactive), and every tier
--     'none' row.
--   * Registry rows of models no policy names any more (gpt-5.6-sol, glm-5.3-flash, qwen...): kept, priced, held.
--     glm-5.3-flash and qwen3.7-plus stay the router's hard-coded last-resort families for a review.
--   * department_budget: data only since founder_instruction 987; the matrix moves no ceiling.
--
-- NOT CALLED FROM A FILE PART: deepseek carries no `file` input. The four callers that send a PDF as a file part
-- (quote_extract, license_extract, drawing_boq, extract_text) are all the sales engineer's, whose fallback is
-- gpt-6-luna, which does carry `file` (catalogue, 29 Sep 2026). No class that falls back to deepseek is sent one.
--
-- Pending: scripts/sql/pending/every_seat_runs_the_founders_model_matrix_and_every_review_stays_cross_family.txt
-- Proved by: scripts/sql/every_seat_runs_the_founders_model_matrix_probe.sql (aborted transaction, PROBE OK)
-- Prevented by: scripts/checks/no_review_class_can_route_to_its_authors_family.test.mjs,
--   scripts/checks/the_registry_prices_are_the_catalogue_s_prices.test.mjs (deepseek's price and modalities),
--   supabase/functions/_shared/think.test.ts (internal_judgement).
-- Idempotent and without begin/commit: the probe replays it inside an aborted transaction before apply.

-- ── 1. DEEPSEEK, REGISTERED AND HELD ────────────────────────────────────────────────────────────────
insert into public.model_registry
  (model_id, provider, tier, in_per_mtok_usd, out_per_mtok_usd,
   cache_read_per_mtok_usd, cache_write_per_mtok_usd, supports_cache, supports_streaming,
   context_len, approved, active, quality_score, supports_vision, supports_audio, supports_tools, note)
values
  ('deepseek/deepseek-v4.1-flash', 'deepseek', 'small', 0.30, 1.20,
   0.006, null, false, true, 1048576, true, true, null, true, false, true,
   'Founder_instruction 1056 (29 Sep 2026): the FALLBACK for every seat but the CEO and the sales engineer, and '
   || 'the primary of the other seats'' reviews. Live 29 Sep 2026: $0.30/$1.20 per Mtok, cache read $0.006, '
   || '1,048,576 context, input text+image, NO file and NO audio, response_format/structured_outputs/tools. '
   || 'TIER small, deliberately: fn_ai_route''s confidence downgrade takes the cheapest MEDIUM row, and at $0.30 '
   || 'this would have become it. supports_cache false: that column makes ai_gateway send Anthropic-style '
   || 'cache_control blocks. quality_score null: not measured on this estate.')
on conflict (model_id) do update set
  provider = excluded.provider, tier = excluded.tier,
  in_per_mtok_usd = excluded.in_per_mtok_usd, out_per_mtok_usd = excluded.out_per_mtok_usd,
  cache_read_per_mtok_usd = excluded.cache_read_per_mtok_usd, context_len = excluded.context_len,
  approved = true, active = true, supports_vision = excluded.supports_vision,
  supports_audio = excluded.supports_audio, supports_tools = excluded.supports_tools,
  note = excluded.note, updated_at = now();

insert into public.llm_route_health
  (model_id, consecutive_failures, failure_threshold, cooldown_seconds, open_until, opened_reason)
select 'deepseek/deepseek-v4.1-flash', 0, 3, 300,
       (select max(h.open_until) from public.llm_route_health h),
       -- the founder's own hold wording, copied from a row that carries it: fn_it_run_is_held and fn_it_detect
       -- recognise the hold by that prefix
       coalesce((select h.opened_reason from public.llm_route_health h
                  where h.opened_reason like 'HELD BY THE FOUNDER%' order by h.model_id limit 1),
                'held with the rest of the fleet from the moment it was registered (founder_instruction 1056): '
                || 'opening the hold is the founder''s')
where not exists (select 1 from public.llm_route_health h where h.model_id = 'deepseek/deepseek-v4.1-flash');

-- ── 2. THE REVIEW POOL FOLLOWS THE MATRIX ───────────────────────────────────────────────────────────
insert into public.review_pool (model_id, rank, active, note) values
  ('openai/gpt-6-luna', 1, true,
   'Founder_instruction 1056: plan B of the CEO and the sales engineer, and the primary of the sales engineer''s '
   || 'reviews. First in the pool so a review whose author wrote on Gemini falls back to it, as the matrix says.'),
  ('anthropic/claude-opus-5.5', 2, true,
   'Founder_instruction 1056: the CEO''s hard work and the comparison report. Reviews every author on Gemini, '
   || 'DeepSeek or luna.'),
  ('deepseek/deepseek-v4.1-flash', 3, true,
   'Founder_instruction 1056: plan B of every other seat and the primary of their reviews. Last in the pool: the '
   || 'depth behind a review whose author fell back to luna (the redaction verify must always have a fallback).')
on conflict (model_id) do update set rank = excluded.rank, active = true, note = excluded.note;

update public.review_pool
   set active = false, rank = 5,
       note = 'Out of rotation 29 Sep 2026 (founder_instruction 1056): no seat''s matrix names gpt-5.6-sol. Kept, '
              || 'registered and held; re-activate only if a ruling names it again. Before: ' || coalesce(note, '')
 where model_id = 'openai/gpt-5.6-sol' and active;

update public.review_pool set rank = 4 where model_id = 'google/gemini-3.8-flash' and rank <> 4;

-- ── 3. THE SEAT'S OWN ROUTE: fn_ai_route ────────────────────────────────────────────────────────────
-- Body read from its canonical file, model_calls_are_never_halted_by_a_department_or_pair_budget.sql (the same
-- text production returns from pg_get_functiondef, 29 Sep 2026). Every change is marked 1056: the seat-route block
-- after the routing-tier swap and its token floor, no ':online' capability substitute, and `, model_id` as a
-- tie-break on the four cheapest-first lookups.
-- CREATE OR REPLACE keeps the routine's ACL, so no revoke here.
CREATE OR REPLACE FUNCTION public.fn_ai_route(p_task_class text DEFAULT NULL::text, p_dept_key text DEFAULT NULL::text, p_confidence numeric DEFAULT NULL::numeric, p_fn text DEFAULT NULL::text, p_escalate boolean DEFAULT false, p_require_caps text[] DEFAULT NULL::text[], p_agent_key text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_class   text;
  v_src     text;
  v_pol     model_policy%rowtype;
  v_reg     model_registry%rowtype;
  v_fb      model_registry%rowtype;
  v_bud     department_budget%rowtype;
  v_pct     numeric := 0;
  v_model   text;
  v_why     text;
  v_min     numeric;
  v_tier    text;
  v_vis     boolean := 'vision' = any(coalesce(p_require_caps, '{}'::text[]));
  v_aud     boolean := 'audio'  = any(coalesce(p_require_caps, '{}'::text[]));
  v_tls     boolean := 'tools'  = any(coalesce(p_require_caps, '{}'::text[]));
  v_sub     model_registry%rowtype;
  v_want    int;
  v_idp     model_policy_by_identity%rowtype;
  v_generic boolean := false;
  v_rt      jsonb;
  v_prior   jsonb;
  v_conf    numeric;
  v_rtier   text;
  v_canon   text;
  v_seat    text;
  v_split   text;
  v_route_base text;
  v_base_pol model_policy%rowtype;
  v_seat_fb text;
begin
  if p_task_class is not null and length(btrim(p_task_class)) > 0 then
    v_class := p_task_class; v_src := 'caller-supplied task_class';
  else
    select task_class into v_class from fn_task_class where fn = p_fn and active;
    if v_class is not null then
      v_src := 'classified from calling function "' || p_fn || '"';
    else
      v_class := 'general_drafting';
      v_generic := true;
      v_src := 'UNMAPPED function "' || coalesce(p_fn,'?') || '" - defaulted to general_drafting (medium). Add a fn_task_class row to route this properly.';
    end if;
  end if;

  -- THE PACK'S FOUR-ROLE TAXONOMY REACHES THE PATH IT WAS WRITTEN FOR (14 Aug 2026).
  --
  -- All 93 employees carry org_agents.routing_tier - director 36, operations_specialist 23,
  -- analyst_controller 21, reviewer_auditor 10 - and on the main employee path it was DEAD.
  -- fn_routing_tier_model below only fires when v_generic is true, i.e. when the calling function
  -- is unmapped; agent_brain IS mapped, to agent_reasoning, so every employee from a marketing
  -- copywriter to the CEO got the same blanket large tier.
  --
  -- Meanwhile model_policy carries routine_employee_reasoning at MEDIUM, and its own rationale
  -- says: "Pack: replaces the current blanket large-tier agent_reasoning. agent_reasoning is LIVE
  -- on anthropic/claude-sonnet-5 and agent_brain is ~93% of OpenRouter spend." It had ZERO callers.
  -- A policy written to replace something, that nothing points at, is a build order nobody wired.
  --
  -- This is a ROUTING decision taken from the role, not an override of task_class routing: the
  -- class is chosen by who is asking, then the policy for that class applies normally.
  --
  -- WHO STAYS ON LARGE, AND WHY. Only operations_specialist moves. reviewer_auditor stays large
  -- deliberately - all 24 Reviewer/Auditor rows in the pack name a large model, and a reviewer on
  -- the cheap model is a green check that means nothing. director and analyst_controller stay
  -- because their work is the consequential kind the large tier exists for.
  if v_class = 'agent_reasoning' and p_agent_key is not null then
    v_canon := coalesce(public.fn_org_agent_resolve(p_agent_key), p_agent_key);
    select a.routing_tier into v_rtier from org_agents a
     where a.agent_key = v_canon and a.active;
    if v_rtier = 'operations_specialist'
       and exists (select 1 from model_policy mp
                    where mp.task_class = 'routine_employee_reasoning' and mp.active) then
      v_class := 'routine_employee_reasoning';
      v_src := v_src || ' | routing_tier "operations_specialist" for "' || v_canon
                     || '" selected the routine employee class instead of the blanket large tier';
    end if;
  end if;

  -- THE SEAT'S OWN ROUTE (29 Sep 2026, sales_engineer; founder_instruction 1056).
  -- think() and every other shared engine bill a step to a class chosen by WHAT the step is
  -- (routine_employee_reasoning, customer_communication, ...). The founder's matrix routes by WHO asks:
  -- the CEO and the sales engineer fall back to openai/gpt-6-luna, every other seat to
  -- deepseek/deepseek-v4.1-flash, and the CEO's judgement runs on Opus. The seat is the caller's agent,
  -- resolved as the agent_reasoning block above resolves it (an alias of a seat is that seat).
  --   1. A policy row named '<seat>__<class>' is that seat's own route for <class>: its MODELS are taken, while
  --      the CLASS stays <class> - ai_cost_log, the response cache, the confidence prior and every author proof
  --      key on it, and ai_cost_log.seat already says who asked. The row travels as policy_class, which
  --      fn_ai_route_review_for reads for a review's pair.
  --   2. Otherwise the seat's PLAN B is its own for every class it calls: the fallback of its catch-all row in
  --      model_policy_by_identity replaces the class's, unless the class has no fallback on purpose (only Gemini
  --      hears) or is a review (its pair is chosen against its author's family).
  -- A '<seat>__<class>' row - reached through the seat, or named by fn_task_class for the seat's own function -
  -- never allows fewer tokens than <class> and keeps <class>'s cache rule.
  if p_agent_key is not null then
    v_seat := coalesce(v_canon, public.fn_org_agent_resolve(p_agent_key), p_agent_key);
    select mp.task_class into v_split from model_policy mp
     where mp.task_class = v_seat || '__' || v_class and mp.active;
    if v_split is not null then
      v_src := v_src || ' | seat "' || v_seat || '" routes "' || v_class || '" on its own policy row ' || v_split;
    end if;
  end if;

  select * into v_pol from model_policy where task_class = coalesce(v_split, v_class) and active;
  if not found then
    select * into v_pol from model_policy where task_class = 'general_drafting' and active;
    v_src := v_src || ' | no policy for "' || v_class || '", fell back to general_drafting';
    v_generic := true;
  end if;

  v_route_base := case when v_split is not null then v_class
                       when position('__' in v_pol.task_class) > 0 then split_part(v_pol.task_class, '__', 2) end;
  if v_route_base is not null then
    select * into v_base_pol from model_policy where task_class = v_route_base and active;
    if found then
      v_pol.max_tokens    := greatest(coalesce(v_pol.max_tokens, 0), coalesce(v_base_pol.max_tokens, 0));
      v_pol.cache_ttl_min := v_base_pol.cache_ttl_min;
    end if;
  end if;

  if v_split is null and not v_generic and v_seat is not null and v_pol.model_fallback is not null
     and cardinality(coalesce(v_pol.reviews_class, '{}')) = 0 then
    select i.fallback_model into v_seat_fb from model_policy_by_identity i
     where i.scope = 'current_agent' and i.identity_key = v_seat;
    if v_seat_fb is not null and v_seat_fb not in (v_pol.model_primary, v_pol.model_fallback) then
      v_src := v_src || ' | seat "' || v_seat || '" falls back to its own plan B ' || v_seat_fb
                     || ' instead of ' || v_pol.model_fallback;
      v_pol.model_fallback := v_seat_fb;
    end if;
  end if;

  -- THE ROLE DEFAULT. model_policy_by_identity carries 120 rows — 96 target employees and 24
  -- current production agents — and had NO reader in the database at all. The pack states its own
  -- precedence on every row: note = 'Role default only; task_class routing overrides it.' So it
  -- applies only where the caller would otherwise get the generic general_drafting fallback:
  -- either the named class has no policy, or the calling function is unmapped in fn_task_class.
  --
  -- v_generic exists because the first version of this branch was UNREACHABLE. It hung off
  -- `if not found` on the model_policy lookup, and an unmapped function has already had v_class
  -- rewritten to 'general_drafting' by then — which IS found. Measured: fn_ai_route(...,'ceo')
  -- returned identity_policy null. Same shape as the unreachable block in
  -- fn_kb_route_activation_blocked found earlier today: a branch guarded by a condition that
  -- cannot occur.
  --
  -- 23 of the 24 current_agent keys resolve to a real org_agents row; 'cat:*' covers the
  -- category desks.
  if v_generic and p_agent_key is not null then
    select * into v_idp from model_policy_by_identity
     where scope = 'current_agent'
       and (identity_key = p_agent_key
            or (identity_key = 'cat:*' and p_agent_key like 'cat:%'))
     order by (identity_key = p_agent_key) desc
     limit 1;
    if found and v_idp.primary_model is not null then
      v_pol.model_primary  := v_idp.primary_model;
      v_pol.model_fallback := coalesce(v_idp.fallback_model, v_pol.model_fallback);
      v_pol.max_tokens     := coalesce(v_idp.max_output_tokens, v_pol.max_tokens);
      v_src := v_src || ' | role default for "' || p_agent_key || '" applied from model_policy_by_identity';
    end if;
  end if;

  -- ---- ROUTING TIER, added 11 Aug 2026 ---------------------------------------------------------
  -- The pack's four-role taxonomy carried onto the 93 real employees as org_agents.routing_tier.
  -- Fires LAST and only if the pack had nothing to say about this specific agent, so an explicit
  -- current_agent row always wins. Resolves tier -> registry tier -> cheapest active approved model
  -- AT CALL TIME: no model id is stored anywhere, so this follows the fleet instead of going stale.
  -- Measured direction against the general_drafting default (haiku, 1.00 USD/Mtok in):
  -- operations_specialist 4x cheaper, analyst/director unchanged, reviewer_auditor 2x dearer and
  -- deliberately so - all 24 Reviewer/Auditor rows in the pack name sonnet-5, and a reviewer on the
  -- cheap model is a green check that means nothing.
  if v_generic and p_agent_key is not null and v_idp.identity_key is null then
    v_rt := public.fn_routing_tier_model(p_agent_key);
    if v_rt is not null and (v_rt->>'model') is not null then
      v_pol.model_primary := v_rt->>'model';
      v_pol.tier          := v_rt->>'registry_tier';
      v_src := v_src || ' | routing_tier "' || (v_rt->>'routing_tier') || '" for "' || p_agent_key
                     || '" resolved to ' || (v_rt->>'model') || ' (' || (v_rt->>'registry_tier') || ' tier)';
    end if;
  end if;
  -- ----------------------------------------------------------------------------------------------

  if v_pol.tier = 'none' then
    return jsonb_build_object(
      'use_llm', false, 'task_class', v_class, 'tier', 'none',
      'why', 'REFUSED. ' || coalesce(v_pol.deterministic_alternative, 'This is deterministic - use code.')
             || ' [' || v_src || ']',
      'deterministic_alternative', v_pol.deterministic_alternative);
  end if;

  v_tier  := v_pol.tier;
  v_model := v_pol.model_primary;
  v_why   := coalesce(v_pol.rationale, 'policy for ' || v_class) || ' [' || v_src || ']';

  if p_escalate then
    v_model := coalesce(v_pol.model_fallback, v_model);
    v_why   := v_why || ' | ESCALATED one tier after an unsatisfactory cheaper attempt';
  end if;

  select (value #>> '{}')::numeric into v_min from decision_policy where key = 'confidence_min';
  -- THE PRIOR, 11 Aug 2026. Both arms below are original and NEITHER HAS EVER FIRED, because
  -- p_confidence is the confidence of THIS call and no caller can know that before the call.
  -- Measured the day this was written: 7 of 1,746 model calls in seven days carried a confidence at
  -- all. The only confidence that CAN exist beforehand is the agent's own recent record on this
  -- task class, so that is what a caller supplying nothing now routes on.
  --
  -- fn_ai_confidence_prior returns null unless there are at least 5 observations AND they vary.
  -- The variance guard is the important half: the two callers that emitted a confidence before
  -- tonight always emitted exactly 1.0000, and a model reporting the same number every time would
  -- otherwise downgrade itself to a cheaper tier on the strength of its own unvarying optimism.
  v_conf := p_confidence;
  if v_conf is null and p_agent_key is not null then
    v_prior := public.fn_ai_confidence_prior(p_agent_key, v_class);
    if v_prior is not null then v_conf := (v_prior->>'prior')::numeric; end if;
  end if;

  if v_conf is not null then
    -- 1056: 'xlarge' is only the founder's named hard routes (the CEO's judgement, the comparison report, on
    -- Opus); a confidence prior never moves them. 'large' keeps the 11 Aug doctrine.
    if v_conf >= 0.95 and v_tier = 'large' then
      select model_id into v_model from model_registry
       where active and approved and tier = 'medium' order by in_per_mtok_usd, model_id limit 1;  -- model_id: 1056 tie-break
      v_why := v_why || ' | confidence ' || v_conf
               || case when v_prior is null then ''
                       else ' (' || p_agent_key || ' own median over ' || (v_prior->>'n')
                            || ' calls on ' || v_class || ', spread ' || (v_prior->>'spread') || ')' end
               || ' >= 0.95, downgraded to medium - no second opinion needed';
    elsif v_min is not null and v_conf < v_min and v_tier = 'small' then
      v_model := coalesce(v_pol.model_fallback, v_model);
      v_why := v_why || ' | confidence ' || v_conf
               || case when v_prior is null then ''
                       else ' (' || p_agent_key || ' own median over ' || (v_prior->>'n') || ' calls)' end
               || ' below floor ' || v_min || ', escalated a tier';
    end if;
  end if;

  -- (Historical, 13 Aug 2026: the halt that used to follow needed a department.) A CALL WITH NO DEPARTMENT: the lookup below needs a
  -- dept_key to find a budget, and 59 of this month's calls arrived without one - inquiry_intake,
  -- drawing_boq, doc_extract, license_extract, supplier_onboard and eleven more, i.e. the demand
  -- path. fn_task_class already maps fn -> task_class for this same function's model choice; it now
  -- carries the owning department too, so an un-attributed call is attributed by what it IS rather
  -- than left outside every ceiling. An explicit p_dept_key from the caller still wins.
  -- CANONICAL BEFORE THE CEILING (14 Aug 2026). department_budget holds the ten canonical rows;
  -- a caller passing a merged-away key ('procurement', 'marketing', 'sales' ...) found NO budget
  -- row and skipped the ceiling entirely. fn_dept_canonical resolves the key the caller used to
  -- the department that actually owns it.
  if public.fn_dept_canonical(coalesce(p_dept_key, (select t.dept_key from fn_task_class t where t.fn = p_fn and t.active))) is not null then
    select * into v_bud from department_budget
     where dept_key = public.fn_dept_canonical(coalesce(p_dept_key, (select t.dept_key from fn_task_class t where t.fn = p_fn and t.active)));
    if found and v_bud.monthly_aed > 0 then
      v_pct := round(100 * coalesce(
        (select sum(cost_aed) from ai_cost_log
          where dept_key = any(public.fn_dept_scope(v_bud.dept_key))
            and occurred_at >= date_trunc('month', now())), 0)
        / v_bud.monthly_aed, 2);
      -- NO HALT AND NO DEGRADE (24 Sep 2026, founder_instruction 987: no caps on LLM spend). v_pct is still
      -- reported as budget_pct so the books can see a department's spend; it no longer refuses or downgrades a call.
    end if;
  end if;

  select * into v_reg from model_registry where model_id = v_model and active;
  if not found then
    select * into v_reg from model_registry
     where active and approved and tier = (case v_tier when 'xlarge' then 'xlarge' else v_tier end)
     order by in_per_mtok_usd, model_id limit 1;  -- model_id: 1056 tie-break
    v_why := v_why || ' | WARNING: policy model "' || v_model || '" is not in model_registry; substituted ' || coalesce(v_reg.model_id,'(none)');
    v_model := v_reg.model_id;
  end if;

  -- CAPABILITY. Price and tier chose the model above; if it cannot see, hear or call tools the
  -- provider will simply reject the payload. Substitute the nearest capable model, preferring the
  -- intended tier, then the closest tier ABOVE it, and only then below - a capability substitution
  -- must never quietly become a quality downgrade.
  v_want := fn_ai_route_tier_rank(v_tier);
  if (v_vis or v_aud or v_tls)
     and not ( (not v_vis or coalesce(v_reg.supports_vision,false))
           and (not v_aud or coalesce(v_reg.supports_audio, false))
           and (not v_tls or coalesce(v_reg.supports_tools, false)) ) then

    select * into v_sub from model_registry
     where active and approved and model_id not like '%:online'      -- 1056: never a web-grounded variant
       and (not v_vis or supports_vision) and (not v_aud or supports_audio) and (not v_tls or supports_tools)
     order by (fn_ai_route_tier_rank(tier) < v_want),                 -- at-or-above the tier first
              abs(fn_ai_route_tier_rank(tier) - v_want),              -- then closest to it
              in_per_mtok_usd, model_id                                -- then cheapest (model_id: 1056 tie-break)
     limit 1;

    if found then
      v_why := v_why || ' | CAPABILITY OVERRIDE: ' || v_model || ' cannot do ('
               || array_to_string(coalesce(p_require_caps,'{}'::text[]), '+') || '); substituted ' || v_sub.model_id
               || ' (' || v_sub.tier || ' tier, intended ' || v_tier || ')';
      v_reg := v_sub; v_model := v_sub.model_id;
    else
      return jsonb_build_object(
        'use_llm', false, 'task_class', v_class, 'tier', v_tier, 'caps', to_jsonb(p_require_caps),
        'why', 'REFUSED. No active approved model in model_registry supports ('
               || array_to_string(coalesce(p_require_caps,'{}'::text[]), '+')
               || '). Add one, or mark the capability on an existing model.');
    end if;
  end if;

  select * into v_fb from model_registry
   where model_id = v_pol.model_fallback and active
     and (not v_vis or supports_vision) and (not v_aud or supports_audio) and (not v_tls or supports_tools);
  if not found and (v_vis or v_aud or v_tls) then
    select * into v_fb from model_registry
     where active and approved and model_id <> v_model and model_id not like '%:online'   -- 1056
       and (not v_vis or supports_vision) and (not v_aud or supports_audio) and (not v_tls or supports_tools)
     order by (fn_ai_route_tier_rank(tier) < v_want), abs(fn_ai_route_tier_rank(tier) - v_want), in_per_mtok_usd, model_id
     limit 1;
  end if;

  return jsonb_build_object(
    'use_llm', true,
    'task_class', v_class,
    'policy_class', v_pol.task_class,   -- 1056: the policy row the models came from (a seat's own, or the class's)
    'tier', v_tier,
    'model', v_model,
    'fallback', v_fb.model_id,
    'max_tokens', v_pol.max_tokens,
    'cache_ttl_min', coalesce(v_pol.cache_ttl_min, 0),
    'cache', coalesce(v_reg.supports_cache, false),
    'stream', coalesce(v_reg.supports_streaming, true),
    'caps', to_jsonb(coalesce(p_require_caps, '{}'::text[])),
    'in_per_mtok_usd', v_reg.in_per_mtok_usd,
    'out_per_mtok_usd', v_reg.out_per_mtok_usd,
    'cache_read_per_mtok_usd', v_reg.cache_read_per_mtok_usd,
    'budget_pct', v_pct,
    'identity_policy', case when v_idp.identity_key is null then null else jsonb_build_object(
        'identity_key', v_idp.identity_key, 'deterministic_first', v_idp.deterministic_first,
        'reasoning_effort', v_idp.reasoning_effort, 'authority_tier', v_idp.authority_tier) end,
    'routing_tier', v_rt,
    'confidence_prior', v_prior,
    'confidence_used', v_conf,
    'why', v_why);
end $function$;

-- ── 3b. THE REVIEW ROUTER TRIES A CLASS'S OWN FALLBACK BEFORE THE POOL ──────────────────────────────
-- Body read from its canonical file, a_review_is_held_rather_than_skipped_and_its_authors_are_the_rows_it_judges.sql.
-- One change, marked 1056: the candidate order. CREATE OR REPLACE keeps the routine's ACL, so no revoke here.
create or replace function public.fn_ai_route_review_for(p_task_class text, p_counterpart_model text,
  p_agent_key text default null, p_fn text default null, p_dept_key text default null, p_require_caps text[] default null)
returns jsonb language plpgsql stable security definer set search_path to 'public', 'pg_temp' as $fn$
declare
  v_names text[]; v_fams text[] := '{}'; v_unknown text[] := '{}'; v_n text; v_f text; v_cp text;
  v_base jsonb; v_rej jsonb := '[]'::jsonb;
  v_pick text; v_pick_fam text; v_fb text; v_tier text;
  v_vis boolean := 'vision' = any (coalesce(p_require_caps, '{}'));
  v_aud boolean := 'audio'  = any (coalesce(p_require_caps, '{}'));
  v_tls boolean := 'tools'  = any (coalesce(p_require_caps, '{}'));
  c record;
begin
  select coalesce(array_agg(distinct btrim(x) order by btrim(x)) filter (where btrim(x) <> ''), '{}') into v_names
    from unnest(string_to_array(coalesce(p_counterpart_model, ''), ',')) x;
  v_cp := array_to_string(v_names, ',');
  foreach v_n in array v_names loop
    continue when v_n = 'deterministic';
    select lower(btrim(r.provider)) into v_f from public.model_registry r where r.model_id = v_n;
    if v_f is null then v_unknown := v_unknown || v_n; else v_fams := array(select distinct unnest(v_fams || v_f)); end if;
  end loop;

  if cardinality(v_names) = 0 or cardinality(v_unknown) > 0 then
    return jsonb_build_object('use_llm', false, 'no_independent_reviewer', true, 'unknown_author', true,
      'task_class', p_task_class, 'author_model', v_cp,
      'why', 'AUTHOR UNKNOWN: ' || coalesce(nullif(array_to_string(v_unknown, ', '), ''), '(none given)')
             || ' is not in model_registry, so its family is unknown and independence cannot be proved. A data defect in '
             || 'what the caller recorded about the author, not a missing reviewer.');
  end if;

  v_base := public.fn_ai_route(p_task_class, p_dept_key, null, p_fn, false, p_require_caps, p_agent_key);
  if not coalesce((v_base->>'use_llm')::boolean, false) then
    return v_base || jsonb_build_object('author_model', v_cp, 'author_family', to_jsonb(v_fams));
  end if;
  if cardinality(v_fams) = 0 then
    return v_base || jsonb_build_object('author_model', 'deterministic', 'author_family', '[]'::jsonb, 'independent', true,
      'reviewer_tier', 'standard', 'why', coalesce(v_base->>'why', '') || ' | INDEPENDENT REVIEW: the author is deterministic code, not a model');
  end if;

  for c in
    -- 1056: the pair of the seat's own row for this review class when the seat has one ('<seat>__<class>'),
    -- otherwise the class's own - never the general_drafting row a missing class falls back to
    with pol as (select model_primary, model_fallback from public.model_policy
                  where task_class = case when right(coalesce(v_base->>'policy_class', ''), length(v_base->>'task_class') + 2)
                                                = '__' || (v_base->>'task_class')
                                          then v_base->>'policy_class' else v_base->>'task_class' end),
    cand as (
      -- 1056: the class's own pair first (primary, then its named fallback), then the pool as depth
      select pol.model_primary model_id, 0 ord from pol
      union all select pol.model_fallback, 1 from pol
      union all select p.model_id, 10 + p.rank from public.review_pool p where p.active
      union all select 'google/gemini-3.8-flash', 2000000
      union all select 'z-ai/glm-5.3-flash', 2000001
      union all select 'qwen/qwen3.7-plus', 2000002)
    select d.model_id, d.ord, lower(btrim(r.provider)) provider, coalesce(r.active and r.approved, false) reg_ok,
           (not v_vis or coalesce(r.supports_vision, false)) and (not v_aud or coalesce(r.supports_audio, false))
             and (not v_tls or coalesce(r.supports_tools, false)) caps_ok,
           h.model_id is not null measured,
           coalesce(h.open_until > now() and h.opened_class is not null, false) tripped
      from (select model_id, min(ord) ord from cand where model_id is not null and model_id <> 'none' group by model_id) d
      left join public.model_registry r on r.model_id = d.model_id
      left join public.llm_route_health h on h.model_id = d.model_id
     order by d.ord, d.model_id
  loop
    if c.provider is null then
      v_rej := v_rej || jsonb_build_object('model', c.model_id, 'why', 'not in model_registry');
    elsif c.provider = any (v_fams) then
      v_rej := v_rej || jsonb_build_object('model', c.model_id, 'why', 'same family as an author (' || c.provider || ')');
    elsif not c.reg_ok then
      v_rej := v_rej || jsonb_build_object('model', c.model_id, 'why', 'inactive or unapproved in model_registry');
    elsif not c.caps_ok then
      v_rej := v_rej || jsonb_build_object('model', c.model_id, 'why', 'lacks a required capability (' || array_to_string(p_require_caps, '+') || ')');
    elsif not c.measured then
      v_rej := v_rej || jsonb_build_object('model', c.model_id, 'why', 'no llm_route_health row: unmeasured is not healthy');
    elsif c.tripped then
      v_rej := v_rej || jsonb_build_object('model', c.model_id, 'why', 'breaker tripped by real failures');
    elsif v_pick is null then
      v_pick := c.model_id; v_pick_fam := c.provider;
      v_tier := case when c.ord >= 2000000 then 'third_family_fallback' else 'standard' end;
    elsif v_fb is null and (c.ord < 2000000 or v_tier = 'third_family_fallback') then
      v_fb := c.model_id;
    end if;
  end loop;

  if v_pick is null then
    return jsonb_build_object('use_llm', false, 'no_independent_reviewer', true,
      'task_class', v_base->>'task_class', 'author_model', v_cp, 'author_family', to_jsonb(v_fams), 'pool_rejected', v_rej,
      'why', 'NO INDEPENDENT REVIEWER: no active, healthy, capable candidate outside the ' || array_to_string(v_fams, '/')
             || ' families, not even a last-resort family. The review is HELD, never run on an author''s family.');
  end if;

  return v_base || jsonb_build_object(
    'model', v_pick, 'fallback', v_fb,
    'in_per_mtok_usd', (select in_per_mtok_usd from public.model_registry where model_id = v_pick),
    'out_per_mtok_usd', (select out_per_mtok_usd from public.model_registry where model_id = v_pick),
    'reviewer_family', v_pick_fam, 'reviewer_tier', v_tier, 'author_model', v_cp, 'author_family', to_jsonb(v_fams),
    'independent', true, 'pool_rejected', v_rej,
    'why', coalesce(v_base->>'why', '') || ' | INDEPENDENT REVIEW: author wrote on ' || v_cp
           || ' (' || array_to_string(v_fams, '/') || '), reviewer routed to ' || v_pick || ' (' || v_pick_fam || ')'
           || coalesce(', fallback ' || v_fb, ', no fallback outside ' || array_to_string(v_fams, '/')));
end $fn$;

-- ── 4. THE MATRIX, CLASS BY CLASS ───────────────────────────────────────────────────────────────────
-- The routes (founder_instruction 1056). Tier is the primary model's registry tier.
--   se            google/gemini-3.8-flash      -> openai/gpt-6-luna             sales engineer
--   se_compare    anthropic/claude-opus-5.5    -> openai/gpt-6-luna             the comparison report
--   se_review     openai/gpt-6-luna            -> anthropic/claude-opus-5.5     a sales engineer review
--   ceo_hard      anthropic/claude-opus-5.5    -> openai/gpt-6-luna             CEO judgement, and its reviews of other seats
--   ceo_easy      google/gemini-3.8-flash      -> openai/gpt-6-luna             CEO routine work (any shared class, section 3)
--   ceo_review    openai/gpt-6-luna            -> deepseek/deepseek-v4.1-flash  the CEO checking its own answer
--   other         google/gemini-3.8-flash      -> deepseek/deepseek-v4.1-flash  every other seat, unowned and shared classes
--   other_review  deepseek/deepseek-v4.1-flash -> openai/gpt-6-luna             another seat's review
--   hears         google/gemini-3.8-flash      -> none                          audio (and video with sound): only Gemini hears
-- A shared class a CEO or sales engineer call reaches keeps its Gemini primary and takes the seat's plan B (luna)
-- from the seat's catch-all row (section 3), so it needs no row of its own. A '<seat>__<class>' row exists only
-- where the seat's PRIMARY differs (the CEO's judgement on Opus), where it is a review whose pair depends on the
-- author, or where the brief gives the seat's own functions their own class.
-- ceo_review follows the founder's review rule, not "CEO reviews of other seats": the CEO verifying the CEO's own
-- answer reviews an author whose primary is Opus (hard) or Gemini (easy), so it runs on the CEO's plan-B family,
-- luna, with DeepSeek as the third family.

-- 4a. The new classes. max_tokens and cache_ttl_min start as the base class's (and fn_ai_route keeps a seat's row
--     at the class's ceiling and cache rule), so no caller is clamped by the move. A seat's row for a REVIEW class
--     carries reviews_class, so the probe and the review checks walk its pair.
insert into public.model_policy
  (task_class, tier, model_primary, model_fallback, max_tokens, rationale, deterministic_alternative, active, cache_ttl_min, reviews_class)
select n.task_class, r.tier, r.p, r.f, b.max_tokens,
       n.why || ' Route ' || n.route || ': ' || r.p || ' -> ' || coalesce(r.f, 'none')
       || ' (founder_instruction 1056, every_seat_runs_the_founders_model_matrix_and_every_review_stays_cross_family.sql).',
       b.deterministic_alternative, true, b.cache_ttl_min, n.reviews
  from (values
    ('internal_judgement', 'routine_employee_reasoning', 'other', null::text[],
     'think()''s synthesis of a seat''s OWN answer or decision (internal audience). Split out of routine_employee_reasoning on 29 Sep 2026 so a seat''s judgement and its planning steps can take different routes: the CEO''s judgement is hard work, its planning is not.'),
    ('sales_engineer__document_extraction', 'document_extraction', 'se', null,
     'The sales engineer reading a quotation, a document, a trade licence, a supplier catalogue or a drawing page to redact into fields (quote_extract, doc_extract, license_extract, extract_text, supplier_catalog_ingest, drawing_redact''s find).'),
    ('sales_engineer__json_extraction', 'json_extraction', 'se', null,
     'The sales engineer turning an inquiry or a supplier''s text into structured fields (inquiry_parse, supplier_review).'),
    ('sales_engineer__procurement_reasoning', 'procurement_reasoning', 'se', null,
     'The sales engineer reasoning about a trade, a scope or a supplier''s mandatory six (inquiry_ai, project_consultant, supplier_onboard).'),
    ('sales_engineer__knowledge_validation', 'knowledge_validation', 'se_review',
     array['internal_judgement','customer_communication','supplier_communication','routine_employee_reasoning'],
     'The independent check of a high-stakes sales engineer answer by another model family (think() verify). Its authors are the think() classes, on Gemini with the sales engineer''s luna behind.'),
    -- copies routine_employee_reasoning, as internal_judgement itself does: a row inserted by this same statement is
    -- not visible to its own join
    ('ceo__internal_judgement', 'routine_employee_reasoning', 'ceo_hard', null,
     'HARD: the CEO''s own answer or decision through think() - judgement, strategy, approvals, the founder''s reports.'),
    ('ceo__knowledge_validation', 'knowledge_validation', 'ceo_review',
     array['ceo__internal_judgement','customer_communication','supplier_communication','routine_employee_reasoning'],
     'The independent check of a high-stakes CEO answer (think() verify): the CEO''s plan-B family, a third family behind it.')
  ) as n(task_class, base, route, reviews, why)
  join (values
    ('se',         'medium', 'google/gemini-3.8-flash',      'openai/gpt-6-luna'),
    ('se_review',  'small',  'openai/gpt-6-luna',            'anthropic/claude-opus-5.5'),
    ('ceo_hard',   'xlarge', 'anthropic/claude-opus-5.5',    'openai/gpt-6-luna'),
    ('ceo_review', 'small',  'openai/gpt-6-luna',            'deepseek/deepseek-v4.1-flash'),
    ('other',      'medium', 'google/gemini-3.8-flash',      'deepseek/deepseek-v4.1-flash')
  ) as r(route, tier, p, f) on r.route = n.route
  join public.model_policy b on b.task_class = n.base
on conflict (task_class) do update set
  tier = excluded.tier, model_primary = excluded.model_primary, model_fallback = excluded.model_fallback,
  reviews_class = excluded.reviews_class, rationale = excluded.rationale, active = true;

-- 4b. Every existing class that calls a model. Primary and fallback move in ONE statement per row, so
--     trg_model_policy_names_a_known_route never sees a half-written pair. Idempotent: a row already on its
--     route is not touched, so a replay appends nothing.
update public.model_policy mp
   set tier = r.tier, model_primary = r.p, model_fallback = r.f,
       rationale = coalesce(mp.rationale, '') || ' | 29 Sep 2026 (founder_instruction 1056, every_seat_runs_the_founders_model_matrix_and_every_review_stays_cross_family.sql): '
                   || m.seat || ', route ' || m.route || ', ' || r.p || ' -> ' || coalesce(r.f, 'none') || '. ' || m.why
  from (values
    -- the sales engineer: both portals, inquiries, drawings and documents, specs, matching, quotes, the report
    ('quote_comparison',                   'sales_engineer', 'se_compare', 'The deep technical comparison of quotations: the ONE sales engineer class on Opus. It reviews the extraction (Gemini), so Opus is also another family.'),
    ('sales_engineer_reasoning',           'sales_engineer', 'se',         'Technical scope, supplier capability, what a line item requires.'),
    ('customer_portal_assistant',          'sales_engineer', 'se',         'The signed-in portal assistant, and now customer_api and messages_api (either portal is Sales).'),
    ('inquiry_qualification_conversation', 'sales_engineer', 'se',         'Inquiry intake, and now the inquiry_intake function.'),
    ('rfq_routing',                        'sales_engineer', 'se',         'Routing an inquiry to suppliers (route_inquiry).'),
    ('redaction_detection',                'sales_engineer', 'se',         'Drawing redaction detection. No caller today: drawing_redact''s find pass sends no class and routes by fn to sales_engineer__document_extraction (8000 tokens; this class allows 1200, the truncation its own comments record).'),
    ('drawing_and_boq_analysis',           'sales_engineer', 'se',         'Reading a drawing and its BoQ, and now the drawing_boq function.'),
    ('identity_redaction_verify',          'sales_engineer', 'se_review',  'Verifies the redaction find, which now runs on Gemini: luna, then Opus - neither is Gemini.'),
    ('drawing_boq_confirm',                'sales_engineer', 'se_review',  'Confirms the BoQ draft, which is Gemini''s or code''s: luna, then Opus.'),
    ('speech_transcription',               'sales_engineer', 'hears',      'Only Gemini carries audio (catalogue, 29 Sep 2026: luna and deepseek do not), so NO fallback: a failed call retries Gemini rather than landing on a model that cannot hear.'),
    -- the CEO: hard
    ('ceo_judgement',                      'ceo', 'ceo_hard', 'HARD: judging a seat''s plan on the record; reviews other seats (Gemini, DeepSeek or luna authors).'),
    ('ceo_approval_decision',              'ceo', 'ceo_hard', 'HARD: an approval on the record; reviews the accountant''s and the sales engineer''s output.'),
    ('ceo_strategic_planning',             'ceo', 'ceo_hard', 'HARD: strategy and capital allocation.'),
    ('chief_of_staff_decision',            'ceo', 'ceo_hard', 'HARD: arbitration between seats.'),
    ('executive_report',                   'ceo', 'ceo_hard', 'HARD: the report the founder acts on.'),
    ('department_planning',                'ceo', 'ceo_hard', 'HARD: planning (the founder names planning as hard). No caller today.'),
    ('seat_deliberation_blind',            'ceo', 'ceo_hard', 'HARD: the reviewing seat''s blind pass; every registered pair is reviewed by the CEO (marketing -> ceo, sales_engineer -> ceo).'),
    ('seat_deliberation_compare',          'ceo', 'ceo_hard', 'HARD: the reviewing seat''s comparison with the revealed proposal.'),
    -- every other seat, and every unowned or shared class
    ('accountant_expense_classification',  'accountant', 'other', ''),
    ('accountant_receipt_extraction',      'accountant', 'other', 'Images only reach DeepSeek: no accountant caller sends a file part.'),
    ('accountant_weekly_report',           'accountant', 'other', ''),
    ('finance_analysis',                   'accountant', 'other', ''),
    ('customer_communication',             'customer_support (shared)', 'other', 'The sales engineer and the CEO take their own routes through sales_engineer__ / ceo__ rows.'),
    ('supplier_communication',             'customer_support (shared)', 'other', 'The sales engineer and the CEO take their own routes through sales_engineer__ / ceo__ rows.'),
    ('support_ai',                         'customer_support', 'other', ''),
    ('visitor_chat',                       'customer_support', 'other', ''),
    ('wa_inbound',                         'customer_support', 'other', ''),
    ('email_triage',                       'customer_support', 'other', ''),
    ('inbound_email',                      'customer_support', 'other', ''),
    ('resend_inbound',                     'customer_support', 'other', ''),
    ('intent_detection',                   'customer_support', 'other', ''),
    ('engineering_reasoning',              'it_engineer', 'other', ''),
    ('reflection_and_learning',            'it_engineer', 'other', ''),
    ('security_incident_analysis',         'it_engineer', 'other', ''),
    ('edge_case_escalation',               'it_engineer', 'other', ''),
    ('health_ping',                        'it_engineer', 'other', ''),
    ('marketing_copy',                     'marketing', 'other', ''),
    ('marketing_evaluate',                 'marketing', 'other', ''),
    ('marketing_plan',                     'marketing', 'other', ''),
    ('marketing_plan_defend',              'marketing', 'other', ''),
    ('marketing_quality_review',           'marketing', 'other', ''),
    ('marketing_research',                 'marketing', 'other', ''),
    ('marketing_watch',                    'marketing', 'hears', 'The whole video with its soundtrack: only Gemini watches and hears, so no fallback.'),
    ('agent_reasoning',                    'unowned (shared)', 'other', ''),
    ('routine_employee_reasoning',         'unowned (shared)', 'other', 'The sales engineer and the CEO take their own routes through sales_engineer__ / ceo__ rows.'),
    ('general_drafting',                   'unowned (shared)', 'other', 'Also the class an unmapped function falls to; model_policy_by_identity then applies the seat''s catch-all.'),
    ('category_classification',            'unowned (shared)', 'other', ''),
    ('content_drafting',                   'unowned (shared)', 'other', ''),
    ('contract_analysis',                  'unowned (shared)', 'other', ''),
    ('legal_analysis',                     'unowned (shared)', 'other', ''),
    ('document_extraction',                'unowned (shared)', 'other', 'The sales engineer''s functions moved to sales_engineer__document_extraction.'),
    ('document_extraction_multimodal',     'unowned (shared)', 'other', ''),
    ('json_extraction',                    'unowned (shared)', 'other', 'The sales engineer''s functions moved to sales_engineer__json_extraction; wa_inbound''s directive parses stay here.'),
    ('json_extraction_text',               'unowned (shared)', 'other', ''),
    ('ocr',                                'unowned (shared)', 'other', ''),
    ('ocr_cleanup',                        'unowned (shared)', 'other', ''),
    ('vision',                             'unowned (shared)', 'other', ''),
    ('procurement_reasoning',              'unowned (shared)', 'other', 'The sales engineer''s functions moved to sales_engineer__procurement_reasoning.'),
    ('knowledge_ingestion',                'unowned (shared)', 'other', ''),
    ('knowledge_research',                 'unowned (shared)', 'other', ''),
    ('memory_retrieval',                   'unowned (shared)', 'other', ''),
    ('summarization',                      'unowned (shared)', 'other', ''),
    ('translation',                        'unowned (shared)', 'other', ''),
    ('translation_general',                'unowned (shared)', 'other', ''),
    ('knowledge_validation',               'unowned (shared)', 'other_review', 'The independent check of a think() answer for every seat but the sales engineer and the CEO: its authors write on Gemini or DeepSeek, so DeepSeek then luna.')
  ) as m(task_class, seat, route, why)
  join (values
    ('se',           'medium', 'google/gemini-3.8-flash',      'openai/gpt-6-luna'),
    ('se_compare',   'xlarge', 'anthropic/claude-opus-5.5',    'openai/gpt-6-luna'),
    ('se_review',    'small',  'openai/gpt-6-luna',            'anthropic/claude-opus-5.5'),
    ('ceo_hard',     'xlarge', 'anthropic/claude-opus-5.5',    'openai/gpt-6-luna'),
    ('other',        'medium', 'google/gemini-3.8-flash',      'deepseek/deepseek-v4.1-flash'),
    ('other_review', 'small',  'deepseek/deepseek-v4.1-flash', 'openai/gpt-6-luna'),
    ('hears',        'medium', 'google/gemini-3.8-flash',      null)
  ) as r(route, tier, p, f) on r.route = m.route
 where mp.task_class = m.task_class
   and (mp.tier, mp.model_primary, coalesce(mp.model_fallback, '-')) is distinct from (r.tier, r.p, coalesce(r.f, '-'));

-- 4c. Who each review judges now that the authors' functions write under their seat's own class.
update public.model_policy mp set reviews_class = v.authors
  from (values
    ('quote_comparison',          array['document_extraction','sales_engineer__document_extraction']),
    ('identity_redaction_verify', array['document_extraction','sales_engineer__document_extraction']),
    ('drawing_boq_confirm',       array['document_extraction','drawing_and_boq_analysis','sales_engineer__document_extraction']),
    ('knowledge_validation',      array['knowledge_ingestion','knowledge_research','internal_judgement','customer_communication',
                                        'supplier_communication','routine_employee_reasoning'])
  ) as v(task_class, authors)
 where mp.task_class = v.task_class and mp.reviews_class is distinct from v.authors;

-- The CEO judges and approves a seat's think() decision too, and think() now bills that decision to internal_judgement.
update public.model_policy set reviews_class = reviews_class || array['internal_judgement']
 where task_class in ('ceo_judgement', 'ceo_approval_decision') and not ('internal_judgement' = any (reviews_class));

-- 4d. Room for Opus 5.5 thinking (opus_5_5_classes_leave_room_for_thinking.sql), for every row the matrix put
--     Opus on, primary or fallback; and drawing_boq's own 8000 (it asked for 8000 under document_extraction).
update public.model_policy
   set max_tokens = greatest(coalesce(max_tokens, 0), 4000)
 where 'anthropic/claude-opus-5.5' in (model_primary, model_fallback) and coalesce(max_tokens, 0) < 4000;
update public.model_policy set max_tokens = 8000
 where task_class = 'drawing_and_boq_analysis' and coalesce(max_tokens, 0) < 8000;

-- ── 5. THE SALES ENGINEER'S FUNCTIONS ON ITS OWN CLASSES ────────────────────────────────────────────
-- supplier_directive is NOT moved: its only live call (wa_inbound, customer_support) names task_class
-- json_extraction explicitly, and a named class wins over this table.
update public.fn_task_class t
   set task_class = v.cls,
       note = coalesce(t.note, '') || ' | 29 Sep 2026 (founder_instruction 1056): ' || t.task_class || ' -> ' || v.cls || ', the sales engineer''s own route.',
       updated_at = now()
  from (values
    ('inquiry_intake',          'inquiry_qualification_conversation'),
    ('inquiry_parse',           'sales_engineer__json_extraction'),
    ('supplier_review',         'sales_engineer__json_extraction'),
    ('quote_extract',           'sales_engineer__document_extraction'),
    ('doc_extract',             'sales_engineer__document_extraction'),
    ('license_extract',         'sales_engineer__document_extraction'),
    ('extract_text',            'sales_engineer__document_extraction'),
    ('supplier_catalog_ingest', 'sales_engineer__document_extraction'),
    ('drawing_boq',             'drawing_and_boq_analysis'),
    ('drawing_redact',          'sales_engineer__document_extraction'),   -- its find sends no class and no max: 8000, as today
    ('inquiry_ai',              'sales_engineer__procurement_reasoning'),
    ('project_consultant',      'sales_engineer__procurement_reasoning'),
    ('supplier_onboard',        'sales_engineer__procurement_reasoning'),
    ('customer_api',            'customer_portal_assistant'),
    ('messages_api',            'customer_portal_assistant')
  ) as v(fn, cls)
 where t.fn = v.fn and t.task_class is distinct from v.cls;

-- ── 6. THE SEAT CATCH-ALLS (model_policy_by_identity, read only for an unmapped call) ───────────────
update public.model_policy_by_identity i
   set primary_model = v.p, fallback_model = v.f, escalation_model = v.e,
       note = 'Catch-all for a call from this seat that no model_policy class covers (fn_ai_route applies it only when '
              || 'v_generic). 29 Sep 2026, founder_instruction 1056: ' || v.p || ' -> ' || v.f
              || coalesce(', escalation ' || v.e, '') || '. ' || v.why
  from (values
    ('sales_engineer', 'google/gemini-3.8-flash', 'openai/gpt-6-luna',            'anthropic/claude-opus-5.5', 'Everything the sales engineer does is Gemini; Opus is its comparison model.'),
    ('marketing',      'google/gemini-3.8-flash', 'deepseek/deepseek-v4.1-flash', null,                        'Every seat but the CEO and the sales engineer.'),
    ('accountant',     'google/gemini-3.8-flash', 'deepseek/deepseek-v4.1-flash', null,                        'Every seat but the CEO and the sales engineer.'),
    ('it_engineer',    'google/gemini-3.8-flash', 'deepseek/deepseek-v4.1-flash', null,                        'Every seat but the CEO and the sales engineer.')
  ) as v(k, p, f, e, why)
 where i.scope = 'current_agent' and i.identity_key = v.k
   and (i.primary_model, i.fallback_model, coalesce(i.escalation_model, '-')) is distinct from (v.p, v.f, coalesce(v.e, '-'));

-- The CEO had no catch-all, so an unmapped CEO call took general_drafting's route (DeepSeek behind it). Unknown
-- work is treated as EASY; the CEO's hard work is named (ceo_judgement, ceo__internal_judgement, ...).
insert into public.model_policy_by_identity
  (identity_key, scope, title, deterministic_first, primary_model, fallback_model, escalation_model, note, package_version, imported_at)
select 'ceo', 'current_agent', 'Chief Executive', 'Yes', 'google/gemini-3.8-flash', 'openai/gpt-6-luna', 'anthropic/claude-opus-5.5',
       'Catch-all for a call from this seat that no model_policy class covers (fn_ai_route applies it only when v_generic). '
       || '29 Sep 2026, founder_instruction 1056: unknown CEO work is treated as EASY (Gemini, luna behind it); the hard '
       || 'work has its own classes on Opus.', '1.0.0', now()
where not exists (select 1 from public.model_policy_by_identity where identity_key = 'ceo' and scope = 'current_agent');

-- customer_support had none either, and without one an unmapped call reaches fn_routing_tier_model, which takes the
-- cheapest active model of the seat's tier - z-ai/glm-5.3-flash is still active - instead of the matrix.
insert into public.model_policy_by_identity
  (identity_key, scope, title, deterministic_first, primary_model, fallback_model, escalation_model, note, package_version, imported_at)
select 'customer_support', 'current_agent', 'Customer Support', 'Yes', 'google/gemini-3.8-flash', 'deepseek/deepseek-v4.1-flash', null,
       'Catch-all for a call from this seat that no model_policy class covers (fn_ai_route applies it only when v_generic). '
       || '29 Sep 2026, founder_instruction 1056: every seat but the CEO and the sales engineer, Gemini with DeepSeek behind '
       || 'it. Without this row an unmapped call took fn_routing_tier_model''s cheapest-in-tier pick.', '1.0.0', now()
where not exists (select 1 from public.model_policy_by_identity where identity_key = 'customer_support' and scope = 'current_agent');

-- ── 6b. THE MODEL-CONSUMER REGISTER FOLLOWS THE FUNCTIONS───────────────────────────────────────────
-- it_model_consumer names each paid consumer as '<fn>:<class>' (every_model_credit_consumer_is_listed_and_a_runaway_
-- is_flagged.sql). Section 5 moved five of them to the sales engineer's own classes; their rows move with them,
-- keeping why a model is needed and who owns it.
update public.it_model_consumer c set consumer = v.new_key
  from (values
    ('inquiry_intake:agent_reasoning',       'inquiry_intake:inquiry_qualification_conversation'),
    ('drawing_boq:document_extraction',      'drawing_boq:drawing_and_boq_analysis'),
    ('drawing_redact:document_extraction',   'drawing_redact:sales_engineer__document_extraction'),
    ('license_extract:document_extraction',  'license_extract:sales_engineer__document_extraction'),
    ('quote_extract:document_extraction',    'quote_extract:sales_engineer__document_extraction')
  ) as v(old_key, new_key)
 where c.consumer = v.old_key
   and not exists (select 1 from public.it_model_consumer x where x.consumer = v.new_key);

-- A '<fn>:think' host is listed for every class think() bills to: the four it always used and the two it was missing
-- (routine_employee_reasoning had been unlisted since the 23 Sep ruling put planning on it; internal_judgement is
-- new here). A seat's own route is logged under the class itself (section 3), so it needs nothing more.
-- Body started from every_model_credit_consumer_is_listed_and_a_runaway_is_flagged.sql. CREATE OR REPLACE keeps its
-- ACL, so no revoke here.
create or replace function public.fn_it_model_consumer_listed(p_fn text, p_class text)
returns boolean language sql stable security definer set search_path to 'public', 'pg_temp' as $fn$
  select exists (select 1 from public.it_model_consumer c
                  where c.consumer = p_fn || ':' || coalesce(p_class, 'unclassified')
                     or (c.consumer = p_fn || ':think'
                         and p_class in ('agent_reasoning', 'knowledge_validation', 'customer_communication', 'supplier_communication',
                                 'routine_employee_reasoning', 'internal_judgement')))
$fn$;

-- ── 7. THE DISABLED BoQ EXCEPTION PINS THE CLASS'S NEW PRIMARY ──────────────────────────────────────
-- It stays OFF (founder_instruction 216: until the founder confirms the cost per drawing). luna is USD 0.10/0.50
-- against Gemini's 0.75/3.75, so the per-call estimate falls; the daily cap is not touched.
update public.paid_route_exception
   set model_id = 'openai/gpt-6-luna',
       note = coalesce(note, '') || ' | 29 Sep 2026 (founder_instruction 1056): model gemini-3.8-flash -> gpt-6-luna, the class''s new '
              || 'primary; the BoQ draft it confirms is read on Gemini, so the confirm must be another family. On the draft''s '
              || 'fallback path (read on luna) the review router sends the confirm to Opus, which this exception does '
              || 'not name, so that confirm waits for the hold like any other call. Still OFF.',
       updated_at = now()
 where route = 'drawing_boq_confirm' and model_id is distinct from 'openai/gpt-6-luna';

-- ── VERDICT ROW (DDL in this file, so no raise; apply_sql.mjs exits 3 on PROBE FAILED) ──────────────
select case
  when (select count(*) from public.model_policy where active and tier <> 'none'
          and (model_primary in ('openai/gpt-5.6-sol', 'z-ai/glm-5.3-flash', 'qwen/qwen3.8-max-0902')
            or model_fallback in ('openai/gpt-5.6-sol', 'z-ai/glm-5.3-flash', 'qwen/qwen3.8-max-0902'))) > 0
    then 'PROBE FAILED: a class still names Sol, GLM or Qwen'
  when (public.fn_ai_route(null, null, null, 'quote_compare', false, null, null)->>'model') <> 'anthropic/claude-opus-5.5'
    then 'PROBE FAILED: quote_compare does not route to Opus'
  when (public.fn_ai_route('internal_judgement', null, null, null, false, null, 'ceo')->>'policy_class')
       is distinct from 'ceo__internal_judgement'
    then 'PROBE FAILED: the CEO''s own route is not taken'
  when (public.fn_ai_route('routine_employee_reasoning', null, null, null, false, null, 'sales_engineer')->>'fallback')
       is distinct from 'openai/gpt-6-luna'
    then 'PROBE FAILED: the sales engineer''s plan B is not its own'
  when (select count(*) from public.llm_route_health where model_id = 'deepseek/deepseek-v4.1-flash'
          and open_until = (select max(open_until) from public.llm_route_health)) <> 1
    then 'PROBE FAILED: deepseek is not held with the fleet'
  when not public.fn_it_model_consumer_listed('wa_inbound', 'internal_judgement')
    or not public.fn_it_model_consumer_listed('sales_engineer', 'customer_communication')
    or not public.fn_it_model_consumer_listed('quote_extract', 'sales_engineer__document_extraction')
    then 'PROBE FAILED: a moved consumer or a think() class reads as unlisted'
  else 'PROBE OK' end as verdict;
