-- SIMPLE TASKS LEAVE SONNET, AND EVERY REPLY RUNS ON THE MODEL ITS TASK NEEDS (part 1 of 3: the T1 tier).
-- Seat: it_engineer (cost). 10 Nov 2026. Founder rulings 1571 ("simple tasks ... do not need Sonnet 5.5; use a cheaper
-- suitable model"), 1339 (every reply is the model's unless OpenRouter is down), 1241 (Gemini only hears), 1240 (no 5.6),
-- 1218 (Pro at the same price), 1217. Design, measured on production today: docs/reports/2026-11-10-design-model-routing.md
-- section 5a, steps 1, 2, 3 and 7. This file needs no eval beyond its probe: every class it moves is internal, or its
-- words convey content code already decided (a status row, a reference, the one intake question).
--
-- MEASURED BEFORE WRITING (production htdblwldjkcgjvmqkbeh, read-only, 10 Nov 2026 01:00-02:30Z; prices from the live
-- OpenRouter catalogue https://openrouter.ai/api/v1/models, read 02:03Z and again 02:40Z, USD per Mtok in / out / cache read):
--   * qwen/qwen3.8-flash          0.15 / 0.47 / 0.016, context 1,000,000, input text+image+video, tools and response_format.
--                                 NOT registered. Qwen family: the only non-OpenAI, non-Anthropic family a T1 fallback and
--                                 a reviewer of an OpenAI author can use without Sonnet's price (2.00 / 10.00).
--   * openai/gpt-6.1-terra-pro    1.00 / 5.00 / 0.05, cache write 1.25, context 1,050,000, input text+image+file.
--                                 NOT registered. The interview's second candidate (eval B); registered INACTIVE here, so no
--                                 router branch (cheapest-in-tier, capability substitution) can choose it before eval B.
--   * deepseek/deepseek-v4.1-flash registered at 0.30 / 1.20 / 0.006 (5 Oct), live 0.051 / 0.567 / 0.018. Stays retired
--                                 (inactive, unapproved, matrix v2): only the stale price is corrected.
--   * google/gemini-3.8-flash     cache read NULL in the registry, live 0.0825.
--   * 14 T1 classes (intent_detection, email_triage, category_classification, json_extraction, json_extraction_text,
--     memory_retrieval, ocr_cleanup, general_drafting, inbound_email, resend_inbound, summarization, health_ping,
--     translation, translation_general) run openai/gpt-6-luna-pro > anthropic/claude-sonnet-5.5. Luna Pro: 31,140 attempts,
--     30,364 OK (97.5%, llm_route_health). So 2.5% of these calls landed on Sonnet at 20x Luna Pro's price.
--   * The intake "voice" (inquiry_intake/slots.ts intakeVoice) ran on conversation_reply (Sonnet) with the ~35k-token brief to
--     reword one sentence code had decided: USD 0.040-0.053 a call (ai_cost_log, 4 and 10 Nov). It moves to voice_draft.
--   * WhatsApp status asks (my_status, my_documents, my_quotes, my_requests, my_jobs, by_id) were answered on
--     conversation_reply (Sonnet) with the brief: USD 0.0118 a call on 10 Nov (23,036 in, 159 out). They move to status_reply.
--   * review_pool active: Sonnet 5.5 (1), Opus 5.5 (2), Luna Pro (3). An Anthropic author's review has no third family behind
--     Luna Pro.
--   * llm_attempt, last 24 h: 0 HTTP 402 since the 01:40Z top-up (ledger 1568); the 95 credit refusals ended 01:01Z.
--
-- WHAT THIS FILE DOES (upserts and guarded updates only; the applier adds the one transaction):
--   0. fn_ai_route: a seat's plan B (model_policy_by_identity, Sonnet 5.5 for all six seats) no longer replaces a class's
--      own fallback that is CHEAPER than it. Without this, steps 3's fallbacks reached only calls that name no seat.
--   1. model_registry: Qwen 3.8 Flash (small, active) and Terra Pro (medium, approved, INACTIVE) at the live prices; the
--      DeepSeek and Gemini cache prices corrected. model_rate rows for the two new models (fn_llm_log books AED from it;
--      3.6725 AED/USD as every row there). llm_route_health rows for both (no hold: rulings 1175 and 1260).
--   2. review_pool: Qwen 3.8 Flash at rank 4, so a review of an OpenAI author can always reach a non-OpenAI model.
--   3. model_policy T1: the 14 classes keep Luna Pro and fall back to Qwen 3.8 Flash, not Sonnet (1571 orders the fallback
--      off Sonnet too). New classes status_reply and voice_draft: tier small, Luna Pro > Qwen 3.8 Flash, 300 output tokens,
--      no response cache (each reply carries its own facts).
--   4. wa_reply_intent: invoice_copy, verification_code and new_request, so the WhatsApp reading can name them. Their
--      templates are FACTS the status lane hands the model (wa_inbound/status_lane.ts), read from the product itself:
--      the invoice and receipt buttons (src/components/me/requests/QuoteDocs.tsx, portalText q_inv_pdf / q_rcpt_pdf), the
--      supplier billing tab (workspaceCopy acct_billing), the sign-in code rules (login_otp: a resend retires every earlier
--      code; the WhatsApp code's "Send it by SMS instead"), and the request chat link (_shared/size_question.ts /me?new=1).
--   5. it_model_consumer: the three new consumers, so fn_it_model_consumer_listed does not flag them.
--
-- NOT HERE, ON PURPOSE (each waits for its eval, as scripts/sql/pending/ notes):
--   * conversation_reply, customer_portal_assistant, visitor_chat > Luna Pro, and knowledge_validation (with its sales
--     engineer row) > Qwen: scripts/sql/customer_chat_and_the_reviewer_move_once_their_evals_pass.sql (evals A and C).
--   * inquiry_qualification_conversation: scripts/sql/the_inquiry_interview_moves_to_the_model_eval_b_passes.sql (eval B).
--   * ceo__knowledge_validation, the Opus classes (1107/1108) and the seat catch-alls: unchanged.
--
-- Prevented by: scripts/sql/every_seat_runs_the_founders_model_matrix_probe.sql (section 4 names every class with its
-- route; the T1 and simple routes are Luna Pro > Qwen 3.8 Flash), scripts/checks/the_registry_prices_are_the_catalogue_s_
-- prices.test.mjs (this file is in OWNING_SQLS), supabase/functions/wa_inbound/status_lane.test.ts, and the verdict row at
-- the end of this file (read-only; it never raises).
--   applied at merge: node scripts/apply_sql.mjs scripts/sql/simple_tasks_leave_sonnet_and_every_reply_runs_on_the_model_its_task_needs.sql --apply --ddl --seat it_engineer

-- ── 0. the router: a seat's plan B never replaces a cheaper fallback a class chose on purpose ───────────────────────
-- fn_ai_route as live (md5(prosrc) 0fa7688f7bfa8edddfb40466f54b473b on 10 Nov 2026, canonical file
-- every_seat_runs_luna_with_gemini_behind_and_the_two_retired_models_leave_routing.sql), byte for byte but ONE condition in
-- the seat plan-B branch. MEASURED: with only the policy rows below, fn_ai_route('status_reply', ..., 'customer_support')
-- answered Luna Pro > SONNET 5.5 (rehearsed 10 Nov 02:50Z): the seat catch-all's plan B (model_policy_by_identity, Sonnet for
-- all six seats) replaced the class's Qwen on every call that names its seat, which is every think() and aiReply() call.
-- CREATE OR REPLACE keeps the ACL and the pinned search_path (no new grant to PUBLIC).
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
  v_seat_fb text; v_seat_p text;
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
  -- (routine_employee_reasoning, customer_communication, ...). The founder's matrix routes by WHO asks. Matrix v2
  -- (5 Oct 2026): every seat runs openai/gpt-6-luna with google/gemini-3.8-flash as its plan B, and the CEO's
  -- hard work and the comparison report run on Opus with luna behind. The seat is the caller's agent,
  -- resolved as the agent_reasoning block above resolves it (an alias of a seat is that seat).
  --   1. A policy row named '<seat>__<class>' is that seat's own route for <class>: its MODELS are taken, while
  --      the CLASS stays <class> - ai_cost_log, the response cache, the confidence prior and every author proof
  --      key on it, and ai_cost_log.seat already says who asked. The row travels as policy_class, which
  --      fn_ai_route_review_for reads for a review's pair.
  --   2. Otherwise the seat's PLAN B is its own for every class it calls: the fallback of its catch-all row in
  --      model_policy_by_identity replaces the class's, unless the class has no fallback on purpose (only Gemini
  --      hears) or is a review (its pair is chosen against its author's family). Since matrix v2 only on a class
  --      that runs on the seat's own primary: an Opus class keeps luna behind it.
  -- A '<seat>__<class>' row - reached through the seat, or named by fn_task_class for the seat's own function -
  -- never allows fewer tokens than <class>. A seat's own row is never served from the semantic cache: that cache is keyed
  -- by class, not model, so a CEO judgement on Opus could otherwise be answered by another seat's Gemini answer.
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
      v_pol.cache_ttl_min := 0;
    end if;
  end if;

  if v_split is null and not v_generic and v_seat is not null and v_pol.model_fallback is not null
     and cardinality(coalesce(v_pol.reviews_class, '{}')) = 0 then
    select i.fallback_model, i.primary_model into v_seat_fb, v_seat_p from model_policy_by_identity i
     where i.scope = 'current_agent' and i.identity_key = v_seat
       and exists (select 1 from org_role o where o.role_id = v_seat and o.status = 'active');  -- a live seat's row only
    if v_seat_fb is not null and v_seat_fb not in (v_pol.model_primary, v_pol.model_fallback)
       and v_pol.model_primary is not distinct from v_seat_p  -- matrix v2: only on the seat's own routine model
       -- 10 Nov 2026 (ruling 1571, it_engineer): a class whose own fallback is CHEAPER than the seat's plan B chose it on
       -- purpose (the T1 classes, status_reply, voice_draft: Qwen 3.8 Flash at USD 0.15 in, the seats' plan B Sonnet 5.5 at
       -- 2.00). It keeps its own; before this, every seat's call put a simple task back on Sonnet when Luna Pro failed.
       and coalesce((select r.in_per_mtok_usd from model_registry r where r.model_id = v_pol.model_fallback), 0)
           >= coalesce((select r.in_per_mtok_usd from model_registry r where r.model_id = v_seat_fb), 0) then
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
    -- 18 Oct 2026 (ledger 1240/1241): the routing tier may only pick inside the class's own pair.
    if v_rt is not null and (v_rt->>'model') is not null and (v_rt->>'model') in (v_pol.model_primary, v_pol.model_fallback) then
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
      -- 18 Oct 2026 (ledger 1240/1241): the cheapest MEDIUM row of the whole registry was Gemini, which may only hear.
      -- A downgrade now stays inside the class's own pair; with no medium model there, the class keeps its primary.
      v_model := coalesce((select model_id from model_registry
       where active and approved and tier = 'medium' and model_id in (v_pol.model_primary, v_pol.model_fallback) order by in_per_mtok_usd, model_id limit 1), v_model);
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
     where active and approved and model_id in (v_pol.model_primary, v_pol.model_fallback)   -- 18 Oct 2026: the class's own pair, never the cheapest of the registry
     order by (model_id = v_pol.model_fallback) desc, in_per_mtok_usd, model_id limit 1;
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
       and (model_id in (v_pol.model_primary, v_pol.model_fallback) or (v_aud and supports_audio))   -- 18 Oct 2026 (ledger 1241): own pair; only a recording reaches the model that hears
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
       and (model_id in (v_pol.model_primary, v_pol.model_fallback) or (v_aud and supports_audio))   -- 18 Oct 2026 (ledger 1241)
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

-- ── 1. the registry: two models registered, two stale prices corrected ──────────────────────────────────────────
insert into public.model_registry (model_id, provider, tier, in_per_mtok_usd, out_per_mtok_usd,
  cache_read_per_mtok_usd, cache_write_per_mtok_usd, supports_cache, supports_streaming, context_len, approved, active,
  quality_score, note, supports_vision, supports_audio, supports_tools)
values
  ('qwen/qwen3.8-flash', 'qwen', 'small', 0.15, 0.47,
   0.016, null, false, true, 1000000, true, true, null,
   'Ruling 1571 (10 Nov 2026): the fallback of every T1 class and of status_reply and voice_draft, and rank 4 of the review pool (the reviewer of an OpenAI author that is neither OpenAI nor priced like Sonnet). OpenRouter 10 Nov 2026: $0.15/$0.47 per Mtok, cache read $0.016, 1,000,000 context, input text+image+video, no file, no audio, tools and response_format. supports_cache false: that column makes ai_gateway send Anthropic-style cache_control blocks. Tier small: above Luna Pro ($0.10), so the cheapest small row is still Luna Pro. Design: docs/reports/2026-11-10-design-model-routing.md.',
   true, false, true),
  ('openai/gpt-6.1-terra-pro', 'openai', 'medium', 1, 5,
   0.05, 1.25, false, true, 1050000, true, false, null,
   'Registered 10 Nov 2026, INACTIVE: the second candidate for the inquiry interview (inquiry_qualification_conversation), used only if GPT-6 Luna Pro fails eval B (ruling 1572; 1218: Pro at the price of Terra). OpenRouter 10 Nov 2026: $1.00/$5.00 per Mtok, cache read $0.05, cache write $1.25, 1,050,000 context, input text+image+file. Activated by scripts/sql/the_inquiry_interview_moves_to_the_model_eval_b_passes.sql only when eval B chooses it.',
   true, false, true)
on conflict (model_id) do update set provider = excluded.provider, tier = excluded.tier,
  in_per_mtok_usd = excluded.in_per_mtok_usd, out_per_mtok_usd = excluded.out_per_mtok_usd,
  cache_read_per_mtok_usd = excluded.cache_read_per_mtok_usd, cache_write_per_mtok_usd = excluded.cache_write_per_mtok_usd,
  supports_cache = excluded.supports_cache, supports_streaming = excluded.supports_streaming, context_len = excluded.context_len,
  approved = excluded.approved, active = excluded.active, note = excluded.note, supports_vision = excluded.supports_vision,
  supports_audio = excluded.supports_audio, supports_tools = excluded.supports_tools, updated_at = now();

-- DeepSeek stays retired (inactive, unapproved, named by no route: matrix v2). Only its price is the catalogue's again.
update public.model_registry set in_per_mtok_usd = 0.051, out_per_mtok_usd = 0.567, cache_read_per_mtok_usd = 0.018,
  updated_at = now()
 where model_id = 'deepseek/deepseek-v4.1-flash' and in_per_mtok_usd is distinct from 0.051;
-- Gemini's implicit cache read is published (0.0825); supports_cache stays false (Google refuses Anthropic cache blocks).
update public.model_registry set cache_read_per_mtok_usd = 0.0825, updated_at = now()
 where model_id = 'google/gemini-3.8-flash' and cache_read_per_mtok_usd is distinct from 0.0825;

insert into public.model_rate (model, tier, in_aed_per_mtok, out_aed_per_mtok, cache_read_aed_per_mtok, cache_write_aed_per_mtok,
  usd_per_m_prompt, usd_per_m_output, source_url, id_verified, verified_at, note)
values
  ('qwen/qwen3.8-flash', 'small', 0.550875, 1.726075, 0.05876, null, 0.15, 0.47, 'https://openrouter.ai/api/v1/models', true,
   date '2026-11-10', 'Converted at 3.6725 AED/USD, as every row here. USD prices from the OpenRouter catalogue on 10 Nov 2026 (ruling 1571). No cache write is published.'),
  ('openai/gpt-6.1-terra-pro', 'medium', 3.6725, 18.3625, 0.183625, 4.590625, 1, 5, 'https://openrouter.ai/api/v1/models', true,
   date '2026-11-10', 'Converted at 3.6725 AED/USD, as every row here. USD prices from the OpenRouter catalogue on 10 Nov 2026 (eval B candidate).')
on conflict (model) do update set tier = excluded.tier, in_aed_per_mtok = excluded.in_aed_per_mtok,
  out_aed_per_mtok = excluded.out_aed_per_mtok, cache_read_aed_per_mtok = excluded.cache_read_aed_per_mtok,
  cache_write_aed_per_mtok = excluded.cache_write_aed_per_mtok, usd_per_m_prompt = excluded.usd_per_m_prompt,
  usd_per_m_output = excluded.usd_per_m_output, verified_at = excluded.verified_at, note = excluded.note;

-- A breaker per model (model_policy's trigger refuses a model without one). No hold (rulings 1175, 1260): open_until null.
insert into public.llm_route_health (model_id, failure_threshold, cooldown_seconds)
values ('qwen/qwen3.8-flash', 3, 300), ('openai/gpt-6.1-terra-pro', 3, 300)
on conflict (model_id) do nothing;

-- ── 2. the review pool: a third family behind every OpenAI author ───────────────────────────────────────────────
insert into public.review_pool (model_id, rank, active, note)
values ('qwen/qwen3.8-flash', 4, true,
  '10 Nov 2026, ruling 1571: a non-OpenAI, non-Anthropic reviewer at USD 0.15/0.47, so a review of an OpenAI author never needs Sonnet''s price and an Anthropic author''s review has a family behind Luna Pro.')
on conflict (model_id) do update set rank = excluded.rank, active = excluded.active, note = excluded.note;

-- ── 3. model_policy: T1 falls back to Qwen; the two new classes ─────────────────────────────────────────────────
update public.model_policy
   set model_fallback = 'qwen/qwen3.8-flash',
       rationale = coalesce(rationale || ' | ', '') || '10 Nov 2026, ruling 1571: a T1 task (internal, or content code decided); its fallback leaves Sonnet 5.5 (USD 2/10) for Qwen 3.8 Flash (USD 0.15/0.47). Luna Pro failed 2.5% of 31,140 attempts, so the fallback carries about 1 call in 40.'
 where task_class in ('intent_detection', 'email_triage', 'category_classification', 'json_extraction', 'json_extraction_text',
                      'memory_retrieval', 'ocr_cleanup', 'general_drafting', 'inbound_email', 'resend_inbound', 'summarization',
                      'health_ping', 'translation', 'translation_general')
   and model_primary = 'openai/gpt-6-luna-pro' and model_fallback = 'anthropic/claude-sonnet-5.5';

insert into public.model_policy (task_class, tier, model_primary, model_fallback, max_tokens, rationale, deterministic_alternative,
  active, cache_ttl_min, reviews_class)
values
  ('status_reply', 'small', 'openai/gpt-6-luna-pro', 'qwen/qwen3.8-flash', 300,
   'Ruling 1571 (10 Nov 2026): a reply to a simple ask on WhatsApp (where is my request, my quotes, my documents, a copy of my invoice, my code did not arrive, is my comparison ready). Code fixes the content (the sender''s own rows, the reference); the model words it in their language (1339). No company brief: about 2.5k tokens, USD 0.0003 a reply (E), against USD 0.0118 on Sonnet with the brief (M, 10 Nov). wa_inbound/status_lane.ts.',
   'none: the words are the model''s (1339); a code-written reply only in an outage (modelOrOutage)', true, 0, null),
  ('voice_draft', 'small', 'openai/gpt-6-luna-pro', 'qwen/qwen3.8-flash', 300,
   'Ruling 1571 (10 Nov 2026): the request chat''s voice. Code decided the sentence and the one question (inquiry_intake/slots.ts); the model says it in their words with the WHOLE conversation (1572) and no brief. Was conversation_reply on Sonnet with the ~35k-token brief: USD 0.040-0.053 a call (M, 4 and 10 Nov); about USD 0.0004 here (E).',
   'none: the words are the model''s (1339); the drafted sentence only in an outage', true, 0, null)
on conflict (task_class) do update set tier = excluded.tier, model_primary = excluded.model_primary,
  model_fallback = excluded.model_fallback, max_tokens = excluded.max_tokens, rationale = excluded.rationale,
  deterministic_alternative = excluded.deterministic_alternative, active = excluded.active,
  cache_ttl_min = excluded.cache_ttl_min, reviews_class = excluded.reviews_class;

-- ── 4. the three asks the WhatsApp reading can now name (facts for the status lane, never sent as they are) ─────────
insert into public.wa_reply_intent (intent_key, label, scope, sort, active, match_patterns, requires_number, requires_identity,
  resolver_note, answer_template)
values
  ('invoice_copy', 'Asking for a copy of an invoice or a payment receipt', 'company', 86, true, '{}', false, false,
   'Facts for wa_inbound/status_lane.ts (status_reply). Where the documents are, read from the product: QuoteDocs.tsx (Invoice (PDF), Receipt (PDF)), portalText q_inv_not_paid, the supplier workspace Account > Billing.',
   'A customer''s invoice and payment receipt for a revealed quote are in the customer portal, https://quotesdone.com/me : My requests, open the request, then "Invoice (PDF)" or "Receipt (PDF)" on the revealed quote (an Arabic invoice is offered there too). A payment that has not completed has no invoice or receipt yet. A supplier''s own billing is in the supplier portal, https://quotesdone.com/portal , under Account > Billing.'),
  ('verification_code', 'A sign-up or sign-in verification code that did not arrive or does not work', 'company', 87, true, '{}', false, false,
   'Facts for wa_inbound/status_lane.ts (status_reply), read from login_otp: a new code retires every earlier one; a WhatsApp code can be sent by SMS instead.',
   'A new sign-in code can be asked for on the sign-in page, and asking for a new one cancels every earlier code, so only the newest code works. A code sent on WhatsApp that has not arrived within a minute can be sent by SMS instead with the "Send it by SMS instead" button. Codes are never sent by a person, and nobody from QuotesDone asks for a code.'),
  ('new_request', 'A buyer describing a new job to be quoted (a new request, drawings, several trades)', 'company', 88, true, '{}', false, false,
   'Ruling 1571: a complicated WhatsApp ask is sent to the app''s request chat. Facts for wa_inbound/status_lane.ts; the link is the one _shared/size_question.ts gives (/me?new=1, /ar/me?new=1 in Arabic).',
   'A new job is posted in the request chat in the app, which takes the details, drawings and photos step by step and sends it to matched suppliers: https://quotesdone.com/me?new=1 (in Arabic: https://quotesdone.com/ar/me?new=1). Posting a request is free.')
on conflict (intent_key) do update set label = excluded.label, scope = excluded.scope, sort = excluded.sort, active = excluded.active,
  resolver_note = excluded.resolver_note, answer_template = excluded.answer_template,
  requires_number = excluded.requires_number, requires_identity = excluded.requires_identity;

-- ── 5. the consumers ───────────────────────────────────────────────────────────────────────────────────────────
insert into public.it_model_consumer (consumer, owner_seat, why_a_model)
values
  ('wa_inbound:status_reply', 'customer_support', 'wording a WhatsApp status, invoice-copy or code answer whose facts code decided (ruling 1571)'),
  ('inquiry_intake:voice_draft', 'sales_engineer', 'saying the request chat''s code-decided sentence and question in the customer''s words (ruling 1571)'),
  ('sales_engineer:voice_draft', 'sales_engineer', 'the re-ask of a request-chat turn whose drafts were refused (_shared/reask.ts), on the voice''s class')
on conflict (consumer) do update set owner_seat = excluded.owner_seat, why_a_model = excluded.why_a_model;

-- ── the verdict (read-only) ──────────────────────────────────────────────────────────────────────────────────────
with t1(c) as (values ('intent_detection'), ('email_triage'), ('category_classification'), ('json_extraction'), ('json_extraction_text'),
                      ('memory_retrieval'), ('ocr_cleanup'), ('general_drafting'), ('inbound_email'), ('resend_inbound'),
                      ('summarization'), ('health_ping'), ('translation'), ('translation_general')),
bad as (
  select 'qwen is not an active approved registry row at 0.15/0.47' w where not exists (select 1 from public.model_registry
     where model_id = 'qwen/qwen3.8-flash' and active and approved and in_per_mtok_usd = 0.15 and out_per_mtok_usd = 0.47)
  union all select 'terra is not registered inactive at 1/5' where not exists (select 1 from public.model_registry
     where model_id = 'openai/gpt-6.1-terra-pro' and not active and approved and in_per_mtok_usd = 1 and out_per_mtok_usd = 5)
  union all select 'deepseek is active again or still mispriced' where exists (select 1 from public.model_registry
     where model_id = 'deepseek/deepseek-v4.1-flash' and (active or approved or in_per_mtok_usd <> 0.051))
  union all select 'a new model has no breaker row' where (select count(*) from public.llm_route_health
     where model_id in ('qwen/qwen3.8-flash', 'openai/gpt-6.1-terra-pro')) <> 2
  union all select 'a new model has no model_rate row' where (select count(*) from public.model_rate
     where model in ('qwen/qwen3.8-flash', 'openai/gpt-6.1-terra-pro')) <> 2
  union all select 'review pool is ' || coalesce((select string_agg(model_id, ',' order by rank) from public.review_pool where active), 'empty')
     where (select string_agg(model_id, ',' order by rank) from public.review_pool where active)
           is distinct from 'anthropic/claude-sonnet-5.5,anthropic/claude-opus-5.5,openai/gpt-6-luna-pro,qwen/qwen3.8-flash'
  union all select t1.c || ' is not Luna Pro > Qwen' from t1 left join public.model_policy p on p.task_class = t1.c
     where p.task_class is null or (p.model_primary, p.model_fallback) is distinct from ('openai/gpt-6-luna-pro', 'qwen/qwen3.8-flash')
  union all select c || ' routes ' || coalesce(public.fn_ai_route(c, null, null, null, false, null, s)->>'model', '-') || '>'
                   || coalesce(public.fn_ai_route(c, null, null, null, false, null, s)->>'fallback', '-')
     from (values ('status_reply', 'customer_support'), ('voice_draft', 'sales_engineer')) v(c, s)
     where coalesce(public.fn_ai_route(c, null, null, null, false, null, s)->>'model', '-') <> 'openai/gpt-6-luna-pro'
        or coalesce(public.fn_ai_route(c, null, null, null, false, null, s)->>'fallback', '-') <> 'qwen/qwen3.8-flash'
  -- the router change: a seat's call keeps a T1 class's Qwen, and a T2 class still falls back to the seat's plan B (Sonnet)
  union all select 'a seat call on ' || c || ' routes ' || coalesce(public.fn_ai_route(c, null, null, null, false, null, s)->>'fallback', '-')
                   || ' behind, not ' || f
     from (values ('summarization', 'ceo', 'qwen/qwen3.8-flash'), ('json_extraction', 'customer_support', 'qwen/qwen3.8-flash'),
                  ('customer_communication', 'customer_support', 'anthropic/claude-sonnet-5.5'),
                  ('routine_employee_reasoning', 'accountant', 'anthropic/claude-sonnet-5.5')) v(c, s, f)
     where coalesce(public.fn_ai_route(c, null, null, null, false, null, s)->>'fallback', '-') <> f
  union all select 'a simple class allows more than 300 output tokens' where exists (select 1 from public.model_policy
     where task_class in ('status_reply', 'voice_draft') and max_tokens <> 300)
  union all select 'an intent row is missing: ' || k from (values ('invoice_copy'), ('verification_code'), ('new_request')) v(k)
     where not exists (select 1 from public.wa_reply_intent where intent_key = v.k and active and answer_template <> '')
  union all select 'a consumer reads as unlisted: ' || f || ':' || c from (values ('wa_inbound', 'status_reply'),
       ('inquiry_intake', 'voice_draft'), ('sales_engineer', 'voice_draft')) v(f, c)
     where not public.fn_it_model_consumer_listed(f, c)
  union all select 'no class falls back to its own primary' where exists (select 1 from public.model_policy
     where active and model_fallback = model_primary and model_primary not in ('none', 'none/deterministic')))
select case when count(*) = 0 then 'PROBE OK: qwen and terra registered, 14 T1 classes on Luna Pro > Qwen, status_reply and voice_draft routed, 3 intents, 3 consumers'
            else 'PROBE FAILED: ' || string_agg(w, '; ') end as verdict
  from bad;
