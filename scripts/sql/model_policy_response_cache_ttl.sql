-- ================================================================================================
-- ROW #8 §7/§32 — the response cache was complete, correct, and switched off by a default.
--
-- ── THE MEASUREMENT THAT ORDERED THIS ───────────────────────────────────────────────────────────
-- Production, 2026-08-09: llm_cache holds 0 rows against 1,021 logged AI calls, and 2 of those
-- 1,021 were served from cache. The obvious reading is "the cache was never built". It was:
--
--     llm_cache             12 columns, including a semantic `embedding_gte`
--     fn_llm_cache_get / _lookup / _put / _store            all four present
--     ai_gateway/index.ts   exact-hash lookup at line 250, store at line 455, semantic
--                           similarity floor of 0.95, and deliberate exclusions for tool-calling
--                           turns and base64 blobs, each with a written reason
--
-- All of it works. Line 241 is why none of it runs:
--
--     const cacheable = Number(body.cache_ttl_min ?? 0) > 0 && !hasBinary && !(body.tools?.length);
--
-- `cache_ttl_min` is a CALLER-supplied field with no default, and no caller supplies it. So
-- `cacheable` is false on every request, the lookup never fires, the store never fires, and the
-- table stays empty. A complete cache, disabled by a `?? 0`.
--
-- ── WHY THE TTL BELONGS ON THE POLICY AND NOT ON THE CALLER ─────────────────────────────────────
-- Whether a response may be replayed is a property of the TASK CLASS, not of the call site. Asking
-- every caller to know it is how it ended up being answered by nobody. `model_policy` already
-- decides the tier, the model, the fallback and the token ceiling per task class; the cache TTL is
-- the same kind of decision and belongs beside them.
--
-- ── THE SET IS DELIBERATELY CONSERVATIVE, AND HERE IS THE RULE ──────────────────────────────────
-- A response may be cached only when it is a FUNCTION OF THE INPUT TEXT ALONE. If the answer
-- depends on anything that can change while the cache entry is alive — live figures, a corpus, the
-- web, the clock — replaying it serves a stale answer to a real customer, and that is a worse
-- outcome than paying for the call.
--
--   ENABLED (24h):
--     json_extraction          extract structure from the text you were given. 216 calls, 100%.
--     category_classification  classify the text you were given.
--     intent_detection         classify the text you were given.
--     ocr_cleanup              tidy the text you were given.
--
--   DELIBERATELY LEFT AT 0, each for a reason:
--     agent_reasoning          reasons over live numbers. A cached answer is a wrong answer.
--     chief_of_staff_decision  same.
--     knowledge_research       web-grounded and time-sensitive.
--     memory_retrieval         retrieves over a corpus that grows; a cached hit MISSES new
--                              knowledge, which is the one failure mode a knowledge base must not
--                              have. Tempting at 183 calls and 100% success — still no.
--     *_drafting               variety in the output is a feature, not a defect to cache away.
--
-- Extending this list is a deliberate act with the rule above to test against, which is the point
-- of putting it in a column rather than in an edge function's default.
--
-- ── WHAT THIS WILL NOT DO ───────────────────────────────────────────────────────────────────────
-- It will not fill the cache by itself. The exact-hash key covers model + max_tokens + system
-- prompt + conversation, so it only hits on a genuine repeat; the semantic path at 0.95 similarity
-- is what catches near-repeats. Whether that produces a high hit rate depends on how repetitive
-- real traffic turns out to be, and that is a measurement to take next session, not a claim to make
-- now. What changes today is that the cache is reachable at all.
-- ================================================================================================

alter table public.model_policy
  add column if not exists cache_ttl_min integer not null default 0;

comment on column public.model_policy.cache_ttl_min is
  'Minutes a RESPONSE for this task class may be replayed from llm_cache. 0 = never cache. '
  'Set non-zero ONLY where the answer is a function of the input text alone: anything that reads '
  'live figures, a growing corpus, the web or the clock must stay 0, because a replayed answer '
  'there is a stale answer served to a real customer. Distinct from model_registry.supports_cache, '
  'which is the provider''s PROMPT-PREFIX cache and a different mechanism entirely.';

update public.model_policy
   set cache_ttl_min = 1440
 where active
   and task_class in ('json_extraction', 'category_classification', 'intent_detection', 'ocr_cleanup');
