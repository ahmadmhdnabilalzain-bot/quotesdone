-- EVERY SEAT GETS THE MODEL ITS OWN WORK NEEDS.
-- it_engineer, 23 September 2026. The founder's ruling: reasoning quality first, cost second.
--
-- This supersedes his ruling of 9 Sep 2026, which put anthropic/claude-fable-5.1 + openai/gpt-6-astra
-- on the CEO and Sales Engineer seats and openai/gpt-5.6-luna on the accountant. Both pairs cost
-- $10/$50 per Mtok. anthropic/claude-opus-5.5, read live from the catalogue on 23 Sep 2026, is
-- $4.00/$20.00 with a 1M context and a $0.20 cache read — cheaper on BOTH axes than what it
-- replaces AND the stronger reasoner. Nothing here is a cost trade.
--
-- HOW "A MODEL PER SEAT" IS ACTUALLY WRITTEN. llm_seat_binding has no model column: it is
-- attribution, not routing. fn_ai_route reads model_policy keyed on task_class, and reaches
-- task_class either from the caller or from fn_task_class keyed on the calling function. So a seat
-- gets its model by (a) the model_policy rows for the classes that seat's functions use, and (b) an
-- fn_task_class row for every function that calls the gateway — which also carries the dept_key
-- the budget ceiling is found by.
--
-- ═══ 1. THE CEO'S DECISIONS WERE GOING TO THE CHEAP TIER ════════════════════════════════════════
--
-- ceo_agent/index.ts:329 passes taskClass 'ceo_judgement'. There is no model_policy row for it, so
-- fn_ai_route fell through `no policy for "ceo_judgement", fell back to general_drafting` — which is
-- ~anthropic/claude-haiku-latest at 900 tokens. The CEO's judgements on refunds and exceptions, the
-- answers fn_ceo_judgement_accept validates against ceo-judgement-v1, were being drafted on the
-- cheapest model in the fleet with a 900-token ceiling.
--
-- I ADD THE CLASS rather than point the caller at ceo_approval_decision. Reasons, in order:
--
--   * ai_cost_log keys on task_class. Collapsing the two makes a plan judgement and a refund
--     approval indistinguishable in the cost log and in the per-seat model A/B the founder has
--     next on his plan. A column that cannot separate two decisions cannot evaluate either.
--   * They are different contracts. ceo_approval_decision answers one approval on the record;
--     ceo_judgement answers fn_ceo_judgement_request's output_schema against measured numbers and
--     code-computed options. Different shapes need different token ceilings, which is the whole
--     reason 900 was wrong.
--   * It is the smaller change: a data row, no function to redeploy. Editing the caller to send a
--     class whose contract it does not match would be a second bug dressed as a fix.
--
-- The caller's own `max: 900` clamps the route too (ai_gateway:326 takes min(body.max, route
-- max_tokens)), so supabase/functions/ceo_agent/index.ts is raised to 2000 in the same PR.
--
-- ═══ 2. THE TOKEN CLAMP ON A JSON CONTRACT ══════════════════════════════════════════════════════
--
-- supplier_catalog_ingest/index.ts:293 asks for max 3000 with response_format 'json', sending a
-- catalogue page as an image. It passes no task_class and had NO fn_task_class row, so it landed on
-- general_drafting: 900. ai_gateway clamps to min(3000, 900) = 900, and a products array truncated
-- at 900 tokens is not JSON, so the function's own parse fell to 'extraction_failed'.
--
-- The fix is a routing row, not a bigger default: document_extraction already means "reading a
-- whole document (scan, drawing, licence, quotation)" and allows 8000, which fits the contract with
-- 2.7x headroom. general_drafting stays at 900 on purpose — it is the "you forgot to map this"
-- path, and a generous default would hide the next unmapped caller instead of truncating visibly.
--
-- EVERY OTHER JSON-RETURNING CALLER WAS AUDITED THE SAME WAY (measured 23 Sep 2026, requested max
-- against the ceiling of the class its fn resolves to):
--
--   caller                          asks   class resolved            ceiling  verdict
--   ceo_agent:329                    900   general_drafting  ->NEW    900     misrouted, fixed above
--   supplier_catalog_ingest:293     3000   general_drafting  ->8000    900     CLAMPED, fixed here
--   inquiry_intake:39               4000   agent_reasoning            8000    fits
--   supplier_onboard:172             900   procurement_reasoning      1500    fits
--   wa_inbound:222                   600   customer_communication      800    fits
--
-- And the non-JSON callers, because a truncated prose answer is also a paid request for nothing:
-- drawing_boq 8000 / document_extraction 8000, quote_compare 10000 / quote_comparison 10000,
-- quote_extract 6000, extract_text 4000, doc_extract 2000, drawing_redact 2000 and license_extract
-- 2000 all against document_extraction 8000; email_triage 700 and resend_inbound 500/400 against
-- intent_detection 800; marketing_social_inbox 300 against marketing_copy 1200. All fit.
-- drawing_redact_verify sends NO max at all, so it takes the route's ceiling — see §4.
-- Held by scripts/checks/no_gateway_caller_is_clamped_below_what_it_asks_for.test.mjs.
--
-- ═══ 3. SEVEN FUNCTIONS OUTSIDE EVERY CEILING — AND WHICH SEVEN THEY REALLY ARE ═════════════════
--
-- The audit listed sales_engineer, supplier_catalog_ingest, accountant, marketing, customer_portal,
-- ceo_agent and it_engineer as missing fn_task_class rows. MEASURED 23 Sep 2026 against the source:
-- of those seven, only ceo_agent and supplier_catalog_ingest make a completion call through
-- ai_gateway. sales_engineer, accountant, marketing, customer_portal and it_engineer contain no
-- call to /functions/v1/ai_gateway, makeLlmRich or makeLlm at all — sales_engineer's only mention
-- is a comment about the free embedding path. A routing row for a call that does not exist is a row
-- that will be wrong by the time the call is written; the check below FAILS the moment any of them
-- starts calling, which is when the row can be right.
--
-- What IS missing, by the same measurement, is a row for marketing_social_inbox (the marketing
-- seat's only gateway caller) and a dept_key on four callers that have a class but no department:
--
--   fn              calls (8-22 Sep)   was          now
--   quote_compare              2,455   (no dept)    marketplace
--   transcribe                     0   (no dept)    marketplace
--   extract_text                   0   (no dept)    marketplace
--   email_triage                   0   (no dept)    customer_experience
--
-- quote_compare is 2,455 of the 3,207 calls in the window — 77% of everything the estate has ever
-- routed — and fn_ai_route's budget branch could not find a budget row for it, so the single
-- largest consumer sat outside every ceiling. That, not the missing table rows, is why the ceiling
-- could never bind. (department_budget's own emptiness is fixed in
-- a_ceiling_exists_before_the_door_is_opened.sql.)
--
-- ═══ 4. THE REDACTION VERIFY PASS IS THE ONE PLACE A MISS LEAKS A SUPPLIER'S IDENTITY ═══════════
--
-- drawing_redact runs FIND (drawing_redact) then VERIFY (drawing_redact_verify) over the redacted
-- page, and publishes only on a clean verify, failing closed on anything else. The verify pass was
-- on general_drafting: haiku at 900 tokens. Session 9 pinned it there deliberately to keep it off
-- google after a 400-token ceiling cut gemini's answer mid-JSON; the diagnosis was wrong (it was
-- the ceiling, measured: 724 output tokens with no max, parsing correctly) but the conclusion — do
-- not route this to redaction_detection — stands, and this file keeps it off google.
--
-- It now has its own class, identity_redaction_verify: anthropic/claude-sonnet-5 primary,
-- anthropic/claude-opus-5.5 on escalate, 2000 tokens (2.7x the 724 measured). A miss here sends a
-- consultant's name, a client's name and a phone number from the buyer's drawing to a supplier who
-- has not been revealed. It is the only vision call in the estate where the cheap model is the
-- wrong answer, and it keeps failing closed: the function still treats truncation, an unparseable
-- answer and an exception as NOT clean.
--
-- ═══ 5. WHAT STAYS DETERMINISTIC ════════════════════════════════════════════════════════════════
--
-- All 23 tier='none' rows are untouched. Money, matching, VAT, permissions, approval thresholds,
-- workflow state, scoring and the rest answer from code and keep answering from code.
--
-- ═══ 6. WHAT STAYS ON AUDIO, VERIFIED FROM THE CATALOGUE ════════════════════════════════════════
--
-- speech_transcription keeps google/gemini-3.1-flash-lite primary and google/gemini-3.5-flash
-- fallback. Both list "audio" in input_modalities in the live catalogue read 23 Sep 2026; no
-- anthropic/ or openai/ row in this fleet does. This was checked, not assumed — swapping in a
-- cheaper non-audio model would have the provider reject the payload, or fn_ai_route's capability
-- branch silently substitute something else.

