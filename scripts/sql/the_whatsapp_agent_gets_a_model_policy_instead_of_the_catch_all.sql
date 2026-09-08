-- THE WHATSAPP AGENT GETS A MODEL POLICY INSTEAD OF THE CATCH-ALL
--
-- The founder, 8 September 2026: "gemini flash 3 is plan A, claude sonnet 5 is plan B."
--
-- WHAT IT WAS RUNNING ON, MEASURED BEFORE CHANGING IT. fn_ai_route('wa_inbound') answered:
--
--   "Safe default for anything unmapped. Medium tier so an unclassified caller degrades gracefully
--    rather than silently getting the cheapest or the dearest model. [no policy for "wa_inbound",
--    fell back to general_drafting]"   -> ~anthropic/claude-haiku-latest, fallback claude-sonnet-5
--
-- So the agent that handles every customer and supplier conversation had no routing rule of its
-- own. It was not misconfigured -- it was unconfigured, answering on a catch-all written for
-- callers nobody had got round to classifying. That is worth naming, because a default that
-- degrades gracefully is exactly the kind of thing nobody investigates.
--
-- WHY flash-lite AND NOT 3.5-flash, asked for as "the most affordable yet capable".
--
-- The decision is made on the MEASURED shape of this workload, not on list prices. 71 real calls in
-- llm_calls average 3077 prompt tokens and 121 output tokens -- a 25:1 ratio, because the system
-- prompt carries the company facts and the reply is a WhatsApp message. Input price therefore
-- dominates almost completely, and ranking models by their headline output price gets it backwards.
--
-- At that shape, per reply:
--     $0.00095   google/gemini-3.1-flash-lite
--     $0.00114   qwen/qwen3.7-plus              (no vision -- disqualified, see below)
--     $0.00368   ~anthropic/claude-haiku-latest  3.9x
--     $0.00570   google/gemini-3.5-flash         6.0x
--     $0.00736   anthropic/claude-sonnet-5       7.7x
--
-- flash-lite is SIX TIMES cheaper than 3.5-flash for the same capability profile that matters here:
-- vision, audio, tools/JSON and a million-token context. It is not a reduced version of Flash on
-- any axis this seat uses.
--
-- qwen is nominally close on price and is disqualified on capability, not cost: supports_vision is
-- false. A supplier photographs a trade licence and sends it on WhatsApp; a model that cannot see
-- it is not cheaper, it is unable.
--
-- WHAT THIS COSTS AGAINST WHAT IT REPLACES. The catch-all was Haiku at $1/$5, so this is a genuine
-- reduction -- roughly a quarter of the cost per reply, about $0.95 per thousand conversations
-- against $3.68.
--
-- THE HONEST LIMITATION. flash-lite is the small tier, and the register's own note describes it as
-- the default for "classification and extraction" -- mechanical work. Conversational nuance with an
-- annoyed customer is exactly where a small model is weakest, and the Sonnet fallback does NOT
-- cover that: a fallback fires on failure, not on a reply that arrives and is merely poor. Two
-- things reduce the exposure -- the approved FAQ corpus answers the common questions with no model
-- at all, and every fact-bearing message (quotation alerts, invoices, licence reminders) is
-- deterministic text the model never writes. What is left for the model is interpretation. If the
-- quality is not there, llm_calls will show it and the primary moves up one tier.
--
-- Sonnet 5 as plan B is the same fallback the catch-all already had, so a Gemini outage degrades to
-- exactly what the agent has been running on all along.
--
-- ONE THING THIS DOES NOT CHANGE. wa_inbound asks the gateway for strict JSON
-- ({reply,lang,audience,escalate}); both models support tools and structured output, and the
-- parser already treats a non-JSON answer as prose rather than an error, so a model that returns a
-- sentence degrades to a reply instead of a failure.

insert into public.model_policy
  (task_class, tier, model_primary, model_fallback, max_tokens, rationale, deterministic_alternative, active, cache_ttl_min)
values
  ('wa_inbound', 'small', 'google/gemini-3.1-flash-lite', 'anthropic/claude-sonnet-5', 900,
   'The customer-support agent on WhatsApp. Founder''s routing, 8 Sep 2026: a Gemini Flash primary with Claude Sonnet 5 as fallback, then "pick the most affordable yet capable model". Chosen on the measured shape of 71 real calls (3077 prompt / 121 output tokens), where input price dominates: flash-lite is 6x cheaper per reply than 3.5-flash with the same vision, audio, tools and 1M context. Previously unmapped and running on the general_drafting catch-all (Haiku), which is how the seat handling every customer conversation ended up on a default nobody chose. Vision matters here: suppliers photograph trade licences and send them on WhatsApp.',
   'The approved FAQ corpus answers first with no model at all (try_faq), and the anonymity scan, the 24-hour window and every notification body are deterministic. The model is used for interpretation, never for a fact.',
   true, 0)
on conflict (task_class) do update
  set tier = excluded.tier,
      model_primary = excluded.model_primary,
      model_fallback = excluded.model_fallback,
      max_tokens = excluded.max_tokens,
      rationale = excluded.rationale,
      deterministic_alternative = excluded.deterministic_alternative,
      active = true,
      cache_ttl_min = excluded.cache_ttl_min;
