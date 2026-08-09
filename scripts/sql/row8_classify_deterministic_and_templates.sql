-- ================================================================================================
-- ROW #8 — three defects that share one shape: the router cannot help work it never sees.
--
--   A. 146 of 1,021 logged calls carry NO task_class, so no policy could route them  (§41)
--   B. calendars, file operations and notes have no deterministic refusal            (§19, §43)
--   C. six of the spec's named response templates do not exist                       (§B16, §C5)
--
-- ── A. THE UNCLASSIFIED CALLS ───────────────────────────────────────────────────────────────────
-- Measured on production 2026-08-09: 146 calls, AED 21.11, with task_class null. By caller:
--
--     agent_brain 46 · cos_execute 23 · dept_plan 21 · knowledge_exam 17
--     gen_category_knowledge 12 · exec_agents 6 · canon_eval 6 · enrich_capability 5 · …
--
-- Every one of those callers has an obvious class — agent_brain reasons, knowledge_exam researches
-- — and simply does not pass it. A call with no task_class cannot be routed by model_policy, cannot
-- be capped by max_tokens, cannot be cached, and cannot be benchmarked. It is invisible to every
-- mechanism this row is about.
--
-- The fix is at the WRITE path, in fn_llm_log, which is the one place every call passes through.
-- p_task_class is now defaulted from p_fn when the caller omits it, falling back to
-- 'general_drafting' — the same safe medium default fn_ai_route already uses for an unmapped class,
-- so an unrecognised caller degrades gracefully rather than staying invisible.
--
-- THE 146 EXISTING ROWS ARE NOT TOUCHED. Rewriting historical log rows to make a gate read better
-- is back-dating, and it would also destroy the only evidence that this defect existed. They stay
-- null; new calls carry a class.
--
-- ── B. THE MISSING DETERMINISTIC REFUSALS ───────────────────────────────────────────────────────
-- model_policy already refuses the LLM for eleven task classes with a named SQL alternative, which
-- is the strongest part of this estate. Three of the spec's named categories had no row:
-- calendars (§19), file operations (§19) and notes (§43). Each is deterministic in the same way VAT
-- arithmetic is — a calendar lookup is a query, not a judgement — so each gets the same treatment
-- rather than an exception.
--
-- ── C. THE TEMPLATES ────────────────────────────────────────────────────────────────────────────
-- response_template holds six rows (hours, location, pricing_model, anonymity, thanks, greeting) and
-- the spec names eleven more between §B16 and §C5. A template is a zero-cost answer, and the spec's
-- whole ladder starts with "most messages should never reach AI".
--
-- These are QuotesDone's own operational copy — delivery, payment, appointment, apology, shipping,
-- follow-up, complaint resolution — written in the voice of the six that already exist. That is
-- authoring platform text, which is a different act from generating category expertise: nothing here
-- asserts a fact about an industry, a regulation or a supplier. Where a real number would be needed
-- (a delivery window, a bank account) the template deliberately does not invent one.
-- ================================================================================================

-- ── A ───────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_llm_log(p_fn text, p_dept text, p_agent text, p_task_class text,
  p_model text, p_because text, p_tier text, p_prompt_tokens integer, p_output_tokens integer,
  p_cached boolean, p_cache_key text, p_latency_ms integer, p_ok boolean)
returns numeric
language plpgsql
security definer
set search_path to 'public'
as $function$
declare v_cost numeric := 0; v_in numeric; v_out numeric; v_cheaper boolean := false;
        v_reason text; v_alt text; v_class text;