begin;

-- ── 1. THE CEO SEAT: every judgement, approval and strategic class on the reasoning model ───────
insert into public.model_policy
  (task_class, tier, model_primary, model_fallback, max_tokens, active, rationale)
values
  ('ceo_judgement', 'xlarge', 'anthropic/claude-opus-5.5', 'anthropic/claude-sonnet-5', 2000, true,
   'The CEO judging one plan on the record: ceo_agent/index.ts:329 builds the request from '
   || 'fn_ceo_judgement_request and fn_ceo_judgement_accept validates the answer against '
   || 'ceo-judgement-v1. WHY opus-5.5: this is the class that decides refunds and exceptions, the '
   || 'one place in the company where a cheaper answer costs real money and the founder''s '
   || 'reputation, and until 23 Sep 2026 it had no policy row at all and fell to '
   || 'general_drafting — haiku at 900 tokens. WHY sonnet-5 as fallback: same family and prompt '
   || 'behaviour, half the price, and a judgement that arrives on the second-best reasoner is worth '
   || 'more than one that does not arrive. 2000 tokens is the structured answer plus its reasoning; '
   || 'the caller''s own max was raised to match, because ai_gateway takes the lower of the two.'),

  ('identity_redaction_verify', 'large', 'anthropic/claude-sonnet-5', 'anthropic/claude-opus-5.5', 2000, true,
   'The second pass over a REDACTED drawing page, asked whether any identity is still legible '
   || '(drawing_redact/index.ts:186, fn drawing_redact_verify). WHY the stronger model on the '
   || 'verify step and not the find step: a false clean here publishes a consultant''s name, a '
   || 'client''s name, a plot number and a phone number from the buyer''s drawing to a supplier who '
   || 'has not been revealed, and no later step can unsend it. The find pass may be cheap because a '
   || 'miss there is caught here; a miss here is caught by nobody. WHY sonnet-5 and not gemini: '
   || 'measured 13 Aug 2026, routing these calls to redaction_detection on gemini refused two of '
   || 'three fixtures while naming the planted identifiers as still legible. WHY opus-5.5 on '
   || 'escalate: the page is refused entirely on an uncertain answer, so the escalation is the '
   || 'difference between publishing a drawing and refusing a customer''s job. 2000 tokens against '
   || 'the 724 measured with no ceiling — a ceiling inside the answer''s natural range reads as an '
   || 'unparseable model, which cost a whole session once. Still fails CLOSED: truncated, '
   || 'unparseable and exception all mean not clean.')
