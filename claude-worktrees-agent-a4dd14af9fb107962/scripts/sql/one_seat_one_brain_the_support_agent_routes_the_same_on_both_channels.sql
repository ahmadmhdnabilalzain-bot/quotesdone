-- ONE SEAT, ONE BRAIN: THE SUPPORT AGENT ROUTES THE SAME ON BOTH CHANNELS
--
-- The founder, 8 September 2026: "just for whatsapp and email. every agent will have different
-- model."
--
-- wa_inbound was given a policy an hour ago. Checking the other half of the same seat found the
-- same hole four more times -- fn_ai_route answers "Safe default for anything unmapped" for every
-- one of them:
--
--   email_triage      -> general_drafting -> ~anthropic/claude-haiku-latest
--   inbound_email     -> general_drafting -> ~anthropic/claude-haiku-latest
--   resend_inbound    -> general_drafting -> ~anthropic/claude-haiku-latest
--   support_ai        -> general_drafting -> ~anthropic/claude-haiku-latest
--
-- So the customer-support agent was unconfigured on BOTH channels, not one. Fixing WhatsApp alone
-- would have left the same seat running a different model depending on which way a customer chose
-- to write in -- and nothing would ever have surfaced that, because the catch-all answers
-- perfectly well.
--
-- WHY THE SAME MODEL ON BOTH. It is one agent. A customer who emails and then sends a WhatsApp is
-- talking to the same seat, and a reply that is sharper on one channel than the other is a defect
-- the customer experiences and no test catches. The channel is transport; the judgement is the
-- agent's.
--
-- AND THE WORK SUITS IT. Three of these four are classification and extraction -- triaging an
-- inbound email, parsing a webhook payload, pulling the sender and intent out of a message -- which
-- is precisely what the register describes flash-lite as the default for. The fourth, support_ai,
-- is the same conversation wa_inbound holds.
--
-- COST, at the measured shape of this workload (3077 prompt / 121 output tokens, from 71 real
-- calls): $0.00095 a reply against $0.00368 on the Haiku catch-all these were using. About a
-- quarter, and the capability that matters here -- vision for a photographed licence, audio for a
-- voice note, tools for the strict JSON envelope, a million tokens of context -- is unchanged.
--
-- Sonnet 5 is plan B throughout, which is what the catch-all already fell back to, so an outage
-- degrades to exactly what these functions have been running on all along.
--
-- WHAT THIS DELIBERATELY DOES NOT TOUCH. Every other task class in model_policy belongs to a seat
-- the founder has not specified yet -- "every agent will have different model". The 40 other rows
-- are left exactly as they are.

insert into public.model_policy
  (task_class, tier, model_primary, model_fallback, max_tokens, rationale, deterministic_alternative, active, cache_ttl_min)
values
  ('support_ai', 'small', 'google/gemini-3.1-flash-lite', 'anthropic/claude-sonnet-5', 900,
   'The customer-support agent answering by email. Same seat as wa_inbound and therefore the same model: a reply that is sharper on WhatsApp than on email is a defect the customer feels and no test catches. Founder''s routing, 8 Sep 2026.',
   'The approved FAQ corpus answers first with no model at all. Every fact-bearing message -- quotation alerts, invoices, licence reminders -- is deterministic text the model never writes.',
   true, 0),
  ('email_triage', 'small', 'google/gemini-3.1-flash-lite', 'anthropic/claude-sonnet-5', 600,
   'Sorting inbound mail into what it is and who it is from. Classification, which is exactly what flash-lite is the register''s default for, and it was running on the unmapped catch-all instead.',
   'Sender matching against leads and customers is a SQL lookup, not a model call. The model is used only where the sender is unknown or the intent is ambiguous.',
   true, 0),
  ('inbound_email', 'small', 'google/gemini-3.1-flash-lite', 'anthropic/claude-sonnet-5', 900,
   'Reading an inbound email into a structured intake -- sender, intent, attachments, whether it belongs to an existing lead. Extraction work, and the 1M context matters because a forwarded thread arrives whole.',
   'Attachment handling, licence parsing and lead matching are deterministic paths (license_extract, fn_support_receive_document). The model reads the prose around them.',
   true, 0),
  ('resend_inbound', 'small', 'google/gemini-3.1-flash-lite', 'anthropic/claude-sonnet-5', 900,
   'The provider webhook that delivers inbound mail. Same parsing job as inbound_email and it was on the same unmapped catch-all.',
   'Signature verification and idempotency are deterministic and must never be a model''s judgement.',
   true, 0),
  -- The founder, 8 Sep 2026: "the customer support agent is basically the chat widget on the
  -- website home page. but once someone logs in either as a customer or supplier that is another
  -- agent which we will build later." So visitor_chat (the site_assistant function, the PUBLIC
  -- widget) is this seat and moves with it; customer_portal_assistant is the SIGNED-IN assistant,
  -- is a different agent, and is deliberately left on Sonnet 5 for whoever builds it.
  --
  -- This is also the only task class currently reaching llm_calls at all, so it is the one row here
  -- where the change is observable in real traffic rather than only in the router.
  ('visitor_chat', 'small', 'google/gemini-3.1-flash-lite', 'anthropic/claude-sonnet-5', 900,
   'The public website chat widget on the home page -- the customer-support agent''s third channel alongside WhatsApp and email, and the same seat, so the same model. A visitor here is anonymous by definition: nothing account-specific can be disclosed, which is the case a small model handles well because the answer comes from approved company knowledge rather than from anyone''s rows. Founder''s scope, 8 Sep 2026.',
   'The approved FAQ corpus answers first with no model at all, and the public facts (3% reveal fee, coverage, minimum job value) are fixed text.',
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