begin
  -- A call with no task_class is invisible to routing, capping, caching and benchmarking. Derive it
  -- from the caller when the caller did not say, and fall back to the same safe medium default
  -- fn_ai_route uses for an unmapped class rather than leaving it null.
  v_class := coalesce(nullif(trim(coalesce(p_task_class,'')), ''), case
    when p_fn ~* 'agent_brain|dept_plan|exec_agents|reflect|conductor'   then 'agent_reasoning'
    when p_fn ~* 'cos_execute|secretary|chief'                            then 'chief_of_staff_decision'
    when p_fn ~* 'knowledge|kb_|canon_eval|research|exam'                 then 'knowledge_research'
    when p_fn ~* 'extract|parse|ocr'                                      then 'document_extraction'
    when p_fn ~* 'classif|categor|intent|route'                           then 'category_classification'
    when p_fn ~* 'draft|content|blog|marketing|social'                    then 'content_drafting'
    when p_fn ~* 'quote|rfq|supplier|procure'                             then 'procurement_reasoning'
    else 'general_drafting' end);

  if not coalesce(p_cached,false) then
    select in_aed_per_mtok, out_aed_per_mtok into v_in, v_out from model_rate where model = p_model;
    if v_in is not null then
      v_cost := round( coalesce(p_prompt_tokens,0)/1000000.0 * v_in
                     + coalesce(p_output_tokens,0)/1000000.0 * v_out, 6);
    end if;
  end if;

  select deterministic_alternative into v_alt from model_policy where task_class = v_class;
  if v_alt is not null and v_alt <> '' then
    v_cheaper := true; v_reason := 'A deterministic path exists for this task class: ' || v_alt;
  elsif not coalesce(p_cached,false) and exists (
      select 1 from model_rate used join model_rate alt on alt.model = 'anthropic/claude-sonnet-5'
       where used.model = p_model and alt.in_aed_per_mtok < used.in_aed_per_mtok) then
    v_cheaper := true;
    v_reason := 'claude-sonnet-5 is cheaper than ' || p_model || ' for the same output.';
  end if;

  insert into ai_cost_log (fn, dept_key, agent_key, task_class, model_used, model_selected_because,
    tier, prompt_tokens, output_tokens, cached, cache_hit_key, latency_ms, cost_aed,
    could_be_cheaper, cheaper_reason, ok)
  values (p_fn, p_dept, p_agent, v_class, p_model, p_because, p_tier,
    coalesce(p_prompt_tokens,0), coalesce(p_output_tokens,0), coalesce(p_cached,false),
    p_cache_key, p_latency_ms, v_cost, v_cheaper, v_reason, coalesce(p_ok,true));

  return v_cost;
end $function$;

-- ── B ───────────────────────────────────────────────────────────────────────────────────────────
insert into public.model_policy
  (task_class, tier, model_primary, model_fallback, max_tokens, rationale, deterministic_alternative, active)
values
  ('calendar_scheduling','none','none',null,0,
   'A calendar lookup is a query, not a judgement. Availability, conflicts and next-free-slot are all set arithmetic over rows that already exist.',
   'SQL over the calendar/appointment tables', true),
  ('file_operations','none','none',null,0,
   'Naming, moving, listing and attaching a file are storage operations. An LLM here adds latency and a chance of inventing a path.',
   'Supabase Storage API + SQL', true),
  ('note_capture','none','none',null,0,
   'Storing and retrieving a note is CRUD. Summarising a note is a different task class and is routed normally.',
   'SQL insert/select', true)
on conflict (task_class) do nothing;

-- ── C ───────────────────────────────────────────────────────────────────────────────────────────
-- No invented figures. Where a real number belongs (a delivery window, bank details, a slot) the
-- copy asks for it or points at the record rather than making one up.
insert into public.response_template (key, channel, intent, body, active)
values
  ('delivery_update','any','delivery',
   'Your order is being tracked. I can see its current stage against the reference on your quote — send me the reference and I will read back the latest movement and the expected date the supplier has confirmed.', true),
  ('appointment_booking','any','appointment',
   'Happy to arrange that. Tell me the emirate, and whether mornings or afternoons suit you better, and I will offer the slots that are actually open rather than a guess.', true),
  ('payment_instructions','any','payment',
   'Payment details are issued on the invoice itself so the reference always matches your order. Send me the quote or invoice number and I will pull up the exact instructions attached to it.', true),
  ('apology','any','apology',
   'I am sorry — that is not the standard we hold ourselves to, and I would be unhappy with it too. Tell me what happened and I will get it in front of someone who can put it right rather than pass you around.', true),
  ('shipping_update','any','shipping',
   'I can check where this is. Give me the order or quote reference and I will read back the latest confirmed movement, and say plainly if the supplier has not updated it recently.', true),
  ('follow_up','any','follow_up',
   'Following up on this so it does not go quiet. Nothing is needed from you unless the details have changed — if they have, tell me what moved and I will update the request.', true),
  ('complaint_resolution','any','complaint',
   'Thank you for putting it clearly — that helps. Here is what I can do now, what I cannot do myself, and who it goes to if you want it escalated. You will get a named owner, not a queue.', true)
on conflict (key) do nothing;