on conflict (task_class) do update set
  tier = excluded.tier, model_primary = excluded.model_primary,
  model_fallback = excluded.model_fallback, max_tokens = excluded.max_tokens,
  active = excluded.active, rationale = excluded.rationale;

update public.model_policy set
  tier = 'xlarge', model_primary = 'anthropic/claude-opus-5.5', model_fallback = 'anthropic/claude-sonnet-5',
  rationale = 'The CEO deciding one approval on the record - a refund, an exception, a supplier '
    || 'removal. WHY opus-5.5 (founder, 23 Sep 2026): every approval in this company is the CEO''s, '
    || 'refunds included, and nothing reaches the founder, so this row IS the last judgement. '
    || 'Cheaper AND stronger than the fable-5.1/gpt-6-astra pair it replaces ($4/$20 against '
    || '$10/$50 on both models). Fallback sonnet-5: an approval that arrives is worth more than one '
    || 'that waits for the best reasoner to come back.'
 where task_class = 'ceo_approval_decision' and active;

update public.model_policy set
  tier = 'xlarge', model_primary = 'anthropic/claude-opus-5.5', model_fallback = 'anthropic/claude-sonnet-5',
  rationale = 'Quarterly priorities and capital allocation against the AED 1M by Aug 2027 target. '
    || 'WHY opus-5.5: the longest-horizon reasoning the company does, and the one answer that is '
    || 'wrong for a quarter rather than for a call. 1M context holds the whole plan, the ledger and '
    || 'the measured KPIs in one request.'
 where task_class = 'ceo_strategic_planning' and active;

update public.model_policy set
  tier = 'xlarge', model_primary = 'anthropic/claude-opus-5.5', model_fallback = 'anthropic/claude-sonnet-5',
  rationale = 'Cross-department arbitration against company goals - which seat gives way when two '
    || 'are both right. WHY opus-5.5: an arbitration is a judgement with no appeal above it, and '
    || 'the intent_router and founder_directive paths both land here, so a shallow answer '
    || 'mis-routes the founder''s own instruction.'
 where task_class = 'chief_of_staff_decision' and active;

update public.model_policy set
  tier = 'xlarge', model_primary = 'anthropic/claude-opus-5.5', model_fallback = 'anthropic/claude-sonnet-5',
  rationale = 'Board-level synthesis for the founder. WHY opus-5.5: this is the report he acts on, '
    || 'and a plausible-sounding wrong synthesis of correct numbers is worse than no report.'
 where task_class = 'executive_report' and active;

-- ── 2. THE SALES ENGINEER: revenue judgement on the reasoning model, eyes on the vision model ───
update public.model_policy set
  tier = 'xlarge', model_primary = 'anthropic/claude-opus-5.5', model_fallback = 'anthropic/claude-sonnet-5',
  max_tokens = 10000,
  rationale = 'Normalising non-comparable supplier scopes and ranking the customer''s top 3. WHY '
    || 'opus-5.5: this is the revenue event. The customer pays 3% when he reveals the supplier this '
    || 'class ranked first, so the ranking IS the product, and it is 2,455 of the 3,207 calls the '
    || 'estate routed between 8 and 22 Sep 2026 - the most consequential class by volume AND by '
    || 'money. 1M context (the registry said 200,000 until today) matters here because every '
    || 'quotation goes on one request. max_tokens stays 10000. Fallback sonnet-5: a ranking that '
    || 'arrives is revenue; one that waits is not.'
 where task_class = 'quote_comparison' and active;

update public.model_policy set
  tier = 'large', model_primary = 'anthropic/claude-sonnet-5', model_fallback = 'anthropic/claude-opus-5.5',
  rationale = 'An AI employee reasoning over its own context, memory and live estate. WHY sonnet-5 '
    || 'primary: this is the working tier, 653 calls in the window, and it runs on every seat''s '
    || 'ordinary turn. WHY opus-5.5 on escalate: fn_ai_route takes the fallback when p_escalate is '
    || 'true, i.e. after an unsatisfactory cheaper attempt, so the escalation is a real second '
    || 'opinion from a better reasoner rather than a retry of the same one. opus-5.5 also replaces '
    || 'opus-4.8 here: $4/$20 against $5/$25, and the stronger model.'
 where task_class = 'agent_reasoning' and active;

