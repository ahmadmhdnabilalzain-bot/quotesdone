-- EVERY CONVERSATION REPLY RUNS ON SONNET 5.5, WITH GEMINI BEHIND IT.
-- Seat: sales_engineer. 13 Oct 2026. Founder ruling 1219: customer chat runs on anthropic/claude-sonnet-5.5 on
-- OpenRouter (it ran on openai/gpt-6-luna since matrix v2, 5 Oct 2026).
--
-- WHAT MOVES - the classes an AI-written conversation reply is routed by, and nothing else:
--   conversation_reply                  NEW. Every reply written by _shared/ai_reply.ts aiReply(): WhatsApp (#1335,
--                                       wa_inbound/model_says.ts), support_reply, the supplier portal's quotation chat
--                                       (supplier_api), the e-mail auto-reply (email_triage), reasoned_delivery and the
--                                       social inbox. It used taskClassFor() = customer_communication / supplier_
--                                       communication, which think() ALSO uses for trade decisions and Arabic
--                                       translation, so those two classes stay on luna and the replies get their own.
--   visitor_chat                        the homepage widget (site_assistant, signed out; _shared/brief_answer.ts)
--   customer_portal_assistant           the customer and supplier portal assistant (site_assistant, signed in). Also the
--                                       fn default of customer_api and messages_api, whose model calls all name a class.
--   inquiry_qualification_conversation  the inquiry intake's conversation turn (inquiry_intake, one call writes the
--                                       customer's reply and the brief)
-- Each runs anthropic/claude-sonnet-5.5 > google/gemini-3.8-flash (the backup the chat classes already had).
-- Judgements, extraction, translation, reviews, the CEO and every other class stay on matrix v2.
--
-- THE MODEL (OpenRouter catalogue, read 13 Oct 2026 00:20 UTC): anthropic/claude-sonnet-5.5, USD 2.00 in / 10.00 out
-- per Mtok, cache read 0.10, cache write 2.50 (5-minute tier), context 1,000,000, input text+image+file. It was not in
-- model_registry, so it is registered here; supports_cache true is what makes ai_gateway mark the brief (sys_stable)
-- with Anthropic cache_control, which is the ruling's cost basis (about USD 14.6 per 1,000 replies).
-- tier 'large', like claude-sonnet-5: fn_ai_route's confidence downgrade takes the cheapest MEDIUM row, never this.
--
-- REVIEWS STAY CROSS-FAMILY with no change: an author on Sonnet (Anthropic) is reviewed by knowledge_validation's
-- Gemini; ceo_judgement's Opus is the author's family, so fn_ai_route_review_for takes its fallback luna.
--
-- Applied at merge only. No transaction lines: apply_sql.mjs runs the file as one transaction.
-- Proved by every_seat_runs_the_founders_model_matrix_probe.sql (route 'chat') replayed after this file.

-- 1. The model, registered at the catalogue's price.
insert into public.model_registry
  (model_id, provider, tier, in_per_mtok_usd, out_per_mtok_usd,
   cache_read_per_mtok_usd, cache_write_per_mtok_usd, supports_cache, supports_streaming,
   context_len, approved, active, quality_score, supports_vision, supports_audio, supports_tools, note)
values
  ('anthropic/claude-sonnet-5.5', 'anthropic', 'large', 2.00, 10.00,
   0.10, 2.50, true, true, 1000000, true, true, null, true, false, true,
   'Founder ruling 1219 (13 Oct 2026): every AI-written conversation reply. OpenRouter 13 Oct 2026: $2.00/$10.00 per '
   || 'Mtok, cache read $0.10, cache write $2.50, 1,000,000 context, input text+image+file, no audio. supports_cache '
   || 'true: ai_gateway sends the company brief as an Anthropic cache_control block.')
on conflict (model_id) do update set
  provider = excluded.provider, tier = excluded.tier,
  in_per_mtok_usd = excluded.in_per_mtok_usd, out_per_mtok_usd = excluded.out_per_mtok_usd,
  cache_read_per_mtok_usd = excluded.cache_read_per_mtok_usd, cache_write_per_mtok_usd = excluded.cache_write_per_mtok_usd,
  supports_cache = true, supports_streaming = true, context_len = excluded.context_len,
  approved = true, active = true, supports_vision = excluded.supports_vision,
  supports_audio = excluded.supports_audio, supports_tools = excluded.supports_tools,
  note = excluded.note, updated_at = now();

-- 2. Its breaker row: fn_ai_route_review_for treats an unmeasured model as unhealthy. Closed, the fleet's thresholds.
insert into public.llm_route_health (model_id, consecutive_failures, failure_threshold, cooldown_seconds, open_until, opened_reason)
select 'anthropic/claude-sonnet-5.5', 0, 3, 300, null, null
where not exists (select 1 from public.llm_route_health h where h.model_id = 'anthropic/claude-sonnet-5.5');

-- 3. The new class every aiReply() reply names.
insert into public.model_policy (task_class, tier, model_primary, model_fallback, max_tokens, rationale, deterministic_alternative, active, cache_ttl_min)
values ('conversation_reply', 'medium', 'anthropic/claude-sonnet-5.5', 'google/gemini-3.8-flash', 4000,
  '13 Oct 2026, founder ruling 1219: every AI-written conversation reply (_shared/ai_reply.ts) runs on anthropic/claude-sonnet-5.5 '
  || 'with google/gemini-3.8-flash behind it; the company brief rides as the cached system block (sys_stable).',
  'Code checks every figure, policy claim and identity in the reply and has the model rewrite it; code writes no reply text.', true, 0)
on conflict (task_class) do update set tier = excluded.tier, model_primary = excluded.model_primary,
  model_fallback = excluded.model_fallback, max_tokens = excluded.max_tokens, rationale = excluded.rationale,
  deterministic_alternative = excluded.deterministic_alternative, active = true, cache_ttl_min = 0;

-- 4. The three chat classes that already exist.
update public.model_policy
   set model_primary = 'anthropic/claude-sonnet-5.5', model_fallback = 'google/gemini-3.8-flash',
       rationale = '13 Oct 2026, founder ruling 1219: every AI-written conversation reply runs on anthropic/claude-sonnet-5.5 '
                   || 'with google/gemini-3.8-flash behind it; the brief is cached in the prompt. Before: '
                   || model_primary || ' > ' || coalesce(model_fallback, 'none') || '.'
 where active
   and task_class in ('visitor_chat', 'customer_portal_assistant', 'inquiry_qualification_conversation');

-- 5. The IT consumer register: a function that thinks through defaultDeps() is a listed consumer of the reply class
--    too (the callers of aiReply are those functions). CREATE OR REPLACE keeps the ACL.
CREATE OR REPLACE FUNCTION public.fn_it_model_consumer_listed(p_fn text, p_class text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select exists (select 1 from public.it_model_consumer c
                  where c.consumer = p_fn || ':' || coalesce(p_class, 'unclassified')
                     or (c.consumer = p_fn || ':think'
                         and p_class in ('agent_reasoning', 'knowledge_validation', 'customer_communication', 'supplier_communication',
                                 'routine_employee_reasoning', 'internal_judgement', 'conversation_reply')))
$function$;
