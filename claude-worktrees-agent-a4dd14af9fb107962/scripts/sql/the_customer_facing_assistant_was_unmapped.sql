-- THE CUSTOMER-FACING ASSISTANT WAS UNMAPPED, SO IT QUIETLY GOT THE CHEAPEST MODEL
--
-- MEASURED, not inferred. Two queries on production, 13 Aug 2026:
--
--   select fn_ai_route('site_assistant', null, null, null);
--     -> "UNMAPPED function \"site_assistant\" - defaulted to general_drafting (medium)"
--        model ~anthropic/claude-haiku-latest
--
--   select model_used, count(*), max(created_at) from llm_calls where fn='site_assistant' group by 1;
--     -> anthropic/claude-sonnet-5            55   last 2026-07-26 14:17
--     -> ~anthropic/claude-haiku-latest        4   last 2026-08-13 01:05
--     -> null                                  1        2026-08-13 01:05   (a level0 FAQ answer)
--
-- The only surface a paying customer talks to was moved onto the cheapest medium-tier model by a
-- MISSING ROW, and nothing reported it, because falling back is not failing. `visitor_chat` has
-- existed in model_policy the whole time and nothing routed to it — a task class with no caller is
-- the same defect as a function with no class.
--
-- TWO CLASSES, BECAUSE THEY ARE TWO DIFFERENT JOBS.
--
--   visitor_chat               an anonymous visitor asking what QuotesDone is and what it costs.
--                              FAQ-shaped, answerable at level 0 most of the time, high volume,
--                              zero account data. Stays medium. Unchanged - this row only makes the
--                              existing intent explicit so it stops reporting as UNMAPPED.
--
--   customer_portal_assistant  a SIGNED-IN customer or supplier asking about their own requests,
--                              their own quotes and their own money, answered from live rows that
--                              fn_wa_context scoped to them in SQL. Getting this wrong is not a
--                              worse paragraph, it is a wrong statement about someone's account.
--                              Large tier.
--
-- ON THE COST, SINCE IT IS THE ONE THING HE ASKED TO BE TOLD ABOUT: the large tier applies ONLY
-- when a verified session is present. The whole signed-in population today is 2 customers and 1
-- supplier, and site_assistant has logged 88 messages in 33 days across ALL visitors. Anonymous
-- traffic - the volume - is untouched on the medium tier with level-0 FAQ answering still enabled.
--
-- cache_ttl_min is 0 on both, and on customer_portal_assistant that is a privacy control rather
-- than a tuning choice: the gateway's semantic cache keys on an embedding of the first 400 chars of
-- the system prompt plus the conversation at 0.95 similarity, and a prompt carrying one customer's
-- account data is otherwise a prompt that can be matched by another customer's.

insert into public.model_policy
  (task_class, tier, model_primary, model_fallback, max_tokens, rationale, deterministic_alternative, active, cache_ttl_min)
values
  ('customer_portal_assistant', 'large', 'anthropic/claude-sonnet-5', 'anthropic/claude-opus-4.8', 1200,
   'The assistant a SIGNED-IN customer or supplier talks to, answering from their own live rows (fn_wa_context). It states facts about a person''s requests, quotes and verification state, so a cheap approximation is a wrong statement about their account rather than a clumsier sentence. Large tier, and cache_ttl_min 0 because the prompt carries one person''s data.',
   null, true, 0)
on conflict (task_class) do update set
  tier = excluded.tier, model_primary = excluded.model_primary, model_fallback = excluded.model_fallback,
  max_tokens = excluded.max_tokens, rationale = excluded.rationale, active = true, cache_ttl_min = 0;

-- site_assistant chooses its class per call now (visitor_chat when anonymous,
-- customer_portal_assistant when a verified session is present), and a caller-supplied task_class
-- wins in fn_ai_route. This row is the floor under that: if the function ever stops passing one,
-- it lands on the class that was written for it instead of reporting UNMAPPED and taking whatever
-- general_drafting happens to point at.
insert into public.fn_task_class (fn, task_class, active)
values ('site_assistant', 'visitor_chat', true)
on conflict (fn) do update set task_class = excluded.task_class, active = true;