update public.model_policy set
  tier = 'large', model_primary = 'anthropic/claude-sonnet-5', model_fallback = 'anthropic/claude-opus-5.5',
  rationale = 'The Sales Engineer reasoning over technical scope, supplier capability and what a '
    || 'line item actually requires. WHY sonnet-5 and not the xlarge pair it used to run '
    || '(fable-5.1/gpt-6-astra, $10/$50): the judgement that earns money is quote_comparison, which '
    || 'IS on opus-5.5 above. This class is the working reasoning around it, and opus-5.5 on '
    || 'escalate gives it the stronger model exactly when a cheaper attempt was not good enough.'
 where task_class = 'sales_engineer_reasoning' and active;

update public.model_policy set
  tier = 'medium', model_primary = 'anthropic/claude-sonnet-5', model_fallback = 'anthropic/claude-opus-5.5',
  rationale = 'Qualifying an inbound inquiry in conversation - the model interprets and rephrases, '
    || 'code controls the state and the questions. WHY sonnet-5: this is the first thing a paying '
    || 'customer reads, and a qualifying question that misreads his trade sends the RFQ to the '
    || 'wrong suppliers, which the exact-trade-match rule then cannot repair. opus-5.5 on escalate '
    || 'for the inquiry nobody can classify.'
 where task_class = 'inquiry_qualification_conversation' and active;

update public.model_policy set
  tier = 'medium', model_primary = 'google/gemini-3.8-flash', model_fallback = 'anthropic/claude-sonnet-5',
  rationale = 'Reading a whole document - a scan, a drawing, a trade licence, a quotation, a '
    || 'supplier catalogue page - into structured fields. WHY gemini-3.8-flash: it is the eyes of '
    || 'the estate. Vision, 1,048,576 context so a multi-page scan goes on one request, and '
    || '$0.75/$3.75 - half the gemini-3.5-flash it replaces on both axes, same context. Extraction '
    || 'is transcription: the judgement about what the document MEANS is a separate class on a '
    || 'stronger model. WHY sonnet-5 as fallback and not another gemini: a fallback that shares the '
    || 'primary''s blind spots is not a fallback. 8000 tokens holds supplier_catalog_ingest''s 3000 '
    || 'JSON products with headroom - it used to land on general_drafting''s 900 and truncate.'
 where task_class = 'document_extraction' and active;

update public.model_policy set
  tier = 'medium', model_primary = 'google/gemini-3.8-flash', model_fallback = 'anthropic/claude-sonnet-5',
  rationale = 'Extract once from an image or PDF, store the structured fields and their source '
    || 'coordinates. WHY gemini-3.8-flash: vision at half the old price, and the coordinates make '
    || 'this re-readable by code afterwards, so the model is asked once and never again.'
 where task_class = 'document_extraction_multimodal' and active;

update public.model_policy set
  tier = 'medium', model_primary = 'google/gemini-3.8-flash', model_fallback = 'anthropic/claude-sonnet-5',
  rationale = 'Reading a drawing and a bill of quantities together. WHY gemini-3.8-flash: vision '
    || 'over large pages at 1M context. WHY sonnet-5 as the escalation: design calculations and '
    || 'low-confidence interpretations are judgement, not reading, and a wrong quantity becomes a '
    || 'wrong price on a real quotation.'
 where task_class = 'drawing_and_boq_analysis' and active;

-- redaction_detection is DELIBERATELY NOT TOUCHED. Its rationale was written for these calls, but
-- drawing_redact's comment block at index.ts:94 records the measurement that stopped it being used:
-- routing the two passes there on staging REFUSED two of three correctly-redacted fixtures and
-- filled verify_detail with identifiers that a look at the published JPGs showed were under solid
-- black. It has no caller, and a policy with no caller is not made better by editing it. The FIND
-- pass stays on document_extraction (gemini-3.8-flash) and the VERIFY pass gets its own class above.
-- The sweep in §7 leaves it alone too: its models are gemini-3.1-flash-lite / gemini-3.5-flash, and
-- the fallback move below would touch it, so it is excluded there by name.

update public.model_policy set
  tier = 'medium', model_primary = 'anthropic/claude-sonnet-5', model_fallback = 'anthropic/claude-opus-5.5',
  rationale = 'Trade-off reasoning within one category, and the supplier''s mandatory six - name, '
    || 'mobile, email, licence, profile, signed T&C. WHY sonnet-5: this class decides whether a '
    || 'supplier is verified, and one confirmed supplier gates every RFQ, so a wrong answer here '
    || 'either admits an unverified company to the marketplace or keeps a real one out. opus-5.5 '
    || 'on escalate for the licence nobody can read.'
 where task_class = 'procurement_reasoning' and active;

update public.model_policy set
  tier = 'medium', model_primary = 'google/gemini-3.8-flash', model_fallback = 'google/gemini-3.5-flash',
  rationale = 'Reading a supplier catalogue or a knowledge source for MEANING, offline, once. WHY '
    || 'gemini-3.8-flash: 1M context takes a whole catalogue in one request at $0.75/Mtok, and this '
    || 'runs in batch rather than in front of a customer, so latency and depth both matter less '
    || 'than the price of reading everything.'
 where task_class = 'knowledge_ingestion' and active;

