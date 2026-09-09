-- THE CEO AND THE SALES ENGINEER GET THE FOUNDER'S MODEL PAIR. 9 September 2026.
--
-- The founder, 9 Sep 2026:
--   "for the CEO we didnt select before and it will be fable 5.1 as A and gpt 6 Astra as B"
--   "for the sales Engineer its same as the CEO since he need to be extremely smart"
--   "we have the customer support already sorted out yesterday with model A and model B"
-- So two seats move and customer support does NOT. Nothing below touches support_ai, visitor_chat,
-- wa_inbound, customer_communication, inbound_email, resend_inbound, email_triage or
-- intent_detection.
--
-- REGISTRATION ONLY, AND THAT COSTS NOTHING. All 8 routes in llm_route_health are held to
-- 2126-08-15 and fn_kernel_paid_provider_gate denies globally; the OpenRouter account holds $4.07
-- against its own $20 floor. Registering a model is a row. Calling one is a bill. This is the
-- former, so the routing is correct and ready the moment the hold lifts.
--
-- WHY REGISTRATION IS THE POINT, not paperwork. fn_ai_route step 9 does this:
--     select * into v_reg from model_registry where model_id = v_model and active;
--     if not found then ... substituted the cheapest active+approved model of that tier ...
--                          v_why := v_why || ' | WARNING: ...'
-- A policy model that is not registered is silently replaced and the only trace is a WARNING inside
-- a string nobody reads. Eight configured model ids in model_policy_by_identity are in exactly that
-- state today. Registering these two is what keeps the founder's ruling from being quietly undone.
--
-- MEASURED, NOT ASSUMED (GET https://openrouter.ai/api/v1/models, 9 Sep 2026, free and unauthenticated):
--   anthropic/claude-fable-5.1  ctx 1,000,000  prompt $10/Mtok  completion $50/Mtok
--                               cache read $0.25/Mtok  cache write $12.50/Mtok
--                               input text+image+file, output text, tools yes, tool_choice NO
--   openai/gpt-6-astra          ctx 1,050,000  prompt $10/Mtok  completion $50/Mtok
--                               cache read $1.00/Mtok  cache write $12.50/Mtok
--                               input text+image+file, output text, tools yes, tool_choice YES
-- Neither takes audio, so supports_audio is false on both and the capability branch in fn_ai_route
-- will correctly substitute away from them for an audio task rather than let the provider reject
-- the payload.
--
-- THE ASYMMETRY THAT MATTERS. fable-5.1 does not advertise tool_choice; gpt-6-astra does. Neither
-- of the four task classes below forces a tool: the CEO seat's decide/command actions and the Sales
-- Engineer's assist/report actions are text in, text out, with the tools called by the edge
-- function around the model rather than by the model. If a later class needs FORCED tool choice, it
-- must not use this pair primary-first, because the B model would then be strictly more capable
-- than the A model on that one axis.
--
-- TIER = xlarge, and it is the ceiling rather than a comfortable fit. model_registry_tier_check
-- allows only small/medium/large/xlarge, and the existing ladder is priced:
--   small 0.25-0.32  medium 1.00-1.50  large 2.00  xlarge 5.00  (USD/Mtok input)
-- Both of these are $10 — twice the current xlarge, claude-opus-4.8. There is no rung above, so
-- xlarge is where they belong: it is the tier the estate already means by "the consequential work,
-- whatever it costs". Because opus-4.8 at $5.00 stays the CHEAPEST xlarge row, nothing that orders
-- by in_per_mtok_usd changes behaviour: the step-9 substitution, the budget-degrade step and the
-- capability override all keep resolving exactly as they did.
--
-- quality_score is left null. Nothing in the database reads it (checked: fn_ai_route,
-- fn_routing_tier_model, fn_llm_preflight, fn_model_cost_usd, fn_classify_llm_failure and
-- fn_kernel_paid_provider_gate all reference model_registry and none of them reference the column),
-- and a number invented here would be a claim about quality nobody has measured.

begin;

-- ── 1. model_registry ────────────────────────────────────────────────────────────────────────────
insert into model_registry (
  model_id, provider, tier,
  in_per_mtok_usd, out_per_mtok_usd, cache_read_per_mtok_usd, cache_write_per_mtok_usd,
  supports_cache, supports_streaming, supports_vision, supports_audio, supports_tools,
  context_len, approved, active, quality_score, note, updated_at)
values
  ('anthropic/claude-fable-5.1', 'anthropic', 'xlarge',
   10.00, 50.00, 0.25, 12.50,
   true, true, true, false, true,
   1000000, true, true, null,
   'Founder''s ruling 9 Sep 2026: model A for the CEO seat and the Sales Engineer. 2x the input '
   || 'cost of opus-4.8 and 40x flash-lite, so it belongs only where the founder put it. Cache '
   || 'reads are $0.25/Mtok - 40x cheaper than its own prompt price and the cheapest cache read in '
   || 'the fleet - so a stable system prefix is worth keeping. Does NOT advertise tool_choice; its '
   || 'own fallback gpt-6-astra does.',
   now()),
  ('openai/gpt-6-astra', 'openai', 'xlarge',
   10.00, 50.00, 1.00, 12.50,
   true, true, true, false, true,
   1050000, true, true, null,
   'Founder''s ruling 9 Sep 2026: model B, the fallback for the CEO seat and the Sales Engineer '
   || '("in case A went off"). First openai/ row in this registry. WATCH THE LONG-CONTEXT '
   || 'OVERRIDE: OpenRouter prices a prompt above 272,000 tokens at $20/Mtok in and $75/Mtok out - '
   || 'double - and this table has no column for a tiered rate, so ai_cost_log will UNDERSTATE any '
   || 'call that crosses that line. No task class below is near it (largest max_tokens is 2,500).',
   now())
on conflict (model_id) do update set
  provider = excluded.provider, tier = excluded.tier,
  in_per_mtok_usd = excluded.in_per_mtok_usd, out_per_mtok_usd = excluded.out_per_mtok_usd,
  cache_read_per_mtok_usd = excluded.cache_read_per_mtok_usd,
  cache_write_per_mtok_usd = excluded.cache_write_per_mtok_usd,
  supports_cache = excluded.supports_cache, supports_streaming = excluded.supports_streaming,
  supports_vision = excluded.supports_vision, supports_audio = excluded.supports_audio,
  supports_tools = excluded.supports_tools,
  context_len = excluded.context_len, approved = excluded.approved, active = excluded.active,
  note = excluded.note, updated_at = now();

-- ── 2. model_rate ────────────────────────────────────────────────────────────────────────────────
-- fn_llm_log prices ai_cost_log from HERE, not from model_registry, and a model missing from this
-- table logs at cost 0 - which is how 247 of 603 rows once billed at zero and the budget halt could
-- not fire for that traffic at all. The conversion is the estate's existing one, found in every
-- current row's own note: 3.6725 AED/USD, 5 Aug 2026. No new FX rate is invented here.
--   in  10.00 * 3.6725 =  36.7250    out 50.00 * 3.6725 = 183.6250
--   fable cache read  0.25 * 3.6725 =  0.918125   write 12.50 * 3.6725 = 45.906250
--   astra cache read  1.00 * 3.6725 =  3.672500   write 12.50 * 3.6725 = 45.906250
insert into model_rate (
  model, tier, in_aed_per_mtok, out_aed_per_mtok,
  cache_read_aed_per_mtok, cache_write_aed_per_mtok,
  usd_per_m_prompt, usd_per_m_output, id_verified, source_url, verified_at, note)
values
  ('anthropic/claude-fable-5.1', 'xlarge', 36.7250, 183.6250, 0.918125, 45.906250,
   10.00, 50.00, true, 'https://openrouter.ai/api/v1/models', '2026-09-09',
   'Converted at 3.6725 AED/USD, the same rate every other row in this table names. USD prices '
   || 'read from the OpenRouter catalog on 9 Sep 2026 and ALLOWED for this account. Dearest input '
   || 'rate in the fleet: fn_llm_log''s could_be_cheaper comparator will flag every call on it '
   || 'against flash-lite at 40x, which is the flag doing its job - whether the cheap model is good '
   || 'enough for a CEO decision is the founder''s policy call, and he has made it.'),
  ('openai/gpt-6-astra', 'xlarge', 36.7250, 183.6250, 3.672500, 45.906250,
   10.00, 50.00, true, 'https://openrouter.ai/api/v1/models', '2026-09-09',
   'Converted at 3.6725 AED/USD, the same rate every other row in this table names. USD prices '
   || 'read from the OpenRouter catalog on 9 Sep 2026 and ALLOWED for this account. These are the '
   || 'BASE rates; OpenRouter doubles them above a 272,000-token prompt and this table cannot '
   || 'express a tiered rate, so a call that long would be under-billed.')
on conflict (model) do update set
  tier = excluded.tier,
  in_aed_per_mtok = excluded.in_aed_per_mtok, out_aed_per_mtok = excluded.out_aed_per_mtok,
  cache_read_aed_per_mtok = excluded.cache_read_aed_per_mtok,
  cache_write_aed_per_mtok = excluded.cache_write_aed_per_mtok,
  usd_per_m_prompt = excluded.usd_per_m_prompt, usd_per_m_output = excluded.usd_per_m_output,
  id_verified = excluded.id_verified, source_url = excluded.source_url,
  verified_at = excluded.verified_at, note = excluded.note;

-- ── 3. model_policy - the two seats ──────────────────────────────────────────────────────────────
-- WHICH CLASSES THESE SEATS ACTUALLY USE. Read before writing: ceo_agent/index.ts and
-- sales_engineer/index.ts make NO model call today, so nothing maps them in fn_task_class and none
-- of the 73 rows there names either function. Two of the four classes below already existed and are
-- named for exactly this work; two are created because the work is real and had nowhere to route.
--
--   ceo_strategic_planning     EXISTS. "Quarterly priorities and capital allocation." The CEO seat's
--                              own class. Retargeted.
--   ceo_approval_decision      CREATED. The founder's ruling of 8 Sep - "all approvals are from CEO,
--                              nothing goes to me" - made every approval this seat's judgement, and
--                              ceo_agent's `decide` action is live and refuses a decision with less
--                              than a sentence of rationale. There is no class for it:
--                              chief_of_staff_decision belongs to the retired Chief of Staff path
--                              (dept_plan, founder_directive, intent_router, orchestrate,
--                              secretary_act) and routing the CEO through it would put his
--                              approvals on somebody else's policy.
--   customer_portal_assistant  EXISTS. "The assistant a SIGNED-IN customer or supplier talks to."
--                              That is precisely sales_engineer's `assist` action under the
--                              founder's 9 Sep ruling - "if its on the home page then the support
--                              replies. but if its on the customer or supplier portal then its the
--                              sales engineer". Retargeted. visitor_chat, the PUBLIC widget, stays
--                              Support's and is untouched.
--   sales_engineer_reasoning   CREATED, and NOT speculative - it repairs a live override. The seat
--                              carries org_agents.routing_tier = 'operations_specialist', and
--                              fn_ai_route has a branch that rewrites task_class 'agent_reasoning'
--                              to 'routine_employee_reasoning' for exactly that routing_tier. So
--                              had this seat simply reused agent_reasoning, the founder's "he needs
--                              to be extremely smart" would have been silently downgraded to
--                              google/gemini-3.5-flash at the medium tier. A class of its own is
--                              what makes the ruling hold.
--
-- No fifth class. drawing_and_boq_analysis, quote_comparison, document_extraction and the rest are
-- shared marketplace classes with existing high-volume callers (drawing_boq, quote_compare,
-- doc_extract); moving them to a $10/Mtok model because one seat also touches that work would be a
-- 5-20x bill on traffic the founder did not rule on.
--
-- max_tokens is never 0 on any row here. 17 existing rows carry 0, and `??` in the gateway does not
-- treat 0 as absent, so maxTok computes to 0 - a call that can emit nothing.

update model_policy set
  tier = 'xlarge',
  model_primary = 'anthropic/claude-fable-5.1',
  model_fallback = 'openai/gpt-6-astra',
  rationale = 'Quarterly priorities and capital allocation. Founder, 9 Sep 2026: "for the CEO we '
    || 'didnt select before and it will be fable 5.1 as A and gpt 6 Astra as B". Was '
    || 'anthropic/claude-sonnet-5 -> anthropic/claude-opus-4.8 at the large tier.'
where task_class = 'ceo_strategic_planning';

update model_policy set
  tier = 'xlarge',
  model_primary = 'anthropic/claude-fable-5.1',
  model_fallback = 'openai/gpt-6-astra',
  rationale = 'The assistant a SIGNED-IN customer or supplier talks to, answering from their own '
    || 'live rows. The Sales Engineer seat owns both portals (founder, 9 Sep 2026: "if its on the '
    || 'home page then the support replies. but if its on the customer or supplier portal then its '
    || 'the sales engineer"), and he gets the CEO''s pair "since he need to be extremely smart". '
    || 'Was anthropic/claude-sonnet-5 -> anthropic/claude-opus-4.8 at the large tier. The PUBLIC '
    || 'widget is visitor_chat and belongs to customer support, which is settled and untouched.'
where task_class = 'customer_portal_assistant';

insert into model_policy (task_class, tier, model_primary, model_fallback, max_tokens,
                          cache_ttl_min, active, deterministic_alternative, rationale)
values
  ('ceo_approval_decision', 'xlarge',
   'anthropic/claude-fable-5.1', 'openai/gpt-6-astra', 1500, 0, true,
   'The authority ceiling itself is deterministic and stays that way: fn_check_authority, '
   || 'org_authority and decision_policy decide whether this seat MAY decide, and the guards on '
   || 'public.refunds refuse money moving except through a ceo_approval row. The model weighs the '
   || 'case and writes the rationale; it never sets the limit and never posts the money.',
   'The CEO deciding one approval on the record - a refund, an exception, a commitment - and '
   || 'writing the rationale ceo_agent''s `decide` action refuses to accept without. Founder, 8 Sep '
   || '2026: "all approvals are from CEO. nothing goes to me." Founder, 9 Sep 2026: fable 5.1 as A, '
   || 'gpt 6 Astra as B. Not chief_of_staff_decision: that class belongs to the retired Chief of '
   || 'Staff functions and its policy is not this seat''s to inherit.'),
  ('sales_engineer_reasoning', 'xlarge',
   'anthropic/claude-fable-5.1', 'openai/gpt-6-astra', 2500, 0, true,
   'Retrieval first, always. fn_sales_assist reads seven corpora under a 0.86 cosine floor with '
   || 'lexical corroboration and records a gap plus an org_tasks row when nothing clears; '
   || 'obligations are a set difference over a field catalogue; arithmetic, units, permissions and '
   || 'state transitions are code. The model is for interpreting a drawing and weighing conflicting '
   || 'evidence - the half deterministic code cannot do.',
   'The Sales Engineer reasoning over technical scope, supplier capability evidence and quote '
   || 'readiness. Founder, 9 Sep 2026: "for the sales Engineer its same as the CEO since he need to '
   || 'be extremely smart." A CLASS OF ITS OWN IS THE POINT: org_agents.routing_tier for '
   || 'sales_engineer is "operations_specialist", and fn_ai_route rewrites task_class '
   || '"agent_reasoning" to "routine_employee_reasoning" for that routing_tier - so reusing '
   || 'agent_reasoning would have routed this seat to google/gemini-3.5-flash at the medium tier '
   || 'and called it the founder''s choice.')
on conflict (task_class) do update set
  tier = excluded.tier,
  model_primary = excluded.model_primary, model_fallback = excluded.model_fallback,
  max_tokens = excluded.max_tokens, cache_ttl_min = excluded.cache_ttl_min,
  active = excluded.active,
  deterministic_alternative = excluded.deterministic_alternative,
  rationale = excluded.rationale;

-- ── 4. A FALLBACK IDENTICAL TO THE PRIMARY IS NOT A FALLBACK ─────────────────────────────────────
-- Five active classes carry model_primary = model_fallback. Two of them are FINE and are left
-- exactly as they are: money_state_change and workflow_state_and_permissions are tier 'none' with
-- both fields set to the literal 'none', which is deterministic-by-design - fn_ai_route returns
-- use_llm=false before either field is ever read.
--
-- The other three are real. In each case the alternate below is read off the tiering this estate
-- already uses, not invented:
--   executive_report / legal_analysis  large, sonnet-5 -> sonnet-5. Every OTHER large class
--     (agent_reasoning, ceo_strategic_planning as it stood, chief_of_staff_decision,
--     contract_analysis, edge_case_escalation) escalates sonnet-5 -> anthropic/claude-opus-4.8, the
--     one xlarge model registered before today. Both rows' own rationales name
--     "anthropic/claude-opus-5" as the escalation, and opus-5 IS NOT IN model_registry - setting it
--     would hand both classes straight to the silent substitution this file exists to prevent.
--   json_extraction_text  small, flash-lite -> flash-lite. Every other small class
--     (category_classification, intent_detection, json_extraction, memory_retrieval, ocr_cleanup,
--     health_ping) falls back to qwen/qwen3.7-plus, whose registry note says in as many words:
--     "Used as the small-tier fallback." Its own rationale names deepseek/deepseek-v4-flash, which
--     is likewise absent from model_registry.
update model_policy set
  model_fallback = 'anthropic/claude-opus-4.8',
  rationale = coalesce(rationale, '') || ' [9 Sep 2026: fallback was anthropic/claude-sonnet-5, '
    || 'identical to the primary, so escalation returned the same model. Set to the registered '
    || 'xlarge model every other large class escalates to. The rationale above names opus-5, which '
    || 'is not in model_registry and would have been silently substituted.]'
where task_class in ('executive_report', 'legal_analysis')
  and active and model_primary = model_fallback;

update model_policy set
  model_fallback = 'qwen/qwen3.7-plus',
  rationale = coalesce(rationale, '') || ' [9 Sep 2026: fallback was '
    || 'google/gemini-3.1-flash-lite, identical to the primary, so escalation returned the same '
    || 'model. Set to the registered small-tier fallback every other small class uses. The '
    || 'rationale above names deepseek-v4-flash, which is not in model_registry.]'
where task_class = 'json_extraction_text'
  and active and model_primary = model_fallback;

commit;
