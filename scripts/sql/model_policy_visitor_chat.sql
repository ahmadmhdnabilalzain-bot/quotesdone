-- visitor_chat is the ONLY purpose in llm_calls over 30 days — 56 calls, every live AI
-- conversation the company actually has with a stranger on the website — and it had no policy
-- of its own. fn_ai_route was answering it with:
--
--     "no policy for \"visitor_chat\", fell back to general_drafting"
--
-- So the one AI path in production that a real human talks to was the unrouted one, served by
-- the catch-all, invisible to any per-class cost or quality measurement.
--
-- Deliberately IDENTICAL to what general_drafting resolves to today — ~anthropic/claude-haiku-latest,
-- medium tier, 900 max tokens, sonnet-5 fallback — so this changes no behaviour at all. It only
-- makes the route explicit, so it can be measured and tuned as itself rather than as "everything
-- unmapped". Verified before and after: fn_ai_route('visitor_chat') returns the same model, tier
-- and token budget, and stops reporting a fallback.
insert into model_policy
  (task_class, tier, model_primary, model_fallback, max_tokens, rationale,
   deterministic_alternative, active, cache_ttl_min)
values
  ('visitor_chat','medium','~anthropic/claude-haiku-latest','anthropic/claude-sonnet-5',900,
   'The public website chat: the only purpose reaching llm_calls in 30 days and a real person is '
   'on the other end, so tone and accuracy are customer-visible. Set identical to the '
   'general_drafting catch-all it was already falling back to, so naming it changed nothing; '
   'tune it here now that it is measurable on its own.',
   'FAQ/template answers for known questions before any model call',
   true, 0)
on conflict (task_class) do nothing;