update public.model_policy set
  model_primary = 'google/gemini-3.8-flash', model_fallback = 'openai/gpt-6-luna',
  rationale = 'Structured extraction from a known shape. WHY gemini-3.8-flash: the shape is given, '
    || 'so this is reading, not judgement - and it is the same model as document_extraction, so an '
    || 'extract and its re-extract do not disagree for a reason nobody can find. gpt-6-luna as '
    || 'fallback at $0.10/$0.50: a known shape that fails validation is retried by code, never '
    || 'sent, so the cheapest capable model is the right fallback here.'
 where task_class in ('json_extraction', 'json_extraction_text') and active;

-- ── 3. CUSTOMER SUPPORT: the signed-in customer gets the reasoner, the public gets the working tier
update public.model_policy set
  tier = 'xlarge', model_primary = 'anthropic/claude-opus-5.5', model_fallback = 'anthropic/claude-sonnet-5',
  rationale = 'The assistant a SIGNED-IN customer or supplier talks to, reasoning over that '
    || 'person''s own quotes, reveals and invoices. WHY opus-5.5: it is the only class that reads '
    || 'real money belonging to the person reading the answer, and it answers about state it can '
    || 'see, so a confident wrong answer about his own reveal is indistinguishable from the truth '
    || 'to him. Distinct from visitor_chat, which knows nothing about anybody.'
 where task_class = 'customer_portal_assistant' and active;

update public.model_policy set
  tier = 'large', model_primary = 'anthropic/claude-sonnet-5', model_fallback = 'google/gemini-3.8-flash',
  rationale = 'The public website chat widget - the support seat talking to a stranger, FAQ first. '
    || 'WHY sonnet-5 and not the flash-lite it ran on: this is the highest-volume public surface '
    || 'and the first sentence anyone reads about the company, and the founder''s standard for the '
    || 'support seat is better than Amazon''s. Volume is served by the deterministic FAQ levels in '
    || 'front of it (level0_faq_keyword, level0_faq_semantic, level0_template answered 18 of the 50 '
    || 'site_assistant calls in the window with no model at all), so the model sees only what code '
    || 'could not answer. WHY gemini-3.8-flash as fallback: a public widget must answer, and at '
    || '$0.75/Mtok it can absorb a spike the large tier should not.'
 where task_class = 'visitor_chat' and active;

update public.model_policy set
  tier = 'large', model_primary = 'anthropic/claude-sonnet-5', model_fallback = '~anthropic/claude-haiku-latest',
  rationale = 'The support seat writing to a customer or a supplier - email, WhatsApp, the portal. '
    || 'WHY sonnet-5: every word is customer-visible and signed in the company''s name, and tone in '
    || 'two languages is exactly what the cheap tier gets subtly wrong. haiku-latest as fallback '
    || 'because a reply that goes out late is a complaint and its cache read is $0.10/Mtok on a '
    || 'system prompt that never changes.'
 where task_class in ('customer_communication', 'support_ai', 'wa_inbound') and active;

update public.model_policy set
  tier = 'medium', model_primary = 'google/gemini-3.8-flash', model_fallback = 'openai/gpt-6-luna',
  rationale = 'Sorting one inbound message into what it is and who it is from. WHY '
    || 'gemini-3.8-flash: the answer is one label from a known set plus a short factual summary - '
    || 'classification, not judgement - and a wrong label is corrected by the next step rather than '
    || 'sent to anyone. WHY gpt-6-luna as fallback at $0.10/$0.50: the cheapest capable model in '
    || 'the fleet is the right second opinion for a label. max_tokens is NOT reduced: email_triage '
    || 'asks for 700 here and 300 cut its Arabic replies in half (founder instruction 705).'
 where task_class in ('intent_detection', 'email_triage', 'inbound_email', 'resend_inbound') and active;

-- ── 4. THE ACCOUNTANT: anything that touches money reasons on opus-5.5 ─────────────────────────
update public.model_policy set
  tier = 'xlarge', model_primary = 'anthropic/claude-opus-5.5', model_fallback = 'anthropic/claude-sonnet-5',
  max_tokens = 2000,
  rationale = 'The accountant''s analysis, including the refund recommendation the CEO then '
    || 'approves. WHY opus-5.5 (founder, 23 Sep 2026 - anything touching money): the books are the '
    || 'one record with an external reader, and AED 6,905.59 of real bookings already sit in them. '
    || 'max_tokens 1400 -> 2000 because a recommendation without its arithmetic is not a '
    || 'recommendation, and this class is read by a person who must be able to check it.'
 where task_class = 'finance_analysis' and active;

update public.model_policy set
  tier = 'xlarge', model_primary = 'anthropic/claude-opus-5.5', model_fallback = 'anthropic/claude-sonnet-5',
  max_tokens = 600,
  rationale = 'Classifying one expense against the chart of accounts. WHY opus-5.5 even though the '
    || 'answer is short: the answer is a LEDGER ENTRY. It is cheap to produce and expensive to be '
    || 'wrong about, it is what a VAT position and a P&L are built from, and at $4/Mtok in on a '
    || '600-token answer the whole month of expenses costs less than one quote comparison. '
    || 'max_tokens 400 -> 600 so the account, the reason and the VAT treatment fit together.'
 where task_class = 'accountant_expense_classification' and active;

update public.model_policy set
  tier = 'medium', model_primary = 'google/gemini-3.8-flash', model_fallback = 'anthropic/claude-sonnet-5',
  rationale = 'Reading a forwarded receipt - image or PDF - into fields. WHY gemini-3.8-flash and '
    || 'NOT opus-5.5 like the rest of the accountant''s classes: this step TRANSCRIBES, it does not '
    || 'decide. The judgement about what the receipt means is accountant_expense_classification, '
    || 'which runs on opus-5.5 and reads these fields. Splitting them puts the reasoning model where '
    || 'the reasoning is and the vision model where the pixels are, and makes a misread '
    || 'distinguishable from a misjudgement in ai_cost_log. WHY sonnet-5 as fallback: a receipt the '
    || 'vision model cannot read must still be read.'
 where task_class = 'accountant_receipt_extraction' and active;

update public.model_policy set
  tier = 'xlarge', model_primary = 'anthropic/claude-opus-5.5', model_fallback = 'anthropic/claude-sonnet-5',
  max_tokens = 2000,
  rationale = 'The weekly financial report. WHY opus-5.5: it states the company''s position to the '
    || 'founder from the ledger, and a report that reads well and totals wrong is worse than none. '
    || 'Weekly, so the cost of the best model here is one call a week.'
 where task_class = 'accountant_weekly_report' and active;

-- ── 5. MARKETING: it speaks in the company's name ──────────────────────────────────────────────
update public.model_policy set
  tier = 'large', model_primary = 'anthropic/claude-sonnet-5', model_fallback = '~anthropic/claude-haiku-latest',
  rationale = 'Public posts, social replies and brand copy. WHY sonnet-5: this text is published '
    || 'under the company''s own name on surfaces the founder does not review first, and a UAE '
    || 'audience reads it in two languages. The deterministic brand_rule_check (tier none) still '
    || 'gates it - the model writes, code checks. haiku-latest as fallback so a scheduled post is '
    || 'not simply missed.'
 where task_class in ('marketing_copy', 'content_drafting', 'supplier_communication') and active;

-- ── 6. THE IT ENGINEER: its own drafting and diagnosis ────────────────────────────────────────
update public.model_policy set
  tier = 'large', model_primary = 'anthropic/claude-sonnet-5', model_fallback = 'google/gemini-3.8-flash',
  rationale = 'The IT seat reasoning about the estate - a finding, a diagnosis, a change. WHY '
    || 'sonnet-5: this seat''s answers become SQL and deployed functions, and the audits it writes '
    || 'are the reason the estate''s defects get found; a shallow diagnosis costs a session, which '
    || 'is dearer than the model. Not opus-5.5: its work is checked by CI, by branch protection and '
    || 'by an independent review before every merge, so it has a real safety net the judgement '
    || 'classes do not.'
 where task_class in ('engineering_reasoning', 'reflection_and_learning') and active;

update public.model_policy set
  tier = 'large', model_primary = 'anthropic/claude-sonnet-5', model_fallback = 'anthropic/claude-opus-5.5',
  rationale = 'A security incident, an escalated edge case, or an independent review of knowledge '
    || 'before it is trusted. WHY sonnet-5 primary and opus-5.5 on escalate: a reviewer on the '
    || 'cheap model is a green check that means nothing, and a severe incident is exactly the case '
    || 'p_escalate exists for.'
 where task_class in ('security_incident_analysis', 'edge_case_escalation', 'knowledge_validation') and active;

-- ── 7. THE SWEEP: nothing expensive or superseded is left named by an active policy ────────────
-- Three blanket moves, each a strict improvement, applied to whatever rows this file did not name
-- one by one. Without them a class nobody edited today keeps a model that is dearer and weaker.
--
--   opus-4.8  -> opus-5.5          $5.00/$25.00 -> $4.00/$20.00, and the better reasoner
--   fable-5.1 -> opus-5.5          $10.00/$50.00 -> $4.00/$20.00 (founder's 9 Sep pair, superseded)
--   gpt-6-astra -> sonnet-5        $10.00/$50.00 -> $2.00/$10.00 as a fallback
--   gemini-3.5-flash -> 3.8-flash  $1.50/$9.00 -> $0.75/$3.75, same 1,048,576 context, same
--                                  modalities INCLUDING audio
-- speech_transcription is excluded from the gemini move: its fallback must stay on a model whose
-- audio support has been read from the catalogue, and moving both rows of an audio pair in one
-- sweep is how a capability quietly disappears.
update public.model_policy set model_primary = 'anthropic/claude-opus-5.5'
 where active and model_primary in ('anthropic/claude-opus-4.8', 'anthropic/claude-fable-5.1');
update public.model_policy set model_fallback = 'anthropic/claude-opus-5.5'
 where active and model_fallback = 'anthropic/claude-opus-4.8';
update public.model_policy set model_fallback = 'anthropic/claude-sonnet-5'
 where active and model_fallback in ('openai/gpt-6-astra', 'anthropic/claude-fable-5.1');
update public.model_policy set model_primary = 'anthropic/claude-sonnet-5'
 where active and model_primary = 'openai/gpt-6-astra';
update public.model_policy set model_primary = 'google/gemini-3.8-flash'
 where active and model_primary = 'google/gemini-3.5-flash' and task_class <> 'speech_transcription';
update public.model_policy set model_fallback = 'google/gemini-3.8-flash'
 where active and model_fallback = 'google/gemini-3.5-flash'
   and task_class not in ('speech_transcription', 'redaction_detection');
-- The accountant's remaining gpt-5.6-luna rows. gpt-5.6-luna stays in the registry (see the
-- catalogue file) but no active policy names it: money reasons on opus-5.5 now.
update public.model_policy set model_primary = 'anthropic/claude-opus-5.5'
 where active and model_primary = 'openai/gpt-5.6-luna';
update public.model_policy set model_fallback = 'anthropic/claude-sonnet-5'
 where active and model_fallback = 'openai/gpt-5.6-luna';

-- ── 8. fn_task_class: the rows the callers need, and the departments the ceiling is found by ───
-- `as ftc` is not decoration: scripts/apply_sql.mjs treats `public.fn_<name>(` as a ROUTINE CALL and
-- refuses the file for calling a routine the database does not have. fn_task_class is a TABLE whose
-- name happens to start with fn_, so the alias keeps the column list off the table name.
insert into public.fn_task_class as ftc (fn, task_class, dept_key, active, note)
values
  ('ceo_agent', 'ceo_judgement', 'exec', true,
   'ceo_agent/index.ts:329 passes taskClass ceo_judgement explicitly, so this row is not what '
   || 'chooses its model - but fn_ai_route finds the BUDGET by fn_task_class.dept_key when the '
   || 'caller sends no p_dept_key, and ceo_agent sends none. Without this row the CEO''s judgements '
   || 'were outside every ceiling as well as on the wrong model.'),
  ('supplier_catalog_ingest', 'document_extraction', 'marketplace', true,
   'Reads a supplier catalogue page as an image into a JSON products array '
   || '(supplier_catalog_ingest/index.ts:293, response_format json, max 3000). Had no row, so it '
   || 'fell to general_drafting and ai_gateway clamped 3000 to 900, truncating the JSON and '
   || 'recording extraction_failed. document_extraction allows 8000.'),
  ('marketing_social_inbox', 'marketing_copy', 'marketing', true,
   'The marketing seat''s only gateway caller - drafting a public social reply. marketing_copy is '
   || 'on sonnet-5 because this text is published in the company''s name.')
on conflict (fn) do update set
  task_class = excluded.task_class, dept_key = excluded.dept_key,
  active = excluded.active, note = excluded.note, updated_at = now();

-- drawing_redact_verify moves off general_drafting onto its own class (see §4 in the header).
update public.fn_task_class set
  task_class = 'identity_redaction_verify', dept_key = 'marketplace', updated_at = now(),
  note = 'The VERIFY pass over a redacted drawing page. Pinned to general_drafting by session 9 to '
    || 'keep it off google after a token ceiling cut gemini''s answer mid-JSON; that kept it off '
    || 'google and also put the estate''s only identity-leak check on haiku at 900 tokens. It now '
    || 'has its own class on sonnet-5 with opus-5.5 on escalate and 2000 tokens.'
 where fn = 'drawing_redact_verify';

-- Four callers that had a class but no department, so fn_ai_route's budget branch could not find a
-- ceiling for them. quote_compare alone is 2,455 of the 3,207 calls logged 8-22 Sep 2026.
update public.fn_task_class set dept_key = 'marketplace', updated_at = now()
 where fn in ('quote_compare', 'extract_text', 'transcribe') and dept_key is null;
update public.fn_task_class set dept_key = 'customer_experience', updated_at = now()
 where fn = 'email_triage' and dept_key is null;

-- ── 9. THE GUARD: an active policy cannot name a model the catalogue or the breaker does not hold
-- This is the recurrence guard for the defect this PR fixes. fn_ai_route SUBSTITUTES silently for
-- an unregistered model (it writes a WARNING into `why` that nobody reads), and before today
-- fn_llm_preflight ALLOWED an unmeasured one. Both holes were opened the same way: a model was
-- added to model_policy and the two tables behind it were not updated in the same breath. A
-- trigger is the only thing that makes those three writes one action.
create or replace function public.trg_model_policy_names_a_known_route()
returns trigger
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $fn$
declare
  v_m text;
begin
  if not coalesce(new.active, false) then return new; end if;
  for v_m in
    select m from unnest(array[new.model_primary, new.model_fallback]) m
     where m is not null and m not in ('none', 'none/deterministic')
  loop
    if not exists (select 1 from model_registry r where r.model_id = v_m and r.active) then
      raise exception 'model_policy.% names "%" which is not an active model_registry row. '
        'fn_ai_route would substitute a different model silently. Add the registry row (prices read '
        'live from the provider catalogue) in the same file.', new.task_class, v_m
        using errcode = '23514';
    end if;
    if not exists (select 1 from llm_route_health h where h.model_id = v_m) then
      raise exception 'model_policy.% names "%" which has no llm_route_health row, so no circuit '
        'breaker covers it and fn_llm_preflight must refuse it. Add the breaker row - carrying the '
        'same open_until as the rest of the fleet - in the same file.', new.task_class, v_m
        using errcode = '23514';
    end if;
  end loop;
  return new;
end $fn$;

revoke execute on function public.trg_model_policy_names_a_known_route() from public, anon, authenticated;

drop trigger if exists trg_model_policy_names_a_known_route on public.model_policy;
create trigger trg_model_policy_names_a_known_route
  before insert or update on public.model_policy
  for each row execute function public.trg_model_policy_names_a_known_route();

-- ── THE PROBE: the routing every seat now gets, printed, from fn_ai_route itself ───────────────
-- Read-only (fn_ai_route is STABLE) and it cannot reach a person. A verdict row, not a raise:
-- a raise here would roll back the DDL above.
create temporary table probe_routes (seat text, task_class text, chosen text, fallback text,
                                     max_tokens int, tier text, use_llm boolean) on commit drop;

insert into probe_routes
select s.seat, s.tc,
       r ->> 'model', r ->> 'fallback', (r ->> 'max_tokens')::int, r ->> 'tier',
       (r ->> 'use_llm')::boolean
  from (values
    ('ceo', 'ceo_judgement'), ('ceo', 'ceo_approval_decision'), ('ceo', 'ceo_strategic_planning'),
    ('ceo', 'chief_of_staff_decision'), ('ceo', 'executive_report'),
    ('sales_engineer', 'quote_comparison'), ('sales_engineer', 'agent_reasoning'),
    ('sales_engineer', 'sales_engineer_reasoning'), ('sales_engineer', 'document_extraction'),
    ('sales_engineer', 'drawing_and_boq_analysis'), ('sales_engineer', 'redaction_detection'),
    ('sales_engineer', 'identity_redaction_verify'), ('sales_engineer', 'procurement_reasoning'),
    ('sales_engineer', 'knowledge_ingestion'), ('sales_engineer', 'json_extraction'),
    ('sales_engineer', 'speech_transcription'),
    ('customer_support', 'customer_portal_assistant'), ('customer_support', 'visitor_chat'),
    ('customer_support', 'customer_communication'), ('customer_support', 'wa_inbound'),
    ('customer_support', 'intent_detection'), ('customer_support', 'email_triage'),
    ('accountant', 'finance_analysis'), ('accountant', 'accountant_expense_classification'),
    ('accountant', 'accountant_receipt_extraction'), ('accountant', 'accountant_weekly_report'),
    ('accountant', 'money_state_change'),
    ('marketing', 'marketing_copy'), ('marketing', 'content_drafting'),
    ('it_engineer', 'engineering_reasoning'), ('it_engineer', 'security_incident_analysis'),
    ('it_engineer', 'knowledge_validation'),
    ('deterministic', 'vat_calculation'), ('deterministic', 'supplier_matching'),
    ('deterministic', 'workflow_state_and_permissions')
  ) s(seat, tc)
  cross join lateral (select public.fn_ai_route(s.tc, null, null, null, false, null, null) r) x;

select 'ROUTE ' || seat || ' / ' || task_class as verdict,
       coalesce(chosen, '(deterministic)') as model, coalesce(fallback, '-') as fallback,
       coalesce(max_tokens, 0) as max_tokens, tier
  from probe_routes order by seat, task_class;

with bad as (
  select count(*) n from probe_routes
   where use_llm and (chosen is null
     or not exists (select 1 from public.model_registry r where r.model_id = chosen and r.active)
     or not exists (select 1 from public.llm_route_health h where h.model_id = chosen))
),
det as (select count(*) n from probe_routes where seat = 'deterministic' and use_llm),
cheap as (
  -- the defect that started this: a judgement class landing on the general_drafting default
  select count(*) n from probe_routes
   where seat in ('ceo', 'accountant') and task_class <> 'accountant_receipt_extraction'
     and use_llm and chosen <> 'anthropic/claude-opus-5.5'
),
gaps as (
  select count(*) n from (
    select model_primary m from public.model_policy where active and model_primary <> 'none'
    union select model_fallback from public.model_policy where active and coalesce(model_fallback,'none') <> 'none'
  ) z where not exists (select 1 from public.llm_route_health h where h.model_id = z.m)
    or not exists (select 1 from public.model_registry r where r.model_id = z.m and r.active)
),
clamp as (
  -- supplier_catalog_ingest asks 3000 and ceo_agent 2000; both must now fit their route
  select count(*) n from probe_routes
   where (task_class = 'document_extraction' and coalesce(max_tokens,0) < 3000)
      or (task_class = 'ceo_judgement' and coalesce(max_tokens,0) < 2000)
      or (task_class = 'identity_redaction_verify' and coalesce(max_tokens,0) < 2000)
)
select case
  when (select n from det)   > 0 then 'PROBE FAILED: ' || (select n from det)::text || ' tier=none class(es) now want a model'
  when (select n from bad)   > 0 then 'PROBE FAILED: ' || (select n from bad)::text || ' route(s) chose a model that is not a registered, measured route'
  when (select n from cheap) > 0 then 'PROBE FAILED: ' || (select n from cheap)::text || ' judgement/money class(es) did not land on opus-5.5'
  when (select n from gaps)  > 0 then 'PROBE FAILED: ' || (select n from gaps)::text || ' active-policy model(s) are missing from model_registry or llm_route_health'
  when (select n from clamp) > 0 then 'PROBE FAILED: ' || (select n from clamp)::text || ' class(es) still allow less than their caller asks for'
  else 'PROBE OK: ' || (select count(*) from probe_routes where use_llm)::text || ' routed classes, all on registered and measured models; '
       || (select count(*) from probe_routes where not use_llm)::text || ' still deterministic; '
       || (select count(*) from public.model_policy where active and tier = 'none')::text
       || ' tier=none rows untouched'
  end as verdict;

commit;
